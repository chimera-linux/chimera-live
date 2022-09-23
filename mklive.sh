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

. ./lib.sh

readonly PKG_BOOT="openresolv device-mapper xz"
readonly PKG_ROOT="base-full linux"

BUILD_DIR="build"

usage() {
    cat <<EOF
Usage: $PROGNAME [opts] [build_dir]

Options:
 -A APK       Override the apk tool (default: apk)
 -a ARCH      Generate an image for ARCH (must be runnable on current machine)
 -o FILE      Output a FILE (default: chimera-linux-ARCH-YYYYMMDD(-FLAVOR).iso)
 -f FLAVOR    Flavor name to include in default iso name
 -r REPO      Path to apk repository.
 -k KEY       Path to apk repository public key.
 -p PACKAGES  List of additional packages to install.
 -h           Print this message.
EOF
    exit ${1:=1}
}

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
    "$APK_BIN" ${APK_REPO} --root "$@"
}

while getopts "a:f:k:o:p:r:h" opt; do
    case "$opt" in
        A) APK_BIN="$OPTARG";;
        a) APK_ARCH="$OPTARG";;
        f) FLAVOR="-$OPTARG";;
        k) APK_KEY="$OPTARG";;
        K) KERNVER="$OPTARG";;
        o) OUT_FILE="$OPTARG";;
        p) PACKAGES="$OPTARG";;
        r) APK_REPO="$APK_REPO --repository $OPTARG";;
        h) usage 0 ;;
        *) usage ;;
    esac
done

shift $((OPTIND - 1))

case "$APK_ARCH" in
    x86_64) PKG_GRUB="grub-i386-pc grub-i386-efi grub-x86_64-efi";;
    aarch64) PKG_GRUB="grub-arm64-efi";;
    riscv64) PKG_GRUB="grub-riscv64-efi";;
    ppc64|ppc64le) PKG_GRUB="grub-powerpc-ieee1275";;
    *) die "unsupported architecture: ${APK_ARCH}";;
esac

case "$PKG_GRUB" in
    *-efi*)
        if ! command -v mkfs.vfat > /dev/null 2>&1; then
            die "cannot create FAT filesystems"
        fi
        if ! command -v mmd > /dev/null 2>&1; then
            die "cannot manipulate FAT filesystems"
        fi
        if ! command -v mcopy > /dev/null 2>&1; then
            die "cannot manipulate FAT filesystems"
        fi
        ;;
esac

# default output file
if [ -z "$OUT_FILE" ]; then
    OUT_FILE="chimera-linux-${APK_ARCH}-$(date '+%Y%m%d')${FLAVOR}.iso"
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

if [ -z "$APK_KEY" ]; then
    APK_KEY="keys/q66@chimera-linux.org-61a1913b.rsa.pub"
fi

if [ ! -f "$APK_KEY" ]; then
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

# copy key
msg "Copying signing key..."

mkdir -p "${ROOT_DIR}/etc/apk/keys" || die "failed to create keys directory"
cp "${APK_KEY}" "${ROOT_DIR}/etc/apk/keys" || die "failed to copy signing key"

# install target packages
msg "Installing target base packages..."

run_apk "${ROOT_DIR}" --initdb add base-files \
    || die "failed to install base-files"

# fix up permissions
chown -R root:root "${ROOT_DIR}"

run_apk "${ROOT_DIR}" add base-minimal \
    || die "failed to install base-minimal"

# needs to be available before adding full package set
msg "Mounting pseudo-filesystems..."
mount_pseudo

msg "Installing target packages..."
run_apk "${ROOT_DIR}" add ${PKG_BOOT} ${PKG_GRUB} ${PKG_ROOT} ${PACKAGES} \
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

for f in "${ROOT_DIR}/boot/"vmlinu[xz]-*; do
    [ -f "$f" ] || break
    KERNFILE=${f##*boot/}
    KERNFILE=${KERNFILE%%-*}
    break
done

if [ -z "$KERNVER" ]; then
    die "unable to determine kernel version"
fi

if [ -z "$KERNFILE" ]; then
    die "unable to determine kernel file name"
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

# generate bootloader image
msg "Generating bootloader image..."

# check if to add graphical menu
#
# when adding stuff for more desktops/display managers,
# adjust accordingly and also adjust the initramfs hooks
if [ -f "${ROOT_DIR}/etc/dinit.d/gdm" ]; then
    GRAPHICAL=1
fi

generate_grub_menu() {
    generate_grub_menu_base menu
    sed \
     -e "s|@@BOOT_TITLE@@|Chimera Linux|g" \
     -e "s|@@KERNFILE@@|${KERNFILE}|g" \
     -e "s|@@KERNVER@@|${KERNVER}|g" \
     -e "s|@@ARCH@@|${APK_ARCH}|g" \
     -e "s|@@BOOT_CMDLINE@@||g" \
     grub/menu${1}.cfg.in
}

generate_grub_ppc() {
    # grub.cfg you can see on the media

    mkdir -p "${BOOT_DIR}/grub"

    cp -f grub/early.cfg "${BOOT_DIR}/grub/grub.cfg"
    echo >> "${BOOT_DIR}/grub/grub.cfg"
    generate_grub_menu >> "${BOOT_DIR}/grub/grub.cfg"
    if [ -n "$GRAPHICAL" ]; then
        echo >> "${BOOT_DIR}/grub/grub.cfg"
        generate_grub_menu _gui >> "${BOOT_DIR}/grub/grub.cfg"
    fi

    # grub.cfg that is builtin into the image

    mkdir -p "${ROOT_DIR}/boot/grub"

    cp -f grub/search.cfg "${ROOT_DIR}/boot/grub"
    echo 'set prefix=($root)/boot/grub' >> "${ROOT_DIR}/boot/grub/search.cfg"

    chroot "${ROOT_DIR}" grub-mkimage --verbose --config="boot/grub/search.cfg" \
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

prepare_menu_standalone() {
    mkdir -p "${ROOT_DIR}/boot/grub"

    cp -f grub/search.cfg "${ROOT_DIR}/boot/grub/grub.cfg"
    generate_grub_menu >> "${ROOT_DIR}/boot/grub/grub.cfg"
    if [ -n "$GRAPHICAL" ]; then
        echo >> "${ROOT_DIR}/boot/grub/grub.cfg"
        generate_grub_menu _gui >> "${ROOT_DIR}/boot/grub/grub.cfg"
    fi
}

generate_image_efi() {
    chroot "${ROOT_DIR}" grub-mkstandalone --format=${1}-efi \
        --output="/tmp/boot${2}.efi" --locales="" --fonts="" \
        boot/grub/grub.cfg || die "failed to generate EFI ${1} image"
}

create_efi_fs() {
    EFIBOOT="${BOOT_DIR}/efiboot.img"
    truncate -s 32M "${EFIBOOT}" \
        || die "failed to create EFI image"
    mkfs.vfat "${EFIBOOT}" || die "failed to format EFI image"
    # create dirs
    LC_CTYPE=C mmd -i "${EFIBOOT}" efi efi/boot \
        || die "failed to populate EFI image"
    # populate
    for img in "$@"; do
        LC_CTYPE=C mcopy -i "${EFIBOOT}" "${ROOT_DIR}/tmp/boot${img}.efi" \
            "::efi/boot/" || die "failed to populate EFI image"
    done
}

generate_grub_x86() {
    prepare_menu_standalone

    # BIOS image
    chroot "${ROOT_DIR}" grub-mkstandalone --format=i386-pc \
        --output="/tmp/bios.img" \
        --install-modules="linux normal iso9660 biosdisk memdisk search" \
        --modules="linux normal iso9660 biosdisk search" \
        --locales="" --fonts="" boot/grub/grub.cfg \
        || die "failed to generate BIOS image"

    generate_image_efi x86_64 x64
    generate_image_efi i386 ia32

    # final BIOS image
    cat "${ROOT_DIR}/usr/lib/grub/i386-pc/cdboot.img" \
        "${ROOT_DIR}/tmp/bios.img" > "${BOOT_DIR}/bios.img"

    create_efi_fs x64 ia32

    # save boot_hybrid.img before it's removed, used by xorriso
    cp -f "${ROOT_DIR}/usr/lib/grub/i386-pc/boot_hybrid.img" "${BUILD_DIR}"
}

generate_grub_efi() {
    prepare_menu_standalone
    generate_image_efi $1 $2
    create_efi_fs $2
}

case "${APK_ARCH}" in
    ppc*) generate_grub_ppc;;
    x86*) generate_grub_x86;;
    aarch64*) generate_grub_efi arm64 aa64;;
    riscv64*) generate_grub_efi riscv64 rv64;;
esac

# clean up target root
msg "Cleaning up target root..."

run_apk "${ROOT_DIR}" del ${PKG_BOOT} \
    || die "failed to remove leftover packages"

cleanup_initramfs

cleanup_dirs() {
    for x in "$@"; do
        rm -rf "${ROOT_DIR}/${x}"
        mkdir -p "${ROOT_DIR}/${x}"
    done
}

cleanup_dirs run tmp var/cache var/tmp

chmod 777 "${ROOT_DIR}/tmp"
chmod 777 "${ROOT_DIR}/var/tmp"

# clean up pointless ramdisk(s)
for f in "${ROOT_DIR}/boot/"initrd*; do
    [ -f "$f" ] && rm -f "$f"
done

# remove on-media grub leftovers
rm -rf "${ROOT_DIR}/boot/grub"

# generate squashfs
msg "Generating squashfs filesystem..."

umount_pseudo

gensquashfs --pack-dir "${ROOT_DIR}" -c xz -k -x \
    "${LIVE_DIR}/filesystem.squashfs" || die "gensquashfs failed"

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
    generate_iso_base -eltorito-boot boot/bios.img -no-emul-boot \
        -boot-load-size 4 -boot-info-table --eltorito-catalog boot/boot.cat \
        --grub2-boot-info --grub2-mbr "${BUILD_DIR}/boot_hybrid.img" \
        -eltorito-alt-boot -e boot/efiboot.img -no-emul-boot \
        -append_partition 2 0xef "${BOOT_DIR}/efiboot.img"
}

generate_iso_efi() {
    generate_iso_base --efi-boot boot/efiboot.img -no-emul-boot \
        -append_partition 2 0xef "${BOOT_DIR}/efiboot.img"
}

case "${APK_ARCH}" in
    ppc*) generate_iso_ppc;;
    x86*) generate_iso_x86;;
    *) generate_iso_efi;;
esac

msg "Successfully generated image (${OUT_FILE})"
