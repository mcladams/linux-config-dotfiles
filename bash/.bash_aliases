#!/bin/bash

# Sourced by ~/.bashrc

# TO-DOs: by HUMANS or AGENTS
# FUNCTIONS: modify functions manage errors and align with policy below
    # functions must have an informative descriptive name (change the names!)
    # commonly used functions should have an acronym/abbreviated short alias additionally
    # functions must have a one or two line usage statement provided on user input error
    # sudo can be used programmatically in these functions as /etc/sudoers has 'mike ALL=(ALL) NOPASSWD: ALL'
    # refer safety notes for irreversible actions
# SAFETY: we are aiming to improve the safety of everything in this file within reason (complexity, breaks functionality)
    # These scripts will only be used by the sudo user uid=1000 'mike'
    # humans make errors so some safety mechanisms required
    # Any irreversible actions made safer BY:
        # Programmtic checks within the script for correct application
        # and/or a y/n prompt for the user to confirm before execution
        # and/or reqruires the user to pass -f | --force option passed
        # and/or should have a -n | --no-action | --dry-run option to simulate execution for user
        # and/or removing dangerous functions from automatic sourcing in .bash_aliases to a separate script
        # and/or take a zfs snapshot before the execution
# TODO-MIKE: zfs snapshot policy, rollback, automaticlly expiring temproary snaps

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
alias dua='du -cxhd1 --all -t20M'
dus() { du -xchd1 $@ | sort -h; }

#### other aliases
alias lsbo='lsblk -o name,size,type,fstype,label,partlabel,uuid,partuuid,mountpoints'

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
# TODO: rename descriptively and add comment as to when each should be used
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

# rs_os {
# turn this alias into a function for runnning a full system filesystem/clone of the **running** os
# check exlcusions for edge cases
alias rsyncos='rsync -haHAX --info=stats1,progress2 --modify-window=2 --exclude={"/dev/*","/proc/*","/sys/*","/run/*","/mnt/*","/media/*","/z*","/lost+found","/tmp/*","/cdrom","/boot/efi","/efi"}'
#

#### apt,dpkg,etc ####
deb2xz() {
    # TODO: move to .dotfiles/scripts or similar as part of homedir normalization project
    # debian 11 bullseye and earlier can only install xz compressed deb packaing, not zstd
    # this converts zstd comrpessed deb to xz, not really required in .bash_aliases anymore
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
    # provided with a list of block device lsblk knames and/or labels,mount them all to /media/(kname|label)
    # not sure if working 
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

alias zls='zfs list -o name,used,acltype,atime,overlay,canmount,mounted,mountpoint'

zlsm() {
# zfs list mount - list datasets with canmount=on and/or currently mounted
    zfs list -o name,used,referenced,canmount,mounted,mountpoint $@ | egrep -e ' on ' -e ' yes '
}

zlsz() {
# TODO ASAP EXTEND this script for ways to present zfs user properties from org.zfbootmenu and org.openzfs.systemd
# zfs list zsys - show zsys custom properties of datasets (fs,snap,all)
# zsys is deprecated, may be around on ubuntu 22.04 LTS and earlier so keep for now
 
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

# Unlock the GNOME login keyring manually from shell
# I can't remember why I needed this but keep it
# I think it was a manjaro distribution i put on an older laptop for someone with autologon
# and a mediasserver / guest user
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


alias zm='sudo mount -t zfs -o zfsutil'

zmp() {
    # test for dataset
    # zfs list -Ho name | grep -qFx "$1" && echo "Exists" || echo "Not found"
    # create mountpoint
    mkdir -p "$2"
    sudo mount -t zfs -o zfsutil "$1" "$2"
}
alias agi='/home/mike/.local/opt/Antigravity IDE/bin/antigravity-ide'
alias code='/home/mike/.local/opt/Antigravity IDE/bin/antigravity-ide'
