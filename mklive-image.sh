#!/bin/sh
#
# Convenience script for generating different kinds of live images

# all extra arguments are passed to mklive.sh as is
#
# Copyright 2022 Daniel "q66" Kolesa
#
# License: BSD-2-Clause
#

IMAGE=
EXTRA_PKGS=

while getopts "b:p:" opt; do
    case "$opt" in
        b) IMAGE="$OPTARG";;
        p) EXTRA_PKGS="$OPTARG";;
        *) ;;
    esac
done

shift $((OPTIND - 1))

readonly BASE_PKGS="cryptsetup lvm2 ${EXTRA_PKGS}"

case "$IMAGE" in
    base)
        PKGS="${BASE_PKGS}"
        ;;
    gnome)
        PKGS="${BASE_PKGS} base-desktop xserver-xorg"
        ;;
    *)
        echo "unknown image type: $IMAGE"
        exit 1
        ;;
esac

./mklive.sh -p "$PKGS" -f "$IMAGE" "$@"
