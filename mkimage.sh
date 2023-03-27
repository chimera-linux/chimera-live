#!/bin/sh
#
# Chimera Linux device image creation tool
#
# This is juts a wrapper around the more advanced device image tools which
# primarily exists to create device images for release. All additional
# arguments are passed to mkpart.sh.
#
# Copyright 2023 Daniel "q66" Kolesa
#
# License: BSD-2-Clause
#

umask 022

readonly PROGNAME=$(basename "$0")

do_cleanup() {
    if [ -n "$ROOT_DIR" -a -d "$ROOT_DIR" ]; then
        umount -fR "$ROOT_DIR" > /dev/null 2>&1
        sync
        rmdir "$ROOT_DIR"
    fi
    if [ -n "$LOOP_DEV" ]; then
        losetup -d "$LOOP_DEV"
    fi
}

error_sig() {
    do_cleanup
    exit ${1:=0}
}

trap 'error_sig $? $LINENO' INT TERM 0

msg() {
    printf "\033[1m$@\n\033[m"
}

die() {
    msg "ERROR: $@"
    error_sig 1 $LINENO
}

if [ "$(id -u)" != "0" ]; then
    die "must be run as root"
fi

usage() {
    cat <<EOF
Usage: $PROGNAME [opts] tarballs -- [mkpart_args]

The platform name is inferred from the last input tarball name.
If multiple tarballs are specified, they are to be separated with
semicolons.

Options:
 -o FILE  Output file name (default: chimera-linux-<arch>-IMAGE-<date>-<platform>.img)
 -s SIZE  The image size (default: 2G)
 -h       Print this message.
EOF
    exit ${1:=1}
}

if ! command -v losetup > /dev/null 2>&1; then
    die "losetup is required"
fi

if ! command -v truncate > /dev/null 2>&1; then
    die "truncate is required"
fi

IMAGE_SIZE=2G
OUT_FILE=
PLATFORM=
LOOP_DEV=
ARCH=

while getopts "o:s:h" opt; do
    case "$opt" in
        o) OUT_FILE="$OPTARG" ;;
        s) IMAGE_SIZE="$OPTARG";;
        h) usage 0 ;;
        *) usage ;;
    esac
done

shift $((OPTIND - 1))

IN_FILES="$1"
shift

if [ -z "$IN_FILES" ]; then
    die "input file(s) not given"
fi

OLD_IFS=$IFS
IFS=;
LAST_FILE=
for tfile in $IN_FILES; do
    if [ ! -r "$tfile" ]; then
        die "could not read input file: $tfile"
    fi
    LAST_FILE=$tfile
done
IFS=$OLD_IFS

ROOT_DIR=$(mktemp -d)

if [ $? -ne 0 ]; then
    die "failed to create root directory"
fi

PLATFORM="${LAST_FILE#*ROOTFS-}"
PLATFORM="${PLATFORM#*DROOTFS-}"
PLATFORM="${PLATFORM#*-}"
PLATFORM="${PLATFORM%%.*}"

ARCH="${LAST_FILE#chimera-linux-}"
ARCH="${ARCH%-ROOTFS*}"
ARCH="${ARCH%-DROOTFS*}"

[ -n "$PLATFORM" -a -n "$ARCH" ] || die "invalid input filename"

if [ ! -r "sfdisk/$PLATFORM" ]; then
    die "unknown platform: $PLATFORM"
fi

if [ -z "$OUT_FILE" ]; then
    OUT_FILE="chimera-linux-${ARCH}-IMAGE-$(date '+%Y%m%d')-${PLATFORM}.img"
fi

mkdir -p "${ROOT_DIR}" || die "failed to create directories"

msg "Creating image..."

truncate -s "$IMAGE_SIZE" "$OUT_FILE" > /dev/null 2>&1 || \
    die "failed to create image"

LOOP_DEV=$(losetup --show -fP "$OUT_FILE")

if [ $? -ne 0 ]; then
    LOOP_DEV=
    die "failed to attach loop device"
fi

msg "Creating and mounting partitions..."

./mkpart.sh -j "$@" "$LOOP_DEV" "$PLATFORM" "$ROOT_DIR" || \
    die "could not set up target image"

./unrootfs.sh "$IN_FILES" "$ROOT_DIR" "$LOOP_DEV" || \
    die "could not install Chimera"

msg "Cleaning up..."

umount -R "$ROOT_DIR" || die "failed to unmount image"
rmdir "$ROOT_DIR" || die "root directory not emoty"
ROOT_DIR=

losetup -d "$LOOP_DEV" || die "failed to detach loop device"
LOOP_DEV=

msg "Compressing image..."
gzip -9 "$OUT_FILE"

msg "Successfully generated image (${OUT_FILE}.gz)."
