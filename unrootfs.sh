#!/bin/sh
#
# Chimera Linux device rootfs extraction tool
#
# This script installs a Chimera system from a device tarball into
# a mounted filesystem, set up e.g. via the mkpart.sh script.
#
# Copyright 2023 Daniel "q66" Kolesa
#
# License: BSD-2-Clause
#

. ./lib.sh

usage() {
    cat <<EOF
Usage: $PROGNAME tarball mountpoint device

The tarball is the Chimera device rootfs tarball. The mountpoint
is where to unpack it. The device is where to install the bootloader,
assuming one is needed; if not given, no bootloader will be installed,
if given, it needs to be the whole block device (not a partition).

Options:
 -h           Print this message.
EOF
    exit ${1:=1}
}

IN_FILES="$1"
shift

ROOT_DIR="$1"
shift

BL_DEV="$1"
shift

if [ -z "$IN_FILES" ]; then
    die "input file(s) not given"
fi

OLD_IFS=$IFS
IFS=;
for tfile in $IN_FILES; do
    if [ ! -r "$tfile" ]; then
        die "could not read input file: $tfile"
    fi
done
IFS=$OLD_IFS

if ! mountpoint -q "$ROOT_DIR"; then
    die "$ROOT_DIR is not a mount point"
fi

if [ -n "$BL_DEV" -a ! -b "$BL_DEV" ]; then
    die "$BL_DEV given but not a block device"
fi

BOOT_UUID=$(findmnt -no uuid "${ROOT_DIR}/boot")
ROOT_UUID=$(findmnt -no uuid "${ROOT_DIR}")
BOOT_FSTYPE=$(findmnt -no fstype "${ROOT_DIR}/boot")
ROOT_FSTYPE=$(findmnt -no fstype "${ROOT_DIR}")

msg "Unpacking rootfs tarball..."

_tarargs=
if [ -n "$(tar --version | grep GNU)" ]; then
    _tarargs="--xattrs-include='*'"
fi

OLD_IFS=$IFS
IFS=;
for tfile in $IN_FILES; do
    tar -pxf "$tfile" --xattrs $_tarargs -C "$ROOT_DIR" ||\
         die "could not extract input file: $file"
done
IFS=$OLD_IFS

# use fsck for all file systems other than f2fs
case "$ROOT_FSTYPE" in
    f2fs) _fpassn="0";;
    *) _fpassn="1";;
esac

# generate fstab
FSTAB=$(mktemp)
TMPL=$(tail -n1 "${ROOT_DIR}/etc/fstab")
# delete tmpfs line
echo "UUID=$ROOT_UUID / $ROOT_FSTYPE defaults 0 ${_fpassn}" > "$FSTAB"
if [ -n "$BOOT_UUID" ]; then
    echo "UUID=$BOOT_UUID /boot $BOOT_FSTYPE defaults 0 2" >> "$FSTAB"
fi
# overwrite old
cat "$FSTAB" > "${ROOT_DIR}/etc/fstab"
rm -f "$FSTAB"

msg "Setting up bootloader..."

if [ -n "$BL_DEV" -a -r "${ROOT_DIR}/etc/default/u-boot-device" ]; then
    "${ROOT_DIR}/usr/bin/install-u-boot" "${BL_DEV}" "${ROOT_DIR}"
fi

# TODO(yoctozepto): support UEFI on arm64 (aarch64)
if [ -n "$BL_DEV" -a -r "${ROOT_DIR}/usr/lib/grub/x86_64-efi" ]; then
    mount_pseudo
    # NOTE(yoctozepto): /dev/disk/by-uuid must exist for update-grub to do the right thing
    [ -d /dev/disk/by-uuid ] || die "/dev/disk/by-uuid not found, update-grub would be misled"
    # TODO(yoctozepto): try with systemd-boot instead
    # TODO(yoctozepto): separate /boot and /boot/efi
    chroot ${ROOT_DIR} /bin/sh -i <<EOF
set -e
grub-install --target x86_64-efi --efi-directory /boot --no-nvram --removable
update-initramfs -c -k all
update-grub
cat > /etc/default/agetty << EOF2
EXTRA_GETTYS="/dev/ttyS0"
EOF2
cat > /etc/default/agetty-ttyS0 << EOF2
GETTY_BAUD="115200"
EOF2
EOF
    if [ $? -ne 0 ]; then
        die "Installing GRUB failed."
    fi
fi

msg "Successfully installed Chimera."
