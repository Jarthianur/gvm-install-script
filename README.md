# gvm-install-script

An *unofficial* script to install GVM alias OpenVAS on debian (10) and ubuntu (20.04).

This script installs GVM, alias OpenVAS. It is not made for docker, but VMs and bare metal deployments. It does not configure any of the components, nor the system to be secure or production ready.

## Usage

Set the following environment variables as for your need.

- `GVM_INSTALL_PREFIX`: Path to the gvm user directory. (default = */var/opt/gvm*)
- `GVM_VERSION`: GVM version to install. (example = *20.08*)
- `GVM_ADMIN_PWD`: Initial admin password. (default = *admin*)

```bash
$ export GVM_VERSION=20.08
$ ./install.sh
```

## Requirements

- base installation of one of
  - debian 10
  - ubuntu 20.04
- internet access
- shell (SSH) on the target system
- *sudo* installed
- user with *sudo* permissions
- at least ~10GB disk storage (my test VM used 9.8GB after all)
- at least 4GB of memory
- at least 2 CPU cores / vCPUs

## Credits

I have made this script based on a blog post from *sadsloth* ([link](https://sadsloth.net/post/install-gvm11-src-on-debian/)) - **big thanks**  -, as well as the installation guidelines found in the various repositories from [greenbone](https://github.com/greenbone).
