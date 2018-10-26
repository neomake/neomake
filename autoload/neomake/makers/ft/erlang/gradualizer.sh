#!/usr/bin/env bash

set -euo pipefail
#set -x

# Set to your gradualizer location or make sure the command is in PATH
GRADUALIZER=gradualizer

if [ x`uname` = x"Darwin" ]; then
    SED=gsed
else
    SED=sed
fi

$GRADUALIZER $@ | $SED '/\(.*on line \([0-9]*\)\)/ {s//\2:\1/}' | sort -n | uniq
