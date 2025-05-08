# Check for interactive bash 
if [ -n "${BASH_VERSION-}" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        PS1='${debian_chroot:+($debian_chroot)}\[\033[01;31m\]\u\[\033[00m\]@\h:\w\$ '
    fi
fi
