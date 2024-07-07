#!/bin/sh
#
# Convenience script for generating releases - this generates all relevant
# images for the given platform so that they can be published
#
# all arguments are passed to the respective commands
#
# Copyright 2022 Daniel "q66" Kolesa
#
# License: BSD-2-Clause
#

APK_BIN="apk"

if ! command -v "$APK_BIN" > /dev/null 2>&1; then
    echo "ERROR: invalid apk command"
    exit 1
fi

if [ -z "$APK_ARCH" ]; then
    APK_ARCH=$(${APK_BIN} --print-arch)
fi

mkdir -p release-stamps

check_stamp() {
    test -f "release-stamps/stamp-$APK_ARCH-$1"
}

touch_stamp() {
    touch "release-stamps/stamp-$APK_ARCH-$1"
}

die() {
    echo "ERROR: $@"
    exit 1
}

# iso images for every platform

echo "LIVE: base"
if ! check_stamp live-base; then
    MKLIVE_BUILD_DIR=build-live-base-$APK_ARCH ./mklive-image.sh -b base -- \
        -a "$APK_ARCH" "$@" || die "failed to build live-base"
    touch_stamp live-base
fi

echo "LIVE: gnome"
if ! check_stamp live-gnome; then
    MKLIVE_BUILD_DIR=build-live-gnome-$APK_ARCH ./mklive-image.sh -b gnome -- \
        -a "$APK_ARCH" "$@" || die "failed to build live-gnome"
    touch_stamp live-gnome
fi

# bootstrap and full rootfses for every target

make_rootfs() {
    ROOT_TYPE="$1"
    shift
    echo "ROOTFS: $ROOT_TYPE"
    if ! check_stamp root-$ROOT_TYPE; then
        MKROOTFS_ROOT_DIR=build-root-$ROOT_TYPE-$APK_ARCH ./mkrootfs-platform.sh \
            -P $ROOT_TYPE -- -a "$APK_ARCH" "$@" \
                || die "failed to build root-$ROOT_TYPE"
        touch_stamp root-$ROOT_TYPE
    fi
}

make_rootfs bootstrap "$@"
make_rootfs full "$@"

make_device() {
    make_rootfs "$@"
    echo "DEVICE: $1"
    if ! check_stamp dev-$1; then
        ./mkimage.sh "chimera-linux-${APK_ARCH}-ROOTFS-$(date '+%Y%m%d')-$1.tar.gz" \
            || die "failed to build dev-$1"
        touch_stamp dev-$1
    fi
}

case "$APK_ARCH" in
    aarch64)
        make_device rpi "$@"
        make_device pbp "$@"
        make_device rockpro64 "$@"
        ;;
    riscv64)
        make_device unmatched "$@"
        ;;
esac
