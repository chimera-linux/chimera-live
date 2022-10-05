#!/bin/sh
#
# Convenience script for generating different kinds of platform tarballs

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

case "$PLATFORM" in
    core)      BASE_PKG="base-core" ;;
    minimal)   BASE_PKG="base-minimal" ;;
    rpi)       PLAT_PKG="base-rpi" ;;
    pbp)       PLAT_PKG="base-pbp" ;;
    unmatched) PLAT_PKG="base-unmatched" ;;
    *)
        echo "unknown PLATFORM type: $PLATFORM"
        echo
        echo "supported platform types: core minimal rpi pbp unmatched"
        exit 1
        ;;
esac

./mkrootfs.sh -b "$BASE_PKG" -p "$PLAT_PKG $EXTRA_PKGS" -f "$PLATFORM" "$@"
