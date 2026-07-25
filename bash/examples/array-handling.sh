# arrayops.bash --- hide some of the nasty syntax for manipulating bash arrays
# Author: Noah Friedman <friedman@splode.com>
# Created: 2016-07-08
# Public domain

# $Id: arrayops.bash,v 1.3 2016/07/28 15:38:55 friedman Exp $

# Commentary:

# These functions try to tame the syntactic nightmare that is bash array
# syntax, which makes perl's almost look reasonable.
#
# For example the apush function below lets you write:
#
#	apush arrayvar newval
#
# instead of
#
#	${arrayvar[${#arrayvar[@]}]}=newval
#
# Because seriously, you've got to be kidding me.

# These functions avoid the use of local variables as much as possible
# (especially wherever modification occurs) because those variable names
# might shadow the array name passed in.  Dynamic scope!

# Code:

#:docstring apush:
# Usage: apush arrayname val1 {val2 {...}}
#
# Appends VAL1 and any remaining arguments to the end of the array
# ARRAYNAME as new elements.
#:end docstring:
apush()
{
    eval "$1=(\"\${$1[@]}\" \"\${@:2}\")"
}

#:docstring apop:
# Usage: apop arrayname {n}
#
# Removes the last element from ARRAYNAME.
# Optional argument N means remove the last N elements.
#:end docstring:
apop()
{
    eval "$1=(\"\${$1[@]:0:\${#$1[@]}-${2-1}}\")"
}

#:docstring aunshift:
# Usage: aunshift arrayname val1 {val2 {...}}
#
# Prepends VAL1 and any remaining arguments to the beginning of the array
# ARRAYNAME as new elements.  The new elements will appear in the same order
# as given to this function, rather than inserting them one at a time.
#
# For example:
#
#	foo=(a b c)
#	aunshift foo 1 2 3
#       => foo is now (1 2 3 a b c)
# but
#
#	foo=(a b c)
#	aunshift foo 1
#       aunshift foo 2
#       aunshift foo 3
#       => foo is now (3 2 1 a b c)
#
#:end docstring:
aunshift()
{
    eval "$1=(\"\${@:2}\" \"\${$1[@]}\")"
}

#:docstring ashift:
# Usage: ashift arrayname {n}
#
# Removes the first element from ARRAYNAME.
# Optional argument N means remove the first N elements.
#:end docstring:
ashift()
{
    eval "$1=(\"\${$1[@]: -\${#$1[@]}+${2-1}}\")"
}

#:docstring aset:
# Usage: aset arrayname idx newval
#
# Assigns ARRAYNAME[IDX]=NEWVAL
#:end docstring:
aset()
{
    eval "$1[\$2]=${@:3}"
}

#:docstring aref:
# Usage: aref arrayname idx {idx2 {...}}
#
# Echoes the value of ARRAYNAME at index IDX to stdout.
# If more than one IDX is specified, each one is echoed.
#
# Unfortunately bash functions cannot return arbitrary values in the usual way.
#:end docstring:
aref()
{
    eval local "v=(\"\${$1[@]}\")"
    local x
    for x in ${@:2} ; do echo "${v[$x]}"; done
}

#:docstring aref:
# Usage: alen arrayname
#
# Echoes the length of the number of elements in ARRAYNAME.
#
# It also returns number as a numeric value, but return values are limited
# by a maximum of 255 so don't rely on this unless you know your arrays are
# relatively small.
#:end docstring:
alen()
{
    eval echo   "\${#$1[@]}"
    eval return "\${#$1[@]}"
}

#:docstring anreverse:
# Usage: anreverse arrayname
#
# Reverse the order of the elements in ARRAYNAME.
# The array variable is altered by this operation.
#:end docstring:
anreverse()
{
    eval set $1 "\"\${$1[@]}\""
    eval unset $1
    while [ $# -gt 1 ]; do
        eval "$1=(\"$2\" \"\${$1[@]}\")"
        set $1 "${@:3}"
    done
}

#provide arrayops

# arrayops.bash ends here
#
#  Chet Ramey <chet.ramey@case.edu>
#
#  Copyright 1999 Chester Ramey
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2, or (at your option)
#   any later version.
#
#   TThis program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software Foundation,
#   Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

# usage: reverse arrayname
reverse()
{
	local -a R
	local -i i
	local rlen temp

	# make r a copy of the array whose name is passed as an arg
	eval R=\( \"\$\{$1\[@\]\}\" \)

	# reverse R
	rlen=${#R[@]}

	for ((i=0; i < rlen/2; i++ ))
	do
		temp=${R[i]}
		R[i]=${R[rlen-i-1]}
		R[rlen-i-1]=$temp
	done

	# and assign R back to array whose name is passed as an arg
	eval $1=\( \"\$\{R\[@\]\}\" \)
}

A=(1 2 3 4 5 6 7)
echo "${A[@]}"
reverse A
echo "${A[@]}"
reverse A
echo "${A[@]}"

# unset last element of A
alen=${#A[@]}
unset A[$alen-1]
echo "${A[@]}"

# ashift -- like shift, but for arrays

ashift()
{
	local -a R
	local n

	case $# in
	1)	n=1 ;;
	2)	n=$2 ;;
	*)	echo "$FUNCNAME: usage: $FUNCNAME array [count]" >&2
		exit 2;;
	esac

	# make r a copy of the array whose name is passed as an arg
	eval R=\( \"\$\{$1\[@\]\}\" \)

	# shift R
	R=( "${R[@]:$n}" )

	# and assign R back to array whose name is passed as an arg
	eval $1=\( \"\$\{R\[@\]\}\" \)
}

ashift A 2
echo "${A[@]}"

ashift A
echo "${A[@]}"

ashift A 7
echo "${A[@]}"

# Sort the members of the array whose name is passed as the first non-option
# arg.  If -u is the first arg, remove duplicate array members.
array_sort()
{
	local -a R
	local u

	case "$1" in
	-u)	u=-u ; shift ;;
	esac

	if [ $# -eq 0 ]; then
		echo "array_sort: argument expected" >&2
		return 1
	fi

	# make r a copy of the array whose name is passed as an arg
	eval R=\( \"\$\{$1\[@\]\}\" \)

	# sort R
	R=( $( printf "%s\n" "${A[@]}" | sort $u) )

	# and assign R back to array whose name is passed as an arg
	eval $1=\( \"\$\{R\[@\]\}\" \)
	return 0
}

A=(3 1 4 1 5 9 2 6 5 3 2)
array_sort A
echo "${A[@]}"

A=(3 1 4 1 5 9 2 6 5 3 2)
array_sort -u A
echo "${A[@]}"
#! /bin/bash

# Format: array_to_string vname_of_array vname_of_string separator
array_to_string()
{
	(( ($# < 2) || ($# > 3) )) && {
		 "$FUNCNAME: usage: $FUNCNAME arrayname stringname [separator]"
		return 2
	}

	local array=$1 string=$2
	((3==$#)) && [[ $3 = ? ]] && local IFS="${3}${IFS}"
	eval $string="\"\${$array[*]}\""
	return 0
}
