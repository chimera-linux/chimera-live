#!/bin/sh
#
# Chimera Linux rootfs creation tool
#
# Copyright 2022 Daniel "q66" Kolesa
#
# License: BSD-2-Clause
#

. ./lib.sh

PKG_BASE="base-core"
ROOT_DIR="build"

usage() {
    cat <<EOF
Usage: $PROGNAME [opts] [ROOT_DIR]

Options:
 -A APK       Override the apk tool (default: apk)
 -a ARCH      Generate an image for ARCH (must be runnable on current machine)
 -b PACKAGE   The base package (default: base-core)
 -o FILE      Output a FILE (default: chimera-linux-ARCH-ROOTFS-YYYYMMDD(-FLAVOR).tar.gz)
 -f FLAVOR    Flavor name to include in default output file name
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

if ! command -v tar > /dev/null 2>&1; then
    die "tar needs to be installed"
fi

APK_ARCH=$(${APK_BIN} --print-arch)

run_apk() {
    "$APK_BIN" ${APK_REPO} --root "$@"
}

while getopts "a:b:f:k:o:p:r:h" opt; do
    case "$opt" in
        A) APK_BIN="$OPTARG";;
        a) APK_ARCH="$OPTARG";;
        b) PKG_BASE="$OPTARG";;
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

# default output file
if [ -z "$OUT_FILE" ]; then
    OUT_FILE="chimera-linux-${APK_ARCH}-ROOTFS-$(date '+%Y%m%d')${FLAVOR}.tar.gz"
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
    ROOT_DIR="$1"
fi

# make absolute so that we aren't prone to bad cleanup with changed cwd
ROOT_DIR=$(realpath "$ROOT_DIR")

if [ -d "$ROOT_DIR" ]; then
    die "$ROOT_DIR already exists"
fi

mkdir -p "${ROOT_DIR}" || die "failed to create directory"

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
run_apk "${ROOT_DIR}" add ${PKG_BASE} ${PACKAGES} \
    || die "failed to install full rootfs"

umount_pseudo

msg "Generating root filesystem tarball..."
tar -C "${ROOT_DIR}" -cvpf "${OUT_FILE}" . || die "tar failed"

msg "Successfully generated tarball (${OUT_FILE})"
