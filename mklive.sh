#!/bin/sh
#
# Chimera Linux live image creation tool
#
# Copyright 2022 q66 <q66@chimera-linux.org>
#
# License: BSD-2-Clause
#
# Uses code from the Debian live-boot project, which is available under the
# GPL-3.0-or-later license. Therefore, as a combined work, this is provided
# under the GPL-3.0-or-later terms.
#

. ./lib.sh

PACKAGES="base-full linux-stable"

if [ -n "$MKLIVE_BUILD_DIR" ]; then
    BUILD_DIR="$MKLIVE_BUILD_DIR"
else
    BUILD_DIR="build"
fi

usage() {
    cat <<EOF
Usage: $PROGNAME [opts] [build_dir]

Options:
 -A APK       Override the apk tool (default: apk)
 -a ARCH      Generate an image for ARCH (must be runnable on current machine)
 -o FILE      Output a FILE (default: chimera-linux-ARCH-YYYYMMDD(-FLAVOR).iso)
 -f FLAVOR    Flavor name to include in default iso name
 -r REPO      Path to apk repository.
 -k DIR       Path to apk repository public key directory.
 -p PACKAGES  List of packages to install (default: base-full linux-stable).
 -s FSTYPE    Filesystem to use (squashfs or erofs, default: erofs)
 -h           Print this message.
EOF
    exit ${1:=1}
}

APK_BIN="apk"
FSTYPE="erofs"
[ -z "$MKLIVE_BOOTLOADER" ] && MKLIVE_BOOTLOADER="grub"

if ! command -v "$APK_BIN" > /dev/null 2>&1; then
    die "invalid apk command"
fi

APK_ARCH=$(${APK_BIN} --print-arch)

run_apk() {
    "$APK_BIN" ${APK_REPO} --arch ${APK_ARCH} --root "$@" --no-interactive
}

while getopts "a:f:k:o:p:r:s:h" opt; do
    case "$opt" in
        A) APK_BIN="$OPTARG";;
        a) APK_ARCH="$OPTARG";;
        f) FLAVOR="-$OPTARG";;
        k) APK_KEYDIR="$OPTARG";;
        K) KERNVER="$OPTARG";;
        o) OUT_FILE="$OPTARG";;
        p) PACKAGES="$OPTARG";;
        r) APK_REPO="$APK_REPO --repository $OPTARG";;
        s) FSTYPE="$OPTARG";;
        h) usage 0 ;;
        *) usage ;;
    esac
done

case "$FSTYPE" in
    squashfs)
        if ! command -v gensquashfs > /dev/null 2>&1; then
            die "gensquashfs needs to be installed (squashfs-tools-ng)"
        fi
        ;;
    erofs)
        if ! command -v mkfs.erofs > /dev/null 2>&1; then
            die "mkfs.erofs needs to be installed (erofs-utils)"
        fi
        ;;
    *) die "unknown live filesystem (${FSTYPE})" ;;
esac

case "$MKLIVE_BOOTLOADER" in
    limine)
        # for now
        PACKAGES="$PACKAGES limine"
        ;;
    nyaboot)
        # for now
        PACKAGES="$PACKAGES nyaboot"
        ;;
esac

shift $((OPTIND - 1))

ISO_VERSION=$(date '+%Y%m%d')

# default output file
if [ -z "$OUT_FILE" ]; then
    OUT_FILE="chimera-linux-${APK_ARCH}-LIVE-${ISO_VERSION}${FLAVOR}.iso"
fi

if [ -z "$APK_REPO" ]; then
    APK_REPO="--repository https://repo.chimera-linux.org/current/main"
    APK_REPO="$APK_REPO --repository https://repo.chimera-linux.org/current/contrib"
fi

for f in ${APK_REPO}; do
    case "$f" in
        --repository) ;;
        http*) ;;
        *)
            if [ ! -f "${f}/${APK_ARCH}/APKINDEX.tar.gz" ]; then
                die "invalid repository ${f}"
            fi
            ;;
    esac
done

if [ -z "$APK_KEYDIR" ]; then
    APK_KEYDIR="keys"
fi

if [ ! -d "$APK_KEYDIR" ]; then
    die "must provide a valid public key directory"
fi

if [ -n "$1" ]; then
    BUILD_DIR="$1"
fi

if [ -d "$BUILD_DIR" ]; then
    die "$BUILD_DIR already exists"
fi
mkdir -p "$BUILD_DIR"

# make absolute so that we aren't prone to bad cleanup with changed cwd
BUILD_DIR=$(realpath "$BUILD_DIR")

IMAGE_DIR="${BUILD_DIR}/image"
ROOT_DIR="${BUILD_DIR}/rootfs"
LIVE_DIR="${IMAGE_DIR}/live"

WRKSRC=$(pwd)

mkdir -p "${LIVE_DIR}" "${ROOT_DIR}" \
    || die "failed to create directories"

# copy keys
msg "Copying signing keys..."

mkdir -p "${ROOT_DIR}/etc/apk/keys" || die "failed to create keys directory"
for k in "${APK_KEYDIR}"/*.pub; do
    [ -r "$k" ] || continue
    cp "$k" "${ROOT_DIR}/etc/apk/keys" || die "failed to copy key '$k'"
done

# install target packages
msg "Installing target base packages..."

run_apk "${ROOT_DIR}" --initdb add chimerautils \
    || die "failed to install chimerautils"

# needs to be available before adding full package set
msg "Mounting pseudo-filesystems..."
mount_pseudo

msg "Installing target packages..."
run_apk "${ROOT_DIR}" add base-live ${PACKAGES} \
    || die "failed to install full rootfs"

msg "Cleaning world..."
run_apk "${ROOT_DIR}" del chimerautils

# determine kernel version
if [ -z "$KERNVER" ]; then
    for f in "${ROOT_DIR}/boot/"vmlinu[xz]-*; do
        [ -f "$f" ] || break
        KERNVER=${f##*boot/}
        KERNVER=${KERNVER#*-}
        break
    done
fi

for f in "${ROOT_DIR}/boot/"vmlinu[xz]-*; do
    [ -f "$f" ] || break
    KERNFILE=${f##*boot/}
    KERNFILE=${KERNFILE%%-*}
    break
done

if [ -z "$KERNVER" ]; then
    die "live media require a kernel, but none detected"
fi

if [ -z "$KERNFILE" ]; then
    die "no kernel found matching '${KERNVER}'"
fi

# add live-boot initramfs stuff
msg "Copying live initramfs scripts..."

if [ ! -x "${ROOT_DIR}/usr/bin/mkinitramfs" ]; then
    die "live media require initramfs-tools, but target root does not contain it"
fi

copy_initramfs() {
    cp -R initramfs-tools/lib/live "${ROOT_DIR}/usr/lib" || return 1
    cp initramfs-tools/bin/* "${ROOT_DIR}/usr/bin" || return 1
    cp initramfs-tools/hooks/* "${ROOT_DIR}/usr/share/initramfs-tools/hooks" \
        || return 1
    cp initramfs-tools/scripts/* "${ROOT_DIR}/usr/share/initramfs-tools/scripts" \
        || return 1
    cp -R data "${ROOT_DIR}/lib/live"
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

# clean up target root
msg "Cleaning up target root..."

cleanup_initramfs

cleanup_dirs() {
    for x in "$@"; do
        rm -rf "${ROOT_DIR}/${x}"
        mkdir -p "${ROOT_DIR}/${x}"
    done
}

cleanup_dirs run tmp root var/cache var/log var/tmp

chmod 777 "${ROOT_DIR}/tmp"
chmod 777 "${ROOT_DIR}/var/tmp"
chmod 750 "${ROOT_DIR}/root"

# clean up pointless ramdisk(s)
for f in "${ROOT_DIR}/boot/"initrd*; do
    [ -f "$f" ] && rm -f "$f"
done

# clean up backup shadow etc
rm -f "${ROOT_DIR}/etc/shadow-" "${ROOT_DIR}/etc/gshadow-" \
      "${ROOT_DIR}/etc/passwd-" "${ROOT_DIR}/etc/group-" \
      "${ROOT_DIR}/etc/subuid-" "${ROOT_DIR}/etc/subgid-"

case "$FSTYPE" in
    squashfs)
        # clean up tmpfiles with xattrs not supported by squashfs
        # (sd-tmpfiles will recreate them as necessary)
        #
        # this list may be expanded as needed
        rm -rf "${ROOT_DIR}/var/lib/tpm2-tss/system/keystore"
        ;;
esac

# generate filesystem
msg "Generating root filesystem..."

umount_pseudo

case "$FSTYPE" in
    squashfs)
        gensquashfs --pack-dir "${ROOT_DIR}" -c xz -k -x \
            "${LIVE_DIR}/filesystem.squashfs" || die "gensquashfs failed"
        ;;
    erofs)
        # tried zstd, it's quite a bit bigger than xz... and experimental
        # when testing, level=3 is 1.9% bigger than 16 and 0.7% bigger than 9
        # ztailpacking has measurable space savings, fragments+dedupe does not
        mkfs.erofs -z lzma -E ztailpacking "${LIVE_DIR}/filesystem.erofs" \
            "${ROOT_DIR}" || die "mkfs.erofs failed"
        ;;
esac

# generate iso image
msg "Generating ISO image..."

mount_pseudo

generate_menu() {
    sed \
     -e "s|@@BOOT_TITLE@@|Chimera Linux|g" \
     -e "s|@@KERNFILE@@|${KERNFILE}|g" \
     -e "s|@@KERNVER@@|${KERNVER}|g" \
     -e "s|@@ARCH@@|${APK_ARCH}|g" \
     -e "s|@@BOOT_CMDLINE@@||g" \
     "$1"
}

# grub support, mkrescue chooses what to do automatically
generate_iso_grub() {
    chroot "${ROOT_DIR}" /usr/bin/grub-mkrescue -o /mnt/image.iso \
        --product-name "Chimera Linux" \
        --product-version "${ISO_VERSION}" \
        --mbr-force-bootable \
        /mnt/image \
        -volid "CHIMERA_LIVE"
}

# base args that will be present for any iso generation
generate_iso_base() {
    chroot "${ROOT_DIR}" /usr/bin/xorriso -as mkisofs -iso-level 3 \
        -rock -joliet -max-iso9660-filenames -omit-period -omit-version-number \
        -relaxed-filenames -allow-lowercase -volid CHIMERA_LIVE \
        "$@" -o /mnt/image.iso /mnt/image
}

# maximally compatible setup for x86_64, one that can boot on bios machines
# as well as both mac efi and pc uefi, and from optical media as well as disk
generate_isohybrid_limine() {
    generate_iso_base \
        -eltorito-boot limine-bios-cd.bin -no-emul-boot -boot-load-size 4 \
        -boot-info-table -hfsplus -apm-block-size 2048 -eltorito-alt-boot \
        -e limine-uefi-cd.bin -efi-boot-part --efi-boot-image \
        --protective-msdos-label --mbr-force-bootable
}

# just plain uefi support with nothing else, for non-x86 machines where there
# is no legacy to worry about, should still support optical media + disk
generate_efi_limine() {
    generate_iso_base \
        -e limine-uefi-cd.bin -efi-boot-part --efi-boot-image \
        -no-emul-boot -boot-load-size 4 -boot-info-table
}

# ppc only, nyaboot + apm hybrid for legacy machines (mac, slof), modern
# machines do not care as long as it's mountable (and need no bootloader)
generate_ppc_nyaboot() {
    generate_iso_base \
        -hfsplus -isohybrid-apm-hfsplus -hfsplus-file-creator-type chrp \
        tbxi boot/ofboot.b -hfs-bless-by p boot -sysid PPC -chrp-boot-part
}

mount --bind "${BUILD_DIR}" "${ROOT_DIR}/mnt" || die "root bind mount failed"

case "$MKLIVE_BOOTLOADER" in
    limine)
        generate_menu limine/limine.conf.in > "${IMAGE_DIR}/limine.conf"
        # efi executables for usb/disk boot
        mkdir -p "${IMAGE_DIR}/EFI/BOOT"
        case "$APK_ARCH" in
            x86_64)
                cp "${ROOT_DIR}/usr/share/limine/BOOTIA32.EFI" "${IMAGE_DIR}/EFI/BOOT"
                cp "${ROOT_DIR}/usr/share/limine/BOOTX64.EFI" "${IMAGE_DIR}/EFI/BOOT"
                ;;
            aarch64)
                cp "${ROOT_DIR}/usr/share/limine/BOOTAA64.EFI" "${IMAGE_DIR}/EFI/BOOT"
                ;;
            riscv64)
                cp "${ROOT_DIR}/usr/share/limine/BOOTRISCV64.EFI" "${IMAGE_DIR}/EFI/BOOT"
                ;;
            loongarch64)
                cp "${ROOT_DIR}/usr/share/limine/BOOTLOONGARCH64.EFI" "${IMAGE_DIR}/EFI/BOOT"
                ;;
            *)
                die "Unknown architecture $APK_ARCH for EFI"
                ;;
        esac
        # make an efi image for eltorito (optical media boot)
        truncate -s 2949120 "${IMAGE_DIR}/limine-uefi-cd.bin" || die "failed to create EFI image"
        chroot "${ROOT_DIR}" /usr/bin/mkfs.vfat -F12 -S 512 "/mnt/image/limine-uefi-cd.bin" > /dev/null \
            || die "failed to format EFI image"
        LC_CTYPE=C chroot "${ROOT_DIR}" /usr/bin/mmd -i "/mnt/image/limine-uefi-cd.bin" EFI EFI/BOOT \
            || die "failed to populate EFI image"
        for img in "${IMAGE_DIR}/EFI/BOOT"/*; do
            img=${img##*/}
            LC_CTYPE=C chroot "${ROOT_DIR}" /usr/bin/mcopy -i "/mnt/image/limine-uefi-cd.bin" \
                "/mnt/image/EFI/BOOT/$img" "::EFI/BOOT/" || die "failed to populate EFI image"
        done
        # now generate
        case "$APK_ARCH" in
            x86_64)
                # but first, necessary extra files for bios
                cp "${ROOT_DIR}/usr/share/limine/limine-bios-cd.bin" "${IMAGE_DIR}"
                cp "${ROOT_DIR}/usr/share/limine/limine-bios.sys" "${IMAGE_DIR}"
                # generate image
                generate_isohybrid_limine || die "failed to generate ISO image"
                # and install bios
                chroot "${ROOT_DIR}" /usr/bin/limine bios-install "/mnt/image.iso"
                ;;
            aarch64|riscv64)
                generate_efi_limine || die "failed to generate ISO image"
                ;;
            *) die "Unknown architecture $APK_ARCH for limine" ;;
        esac
        ;;
    nyaboot)
        case "$APK_ARCH" in
            ppc*) ;;
            *) die "Unknown architecture $APK_ARCH for nyaboot" ;;
        esac
        # necessary dirs
        mkdir -p "${IMAGE_DIR}/boot"
        mkdir -p "${IMAGE_DIR}/etc"
        mkdir -p "${IMAGE_DIR}/ppc/chrp"
        # generate menu
        generate_menu yaboot/yaboot.conf.in > "${IMAGE_DIR}/etc/yaboot.conf"
        generate_menu yaboot/yaboot.msg.in > "${IMAGE_DIR}/etc/yaboot.msg"
        # needs to be present in both locations
        cat yaboot/ofboot.b > "${IMAGE_DIR}/boot/ofboot.b"
        cat yaboot/ofboot.b > "${IMAGE_DIR}/ppc/bootinfo.txt"
        # now install the yaboot binary
        cp "${ROOT_DIR}/usr/lib/nyaboot.bin" "${IMAGE_DIR}/boot/yaboot"
        ;;
    grub)
        mkdir -p "${IMAGE_DIR}/boot/grub"
        generate_menu grub/menu.cfg.in > "${IMAGE_DIR}/boot/grub/grub.cfg"
        generate_iso_grub || die "failed to generate ISO image"
        ;;
    *)
        die "Unknown bootloader $MKLIVE_BOOTLOADER"
        ;;
esac

umount -f "${ROOT_DIR}/mnt"
umount_pseudo

mv "${BUILD_DIR}/image.iso" "$OUT_FILE"

msg "Successfully generated image (${OUT_FILE})"
