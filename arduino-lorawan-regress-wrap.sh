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
#	RamaSubbu, MCCI	August 2021
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
    printf -- "--build-cache-path %s/%s\n" "$MCCI_BUILD_CACHE_PATH" "$(printf "%s" "$1" | tr -c -- -A-Za-z0-9_,=. _)"
}

# create option for setting build directory
#	$1: sketch name
function _builddir_opts {
    printf -- "--build-path %s/%s\n" "$MCCI_BUILD_PATH" "$(printf "%s" "$(basename "$1")" | tr -c -- -A-Za-z0-9_. _)"
}

# create option for scanning libraries
function _libopts {
    printf -- "--libraries %s\n" libraries
}

function _commonopts {
    true
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
    local BOARD
    BOARD="mcci:stm32:${1:-mcci_catena_4610}:opt=${3:-osstd},xserial=${4:-generic},upload_method=${6:-STLink},sysclk=${7:-pll32m}"
    _cacheopts "$BOARD"
    _libopts
    _commonopts
    echo -b "$BOARD,lorawan_region=${2:-us915}"
    echo --build-property recipe.hooks.objcopy.postobjcopy.1.pattern=true
}

# do a generic compile
function ci_arduino-lorawan_generic {
    local MCCI_RADIO MCCI_REGION MCCI_BOARD REGION_IS_USLIKE
    local MCCI_CI_FILTER_NAME
    for iSketch in "$@"; do
        declare -i SKETCH_IS_USLIKE=0
        declare -i REGION_IS_USLIKE=0
        if [[ "${iSketch/us915/}" != "${iSketch}" ]]; then
            SKETCH_IS_USLIKE=1
        fi
        MCCI_CI_FILTER_NAME="$(dirname "$iSketch")/extra/ci/arduino-lorawan-filter.sh"

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
                
                    if grep -q COMPILE_REGRESSION_TEST "${iSketch}"; then
                        _ci_compile "${iSketch}" $($GENOPTS "$MCCI_BOARD" projcfg) $(_builddir_opts "${iSketch}")
                        _ci_projcfg "${iSketch}" "CFG_$MCCI_REGION" "CFG_$MCCI_RADIO"
                        _ci_compile_fail "${iSketch}" $($GENOPTS "$MCCI_BOARD" projcfg) $(_builddir_opts "${iSketch}")
                    elif [[ $USE_PROJCFG -eq 0 && "$iRadio" != "sx1276" ]]; then
                        _ci_compile "${iSketch}" $($GENOPTS "$MCCI_BOARD" "$iRegion") $(_builddir_opts "${iSketch}")
                    else
                        _ci_compile "${iSketch}" $($GENOPTS "$MCCI_BOARD" projcfg) $(_builddir_opts "${iSketch}")
                    fi
                done
            done
        done
    done
}

function ci_samd {
    _boxcomment "SAMD"
    typeset -a MCCI_BOARDS=(mcci_catena_4450 mcci_catena_4410 mcci_catena_4420 mcci_catena_4460 mcci_catena_4470)
    typeset -a MCCI_REGIONS=(us915 eu868 au915 as923 as923jp kr920 in866)
    typeset -a MCCI_RADIOS=(sx1276)
    typeset GENOPTS=_samdopts
    ci_arduino-lorawan_generic "$@"
}

function ci_stm32 {
    _boxcomment "STM32"
    typeset -a MCCI_BOARDS=(mcci_catena_4610 mcci_catena_4612 mcci_catena_4618 mcci_catena_4630 mcci_catena_4801 mcci_catena_4802 )
    typeset -a MCCI_REGIONS=(us915 eu868 au915 as923 as923jp kr920 in866)
    typeset -a MCCI_RADIOS=(sx1276)
    typeset GENOPTS=_stm32l0opts
    ci_arduino-lorawan_generic "$@"
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
    typeset -a MCCI_EXAMPLES_BUILD
    typeset -gx MCCI_CI_ARCH="$1"
    typeset -a B_INDEX=(0 1 3 4 5)  
    j=0
    k=0

    # shellcheck disable=2207
    MCCI_EXAMPLES_ALL=($(_list_examples "$OPTLIBRARY"))

    # for group of sketch with uncontinuous index number (ex: 0, 1, 3, 4)
    _boxverbose "Examples:" "${MCCI_EXAMPLES_ALL[@]}" 
    for i in "${MCCI_EXAMPLES_ALL[@]}"; do
    	if [[ $j -le 4 ]] && [[ $k -eq ${B_INDEX[$j]} ]]; then
      	    MCCI_EXAMPLES_BUILD[$j]=$i
      	    j=$((j+1))
       fi
       k=$((k+1))
    done
  
     ci_"$1" "${MCCI_EXAMPLES_BUILD[@]}"

    # End
  
}

function _main {
    _init "$@"

    _setup_path
    _setup_arduino-lorawan libraries/arduino-lorawan
    _setup_arduino_cli
    for iArch in ${MCCI_ARDUINO_FQCNS[$OPTARCH]} ; do
        _setup_board_package "$iArch"
    done

    _compile "$OPTARCH"
    _ci_check_errors
}

_main "$@"
