#!/usr/bin/env bash
if [ -z $IN_NIX_SHELL ];
then
	echo "you are not in a nix-shell" >&2
	exit 1
fi


echo $stdenv
source $stdenv/setup

# doesn't seem effective in the context of quickfix
# if there is a subfolder called "build", most likely we should run it from there
# if [ -d "build" ]; then
# 	echo "there is a build/ folder"
# 	cd build
# fi

# to get gcc messages in English
export LANG=C

if [ -z "$buildPhase" ]; then
	echo "build from function"
	echo "CWD: $PWD"
	buildPhase
else
	$buildPhase
fi
