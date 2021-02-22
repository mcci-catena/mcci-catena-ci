#!/bin/bash

##############################################################################
#
# Module: setup.sh
#
# Function:
#	Set up workspace for CI testing
#
# Copyright and License:
#	See accompanying LICENSE.md file
#
# Author:
#	Terry Moore, MCCI	February 2021
#
##############################################################################

MCCI_PNAME="$(basename "$0")"
MCCI_PDIR="$(dirname "$0")"
declare -r MCCI_PNAME MCCI_PDIR

declare -i OPTDEBUG OPTVERBOSE
OPTDEBUG=0
OPTVERBOSE=0
OPTARCH=
OPTLIBRARY=

##############################################################################
# output
##############################################################################

function _verbose {
	if [ "$OPTVERBOSE" -ne 0 ]; then
		echo "$MCCI_PNAME:" "$@" 1>&2
	fi
}

function _debug {
	if [ "$OPTDEBUG" -ne 0 ]; then
		echo "$@" 1>&2
	fi
}

#### _error: define a function that will echo an error message to STDERR.
#### using "$@" ensures proper handling of quoting.
function _error {
	echo "$@" 1>&2
}

#### _fatal: print an error message and then exit the script.
function _fatal {
	_error "$@" ; exit 1
}

##############################################################################
# args
##############################################################################


function _getargs {
	local OPT NEXTBOOL
	typeset -i NEXTBOOL

	NEXTBOOL=1
	function _usage {
		echo "$MCCI_PNAME: usage: -a {arch} -l {library}"
	}
	while getopts a:Dl:v OPT
	do
		# postcondition: NEXTBOOL=0 iff previous option was -n
		# in all other cases, NEXTBOOL=1
		if [ $NEXTBOOL -eq -1 ]; then
			NEXTBOOL=0
		else
			NEXTBOOL=1
		fi

		case "$OPT" in
		D)	OPTDEBUG=$NEXTBOOL;;
		v)	OPTVERBOSE=$NEXTBOOL;;
		a)	OPTARCH="$OPTARG"
			_debug "OPTARCH: $OPTARCH"
			if [[ $OPTDEBUG -ne 0 ]]; then
				declare -p MCCI_ARDUINO_FQCNS
			fi
			if [[ -z "${MCCI_ARDUINO_FQCNS[$OPTARCH]}" ]]; then
				_fatal "Unknown arch: $OPTARG"
			fi
			;;
		l)	OPTLIBRARY="$OPTARG"
			if [[ ! -d "$OPTLIBRARY" ]]; then
				_fatal "Library path error: $OPTLIBRARY"
			fi
			;;
		*)	_usage
			exit 1
		esac
	done

	if [[ -z "$OPTARCH" ]]; then
		_fatal "-a not supplied"
	fi
	if [[ -z "$OPTLIBRARY" ]]; then
		_fatal "-l not supplied"
	fi
}

function _init {
	set -e

	# shellcheck source=./common-init.sh
	source "$MCCI_PDIR"/common-init.sh
	_setup_env

	_getargs "$@"
}

function _main {
	_init "$@"

	_setup_path
	_setup_cli
	for iArch in ${MCCI_ARDUINO_FQCNS[$OPTARCH]} ; do
		_setup_board_package "$iArch"
	done
	if [[ $OPTVERBOSE != 0 ]]; then
		_boxcomment "successful completion"
	fi
}

_main "$@"
