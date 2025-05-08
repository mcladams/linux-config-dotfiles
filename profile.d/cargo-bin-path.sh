# shellcheck shell=sh
# modified from ubuntu's apps-bin-path.sh

# Expand $PATH to include the directory where _snappy_ *cargo* applications go.

# if rust enstalled
if [ ! (printenv CARGO_HOME) ]; then
    cargo_bin_path = $(realpath $CARGO_HOME/bin
elif [ -f /usr/local/cargo/env ]; then
    set -a
    . "/usr/local/cargo/env"
    set +a
    carbon_bin_path=export CARGO_HOME="/usr/local/cargo"
  export RUSTUP_HOME="/usr/local/rustup"
fi



RUSTUP_HOME="/usr/local/rustup"
export RUSTUP_HOME
CARGO_HOME="/usr/local/cargo"
export CARGO_HOME
cargo_bin_path="/usr/local/cargo/bin"
if [ -n "${PATH##*${cargo_bin_path}}" ] && [ -n "${PATH##*${cargo_bin_path}:*}" ]; then
    export PATH="$PATH:${cargo_bin_path}"
fi

