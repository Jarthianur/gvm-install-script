#!/bin/bash

# MIT License
#
# Copyright (c) 2020 Jarthianur
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -eE
sudo -u $USER bash -c id

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
    require 1 2
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
    echo ''
}

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
export GVM_VERSION="${GVM_VERSION:-}"
export GVM_ADMIN_PWD="${GVM_ADMIN_PWD:-admin}"

require GVM_INSTALL_PREFIX
require GVM_VERSION
require GVM_ADMIN_PWD

### INSTALL ###

function update_system() {
    apt update
    apt upgrade -y
    apt dist-upgrade -y
    apt autoremove -y
}

function install_deps() {
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
    echo 'deb https://dl.yarnpkg.com/debian/ stable main' \
        | tee /etc/apt/sources.list.d/yarn.list
    apt update
    apt install -y --no-install-recommends \
        bison cmake curl doxygen fakeroot gcc \
        gcc-mingw-w64 gettext git gnupg gnutls-bin \
        graphviz heimdal-dev libgcrypt20-dev libglib2.0-dev \
        libgnutls28-dev libgpgme-dev libhiredis-dev \
        libical-dev libksba-dev libldap2-dev libmicrohttpd-dev \
        libpcap-dev libpopt-dev libradcli-dev libsnmp-dev \
        libsqlite3-dev libssh-gcrypt-dev libxml2-dev nmap \
        nsis perl-base pkg-config postgresql postgresql-contrib \
        postgresql-server-dev-all python3-defusedxml python3-lxml \
        python3-paramiko python3-pip python3-psutil python3-setuptools \
        python-polib redis redis-server rpm rsync smbclient \
        snmp socat software-properties-common sshpass \
        texlive-fonts-recommended texlive-latex-extra uuid-dev \
        vim virtualenv wget xmltoman xml-twig-tools xsltproc yarn
}

log -i "Update system"
exec_as root update_system
log -i "Install dependencies"
exec_as root install_deps

function setup_path_ld() {
    echo "export PATH=\"\$PATH:$GVM_INSTALL_PREFIX/bin:$GVM_INSTALL_PREFIX/sbin:$GVM_INSTALL_PREFIX/.local/bin\"" \
        | tee -a /etc/profile.d/gvm.sh
    chmod 755 /etc/profile.d/gvm.sh
    . /etc/profile.d/gvm.sh
    cat << EOF > /etc/ld.so.conf.d/gvm.conf
$GVM_INSTALL_PREFIX/lib
EOF
}

function setup_user() {
    useradd -c "GVM/OpenVAS user" -d "$GVM_INSTALL_PREFIX" -m -s /bin/bash -U -G redis gvm
}

log -i "Setup user"
exec_as root setup_path_ld GVM_INSTALL_PREFIX
exec_as root setup_user GVM_INSTALL_PREFIX

function system_tweaks() {
    sysctl -w net.core.somaxconn=1024
    sysctl vm.overcommit_memory=1
    echo 'net.core.somaxconn=1024'  >> /etc/sysctl.conf
    echo 'vm.overcommit_memory=1' >> /etc/sysctl.conf
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
$AS_GVM "mkdir ~/src"

function clone_sources() {
    cd ~/src
    git clone -b "gvm-libs-$GVM_VERSION" --single-branch  https://github.com/greenbone/gvm-libs.git
    git clone -b "openvas-$GVM_VERSION" --single-branch https://github.com/greenbone/openvas.git
    git clone -b "gvmd-$GVM_VERSION" --single-branch https://github.com/greenbone/gvmd.git
    git clone -b master --single-branch https://github.com/greenbone/openvas-smb.git
    git clone -b "gsa-$GVM_VERSION" --single-branch https://github.com/greenbone/gsa.git
    git clone -b "ospd-openvas-$GVM_VERSION" --single-branch  https://github.com/greenbone/ospd-openvas.git
    git clone -b "ospd-$GVM_VERSION" --single-branch https://github.com/greenbone/ospd.git
}

exec_as gvm clone_sources GVM_VERSION

function install_gvm_libs() {
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
    cd ~/src/gvm-libs
    mkdir build
    cd build
    cmake -DCMAKE_INSTALL_PREFIX="$GVM_INSTALL_PREFIX" ..
    make -j
    make doc
    make install
}

function install_openvas_smb() {
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
    cd ~/src/openvas-smb
    mkdir build
    cd build
    cmake -DCMAKE_INSTALL_PREFIX="$GVM_INSTALL_PREFIX" ..
    make -j
    make install
}

function install_openvas() {
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
    cd ~/src/openvas
    mkdir build
    cd build
    cmake -DCMAKE_INSTALL_PREFIX="$GVM_INSTALL_PREFIX" ..
    make -j
    make doc
    make install
}

log -i "Install gvm-libs"
exec_as gvm install_gvm_libs PKG_CONFIG_PATH GVM_INSTALL_PREFIX
log -i "Install openvas-smb"
exec_as gvm install_openvas_smb PKG_CONFIG_PATH GVM_INSTALL_PREFIX
log -i "Install openvas"
exec_as gvm install_openvas PKG_CONFIG_PATH GVM_INSTALL_PREFIX
$AS_ROOT ldconfig

function config_redis() {
    cp /etc/redis/redis.conf /etc/redis/redis.conf.orig
    cp "$GVM_INSTALL_PREFIX/src/openvas/config/redis-openvas.conf" /etc/redis/
    chown redis:redis /etc/redis/redis-openvas.conf
    echo 'db_address = /run/redis-openvas/redis.sock' > "$GVM_INSTALL_PREFIX/etc/openvas/openvas.conf"
    chown gvm:gvm "$GVM_INSTALL_PREFIX/etc/openvas/openvas.conf"
    systemctl enable --now redis-server@openvas.service
}

log -i "Configure redis"
exec_as root config_redis GVM_INSTALL_PREFIX

function edit_sudoers() {
    sed -e "s|\(Defaults\s*secure_path.*\)\"|\1:$GVM_INSTALL_PREFIX/sbin\"|" -i /etc/sudoers
    echo "gvm ALL = NOPASSWD: $GVM_INSTALL_PREFIX/sbin/openvas" > /etc/sudoers.d/gvm
    echo "gvm ALL = NOPASSWD: $GVM_INSTALL_PREFIX/sbin/gsad" >> /etc/sudoers.d/gvm
    chmod 440 /etc/sudoers.d/gvm
}

log -i "Edit sudoers"
exec_as root edit_sudoers GVM_INSTALL_PREFIX

function install_gvmd() {
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
    cd ~/src/gvmd
    mkdir build
    cd build
    cmake -DCMAKE_INSTALL_PREFIX="$GVM_INSTALL_PREFIX" ..
    make -j
    make doc
    make install
}

log -i "Install gvmd"
exec_as gvm install_gvmd PKG_CONFIG_PATH GVM_INSTALL_PREFIX

function setup_postgres() {
    createuser -DRS gvm
    createdb -O gvm gvmd
    psql gvmd -c 'create role dba with superuser noinherit;'
    psql gvmd -c 'grant dba to gvm;'
    psql gvmd -c 'create extension "uuid-ossp";'
    psql gvmd -c 'create extension "pgcrypto";'
}

log -i "Setup postgresql"
exec_as postgres setup_postgres

function setup_gvmd() {
    gvm-manage-certs -a
    gvmd --create-user=admin --password="$GVM_ADMIN_PWD"
    # set feed owner
    local admin_id="$(gvmd --get-users --verbose | grep admin | cut -d ' ' -f2 | tr -d '\n')"
    gvmd --modify-setting 78eceaec-3385-11ea-b237-28d24461215b --value "$admin_id"
}

log -i "Setup gvmd"
exec_as gvm setup_gvmd GVM_ADMIN_PWD

function install_gsa() {
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
    cd ~/src/gsa
    mkdir build
    cd build
    cmake -DCMAKE_INSTALL_PREFIX="$GVM_INSTALL_PREFIX" ..
    make -j
    make doc
    make install
    touch "$GVM_INSTALL_PREFIX/var/log/gvm/gsad.log"
}

log -i "Install gsa"
exec_as gvm install_gsa PKG_CONFIG_PATH GVM_INSTALL_PREFIX

function install_ospd_openvas() {
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
    cd ~/src
    virtualenv --python python3.7 "$GVM_INSTALL_PREFIX/bin/ospd-scanner/"
    . "$GVM_INSTALL_PREFIX/bin/ospd-scanner/bin/activate"
    mkdir "$GVM_INSTALL_PREFIX/var/run/ospd/"
    cd ospd
    pip3 install .
    cd ../ospd-openvas/
    pip3 install .
}

log -i "Install ospd-openvas"
exec_as gvm install_ospd_openvas PKG_CONFIG_PATH GVM_INSTALL_PREFIX

function create_gvmd_service() {
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
PIDFile=$GVM_INSTALL_PREFIX/var/run/gvmd.pid
WorkingDirectory=$GVM_INSTALL_PREFIX
ExecStart=$GVM_INSTALL_PREFIX/sbin/gvmd --osp-vt-update=$GVM_INSTALL_PREFIX/var/run/ospd.sock
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
    systemctl status gvmd.service
}

function create_gsad_service() {
    cat << EOF > /etc/systemd/system/gsad.service
[Unit]
Description=Greenbone Security Assistant (gsad)
Documentation=man:gsad(8) https://www.greenbone.net
After=network.target
Wants=gvmd.service
[Service]
Type=forking
PIDFile=$GVM_INSTALL_PREFIX/var/run/gsad.pid
WorkingDirectory=$GVM_INSTALL_PREFIX
ExecStart=$GVM_INSTALL_PREFIX/sbin/gsad --drop-privileges=gvm
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
    systemctl status gsad.service
}

function create_openvas_service() {
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
PIDFile=$GVM_INSTALL_PREFIX/var/run/ospd-openvas.pid
ExecStart=$GVM_INSTALL_PREFIX/bin/ospd-scanner/bin/python $GVM_INSTALL_PREFIX/bin/ospd-scanner/bin/ospd-openvas --pid-file $GVM_INSTALL_PREFIX/var/run/ospd-openvas.pid --unix-socket=$GVM_INSTALL_PREFIX/var/run/ospd.sock --log-file $GVM_INSTALL_PREFIX/var/log/gvm/ospd-scanner.log --lock-file-dir $GVM_INSTALL_PREFIX/var/run/ospd/
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
    systemctl status ospd-openvas.service
}

log -i "Create GVM services"
exec_as root create_gvmd_service GVM_INSTALL_PREFIX
exec_as root create_gsad_service GVM_INSTALL_PREFIX
exec_as root create_openvas_service GVM_INSTALL_PREFIX

function set_default_scanner() {
    local id="$(gvmd --get-scanners | grep -i openvas | cut -d ' ' -f1 | tr -d '\n')"
    gvmd --modify-scanner="$id" --scanner-host="$GVM_INSTALL_PREFIX/var/run/ospd.sock"
}

log -i "Set OpenVAS default scanner"
exec_as gvm set_default_scanner GVM_INSTALL_PREFIX

function update_feed() {
    # maybe loop in case of failure
    greenbone-nvt-sync
    sudo openvas -u
    greenbone-certdata-sync
    greenbone-scapdata-sync
    greenbone-feed-sync --type GVMD_DATA
    greenbone-feed-sync --type SCAP
    greenbone-feed-sync --type CERT
}

log -i "Update plugin feed"
exec_as gvm update_feed

log -i "GVM installation completed"
log -w "It might still take some time for the plugin feed to be imported!"
