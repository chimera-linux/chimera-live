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
KERNEL_PKGS=

while getopts "b:k:p:" opt; do
    case "$opt" in
        b) IMAGE="$OPTARG";;
        k) KERNEL_PKGS="$OPTARG";;
        p) EXTRA_PKGS="$OPTARG";;
        *) ;;
    esac
done

shift $((OPTIND - 1))

if [ -z "$KERNEL_PKGS" ]; then
    KERNEL_PKGS="linux-lts linux-lts-zfs-bin zfs"
fi

readonly BASE_PKGS="cryptsetup-scripts lvm2 firmware-linux-soc ${KERNEL_PKGS} ${EXTRA_PKGS}"

case "$IMAGE" in
    base)
        PKGS="${BASE_PKGS}"
        ;;
    gnome)
        PKGS="${BASE_PKGS} gnome"
        ;;
    plasma)
        PKGS="${BASE_PKGS} plasma-desktop xserver-xorg"
        ;;
    *)
        echo "unknown image type: $IMAGE"
        echo
        echo "supported image types: base gnome"
        exit 1
        ;;
esac

./mklive.sh -p "$PKGS" -f "$IMAGE" "$@"
