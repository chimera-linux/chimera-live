#!/bin/sh
#
# Convenience script for generating different kinds of platform tarballs
#
# all extra arguments are passed to mkrootfs.sh as is
#
# Copyright 2022 Daniel "q66" Kolesa
#
# License: BSD-2-Clause
#

PLATFORM=
EXTRA_PKGS=

while getopts "P:p:" opt; do
    case "$opt" in
        P) PLATFORM="$OPTARG";;
        p) EXTRA_PKGS="$OPTARG";;
        *) ;;
    esac
done

shift $((OPTIND - 1))

BASE_PKG="base-full"
PLAT_PKG=

PLATFORMS="core minimal rpi pbp reform-imx8mq unmatched"

for pkg in ${PLATFORMS}; do
    if [ "$pkg" = "$PLATFORM" ]; then
        case "$PLATFORM" in
            core) BASE_PKG="base-core" ;;
            minimal) BASE_PKG="base-minimal" ;;
            *) ;;
        esac
        exec ./mkrootfs.sh -b "$BASE_PKG" -p "base-$PLATFORM $EXTRA_PKGS" \
            -f "$PLATFORM" "$@"
    fi
done

echo "unknown PLATFORM type: $PLATFORM"
echo
echo "supported platform types: core minimal"
echo "                          rpi pbp reform-imx8mq"
echo "                          unmatched"
exit 1
