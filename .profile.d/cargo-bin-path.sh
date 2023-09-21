# shellcheck shell=sh
# modified from ubuntu's apps-bin-path.sh

# Expand $PATH to include the directory where snappy applications go.
RUSTUP_HOME="/usr/local/rustup"
export RUSTUP_HOME
CARGO_HOME="/usr/local/cargo"
export CARGO_HOME
cargo_bin_path="/usr/local/cargo/bin"
if [ -n "${PATH##*${cargo_bin_path}}" ] && [ -n "${PATH##*${cargo_bin_path}:*}" ]; then
    export PATH="$PATH:${cargo_bin_path}"
fi

# Ensure base distro defaults xdg path are set if nothing filed up some
# defaults yet.
#if [ -z "$XDG_DATA_DIRS" ]; then
#    export XDG_DATA_DIRS="/usr/local/share:/usr/share"
#$fi
#
# Desktop files (used by desktop environments within both X11 and Wayland) are
# looked for in XDG_DATA_DIRS; make sure it includes the relevant directory for
# snappy applications' desktop files.
#snap_xdg_path="/var/lib/snapd/desktop"
#if [ -n "${XDG_DATA_DIRS##*${snap_xdg_path}}" ] && [ -n "${XDG_DATA_DIRS##*${snap_xdg_path}:*}" ]; then
#    export XDG_DATA_DIRS="${XDG_DATA_DIRS}:${snap_xdg_path}"
#fi

