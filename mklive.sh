#!/bin/sh
#
# Chimera Linux live image creation tool
#
# Copyright 2022 Daniel "q66" Kolesa
#
# License: BSD-2-Clause
#
# Uses code from the Debian live-boot project, which is available under the
# GPL-3.0-or-later license. Therefore, as a combined work, this is provided
# under the GPL-3.0-or-later terms.
#

umask 022

readonly PROGNAME=$(basename "$0")
readonly PKG_BOOT="openresolv device-mapper xz"
readonly PKG_ROOT="base-full linux"

BUILD_DIR="build"

mount_pseudo() {
    mount -t devtmpfs none "${ROOT_DIR}/dev" || die "failed to mount devfs"
    mount -t proc none "${ROOT_DIR}/proc" || die "failed to mount procfs"
    mount -t sysfs none "${ROOT_DIR}/sys" || die "failed to mount sysfs"
}

umount_pseudo() {
    umount -f "${ROOT_DIR}/dev" > /dev/null 2>&1
    umount -f "${ROOT_DIR}/proc" > /dev/null 2>&1
    umount -f "${ROOT_DIR}/sys" > /dev/null 2>&1
}

error_sig() {
    umount_pseudo
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

usage() {
    cat <<EOF
Usage: $PROGNAME [opts] [build_dir]

Options:
 -A APK       Override the apk tool (default: apk)
 -a ARCH      Generate an image for ARCH (must be runnable on current machine)
 -o FILE      Output a FILE (chimera-linux-ARCH-YYYYMMDD.iso by default)
 -r REPO      Path to apk repository.
 -k KEY       Path to apk repository public key.
 -h           Print this message.
EOF
    exit ${1:=1}
}

if [ "$(id -u)" != "0" ]; then
    die "must be run as root"
fi

APK_BIN="apk"

if ! command -v "$APK_BIN" > /dev/null 2>&1; then
    die "invalid apk command"
fi

if ! command -v gensquashfs > /dev/null 2>&1; then
    die "gensquashfs needs to be installed (squashfs-tools-ng)"
fi

if ! command -v xorriso > /dev/null 2>&1; then
    die "xorriso needs to be installed"
fi

APK_ARCH=$(${APK_BIN} --print-arch)

run_apk() {
    "$APK_BIN" --repository "${APK_REPO}" --root "$@"
}

while getopts "a:k:o:r:h" opt; do
    case "$opt" in
        A) APK_BIN="$OPTARG";;
        a) APK_ARCH="$OPTARG";;
        k) APK_KEY="$OPTARG";;
        K) KERNVER="$OPTARG";;
        o) OUT_FILE="$OPTARG";;
        r) APK_REPO="$OPTARG";;
        h) usage 0 ;;
        *) usage ;;
    esac
done

shift $((OPTIND - 1))

case "$APK_ARCH" in
    x86_64) PKG_GRUB="grub-i386-pc grub-i386-efi grub-x86_64-efi";;
    aarch64) PKG_GRUB="grub-arm64-efi";;
    riscv64) PKG_GRUB="grub-riscv64-efi";;
    ppc64)|ppc64le) PKG_GRUB="grub-powerpc-ieee1275";;
    *) die "unsupported architecture: ${APK_ARCH}";;
esac

# default output file
if [ -z "$OUT_FILE" ]; then
    OUT_FILE="chimera-linux-${APK_ARCH}-$(date '+%Y%m%d').iso"
fi

if [ -z "$APK_REPO" -o ! -f "${APK_REPO}/${APK_ARCH}/APKINDEX.tar.gz" ]; then
    die "must provide a valid repository"
fi

if [ -z "$APK_KEY" -o ! -f "$APK_KEY" ]; then
    die "must provide a valid public key"
fi

if [ -n "$1" ]; then
    BUILD_DIR="$1"
fi

# make absolute so that we aren't prone to bad cleanup with changed cwd
BUILD_DIR=$(realpath "$BUILD_DIR")

IMAGE_DIR="${BUILD_DIR}/image"
ROOT_DIR="${BUILD_DIR}/rootfs"
BOOT_DIR="${IMAGE_DIR}/boot"
LIVE_DIR="${IMAGE_DIR}/live"

if [ -d "$BUILD_DIR" ]; then
    die "$BUILD_DIR already exists"
fi

WRKSRC=$(pwd)

mkdir -p "${BOOT_DIR}" "${LIVE_DIR}" "${ROOT_DIR}" \
    || die "failed to create directories"

# initialize both roots
msg "Initializing roots..."

do_initdb() {
    cd "$1"

    mkdir -p dev tmp etc/apk/keys usr/lib/apk/db var/cache/apk \
        var/cache/misc var/log || die "failed to create root dirs"

    ln -sf usr/lib lib

    touch usr/lib/apk/db/installed
    touch etc/apk/world

    cp "${APK_KEY}" etc/apk/keys || die "failed to copy signing key"
    cd "${WRKSRC}"
}

do_initdb "${ROOT_DIR}"

# install target packages
msg "Installing target base packages..."

run_apk "${ROOT_DIR}" --no-scripts add base-minimal \
    || die "failed to install target base-minimal"
run_apk "${ROOT_DIR}" fix base-files dash dinit-chimera \
    || die "failed to fix up target root"

# needs to be available before adding full package set
msg "Mounting pseudo-filesystems..."
mount_pseudo

msg "Installing target packages..."
run_apk "${ROOT_DIR}" add ${PKG_BOOT} ${PKG_GRUB} ${PKG_ROOT} \
    || die "failed to install full rootfs"

# determine kernel version
if [ -z "$KERNVER" ]; then
    for f in "${ROOT_DIR}/boot/"vmlinu[xz]-*; do
        [ -f "$f" ] || break
        KERNVER=${f##*boot/}
        KERNVER=${KERNVER#*-}
        break
    done
fi

if [ -z "$KERNVER" ]; then
    die "unable to determine kernel version"
fi

# add live-boot initramfs stuff
msg "Copying live initramfs scripts..."

copy_initramfs() {
    cp -R initramfs-tools/lib/live "${ROOT_DIR}/usr/lib" || return 1
    cp initramfs-tools/bin/* "${ROOT_DIR}/usr/bin" || return 1
    cp initramfs-tools/hooks/* "${ROOT_DIR}/usr/share/initramfs-tools/hooks" \
        || return 1
    cp initramfs-tools/scripts/* "${ROOT_DIR}/usr/share/initramfs-tools/scripts" \
        || return 1
}

cleanup_initramfs() {
    rm -rf "${ROOT_DIR}/usr/lib/live"
    cd "${WRKSRC}/initramfs-tools/bin"
    for x in *; do
        rm -f "${ROOT_DIR}/usr/bin/$x"
    done
    cd "${WRKSRC}/initramfs-tools/hooks"
    for x in *; do
        rm -f "${ROOT_DIR}/usr/share/initramfs-tools/hooks/$x"
    done
    cd "${WRKSRC}/initramfs-tools/scripts"
    for x in *; do
        rm -f "${ROOT_DIR}/usr/share/initramfs-tools/scripts/$x"
    done
    cd "${WRKSRC}"
}

copy_initramfs || die "failed to copy initramfs files"

# generate initramfs
msg "Generating initial ramdisk and copying kernel..."
chroot "${ROOT_DIR}" mkinitramfs -o /tmp/initrd "${KERNVER}" \
    || die "unable to generate ramdisk"
    
mv "${ROOT_DIR}/tmp/initrd" "${LIVE_DIR}"

for f in "${ROOT_DIR}/boot/"vmlinu[xz]-"${KERNVER}"; do
    tf=${f##*boot/}
    cp -f "$f" "${LIVE_DIR}/${tf%%-*}"
done

# generate bootloader image
msg "Generating bootloader image..."

generate_grub_ppc() {
    mkdir -p "${BOOT_DIR}/grub"
    sed \
     -e "s|@@BOOT_TITLE@@|Chimera Linux|g" \
     -e "s|@@KERNVER@@|${KERNVER}|g" \
     -e "s|@@ARCH@@|${APK_ARCH}|g" \
     -e "s|@@BOOT_CMDLINE@@||g" \
     ppc/grub.cfg.in > "${BOOT_DIR}/grub/grub.cfg"

    mkdir -p "${ROOT_DIR}/boot/grub"
    cp -f ppc/early.cfg "${ROOT_DIR}/boot/grub"

    chroot "${ROOT_DIR}" grub-mkimage --verbose --config="boot/grub/early.cfg" \
        --prefix="boot/grub" --directory="/usr/lib/grub/powerpc-ieee1275" \
        --format="powerpc-ieee1275" --output="/tmp/grub.img" \
        boot datetime disk ext2 help hfs hfsplus ieee1275_fb iso9660 ls \
        macbless ofnet part_apple part_gpt part_msdos scsi search reboot \
        linux || die "failed to generate grub image"

    cp -f "${ROOT_DIR}/tmp/grub.img" "${BOOT_DIR}"

    mkdir -p "${IMAGE_DIR}/ppc"
    cp -f ppc/ofboot.b "${BOOT_DIR}"
    cp -f ppc/ofboot.b "${BOOT_DIR}/bootinfo.txt"
    cp -f ppc/ofboot.b "${IMAGE_DIR}/ppc/bootinfo.txt"
}

generate_grub_x86() {
    die "not implemented yet"
}

generate_grub_aarch64() {
    die "not implemented yet"
}

case "${APK_ARCH}" in
    ppc*) generate_grub_ppc;;
    x86*) generate_grub_x86;;
    aarch64*) generate_grub_aarch64;;
esac

generate_grub_ppc

# clean up target root
msg "Cleaning up target root..."

run_apk "${ROOT_DIR}" del base-minimal ${PKG_BOOT} ${PKG_GRUB} \
    || die "failed to remove leftover packages"

cleanup_initramfs

cleanup_dirs() {
    for x in "$@"; do
        rm -rf "${ROOT_DIR}/${x}"
        mkdir -p "${ROOT_DIR}/${x}"
    done
}

cleanup_dirs "${ROOT_DIR}/run" "${ROOT_DIR}/tmp" "${ROOT_DIR}/var/cache" \
    "${ROOT_DIR}/var/tmp" "${ROOT_DIR}/var/run"

# clean up pointless ramdisk(s)
for f in "${ROOT_DIR}/boot/"initrd*; do
    [ -f "$f" ] && rm -f "$f"
done

# remove early.cfg
rm -rf "${ROOT_DIR}/boot/grub"

# generate squashfs
msg "Generating squashfs filesystem..."

umount_pseudo

gensquashfs --pack-dir "${ROOT_DIR}" -c xz "${LIVE_DIR}/filesystem.squashfs" \
    || die "gensquashfs failed"

# generate iso image
msg "Generating ISO image..."

generate_iso_base() {
   xorriso -as mkisofs -iso-level 3 -rock -joliet \
        -max-iso9660-filenames -omit-period -omit-version-number \
        -relaxed-filenames -allow-lowercase -volid "CHIMERA_LIVE" "$@" \
        -output "${OUT_FILE}" "${IMAGE_DIR}" \
        || die "failed to generate ISO image"
}

generate_iso_ppc() {
    generate_iso_base -hfsplus -isohybrid-apm-hfsplus \
        -hfsplus-file-creator-type chrp tbxi boot/ofboot.b \
        -hfs-bless-by p boot -sysid PPC -chrp-boot-part
}

generate_iso_x86() {
    die "not implemented yet"
}

generate_iso_efi() {
    die "not implemented yet"
}

case "${APK_ARCH}" in
    ppc*) generate_iso_ppc;;
    x86*) generate_iso_x86;;
    *) generate_iso_efi;;
esac

generate_iso_ppc

msg "Successfully generated image (${OUT_FILE})"