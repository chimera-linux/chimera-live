#!/bin/sh
#
# Chimera Linux device image creation tool
#
# Copyright 2022 Daniel "q66" Kolesa
#
# License: BSD-2-Clause
#

umask 022

readonly PROGNAME=$(basename "$0")

do_cleanup() {
    [ -z "$ROOT_DIR" ] && return 0
    umount -f "${ROOT_DIR}/boot" > /dev/null 2>&1
    umount -f "${ROOT_DIR}" > /dev/null 2>&1
    if [ -n "$LOOP_OUT" ]; then
        kpartx -d "$OUT_FILE" > /dev/null 2>&1
    fi
    [ -d "$ROOT_DIR" ] && rmdir "$ROOT_DIR"
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
Usage: $PROGNAME [opts] tarball

Currently available platforms: rpi pbp reform-imx8mq unmatched

The platform name is inferred from the input rootfs name.

Options:
 -a ARCH      Force the target architecture to ARCH
 -b FSTYPE    The /boot file system type (default: vfat)
 -B BOOTSIZE  The /boot file system size (default: 256MiB)
 -r FSTYPE    The / file system type (default: ext4)
 -s SIZE      The image size (default: 2G)
 -o FILE      Output a FILE (default: chimera-linux-PLATFORM-YYYYMMDD.img)
 -P PLATFORM  Force the platform type to PLATFORM
 -h           Print this message.
EOF
    exit ${1:=1}
}

PLATFORM=
ARCH=

while getopts "a:b:B:r:s:o:P:h" opt; do
    case "$opt" in
        b) BOOT_FSTYPE="$OPTARG";;
        B) BOOT_FSSIZE="$OPTARG";;
        r) ROOT_FSTYPE="$OPTARG";;
        s) IMG_SIZE="$OPTARG";;
        o) OUT_FILE="$OPTARG";;
        P) PLATFORM="$OPTARG";;
        a) ARCH="$OPTARG";;
        h) usage 0 ;;
        *) usage ;;
    esac
done

shift $((OPTIND - 1))

IN_FILE="$1"
shift

if [ -z "$IN_FILE" ]; then
    die "input file not given"
fi

if [ ! -r "$IN_FILE" ]; then
    die "cannot read input file: $IN_FILE"
fi

ROOT_DIR=$(mktemp -d)

if [ $? -ne 0 ]; then
    die "failed to create root directory"
fi

if [ -z "$PLATFORM" ]; then
    PLATFORM="${IN_FILE#*ROOTFS-}"
    PLATFORM="${PLATFORM#*-}"
    PLATFORM="${PLATFORM%%.*}"
fi

if [ -z "$ARCH" ]; then
    ARCH="${IN_FILE#chimera-linux-}"
    ARCH="${ARCH%-ROOTFS*}"
fi

case "$PLATFORM" in
    rpi|pbp|reform-imx8mq|unmatched) ;;
    *) die "unknown platform: $PLATFORM" ;;
esac

# defaults
: ${BOOT_FSTYPE:=vfat}
: ${BOOT_FSSIZE:=256MiB}
: ${ROOT_FSTYPE:=ext4}
: ${IMG_SIZE:=2G}

if [ -z "$OUT_FILE" ]; then
    OUT_FILE="chimera-linux-${ARCH}-IMAGE-$(date '+%Y%m%d')-${PLATFORM}.img"
fi

readonly CHECK_TOOLS="truncate sfdisk kpartx tar chpasswd mkfs.${BOOT_FSTYPE} mkfs.${ROOT_FSTYPE}"

for tool in ${CHECK_TOOLS}; do
    if ! command -v $tool > /dev/null 2>&1; then
        die "missing tool: $tool"
    fi
done

msg "Creating disk image..."

truncate -s "${IMG_SIZE}" "${OUT_FILE}" > /dev/null 2>&1 \
    || die "failed to create image"

mkdir -p "${ROOT_DIR}" \
    || die "failed to create directories"

msg "Creating partitions..."

_bargs=
if [ "$BOOT_FSTYPE" = "vfat" ]; then
    _bargs="-I -F16"
fi

_rargs=
case "$ROOT_FSTYPE" in
    # disable journal on ext3/4 to improve lifespan of flash memory
    ext[34]) _rargs="-O ^has_journal";;
esac

BOOT_PARTN=1
ROOT_PARTN=2

# all device targets use a partition layout with a separate boot partition
# and a root partition, the boot partition is vfat by default for best
# compatibility (u-boot etc) and sized 256M (to fit multiple kernels)
# while the root partition takes up the rest of the device
case "$PLATFORM" in
    pbp|reform-imx8mq)
        # GPT-using u-boot devices, start at 16M to leave enough space
        sfdisk "$OUT_FILE" << EOF
label: gpt
unit: sectors
first-lba: 32768
name=boot, size=${BOOT_FSSIZE}, bootable, attrs="LegacyBIOSBootable"
name=root
EOF
    ;;
    unmatched)
        # hifive unmatched needs gpt and spl/uboot need special partitions
        sfdisk "$OUT_FILE" << EOF
label: gpt
unit: sectors
first-lba: 34
name=spl,   start=34,    size=2048,           type=5B193300-FC78-40CD-8002-E86C45580B47
name=uboot, start=2082,  size=8192,           type=2E54B353-1271-4842-806F-E436D6AF6985
name=boot,  start=16384, size=${BOOT_FSSIZE}, bootable, attrs="LegacyBIOSBootable"
name=root
EOF
        BOOT_PARTN=3
        ROOT_PARTN=4
    ;;
    *)
        sfdisk "$OUT_FILE" << EOF
label: dos
2048,${BOOT_FSSIZE},b,*
,+,L
EOF
    ;;
esac

if [ $? -ne 0 ]; then
    die "failed to format the image"
fi

LOOP_OUT=$(kpartx -av "$OUT_FILE")

if [ $? -ne 0 ]; then
    die "failed to set up loop device"
fi

LOOP_DEV=$(echo $LOOP_OUT | grep -o "loop[0-9]*" | uniq)

if [ -z "$LOOP_DEV" ]; then
    die "failed to identify loop device"
fi

# make into a real path
LOOP_PART="/dev/mapper/${LOOP_DEV}p"

mkfs.${BOOT_FSTYPE} ${_bargs} "${LOOP_PART}${BOOT_PARTN}" \
    || die "failed to create boot file system"

mkfs.${ROOT_FSTYPE} ${_rargs} "${LOOP_PART}${ROOT_PARTN}" \
    || die "failed to create root file system"

mount "${LOOP_PART}${ROOT_PARTN}" "${ROOT_DIR}" || die "failed to mount root file system"
mkdir -p "${ROOT_DIR}/boot"
mount "${LOOP_PART}${BOOT_PARTN}" "${ROOT_DIR}/boot" || die "failed to mount boot directory"

BOOT_UUID=$(blkid -o value -s UUID "${LOOP_PART}${BOOT_PARTN}")
ROOT_UUID=$(blkid -o value -s UUID "${LOOP_PART}${ROOT_PARTN}")

msg "Unpacking rootfs tarball..."

_tarargs=
if [ -n "$(tar --version | grep GNU)" ]; then
    _tarargs="--xattrs-include='*'"
fi

tar -pxf "$IN_FILE" --xattrs $_tarargs -C "$ROOT_DIR"

# use fsck for all file systems other than f2fs
case "$ROOT_FSTYPE" in
    f2fs) _fpassn="0";;
    *) _fpassn="1";;
esac

echo "UUID=$ROOT_UUID / $ROOT_FSTYPE defaults 0 ${_fpassn}" >> "${ROOT_DIR}/etc/fstab"
echo "UUID=$BOOT_UUID /boot $BOOT_FSTYPE defaults 0 2" >> "${ROOT_DIR}/etc/fstab"

msg "Setting up bootloader..."

flash_file() {
    dd if="${ROOT_DIR}/usr/lib/u-boot/$1" of="/dev/${LOOP_DEV}" seek=$2 \
        conv=notrunc,fsync > /dev/null 2>&1 \
            || die "failed to flash $1"
}

case "$PLATFORM" in
    pbp)
        flash_file pinebook-pro-rk3399/idbloader.img 64
        flash_file pinebook-pro-rk3399/u-boot.itb 16384
        ;;
    reform-imx8mq)
        flash_file imx8mq_reform2/flash.bin 66
        ;;
    unmatched)
        flash_file sifive_unmatched/u-boot-spl.bin 34
        flash_file sifive_unmatched/u-boot.itb 2082
        ;;
esac

echo "Finalizing..."

echo root:chimera | chpasswd -c SHA512 -R "${ROOT_DIR}"

echo chimera > "${ROOT_DIR}/etc/hostname"
echo 127.0.0.1 chimera >> "${ROOT_DIR}/etc/hosts"
echo ::1 chimera >> "${ROOT_DIR}/etc/hosts"

umount -R "$ROOT_DIR" || die "failed to unmount image"
kpartx -dv "$OUT_FILE" || die "failed to detach loop device"

rmdir "$ROOT_DIR" || die "root directory not emoty"

chmod 644 "$OUT_FILE"

msg "Compressing image..."
gzip -9 "$OUT_FILE"

msg "Successfully created image (${OUT_FILE}.gz)"
