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
    core)    BASE_PKG="base-core" ;;
    minimal) BASE_PKG="base-minimal" ;;
    rpi3)    PLAT_PKG="base-rpi3" ;;
    rpi4)    PLAT_PKG="base-rpi4" ;;
    pbp)     PLAT_PKG="base-pbp" ;;
    *)
        echo "unknown PLATFORM type: $PLATFORM"
        echo
        echo "supported platform types: core minimal rpi3 rpi4 pbp"
        exit 1
        ;;
esac

./mkrootfs.sh -b "$BASE_PKG" -p "$PLAT_PKG $EXTRA_PKGS" -f "$PLATFORM" "$@"
