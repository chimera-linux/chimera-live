# this sets up the user in the live environment
#
# a part of chimera linux, license: BSD-2-Clause

Chimera_Service() {
    if [ -f /root/etc/dinit.d/$1 -o -f /root/usr/lib/dinit.d/$1 ]; then
        ln -sf ../$1 /root/etc/dinit.d/boot.d/$1
    fi
}

Chimera_User() {
    log_begin_msg "Setting up user"

    USERNAME="anon"
    USERPASS="chimera"
    [ -x /root/usr/bin/mksh ] && USERSHELL="/usr/bin/mksh"
    [ -z "$USERSHELL" ] && USERSHELL="/bin/sh"

    for _PARAMETER in ${LIVE_BOOT_CMDLINE}; do
        case "${_PARAMETER}" in
            live-user=*)
                USERNAME="${_PARAMETER#live-user=}"
                ;;
            live-password=*)
                USERPASS="${_PARAMETER#live-password=}"
                ;;
            live-shell=*)
                USERSHELL="${_PARAMETER#live-shell=}"
                ;;
        esac
    done

    # hostname; prevent syslog from doing dns lookup
    echo "127.0.0.1 $(cat /root/etc/hostname)" >> /root/etc/hosts
    echo "::1 $(cat /root/etc/hostname)" >> /root/etc/hosts

    # /etc/issue
    if [ -f "/lib/live/data/issue.in" ]; then
        sed \
            -e "s|@USER@|${USERNAME}|g" \
            -e "s|@PASSWORD@|${USERPASS}|g" \
            "/lib/live/data/issue.in" > /root/etc/issue
    fi

    chroot /root useradd -m -c "$USERNAME" -s "$USERSHELL" "$USERNAME"

    chroot /root sh -c "echo 'root:${USERPASS}'|chpasswd -c SHA512"
    chroot /root sh -c "echo '$USERNAME:${USERPASS}'|chpasswd -c SHA512"

    if [ -x /root/usr/bin/doas ]; then
        echo "permit persist $USERNAME" >> /root/etc/doas.conf
        chmod 600 /root/etc/doas.conf
    fi

    if [ -f /root/etc/sudoers ]; then
        echo "$USERNAME ALL=(ALL) ALL" >> /root/etc/sudoers
    fi

    # create boot.d as tmpfiles has not yet run
    chroot /root mkdir -p "/etc/dinit.d/boot.d"

    # enable default services
    Chimera_Service rtkit
    Chimera_Service polkitd
    Chimera_Service syslog-ng

    # use networkmanager if installed, e.g. for gnome integration
    if [ -f "/root/usr/lib/dinit.d/networkmanager" ]; then
        Chimera_Service networkmanager
    else
        Chimera_Service dhcpcd
    fi

    # handle explicitly given serial consoles, prefer this as we
    # don't need to guess stuff like parity information from stty
    #
    # also activate other services the user has explicitly requested
    for _PARAMETER in ${LIVE_BOOT_CMDLINE}; do
        case "${_PARAMETER}" in
            services=*)
                SERVICES="${_PARAMETER#services=}"
                OLDIFS=$IFS
                IFS=,
                for srv in ${SERVICES}; do
                    Chimera_Service "${srv}"
                done
                IFS=$OLDIFS
                unset OLDIFS
                ;;
        esac
    done

    log_end_msg
}
