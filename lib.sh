#!/bin/sh
#
# Shared functions to be used by image creation scripts.
#
# Copyright 2022 Daniel "q66" Kolesa
#
# License: BSD-2-Clause
#

umask 022

readonly PROGNAME=$(basename "$0")

mount_pseudo() {
    mount -t devtmpfs none "${ROOT_DIR}/dev" || die "failed to mount devfs"
    mount -t proc none "${ROOT_DIR}/proc" || die "failed to mount procfs"
    mount -t sysfs none "${ROOT_DIR}/sys" || die "failed to mount sysfs"
}

umount_pseudo() {
    [ -z "$ROOT_DIR" ] && return 0
    sync
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

if [ "$(id -u)" != "0" ]; then
    die "must be run as root"
fi
