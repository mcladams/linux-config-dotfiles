#!/usr/bin/env bash
#
#### extract for testing from
# bin_steam.sh - launcher script for Steam on Linux
#
# This is the Steam script that typically resides in /usr/bin
# It will create the Steam bootstrap if necessary and then launch steam.

# verbose
#set -x

set -e

# Get the full name of this script
STEAMSCRIPT="$(cd "${0%/*}" && echo "$PWD")/${0##*/}"
export STEAMSCRIPT
bootstrapscript="$(readlink -f "$STEAMSCRIPT")"
bootstrapdir="$(dirname "$bootstrapscript")"
log_opened=
