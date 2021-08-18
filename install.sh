#!/bin/bash

# This is free and unencumbered software released into the public domain.
#
# Anyone is free to copy, modify, publish, use, compile, sell, or
# distribute this software, either in source code form or as a compiled
# binary, for any purpose, commercial or non-commercial, and by any
# means.
#
# In jurisdictions that recognize copyright laws, the author or authors
# of this software dedicate any and all copyright interest in the
# software to the public domain. We make this dedication for the benefit
# of the public at large and to the detriment of our heirs and
# successors. We intend this dedication to be an overt act of
# relinquishment in perpetuity of all present and future rights to this
# software under copyright law.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# For more information, please refer to <https://unlicense.org>

set -eE
sudo bash -c "echo 'User $USER is sudo enabled.'"

export DEBIAN_FRONTEND=noninteractive
export AS_ROOT="sudo bash -c"
export AS_GVM="sudo -u gvm bash -c"
export PROMPT="$(basename $0)"

function log() {
    local TIME=$(date +"%T")
    case $1 in
    -i)
        echo -en "\033[0;32m[INFO ]\033[0m"
        shift
        ;;
    -w)
        echo -en "\033[0;33m[WARN ]\033[0m"
        shift
        ;;
    -e)
        echo -en "\033[0;31m[ERROR]\033[0m"
        shift
        ;;
    esac
    local ROUTINE=''
    if [ -n "${FUNCNAME[1]}" ]; then
        ROUTINE="->${FUNCNAME[1]}"
    fi
    echo " ${TIME} ${PROMPT}${ROUTINE}:: $*"
}

function require() {
    local error=0
    for v in $*; do
        if [ -z "${!v}" ]; then
            log -e Env. $v is not set!
            error=1
        fi
    done
    return $error
}

function exec_as() {
    local user="$1"
    local fn="$2"
    shift; shift
    local env=()
    for e in $@; do
        env+=( "$e=${!e}" )
    done
    sudo "${env[@]}" -u "$user" bash -c "$(declare -f $fn); $fn"
}

function print_help() {
    echo 'GVM install script'
    echo ''
    echo 'Configuration is done via environment variables as seen below.'
    echo ''
    echo 'Usage: ./install.sh [OPTIONS]'
    echo ''
    echo 'OPTIONS:'
    echo '  -h | --help : Display this message'
    echo ''
    echo 'ENVIRONMENT:'
    echo ''
    echo '  GVM_INSTALL_PREFIX : Path to the gvm user directory. (default = /var/opt/gvm)'
    echo '  GVM_VERSION        : GVM version to install.'
    echo '  GVM_ADMIN_PWD      : Initial admin password. (default = admin)'
    echo '  GVM_GSAD_OPTS      : Options to pass into gsad service, refer to "gsad --help". (eg. SSL certificate)'
    echo ''
}

trap "log -e 'Installation failed!'" ERR

for arg in $@; do
    case $arg in
    -h | --help | *)
        print_help
        exit 1
        ;;
    esac
done

### ARGUMENTS ###

export GVM_INSTALL_PREFIX="${GVM_INSTALL_PREFIX:-/var/opt/gvm}"
export GVM_VERSION="${GVM_VERSION:-21.04}"
export GVM_ADMIN_PWD="${GVM_ADMIN_PWD:-admin}"

require GVM_INSTALL_PREFIX
require GVM_VERSION
require GVM_ADMIN_PWD

### INSTALL ###

$AS_ROOT "systemctl stop gvmd.service gsad.service ospd-openvas.service || true"

function update_system() {
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt update
    apt upgrade -yq
    apt dist-upgrade -yq
    apt autoremove -yq
}

function install_deps() {
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt install -yq \
        bison cmake curl doxygen fakeroot gcc g++ \
        gcc-mingw-w64 gettext git gnupg gnutls-bin \
        graphviz heimdal-dev libgcrypt20-dev libglib2.0-dev \
        libgnutls28-dev libgpgme-dev libhiredis-dev \
        libical-dev libksba-dev libldap2-dev libmicrohttpd-dev \
        libpcap-dev libpopt-dev libradcli-dev libsnmp-dev \
        libsqlite3-dev libssh-gcrypt-dev libxml2-dev nmap nodejs npm \
        nsis perl-base pkg-config postgresql postgresql-contrib \
        postgresql-server-dev-all python3-defusedxml python3-lxml \
        python3-paramiko python3-pip python3-psutil python3-setuptools \
        python3-polib python3-dev redis redis-server rpm rsync smbclient \
        snmp socat software-properties-common sshpass \
        texlive-fonts-recommended texlive-latex-extra uuid-dev \
        vim virtualenv wget xmltoman xml-twig-tools xsltproc libnet1-dev libunistring-dev
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
    echo 'deb https://dl.yarnpkg.com/debian/ stable main' \
        | tee /etc/apt/sources.list.d/yarn.list
    apt update
    apt install -yq yarn
}

log -i "Update system"
exec_as root update_system
log -i "Install dependencies"
exec_as root install_deps

function setup_user() {
    set -e
    if [[ "$(id gvm 2>&1 | grep -o 'no such user')" == "no such user" ]]; then
        useradd -c "GVM/OpenVAS user" -d "$GVM_INSTALL_PREFIX" -m -s /bin/bash -U -G redis gvm
    else
        usermod -c "GVM/OpenVAS user" -d "$GVM_INSTALL_PREFIX" -m -s /bin/bash -aG redis gvm
    fi
    echo "export PATH=\"\$PATH:$GVM_INSTALL_PREFIX/bin:$GVM_INSTALL_PREFIX/sbin:$GVM_INSTALL_PREFIX/.local/bin\"" \
        | tee /etc/profile.d/gvm.sh
    chmod 755 /etc/profile.d/gvm.sh
    . /etc/profile.d/gvm.sh
    cat << EOF > /etc/ld.so.conf.d/gvm.conf
$GVM_INSTALL_PREFIX/lib
EOF
}

log -i "Setup user"
exec_as root setup_user GVM_INSTALL_PREFIX

function system_tweaks() {
    set -e
    sysctl -w net.core.somaxconn=1024
    sysctl vm.overcommit_memory=1
    if [ -z "$(grep -o 'net.core.somaxconn' /etc/sysctl.conf)"  ]; then
        echo 'net.core.somaxconn=1024'  >> /etc/sysctl.conf
    fi
    if [ -z "$(grep -o 'vm.overcommit_memory' /etc/sysctl.conf)"  ]; then
        echo 'vm.overcommit_memory=1' >> /etc/sysctl.conf
    fi
    cat << EOF > /etc/systemd/system/disable-thp.service
[Unit]
Description=Disable Transparent Huge Pages (THP)
[Service]
Type=simple
ExecStart=/bin/sh -c "echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled && echo 'never' > /sys/kernel/mm/transparent_hugepage/defrag"
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now disable-thp
}

log -i "System tweaks"
exec_as root system_tweaks

log -i "Clone GVM sources"
export PKG_CONFIG_PATH=$GVM_INSTALL_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH
$AS_GVM "mkdir -p ~/src"

function clone_sources() {
    set -e
    cd ~/src
    git clone -b "gvm-libs-$GVM_VERSION" https://github.com/greenbone/gvm-libs.git \
        || (cd gvm-libs; git pull --all; git checkout "gvm-libs-$GVM_VERSION"; git pull; cd ..)
    git clone -b "openvas-$GVM_VERSION" https://github.com/greenbone/openvas.git \
        || (cd openvas; git pull --all; git checkout "openvas-$GVM_VERSION"; git pull; cd ..)
    git clone -b "gvmd-$GVM_VERSION" https://github.com/greenbone/gvmd.git \
        || (cd gvmd; git pull --all; git checkout "gvmd-$GVM_VERSION"; git pull; cd ..)
    git clone -b master --single-branch https://github.com/greenbone/openvas-smb.git \
        || (cd openvas-smb; git pull; cd ..)
    git clone -b "gsa-$GVM_VERSION" https://github.com/greenbone/gsa.git \
        || (cd gsa; git pull --all; git checkout "gsa-$GVM_VERSION"; git pull; cd ..)
    git clone -b "ospd-openvas-$GVM_VERSION" https://github.com/greenbone/ospd-openvas.git \
        || (cd ospd-openvas; git pull --all; git checkout "ospd-openvas-$GVM_VERSION"; git pull; cd ..)
    git clone -b "ospd-$GVM_VERSION" https://github.com/greenbone/ospd.git \
        || (cd ospd; git pull --all; git checkout "ospd-$GVM_VERSION"; git pull; cd ..)
}

exec_as gvm clone_sources GVM_VERSION

function install_gvm_libs() {
    set -e
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
    cd ~/src/gvm-libs
    mkdir -p build
    cd build
    rm -rf *
    cmake -DCMAKE_INSTALL_PREFIX="$GVM_INSTALL_PREFIX" \
      -DLOCALSTATEDIR="$GVM_INSTALL_PREFIX/var" -DSYSCONFDIR="$GVM_INSTALL_PREFIX/etc" ..
    make -j$(nproc)
    make doc
    make install
}

function install_openvas_smb() {
    set -e
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
    cd ~/src/openvas-smb
    mkdir -p build
    cd build
    rm -rf *
    cmake -DCMAKE_INSTALL_PREFIX="$GVM_INSTALL_PREFIX" ..
    make -j$(nproc)
    make install
}

function install_openvas() {
    set -e
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
    cd ~/src/openvas
    mkdir -p build
    cd build
    rm -rf *
    cmake -DCMAKE_INSTALL_PREFIX="$GVM_INSTALL_PREFIX" \
      -DLOCALSTATEDIR="$GVM_INSTALL_PREFIX/var" -DSYSCONFDIR="$GVM_INSTALL_PREFIX/etc" ..
    make -j$(nproc)
    make doc
    make install
}

$AS_ROOT "mkdir -p -m 750 /run/gvm /run/ospd"
$AS_ROOT "chown -R gvm. /run/gvm /run/ospd"
log -i "Install gvm-libs"
exec_as gvm install_gvm_libs PKG_CONFIG_PATH GVM_INSTALL_PREFIX
log -i "Install openvas-smb"
exec_as gvm install_openvas_smb PKG_CONFIG_PATH GVM_INSTALL_PREFIX
log -i "Install openvas"
exec_as gvm install_openvas PKG_CONFIG_PATH GVM_INSTALL_PREFIX
$AS_ROOT ldconfig

function config_redis() {
    set -e
    cp -f /etc/redis/redis.conf /etc/redis/redis.conf.orig
    cp -f "$GVM_INSTALL_PREFIX/src/openvas/config/redis-openvas.conf" /etc/redis/
    chown redis:redis /etc/redis/redis-openvas.conf
    echo 'db_address = /run/redis-openvas/redis.sock' > "$GVM_INSTALL_PREFIX/etc/openvas/openvas.conf"
    chown gvm:gvm "$GVM_INSTALL_PREFIX/etc/openvas/openvas.conf"
    systemctl enable --now redis-server@openvas.service
}

log -i "Configure redis"
exec_as root config_redis GVM_INSTALL_PREFIX

function edit_sudoers() {
    set -e
    if [[ "$(grep -o '$GVM_INSTALL_PREFIX/sbin' /etc/sudoers || true)" == "" ]]; then
        sed -e "s|\(Defaults\s*secure_path.*\)\"|\1:$GVM_INSTALL_PREFIX/sbin\"|" -i /etc/sudoers
    fi
    echo "gvm ALL = NOPASSWD: $GVM_INSTALL_PREFIX/sbin/openvas" > /etc/sudoers.d/gvm
    echo "gvm ALL = NOPASSWD: $GVM_INSTALL_PREFIX/sbin/gsad" >> /etc/sudoers.d/gvm
    chmod 440 /etc/sudoers.d/gvm
}

log -i "Edit sudoers"
exec_as root edit_sudoers GVM_INSTALL_PREFIX

function install_gvmd() {
    set -e
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
    cd ~/src/gvmd
    mkdir -p build
    cd build
    rm -rf *
    cmake -DCMAKE_INSTALL_PREFIX="$GVM_INSTALL_PREFIX" -DSYSTEMD_SERVICE_DIR="$GVM_INSTALL_PREFIX" \
      -DLOCALSTATEDIR="$GVM_INSTALL_PREFIX/var" -DSYSCONFDIR="$GVM_INSTALL_PREFIX/etc" ..
    make -j$(nproc)
    make doc
    make install
}

log -i "Install gvmd"
exec_as gvm install_gvmd PKG_CONFIG_PATH GVM_INSTALL_PREFIX

function setup_postgres() {
    set -e
    psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='gvm'" | grep -q 1 \
        || createuser -DRS gvm
    psql -lqt | cut -d '|' -f 1 | grep -qw gvmd \
        || createdb -O gvm gvmd
    psql gvmd -c 'create role dba with superuser noinherit;' \
        2>&1 | grep -e 'already exists' -e 'CREATE ROLE'
    psql gvmd -c 'grant dba to gvm;'
    psql gvmd -c 'create extension "uuid-ossp";' \
        2>&1 | grep -e 'already exists' -e 'CREATE EXTENSION'
    psql gvmd -c 'create extension "pgcrypto";' \
        2>&1 | grep -e 'already exists' -e 'CREATE EXTENSION'
}

log -i "Setup postgresql"
exec_as postgres setup_postgres

function setup_gvmd() {
    set -e
    . /etc/profile.d/gvm.sh
    gvmd --migrate
    gvm-manage-certs -af
    gvmd --get-users | grep admin || gvmd --create-user=admin --password="$GVM_ADMIN_PWD"
    # set feed owner
    local admin_id="$(gvmd --get-users --verbose | grep admin | cut -d ' ' -f2 | tr -d '\n')"
    gvmd --modify-setting 78eceaec-3385-11ea-b237-28d24461215b --value "$admin_id"
}

log -i "Setup gvmd"
exec_as gvm setup_gvmd GVM_ADMIN_PWD

function install_gsa() {
    set -e
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
    cd ~/src/gsa
    mkdir -p build
    cd build
    rm -rf *
    cmake -DCMAKE_INSTALL_PREFIX="$GVM_INSTALL_PREFIX" -DSYSTEMD_SERVICE_DIR="$GVM_INSTALL_PREFIX" \
      -DLOCALSTATEDIR="$GVM_INSTALL_PREFIX/var" -DSYSCONFDIR="$GVM_INSTALL_PREFIX/etc" ..
    make -j$(nproc)
    make doc
    make install
    touch "$GVM_INSTALL_PREFIX/var/log/gvm/gsad.log"
}

log -i "Install gsa"
exec_as gvm install_gsa PKG_CONFIG_PATH GVM_INSTALL_PREFIX

function install_ospd_openvas() {
    set -e
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
    cd ~/src
    if [ ! -d "$GVM_INSTALL_PREFIX/bin/ospd-scanner/" ]; then
        virtualenv --python python3 "$GVM_INSTALL_PREFIX/bin/ospd-scanner/"
    fi
    . "$GVM_INSTALL_PREFIX/bin/ospd-scanner/bin/activate"
    python3 -m pip install --upgrade pip
    cd ospd
    pip3 install .
    cd ../ospd-openvas/
    pip3 install .
}

log -i "Install ospd-openvas"
exec_as gvm install_ospd_openvas PKG_CONFIG_PATH GVM_INSTALL_PREFIX

function create_gvmd_service() {
    set -e
    cat << EOF > /etc/systemd/system/gvmd.service
[Unit]
Description=Open Vulnerability Assessment System Manager Daemon
Documentation=man:gvmd(8) https://www.greenbone.net
Wants=postgresql.service ospd-openvas.service
After=postgresql.service ospd-openvas.service
[Service]
Type=forking
User=gvm
Group=gvm
PIDFile=/run/gvm/gvmd.pid
WorkingDirectory=$GVM_INSTALL_PREFIX
ExecStart=$GVM_INSTALL_PREFIX/sbin/gvmd --osp-vt-update=/run/ospd/ospd.sock -c /run/gvm/gvmd.sock
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=mixed
Restart=on-failure
RestartSec=2min
KillMode=process
KillSignal=SIGINT
GuessMainPID=no
PrivateTmp=true
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now gvmd.service
    systemctl --no-pager status gvmd.service
}

function create_gsad_service() {
    set -e
    cat << EOF > /etc/systemd/system/gsad.service
[Unit]
Description=Greenbone Security Assistant (gsad)
Documentation=man:gsad(8) https://www.greenbone.net
After=network.target
Wants=gvmd.service
[Service]
Type=forking
PIDFile=/run/gvm/gsad.pid
WorkingDirectory=$GVM_INSTALL_PREFIX
ExecStart=$GVM_INSTALL_PREFIX/sbin/gsad --drop-privileges=gvm --munix-socket=/run/gvm/gvmd.sock $GVM_GSAD_OPTS
Restart=on-failure
RestartSec=2min
KillMode=process
KillSignal=SIGINT
GuessMainPID=no
PrivateTmp=true
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now gsad.service
    systemctl --no-pager status gsad.service
}

function create_openvas_service() {
    set -e
    cat << EOF > /etc/systemd/system/ospd-openvas.service 
[Unit]
Description=Job that runs the ospd-openvas daemon
Documentation=man:gvm
After=network.target redis-server@openvas.service
Wants=redis-server@openvas.service
[Service]
Environment=PATH=$GVM_INSTALL_PREFIX/bin/ospd-scanner/bin:$GVM_INSTALL_PREFIX/bin:$GVM_INSTALL_PREFIX/sbin:$GVM_INSTALL_PREFIX/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Type=forking
User=gvm
Group=gvm
WorkingDirectory=$GVM_INSTALL_PREFIX
PIDFile=/run/ospd/ospd-openvas.pid
ExecStart=$GVM_INSTALL_PREFIX/bin/ospd-scanner/bin/python $GVM_INSTALL_PREFIX/bin/ospd-scanner/bin/ospd-openvas --pid-file /run/ospd/ospd-openvas.pid --unix-socket=/run/ospd/ospd.sock --log-file $GVM_INSTALL_PREFIX/var/log/gvm/ospd-scanner.log --lock-file-dir /run/ospd/
Restart=on-failure
RestartSec=2min
KillMode=process
KillSignal=SIGINT
GuessMainPID=no
PrivateTmp=true
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now ospd-openvas.service
    systemctl --no-pager status ospd-openvas.service
}

log -i "Create GVM services"
exec_as root create_gvmd_service GVM_INSTALL_PREFIX
exec_as root create_gsad_service GVM_INSTALL_PREFIX GVM_GSAD_OPTS
exec_as root create_openvas_service GVM_INSTALL_PREFIX

function set_default_scanner() {
    set -e
    . /etc/profile.d/gvm.sh
    local id="$(gvmd --get-scanners | grep -i openvas | cut -d ' ' -f1 | tr -d '\n')"
    gvmd --modify-scanner="$id" --scanner-host="/run/ospd/ospd.sock"
}

log -i "Set OpenVAS default scanner"
exec_as gvm set_default_scanner GVM_INSTALL_PREFIX

function create_feed_update_service() {
    set -e
    cat << EOF > "$GVM_INSTALL_PREFIX/bin/gvm-update-feed.sh"
#!/bin/bash
. /etc/profile.d/gvm.sh
echo "SYNC NVTs ..."
greenbone-nvt-sync
sleep 120
echo "SYNC GVMD DATA ..."
greenbone-feed-sync --type GVMD_DATA
sleep 120
echo "SYNC SCAP DATA ..."
#greenbone-feed-sync --type SCAP
greenbone-scapdata-sync
sleep 120
echo "SYNC CERT DATA ..."
#greenbone-feed-sync --type CERT
greenbone-certdata-sync
EOF
    chown gvm:gvm "$GVM_INSTALL_PREFIX/bin/gvm-update-feed.sh"
    chmod 755 "$GVM_INSTALL_PREFIX/bin/gvm-update-feed.sh"

    cat << EOF > /etc/systemd/system/gvm-feed-update.service
[Unit]
Description=GVM feed update

[Service]
Type=simple
User=gvm
Group=gvm
ExecStart=$GVM_INSTALL_PREFIX/bin/gvm-update-feed.sh
Restart=on-failure
RestartSec=30sec
EOF

    cat << EOF > /etc/systemd/system/gvm-feed-update.timer
[Unit]
Description=GVM feed update timer

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now gvm-feed-update.timer
}

log -i "Create weekly feed update service"
exec_as root create_feed_update_service GVM_INSTALL_PREFIX

function kickoff_feed_sync() {
    systemctl start gvm-feed-update.service
}

log -i "Start initial feed sync"
exec_as root kickoff_feed_sync

log -i "GVM installation completed"
log -i "Plugin feeds are synced in background. This might take a while ..."
log -i "Please reboot the machine as soon as possible."
