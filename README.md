# gvm-install-script

An *unofficial* script to install GVM alias OpenVAS on debian (10).
**This is currently WORK IN PROGRESS**

This script installs GVM, alias OpenVAS, on a debian system of version 10 (buster). It is not made for docker, but VMs and bare metal deployments. It does not configure any of the components, nor the system to be secure or production ready.

## Usage

Set the following environment variables as for your need.

- `GVM_INSTALL_PREFIX`: Path to the gvm user directory. (default = */var/opt/gvm*)
- `GVM_VERSION`: GVM version to install. (example = *20.08*)
- `GVM_ADMIN_PWD`: Initial admin password. (default = *admin*)

```bash
$ export GVM_VERSION=20.08
$ ./install.sh
```

I would recommend to run this inside a *screen* session, and specify a logfile.

## Requirements

- debian 10 installation
- internet access
- shell (SSH) on the target system
- user with *sudo* permissions
- at least ~10GB disk storage (my test VM used 9.8GB after all)
- at least 4GB of memory

## Credits

I have made this script based on a blog post from *sadsloth* ([link](https://sadsloth.net/post/install-gvm11-src-on-debian/)) - **big thanks**  -, as well as the installation guidelines found in the various repositories from [greenbone](https://github.com/greenbone).
