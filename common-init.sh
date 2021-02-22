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

	# MCCI_ADDITIONAL_URLS specifies paths to board files
	declare -gx MCCI_ADDITIONAL_URLS
	MCCI_ADDITIONAL_URLS="https://github.com/mcci-catena/arduino-boards/raw/master/BoardManagerFiles/package_mcci_index.json,https://adafruit.github.io/arduino-board-index/package_adafruit_index.json,https://dl.espressif.com/dl/package_esp32_index.json"

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
	fi
}

#### set up a board package: $1 is fqbn
function _setup_board_package {
	_assert_setup_env
	local CORE
	CORE="$(arduino-cli core list | awk 'NR>1 {print $1}' | grep "^$1"'$')"
	if [[ -z "$CORE" ]]; then
		arduino-cli core install "$@"
	fi
}

# log a compile error message
function _ci_error {
	local MESSAGE
	MESSAGE="$(basename "$1" .ino) for ${MCCI_TARGET} board ${MCCI_BOARD} region ${MCCI_REGION} radio ${MCCI_RADIO}: $2"
	echo "Error: $MESSAGE"
	MCCI_ERRORS+=("::error::$MESSAGE")
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
	echo "${MCCI_SKETCH} ${MCCI_BOARD} ${MCCI_REGION} ${MCCI_RADIO}:"
	echo "arduino-cli compile" "$@" "${MCCI_SKETCH}"
	arduino-cli compile "$@" "${MCCI_SKETCH}" || _error "${MCCI_SKETCH}" "compile failed"
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
	echo "${MCCI_SKETCH} ${MCCI_BOARD} ${MCCI_REGION} ${MCCI_RADIO}:"
	arduino-cli compile "$@" "${MCCI_SKETCH}" && _error "${MCCI_SKETCH}" "didn't fail but should have"
}