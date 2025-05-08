#!/bin/bash

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.
#
#if [ -f ~/.bash_aliases ]; then
#    . ~/.bash_aliases
#fi

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias dir='dir --color=auto'
    alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# some more ls aliases
alias ll='ls -Al'
alias la='ls -A'
alias l='ls -CF'

#### disk usage ####
alias du1='du -cxhd1'
alias du5='du -cxhd1 --all -t20M'

#### other aliases
alias lsb='lsblk -o name,size,type,partlabel,fstype,label,mountpoint'
alias lsbu='lsblk -o name,size,fstype,label,uuid,mountpoint'
alias lsbp='lsblk -o name,size,fstype,label,partuuid,mountpoint'
alias lsbup='lsblk -o name,size,fstype,label,uuid,kname,type,partuuid'

#### general functions
# list user functions defined
# alternatively 'compgen -A function'
alias flist='declare -F |cut -d" " -f3 | egrep -v "^_"'
alias fdef='declare -f'

lsiommu() {
# lsiommu: list members of iommu groups
    shopt -s nullglob
    for g in $(find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V); do
        echo "IOMMU Group ${g##*/}:"
        for d in $g/devices/*; do
            echo -e "\t$(lspci -nns ${d##*/})"
        done;
    done;
    shopt -u nullglob
}

pname_abs() {
# pn_abs: get absolute pathname(s) from relative
    if [ ! -a $1 ]; then
        echo '"'$1'"' was not found.
        return
    fi
    pathname=$(readlink -f $1)
    filename=${pathname##*/}
    path=${pathname%/*}
    #echo $path $filename $pathname
    echo $pathname
}

#### rsync ####
rs_cp() {
# copy-overwrite dest if different regardless
    rsync -hh --info=stats1,progress2 --modify-window=2 -aHAX "$@"
}

rs_up() {
# copy-update do not overwrite newer on dest
    rsync -hh --info=stats1,progress2 --modify-window=2 -aHAX --update "$@"
}

rs_mir() {
# copy-clone by removing extra dest files
    rsync -hh --info=stats1,progress2 --modify-window=2 -aHAX --delete "$@"
}

rs_mv() {
# move by removing source files
    rsync -hh --info=stats1,progress2 --modify-window=2 -aHAX --remove-source-files "$@"
}

#rs_sys { #full system filesystem backup
#
#

#### apt,dpkg,etc ####
deb2xz() {
    set -e
    pkges="$@"
    for pkg in $pkges; do
        if [ ! "${pkg##*.}" = "deb" ] || [ ! -f $pkg ]; then
            echo '"'$pkg'"' is not a file or does not end in .deb
            continue
        elif grep -q "control.tar.xz" <<< $files; then
            echo '"'$pkg'"' is already in tar.xz format, not touching it.
            continue
        fi
        pathname=$(readlink -f $pkg)
        path=${pathname%/*}
        filename=${pathname##*/}
        pkgname=${filename%.*}
        # do it in a tmp dir
        mkdir /tmp/$pkgname
        pushd /tmp/$pkgname
        ar -x $pathname
        zstd -d < control.tar.zst | xz > control.tar.xz
        zstd -d < data.tar.zst | xz > data.tar.xz
        mv $pathname /tmp/$filename
        ar -m -c -a sdsd $pathname debian-binary control.tar.xz data.tar.xz
        popd
    done
    echo "Done. Original debs move to /tmp"
}


mnta() {
    for arg in $@; do
        if grep -q "$arg" <<< $(lsblk -n -o label); then
            #argnospace=$(echo "$arg" | sed 's/[ ]/\-/g')
            mkdir -p /media/mnt/$argnospace
            mount LABEL="$arg" /media/mnt/$argnospace
        elif grep -q ${arg##*/} <<< $(lsblk -n -o kname); then
            kdev=${arg##*/}
            mkdir -p /media/mnt/$kdev
            mount /dev/$kdev /media/mnt/$kdev
        else
            echo "$arg" neither a label nor a device name, not mounted
        fi
    done
}

#### zfs list,mount,move ####

alias zls='zfs list -o name,used,referenced,canmount,mounted,mountpoint'

zlsm() {
# zfs list mount - list datasets with canmount=on and/or currently mounted
    zfs list -o name,used,referenced,canmount,mounted,mountpoint $@ | egrep -e ' on ' -e ' yes '
}

zlsz() {
# zfs list zsys - show zsys custom properties of datasets (fs,snap,all)
    if [ "$1" = "-t" ]; then
        type="$2"
        shift 2
    else
        type="filesystem"
    fi
    if [ "$1" = "-r" ]; then
        recurs="-r"
        shift 1
    fi
    zfs get $recurs -o name,property,value -t $type all "$@" | egrep -e 'com\.ubuntu\.zsys'
}


#### repace spaces with underscore ####
underscore() {
#    if [ $1 ]; then maxd=$1; else maxd=20; fi
    for i in {1..18}; do
        find ./ -mindepth $i -maxdepth $i -regex '.*[ ].*' -print0 | xargs -0 sed 's/[ ]/_/g'
    done
}

alias zsnap_large='zfs list -o used,name -t snapshot | sort -h | tail'
alias conf='/usr/bin/git --git-dir=$HOME/.conf.git --work-tree=$HOME'

# ~/.bash_aliases or ~/.bashrc
# Unlock the GNOME login keyring manually from shell

unlock-keyring() {
    local SCRIPT_PATH="$HOME/bin/unlock.py"

    if [[ ! -x "$SCRIPT_PATH" ]]; then
        echo "Error: $SCRIPT_PATH not found or not executable."
        return 1
    fi

    if ! pgrep -u "$USER" gnome-keyring-daemon > /dev/null; then
        echo "Warning: gnome-keyring-daemon does not appear to be running." >&2
    fi

    echo -n "Enter keyring password: "
    read -rs KEYRING_PASSWORD
    echo

    echo "$KEYRING_PASSWORD" | "$SCRIPT_PATH"
    local status=$?

    if [[ $status -eq 0 ]]; then
        echo "✅ Keyring unlocked successfully."
    else
        echo "❌ Failed to unlock keyring. Check password or session state."
    fi

    unset KEYRING_PASSWORD
}
alias cps='cp -a --reflink=auto --backup=simple --update=older'
