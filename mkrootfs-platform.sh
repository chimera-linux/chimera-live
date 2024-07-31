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
PLAT_PKG="base-$PLATFORM"
KERNEL_PKG=

PLATFORMS="bootstrap full rpi pbp rockpro64 unmatched ec2"

for pkg in ${PLATFORMS}; do
    if [ "$pkg" = "$PLATFORM" ]; then
        case "$PLATFORM" in
            bootstrap) BASE_PKG="base-bootstrap" ;;
            full) ;;
            rpi) KERNEL_PKG="linux-rpi" ;;
            ec2) PLAT_PKG="systemd-boot !base-full-firmware"; KERNEL_PKG="linux-lts" ;;
            *) KERNEL_PKG="linux-lts" ;;
        esac
        exec ./mkrootfs.sh -b "$BASE_PKG" \
            -p "$PLAT_PKG $KERNEL_PKG $EXTRA_PKGS" \
            -f "$PLATFORM" "$@"
    fi
done

echo "unknown PLATFORM type: $PLATFORM"
echo
echo "supported platform types: full bootstrap"
echo "                          rpi pbp rockpro64"
echo "                          unmatched ec2"
exit 1
