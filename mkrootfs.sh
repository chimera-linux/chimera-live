#!/bin/sh
#
# Chimera Linux rootfs creation tool
#
# Copyright 2022 q66 <q66@chimera-linux.org>
#
# License: BSD-2-Clause
#

. ./lib.sh

PKG_BASE="base-full"

if [ -n "$MKROOTFS_ROOT_DIR" ]; then
    ROOT_DIR="$MKROOTFS_ROOT_DIR"
else
    ROOT_DIR="build"
fi

TAR_TYPE="ROOTFS"

usage() {
    cat <<EOF
Usage: $PROGNAME [opts] [ROOT_DIR]

Options:
 -A APK       Override the apk tool (default: apk)
 -a ARCH      Generate an image for ARCH (must be runnable on current machine)
 -b PACKAGE   The base package (default: base-full)
 -B TARBALL   Generate a delta tarball against TARBALL
 -o FILE      Output a FILE (default: chimera-linux-ARCH-${TAR_TYPE}-YYYYMMDD(-FLAVOR).tar.gz)
 -f FLAVOR    Flavor name to include in default output file name
 -r REPO      Path to apk repository.
 -k DIR       Path to apk repository public key directory.
 -p PACKAGES  List of additional packages to install.
 -h           Print this message.
EOF
    exit ${1:=1}
}

APK_BIN="apk"
BASE_TAR=

if ! command -v "$APK_BIN" > /dev/null 2>&1; then
    die "invalid apk command"
fi

if ! command -v tar > /dev/null 2>&1; then
    die "tar needs to be installed"
fi

APK_ARCH=$(${APK_BIN} --print-arch)

run_apk() {
    "$APK_BIN" ${APK_REPO} --arch ${APK_ARCH} --root "$@" --no-interactive
}

while getopts "a:b:B:f:k:o:p:r:h" opt; do
    case "$opt" in
        A) APK_BIN="$OPTARG";;
        B) BASE_TAR="$OPTARG"; TAR_TYPE="DROOTFS";;
        a) APK_ARCH="$OPTARG";;
        b) PKG_BASE="$OPTARG";;
        f) FLAVOR="-$OPTARG";;
        k) APK_KEYDIR="$OPTARG";;
        K) KERNVER="$OPTARG";;
        o) OUT_FILE="$OPTARG";;
        p) PACKAGES="$OPTARG";;
        r) APK_REPO="$APK_REPO --repository $OPTARG";;
        h) usage 0 ;;
        *) usage ;;
    esac
done

shift $((OPTIND - 1))

# default output file
if [ -z "$OUT_FILE" ]; then
    OUT_FILE="chimera-linux-${APK_ARCH}-${TAR_TYPE}-$(date '+%Y%m%d')${FLAVOR}.tar.gz"
fi

# overlay
if [ -n "$BASE_TAR" -a ! -r "$BASE_TAR" ]; then
    die "invalid base tarball $BASE_TAR"
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
    ROOT_DIR="$1"
fi

if [ -d "$ROOT_DIR" ]; then
    die "$ROOT_DIR already exists"
fi

mkdir -p "${ROOT_DIR}" || die "failed to create directory"

# make absolute so that we aren't prone to bad cleanup with changed cwd
ROOT_DIR=$(realpath "$ROOT_DIR")

if [ -n "$BASE_TAR" ]; then
    ROOT_LOWER="${ROOT_DIR}/lower"
    ROOT_UPPER="${ROOT_DIR}/upper"
    ROOT_WORK="${ROOT_DIR}/work"
    ROOT_DIR="${ROOT_DIR}/merged"

    mkdir -p "${ROOT_LOWER}" || die "failed to create lower"
    mkdir -p "${ROOT_UPPER}" || die "failed to create upper"
    mkdir -p "${ROOT_WORK}" || die "failed to create work"
    mkdir -p "${ROOT_DIR}" || die "failed to create merged"

    # unpack the base tarball into lower
    tar -pxf "$BASE_TAR" -C "${ROOT_LOWER}" || die "failed to unpack base tar"

    # mount the overlay
    mount -t overlay overlay -o \
        "lowerdir=${ROOT_LOWER},upperdir=${ROOT_UPPER},workdir=${ROOT_WORK}" \
        "${ROOT_DIR}" || die "failed to mount overlay"

    TAR_DIR="${ROOT_UPPER}"
else
    # copy keys
    msg "Copying signing keys..."

    mkdir -p "${ROOT_DIR}/etc/apk/keys" || \
        die "failed to create keys directory"
    for k in "${APK_KEYDIR}"/*.pub; do
        [ -r "$k" ] || continue
        cp "$k" "${ROOT_DIR}/etc/apk/keys" || die "failed to copy key '$k'"
    done

    # install target packages
    msg "Installing target base packages..."

    run_apk "${ROOT_DIR}" --initdb add chimerautils \
        || die "failed to install chimerautils"

    TAR_DIR="${ROOT_DIR}"
fi

# needs to be available before adding full package set
msg "Mounting pseudo-filesystems..."
mount_pseudo

msg "Installing target packages..."
run_apk "${ROOT_DIR}" add ${PKG_BASE} ${PACKAGES} \
    || die "failed to install full rootfs"

msg "Cleaning up..."

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

msg "Setting up hostname and password..."

if [ -x "${ROOT_DIR}/usr/bin/init" ]; then
    # do not set it for tiny container images
    echo chimera > "${ROOT_DIR}/etc/hostname"
fi

if [ -x "${ROOT_DIR}/usr/bin/chpasswd" ]; then
    # we could use host chpasswd, but with chroot we know what we have
    echo root:chimera | chroot "${ROOT_DIR}" /usr/bin/chpasswd -c SHA512
fi

# clean up backup shadow etc
rm -f "${ROOT_DIR}/etc/shadow-" "${ROOT_DIR}/etc/gshadow-" \
      "${ROOT_DIR}/etc/passwd-" "${ROOT_DIR}/etc/group-" \
      "${ROOT_DIR}/etc/subuid-" "${ROOT_DIR}/etc/subgid-"

umount_pseudo

msg "Generating root filesystem tarball..."
tar -C "${TAR_DIR}" -cvpzf "${OUT_FILE}" . || die "tar failed"

msg "Successfully generated tarball (${OUT_FILE})"
