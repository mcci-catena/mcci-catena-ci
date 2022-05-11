#!/bin/bash

##############################################################################
#
# Module: common-init.sh
#
# Function:
#	This script must be sourced; it sets variables used by other
#	scripts in this directory.
#
# Usage:
#	source common-init.sh
#
# Copyright and License:
#	See accompanying LICENSE.md file
#
# Author:
#	Terry Moore, MCCI	February 2021
#
##############################################################################

#### Capture the file path ####
MCCI_THISFILE="$0"

function _error {
    if [[ -z "$CI" ]]; then
        echo "$@" 1>&2
    else
        #
        # we really want MCCI_PNAME not to be quoted, so it will vanish if undefined,
        # causing the printf to produce nothing, and then causing awk to product nothing.
        #
        # shellcheck disable=2086
        echo "::error $(printf "%s" ${MCCI_PNAME} | awk '{printf("file=%s", $0)}')::$(caller 0 | awk '{printf("%s:", $2); }'): $*"
    fi
}

# display error and exit
function _fatal {
    _error "$@"
    exit 1
}

function _assert_setup_env {
    if [[ ${MCCI_ENV_SETUP_COMPLETE:-0} == 0 ]]; then
        _fatal "_setup_env not called yet"
    fi
}

#### Setup env vars ####
function _setup_env {
    # MCCI_TOP is the pointer to the top level dir, assumed to be one above here
    declare -gx MCCI_TOP
    if [ X"$CI" != X1 ]; then
        # no CI; use parent dir
        MCCI_TOP="$(realpath "$(dirname "$MCCI_THISFILE")/..")"
    else
        # CI: use GITHUB_WORKSPACE
        MCCI_TOP="${GITHUB_WORKSPACE:?CI defined but GITHUB_WORKSPACE is not defined}"
    fi

    # setup MCCI_LMIC_PATH - initially empty
    declare -gx MCCI_LMIC_PATH

    # MCCI_ADDITIONAL_URLS specifies paths to board files
    declare -gx MCCI_ADDITIONAL_URLS
    MCCI_ADDITIONAL_URLS="https://github.com/mcci-catena/arduino-boards/raw/master/BoardManagerFiles/package_mcci_index.json,https://adafruit.github.io/arduino-board-index/package_adafruit_index.json,https://dl.espressif.com/dl/package_esp32_index.json"

    # make sure there's a build cache dir
    declare -gx MCCI_BUILD_CACHE_PATH
    MCCI_BUILD_CACHE_PATH="$MCCI_TOP/.core"
    if [[ ! -d "$MCCI_BUILD_CACHE_PATH" ]]; then
        rm -rf "$MCCI_BUILD_CACHE_PATH"
        mkdir "$MCCI_BUILD_CACHE_PATH"
    fi

    # make sure there's a build dir
    declare -gx MCCI_BUILD_PATH
    MCCI_BUILD_PATH="$MCCI_TOP/.build"
    if [[ ! -d "$MCCI_BUILD_PATH" ]]; then
        rm -rf "$MCCI_BUILD_PATH"
        mkdir "$MCCI_BUILD_PATH"
    fi

    # MCCI_ERRORS is an array of error messages
    declare -ga MCCI_ERRORS
    trap 'printf "%s\n" "${MCCI_ERRORS[@]}"' 0

    # MCCI_ARDUINO_FQCNS is an array of fully-qualified core names
    declare -gA MCCI_ARDUINO_FQCNS
    MCCI_ARDUINO_FQCNS=(
        [samd]=mcci:samd
        [stm32]=mcci:stm32
        [avr]="arduino:avr adafruit:avr"
        [esp32]="esp32:esp32"
        )

    # record that we've completed init.
    declare -gri MCCI_ENV_SETUP_COMPLETE=1
}

function _setup_path {
    _assert_setup_env
    if [ ! -d "${MCCI_TOP}/bin" ]; then
        mkdir "${MCCI_TOP}/bin"
    fi

    PATH="$PATH:${MCCI_TOP}/bin"
}

#### set up the Arduino-CLI ####
function _setup_arduino_cli {
    _assert_setup_env
    if [[ ! -x "${MCCI_TOP}/bin/arduino-cli" ]] ; then
        curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | BINDIR="${MCCI_TOP}"/bin sh
        arduino-cli config init
    fi
    # change each , in MCCI_ADDITIONAL_URLS to a space, then set the CLI defaults.
    arduino-cli config set board_manager.additional_urls ${MCCI_ADDITIONAL_URLS//,/ }
}

#### set up a board package: $1 is fqbn
function _setup_board_package {
    _assert_setup_env
    local CORE FIRST
    declare -i FIRST
    FIRST=0
    CORE=
    CORE="$(arduino-cli core list | awk 'NR>1 {print $1}' | grep "^$1"'$')" || { FIRST=1 ; true ; }
    if [[ -z "$CORE" ]]; then
        arduino-cli core install "$@"
        if [[ "$1" = "esp32:esp32" && $FIRST -ne 0 ]]; then
            # gotta have python3 and pip3, but that's in base.
            sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 1
            python3 -m pip install -U pip
            pip3 install setuptools
            pip3 install pyserial
            pip3 install esptool
        fi
    fi
}


#### set up the Catena-Arduino-Platform: $1 is path
function _setup_Catena-Arduino-Platform {
    _assert_setup_env
    }
    
#### set up the arduino-lorawan: $1 is path
function _setup_arduino-lorawan {
    _assert_setup_env
    }    

#### set up the lmic: $1 is path
function _setup_lmic {
    _assert_setup_env
    if [[ ! -d "$1/project_config" ]]; then
        _fatal "$1 doesn't look like an arduino-lmic directory"
    fi
    declare -gx MCCI_LMIC_PATH
    MCCI_LMIC_PATH="$1"
}

# log a compile error message
function _ci_error {
    local MESSAGE
    MESSAGE="$(basename "$1" .ino) for board ${MCCI_BOARD} region ${MCCI_REGION} radio ${MCCI_RADIO}: $2"
    # put it into the log now, along with the project config.
    echo "Error: $MESSAGE"
    _boxcomment lmic_project_config.h
    cat "$MCCI_LMIC_PATH/project_config/lmic_project_config.h"
    # and save it for the summary
    MCCI_ERRORS+=("::error::$MESSAGE")
}

# return non-zero if any errors have been logged
function _ci_check_errors {
    return $(( ${#MCCI_ERRORS[*]} != 0 ))
}

#### print a comment in a box, so you can find thigns in a log ####
function _boxcomment {
    printf "%s\n" "$@" | fmt | awk '
    {
        if (maxlen < length($0)) {
            maxlen = length($0)
        }
        lines[nlines++] = $0;
    }
    function repeat(s, n	, result, i) {
        result = "";
        for (i = 0; i < n; ++i) {
            result = result s;
        }
        return result;
    }
    END	{
        mark = repeat("#", maxlen + 4);
        printf("%s\n", mark);
        for (i = 0; i < nlines; ++i) {
            printf("# %-" maxlen "s #\n", lines[i]);
        }
        printf("%s\n", mark);
    }'
}

function _boxverbose {
    if [[ $OPTVERBOSE -ne 0 ]]; then
        _boxcomment "$@"
    fi
}

# split up a word that might be FOO=value or FOO, and output
# FOO value or FOO 1, respectively. Remove anything that's not
# legal C, and make sure it's not empty. Stuff _EMPTY_ in the
# first arg if empty. Stuff 1 in the second arg if empty.
function _splitdef {
    local VAR VNAME VAL
    VAR="$(echo "$1" | tr -cd A-Za-z0-9_=)"
    if [[ "$VAR" = "${VAR/=/}" ]]; then
        echo "${VAR:-_EMPTY_}" 1
    else
        VNAME="${VAR%%=*}"
        VAL="${VAR#*=}"
        echo "${VNAME:-_EMPTY_}" "${VAL:-1}"
    fi
}

# do a compile
#
# arguments:
#	$1	sketch
#	$2..	args to arduino-cli
function _ci_compile {
    local MCCI_SKETCH
    MCCI_SKETCH="$1"
    shift
    echo "::group::Compile ${MCCI_SKETCH} ${MCCI_BOARD} ${MCCI_REGION} ${MCCI_RADIO}"
    echo "arduino-cli compile" "$@" "${MCCI_SKETCH}"
    arduino-cli compile "$@" "${MCCI_SKETCH}" || _ci_error "${MCCI_SKETCH}" "compile failed"
    echo "::endgroup::"
}

# do a compile: but expect the compile to fail.
#
# arguments:
#	$1	sketch
#	$2..	args to arduino-cli
function _ci_compile_fail {
    local MCCI_SKETCH
    MCCI_SKETCH="$1"
    shift
    echo "::group::Compile ${MCCI_SKETCH} ${MCCI_BOARD} ${MCCI_REGION} ${MCCI_RADIO} (expecting failure)"
    echo "arduino-cli compile" "$@" "${MCCI_SKETCH}"
    if arduino-cli compile "$@" "${MCCI_SKETCH}" ; then
        _ci_error "${MCCI_SKETCH}" "didn't fail but should have"
    else
        # if set -e is on, we need something here to keep from failing.
        true
    fi
    echo "::endgroup::"
}

#
# make a list of examples to be checked in a given library:
#	$1:	pointer to library dir
function _list_examples {
    for i in "$1"/examples/* ; do
        CANDIDATE=$(basename $i)
        if [ -f "$i/${CANDIDATE}.ino" ]; then
            echo "$i/${CANDIDATE}.ino"
        fi
    done
}

