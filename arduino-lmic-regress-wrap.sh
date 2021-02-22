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
	if [[ $OPTDEBUG -ne 0 ]]; then
		set -x
	fi
}

##############################################################################
# library
##############################################################################

# create option for storing core.a
#	$1: fqbn with config options
#
function _cacheopts {
	printf "--build-cache-path %s/%s\n" "$MCCI_BUILD_CACHE_PATH" "$(printf "%s" "$1" | tr -c -- -A-Za-z0-9_,=. _)"
}

# create option for setting build directory
#	$1: sketch name
function _builddir_opts {
	printf "--build-cache-path %s/%s\n" "$MCCI_BUILD_PATH" "$(printf "%s" "$(basename "$1")" | tr -c -- -A-Za-z0-9_. _)"
}

# create option for scanning libraries
function _libopts {
	printf "--libraries %s\n" libraries
}

function _commonopts {
	true
}

# put options into the project config file.
function _projcfg {
	{
	printf "%s\n" "/* generated by arduino-regress.sh */"
	for i in "$@" ; do
		# we depend on re-parsing of unquoted results; splitdef will give us two fields.
		# shellcheck disable=2183,2046
		printf '#define %s %s\n' $(_splitdef "$i")
	done
	}  > "$MCCI_LMIC_PATH"/project_config/lmic_project_config.h
}

# set up project config file for class A device, and also include any
# other config items from args.
function _projcfg_class_a {
	_projcfg "$@" "DISABLE_PING" "DISABLE_BEACONS"
}

# usage: _samdopts BOARD REGION
function _samdopts {
	local BOARD
	BOARD="mcci:samd:${1:-mcci_catena_4450}"
	_cacheopts "$BOARD"
	_libopts
	_commonopts
	echo -b "$BOARD:lorawan_region=${2:-us915}" 
}

# usage: _stm32l0opts BOARD REGION opt xserial upload sysclk
function _stm32l0opts {
	local BOARD="mcci:stm32:${1:-mcci_catena_4610}:opt=${3:-osstd},xserial=${4:-generic},upload_method=${6:-STLink},sysclk=${7:-pll32m}"
	_cacheopts "$BOARD"
	_libopts
	_commonopts
	echo -b "$BOARD"
	echo --build-property recipe.hooks.objcopy.postobjcopy.1.pattern=true
}

# usage: _avropts BOARD
function _avropts {
	local BOARD
	BOARD=adafruit:avr:${1:-feather32u4}
	_cacheopts "$BOARD"
	_libopts
	_commonopts
	echo -b "$BOARD"
}

# usage: _esp32opts BOARD
function _esp32opts {
	local BOARD
	BOARD="esp32:esp32:${1:-heltec_wifi_lora_32}:FlashFreq=80"
	_cacheopts "$BOARD"
	_libopts
	_commonopts
	echo -b "$BOARD"
}

function ci_lmic_generic {
    local MCCI_RADIO MCCI_REGION MCCI_BOARD REGION_IS_USLIKE
    local SKETCH_IS_USLIKE REGION_IS_USLIKE SKETCH_HAS_LMIC_FILTER
	for iSketch in "$@"; do
	    declare -i SKETCH_IS_USLIKE=0
	    declare -i REGION_IS_USLIKE=0
        declare -i SKETCH_HAS_LMIC_FILTER=0
	    if [[ "${iSketch/us915/}" != "${iSketch}" ]]; then
	    	SKETCH_IS_USLIKE=1
	    fi
        if [[ -f "$(dirname "$iSketch")/ci/lmic-filter.sh" ]]; then
            SKETCH_HAS_LMIC_FILTER=1
            # shellcheck disable=1090
            source "$(dirname "$iSketch")/ci/lmic-filter.sh"
        fi

        for iRadio in "${MCCI_RADIOS[@]}"; do
            for iBoard in "${MCCI_BOARDS[@]}"; do
                for iRegion in "${MCCI_REGIONS[@]}" ; do
                    declare -i REGION_IS_USLIKE=0
                    case "${iRegion}" in
                        us915 | au915) REGION_IS_USLIKE=1;;
                    esac
                    if [[ ${SKETCH_IS_USLIKE} -ne 0 ]] && [[ ${REGION_IS_USLIKE} -eq 0 ]] ; then
                        continue
                    fi
                    MCCI_RADIO="${iRadio}"
                    MCCI_REGION="${iRegion}"
                    MCCI_BOARD="${iBoard}"
                    if [[ $SKETCH_HAS_LMIC_FILTER -ne 0 ]]; then
                        if _lmic_filter skip "$iSketch"; then
                            continue
                        fi
                    fi
                    if grep -q COMPILE_REGRESSION_TEST "${iSketch}"; then
                        _projcfg COMPILE_REGRESSION_TEST "CFG_$iRegion" "CFG_$MCCI_RADIO"
                        _ci_compile "${iSketch}" $($GENOPTS "$MCCI_BOARD" projcfg) $(_builddir_opts "${iSketch}")
                        _projcfg "CFG_$MCCI_REGION" "CFG_$MCCI_RADIO"
                        _ci_compile_fail "${iSketch}" $($GENOPTS "$MCCI_BOARD" projcfg) $(_builddir_opts "${iSketch}")
                    elif [[ $MCCI_USE_PROJCFG -eq 0 && "$iRadio" != "sx1276" ]]; then
                        _ci_compile "${iSketch}" $($GENOPTS "$MCCI_BOARD" "$iRegion") $(_builddir_opts "${iSketch}")
                    else
                        _projcfg "CFG_$MCCI_REGION" "CFG_$MCCI_RADIO"
                        _ci_compile "${iSketch}" $($GENOPTS "$MCCI_BOARD" projcfg) $(_builddir_opts "${iSketch}")
                    fi
                done
            done
        done
	done
}

function ci_samd {
	_boxcomment "SAMD"
	local MCCI_BOARDS MCCI_REGIONS MCCI_RADIOS MCCI_USE_PROJCFG
	declare -ri MCCI_USE_PROJCFG=0
	typeset -a MCCI_BOARDS=(mcci_catena_4450 mcci_catena_4410 mcci_catena_4420 mcci_catena_4460 mcci_catena_4470)
	typeset -a MCCI_REGIONS=(us915 eu868 au915 as923 as923jp kr920 in866)
	typeset -a MCCI_RADIOS=(sx1276)
	typeset GENOPTS=_samdopts
	ci_lmic_generic "$@"
}

function ci_stm32 {
	_boxcomment "STM32"
	local MCCI_BOARDS MCCI_REGIONS MCCI_RADIOS MCCI_USE_PROJCFG
	declare -ri MCCI_USE_PROJCFG=0
	typeset -a MCCI_BOARDS=(mcci_catena_4610 mcci_catena_4612 mcci_catena_4618 mcci_catena_4630 mcci_catena_4801 mcci_catena_4802)
	typeset -a MCCI_REGIONS=(us915 eu868 au915 as923 as923jp kr920 in866)
	typeset -a MCCI_RADIOS=(sx1276)
	typeset GENOPTS=_samdopts
	ci_lmic_generic "$@"
}

function ci_esp32 {
	_boxcomment "ESP32"
	local MCCI_BOARDS MCCI_REGIONS MCCI_RADIOS MCCI_USE_PROJCFG
	declare -ri MCCI_USE_PROJCFG=1
	typeset -a MCCI_BOARDS=(heltec_wifi_lora_32)
	typeset -a MCCI_REGIONS=(us915 eu868 au915 as923 as923jp kr920 in866)
	typeset -a MCCI_RADIOS=(sx1276)
	typeset GENOPTS=_esp32opts
	ci_lmic_generic "${MCCI_EXAMPLES_ALL[@]}"
}

function ci_avr {
	_boxcomment "AVR 32u4"
	local MCCI_BOARDS MCCI_REGIONS MCCI_RADIOS MCCI_USE_PROJCFG
	declare -ri MCCI_USE_PROJCFG=1
	typeset -a MCCI_BOARDS=(feather32u4)
	typeset -a MCCI_REGIONS=(us915 eu868 au915 as923 as923jp kr920 in866)
	typeset -a MCCI_RADIOS=(sx1276 sx1272)
	typeset GENOPTS=_avropts
	ci_lmic_generic "${MCCI_EXAMPLES_ALL[@]}"
}


function _init {
	set -e

	# shellcheck source=./common-init.sh
	source "$MCCI_PDIR"/common-init.sh
	_setup_env

	_getargs "$@"
}

function _compile {
	typeset -a MCCI_EXAMPLES_ALL
	# shellcheck disable=2207
	MCCI_EXAMPLES_ALL=($(_list_examples "$OPTLIBRARY"))

	_boxverbose "Examples:" "${MCCI_EXAMPLES_ALL[@]}"

	ci_"$1" "${MCCI_EXAMPLES_ALL[@]}"
}

function _main {
	_init "$@"

	_setup_path
	_setup_lmic libraries/arduino-lmic
	_setup_arduino_cli
	for iArch in ${MCCI_ARDUINO_FQCNS[$OPTARCH]} ; do
		_setup_board_package "$iArch"
	done

	_compile "$OPTARCH"
}

_main "$@"
