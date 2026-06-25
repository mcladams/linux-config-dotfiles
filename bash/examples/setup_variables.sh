#!/usr/bin/env bash
#
#### extract for testing from
# bin_steam.sh - launcher script for Steam on Linux
#
# This is the Steam script that typically resides in /usr/bin
# It will create the Steam bootstrap if necessary and then launch steam.

# verbose
#set -x

######## record all current env var names
	ENVVARS="$(compgen -v | sort)"

set -e

# Get the full name of this script
STEAMSCRIPT="$(cd "${0%/*}" && echo "$PWD")/${0##*/}"
export STEAMSCRIPT
bootstrapscript="$(readlink -f "$STEAMSCRIPT")"
bootstrapdir="$(dirname "$bootstrapscript")"
log_opened=

log () {
    echo "bin_steam.sh[$$]: $*" >&2 || :
}

########
	echo "Testing us of log function with log dollar doublequote enclosed stuff"
	log $"STEAMSCRIPT is $STEAMSCRIPT \n PWD is $PWD \n \
	bootstrapscript is $bootstrapscript bootstrapdir is $bootstrapdir"

export STEAMSCRIPT_VERSION=1.0.0.82

# Set up domain for script localization
export TEXTDOMAIN=steam

function detect_platform()
{
	# Maybe be smarter someday
	# Right now this is the only platform we have a bootstrap for, so hard-code it.
	echo ubuntu12_32
}

function setup_variables()
{
	# 'steam' or sometimes 'steambeta'
	STEAMPACKAGE="${0##*/}"

	if [ "$STEAMPACKAGE" = bin_steam.sh ]; then
		STEAMPACKAGE=steam
	fi

	STEAMCONFIG=~/.steam
	# ~/.steam/steam or ~/.steam/steambeta
	STEAMDATALINK="$STEAMCONFIG/$STEAMPACKAGE"
	STEAMBOOTSTRAP=steam.sh
	# User-controlled, often ~/.local/share/Steam or ~/Steam
	LAUNCHSTEAMDIR="$(readlink -e -q "$STEAMDATALINK" || true)"
	# Normally 'ubuntu12_32'
	LAUNCHSTEAMPLATFORM="$(detect_platform)"
	# Often in /usr/lib/steam
	LAUNCHSTEAMBOOTSTRAPFILE="$bootstrapdir/bootstraplinux_$LAUNCHSTEAMPLATFORM.tar.xz"
	if [ ! -f "$LAUNCHSTEAMBOOTSTRAPFILE" ]; then
		LAUNCHSTEAMBOOTSTRAPFILE="/usr/lib/$STEAMPACKAGE/bootstraplinux_$LAUNCHSTEAMPLATFORM.tar.xz"
	fi

	# Get the default data path
	STEAM_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
	case "$STEAMPACKAGE" in
		steam)
			CLASSICSTEAMDIR="$HOME/Steam"
			DEFAULTSTEAMDIR="$STEAM_DATA_HOME/Steam"
			;;
		steambeta)
			CLASSICSTEAMDIR="$HOME/SteamBeta"
			DEFAULTSTEAMDIR="$STEAM_DATA_HOME/SteamBeta"
			;;
		*)
			log $"Unknown Steam package '$STEAMPACKAGE'"
			exit 1
			;;
	esac

	# Create the config directory if needed
	if [[ ! -d "$STEAMCONFIG" ]]; then
		mkdir "$STEAMCONFIG"
	fi

######## use comm to get uniques to new set of all vars
	FINALVARS="$(compgen -v | sort)"
	NEWVARS=$(comm -1 -3 <"ENVVARS" <"FINALVARS")
	for var in $NEWVARS; do printf "$var:\t\t${!var}"; done

}
setup_variables
