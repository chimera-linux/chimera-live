#!/bin/sh
#
# Chimera Linux device partitioning and filesystem tool
#
# This script is usually used as a part of device image creation and partitions
# a device or with a known layout, and creates appropriate filesystems. The
# result is mounted in a way that can be accepted by the other stages.
#
# Copyright 2023 Daniel "q66" Kolesa
#
# License: BSD-2-Clause
#

readonly PROGNAME=$(basename "$0")

do_cleanup() {
    if [ -n "$TARGET_MNT" -a -d "$TARGET_MNT" ]; then
        umount -fR "$TARGET_MNT" > /dev/null 2>&1
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

TARGET_MNT=
BOOT_FSTYPE=vfat
BOOT_FSSIZE=256MiB
ROOT_FSTYPE=ext4
BOOT_MKARGS=
ROOT_MKARGS=
ROOT_JOURNAL=1

if [ "$(id -u)" != "0" ]; then
    die "must be run as root"
fi

if ! command -v findmnt > /dev/null 2>&1; then
    die "findmnt is required"
fi

if ! command -v sfdisk > /dev/null 2>&1; then
    die "sfdisk is required"
fi

usage() {
    cat <<EOF
Usage: $PROGNAME [opts] DEVICE PLATFORM MNTPT

The FILE_OR_DEVICE is a block device (whole, either physical or one set
up with 'losetup -fP'). The PLATFORM must match a device layout file in
sfdisk/. The MNTPT is a directory to mount the resulting structure in.

Options:
  -b FSTYPE  The /boot file system type (current: ${BOOT_FSTYPE})
  -B FSSIZE  The /boot file system size (current: ${BOOT_FSSIZE})
  -r FSTYPE  The / file system type (current: ${ROOT_FSTYPE})
  -m ARGS    Additional arguments for /boot mkfs.
  -M ARGS    Additional arguments for / mkfs.
  -j         Disable journal for /.
  -h         Print this message.
EOF
    exit ${1:=1}
}

while getopts "b:B:r:m:M:jh" opt; do
    case "$opt" in
        b) BOOT_FSTYPE="$OPTARG";;
        B) BOOT_FSSIZE="$OPTARG";;
        r) ROOT_FSTYPE="$OPTARG";;
        m) BOOT_MKARGS="$OPTARG";;
        M) ROOT_MKARGS="$OPTARG";;
        j) ROOT_JOURNAL=0;;
        h) usage 0;;
        *) usage;;
    esac
done

if ! command -v mkfs.${BOOT_FSTYPE} > /dev/null 2>&1; then
    die "mkfs.${BOOT_FSTYPE} is required"
fi

if ! command -v mkfs.${ROOT_FSTYPE} > /dev/null 2>&1; then
    die "mkfs.${ROOT_FSTYPE} is required"
fi

shift $((OPTIND - 1))

BDEV=$1
shift

PLATFORM=$2
shift

MNTPT=$(readlink -f "$3")
shift

[ -b "$BDEV" ] || die "input must be a block device"

# We need a partition layout file for each platform
#
# In general, U-Boot targets use GPT with 4 partitions, the first two holding
# the U-Boot SPL and U-Boot itself (and typically having the "Linux reserved"
# partition type except when something else is necessary) and the other
# two holding /boot and the actual root file system
#
# Raspberry Pi uses MBR for best compatibility and has two partitions,
# one for /boot and one for the root filesystem
#
# All devices default to FAT32 /boot and ext4 /, for best compatibility
#
[ -r "sfdisk/${PLATFORM}" ] || die "unknown platform ${PLATFORM}"

[ -n "$MNTPT" -a -d "$MNTPT" ] || die "unknown or invalid mount point"

TARGET_MNT="$MNTPT"

# we need to figure these out to know where to create filesystems
BOOT_PARTN=
ROOT_PARTN=

seqn=1
for part in $(grep name= "sfdisk/${PLATFORM}" | sed 's/,.*//'); do
    case "$part" in
        name=boot) BOOT_PARTN=$seqn ;;
        name=root) ROOT_PARTN=$seqn ;;
        *) ;;
    esac
    seqn=$(($seqn + 1))
done

[ -n "$BOOT_PARTN" -a -n "$ROOT_PARTN" ] || \
    die "could not locate partition numbers"

sed "s,@BOOT_SIZE@,${BOOT_FSSIZE},g" "sfdisk/${PLATFORM}" | sfdisk "${BDEV}"

if [ $? -ne 0 ]; then
    die "could not partition ${BDEV}"
fi

# locate partitions; try FOOnN as well as fooN, as both may appear, whole
# devices that end with numbers will include the 'p' (e.g. loopN and nvmeNnM)

ROOT_DEV="${BDEV}p${ROOT_PARTN}"
[ -b "$ROOT_DEV" ] || ROOT_DEV="${BDEV}${ROOT_PARTN}"
[ -b "$ROOT_DEV" ] || die "unknown root partition"

BOOT_DEV="${BDEV}p${BOOT_PARTN}"
[ -b "$BOOT_DEV" ] || BOOT_DEV="${BDEV}${BOOT_PARTN}"
[ -b "$BOOT_DEV" ] || die "unknown boot partition"

# filesystem parameters

if [ "$BOOT_FSTYPE" = "vfat" ]; then
    BOOT_MKARGS="-I -F16 $BOOT_MKARGS"
fi

case "$ROOT_FSTYPE" in
    # disable journal on ext3/4 to improve lifespan of flash memory
    ext[34])
        if [ "$ROOT_JOURNAL" -eq 0 ]; then
            ROOT_MKARGS="-O ^has_journal $ROOT_MKARGS"
        fi
        ;;
esac

# create filesystems

mkfs.${BOOT_FSTYPE} ${BOOT_MKARGS} "${BOOT_DEV}" \
    || die "failed to create boot file system"

mkfs.${ROOT_FSTYPE} ${ROOT_MKARGS} "${ROOT_DEV}" \
    || die "failed to create root file system"

# mount filesystems

mount "${ROOT_DEV}" "${TARGET_MNT}" || die "failed to mount root"
mkdir -p "${TARGET_MNT}/boot" || die "failed to create boot mount"
mount "${BOOT_DEV}" "${TARGET_MNT}/boot" || die "failed to mount boot"

echo "Mounted '${ROOT_DEV}' at '${TARGET_MNT}'."

# ensure this remains mounted
TARGET_MNT=

exit 0
