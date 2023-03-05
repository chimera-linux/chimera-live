# this sets up the user in the live environment
#
# a part of chimera linux, license: BSD-2-Clause

Chimera_Service() {
    if [ -f /root/etc/dinit.d/$1 ]; then
        ln -sf ../$1 /root/etc/dinit.d/boot.d/$1
    fi
}

Chimera_Userserv() {
    if [ -f /root/etc/dinit.d/user/$1 ]; then
        ln -sf ../$1 /root/home/$2/.config/dinit.d/boot.d/$1
    fi
}

Chimera_Getty() {
    local ttyn speed dspeed cflags confname gargs
    # sanitize the input string a bit
    ttyn=$1
    ttyn=${ttyn#/dev/}
    speed=$ttyn
    speed=${speed#*,}
    if [ "$speed" = "$ttyn" ]; then
        speed=
    fi
    ttyn=${ttyn%,*}
    # ensure it exists
    [ -c "/dev/$ttyn" ] || return 0
    # filter some stuff out
    case $ttyn in
        tty[0-9]*) return 0 ;; # skip graphical ttys; managed differently
        console) return 0 ;;
        *)
            # check if we have a matching agetty
            if [ ! -f "/root/etc/dinit.d/agetty-$ttyn" ]; then
                return 0
            fi
            ;;
    esac
    # ensure it's not active already
    [ -L "/root/etc/dinit.d/boot.d/$ttyn" ] && return 0
    # ensure it's a terminal
    dspeed=$(stty -f "/dev/$ttyn" speed 2>/dev/null)
    if [ $? -ne 0 ]; then
        # not a terminal
        return 0
    fi
    # generate an environment file
    confname="/root/etc/default/agetty-$ttyn"
    rm -f "$confname"
    # always assume local line for additional non-graphical consoles
    # also do not clear the terminal before login prompt when doing serial
    gargs="-L --noclear"
    if [ -n "$speed" ]; then
        # speed was given
        case "$speed" in
            *n8*)
                speed=${speed%n*}
                gargs="$gargs -8"
                ;;
            *[oen]*)
                speed=${speed%o*}
                speed=${speed%e*}
                speed=${speed%n*}
                ;;
            *)
                # assume 8bit no parity
                gargs="$gargs -8"
                ;;
        esac
    else
        # detect
        speed=$dspeed
        cflags=$(stty -f "/dev/$ttyn" | grep "^cflags: " 2>/dev/null)
        if [ "$cflags" != "${cflags#*cs8 -parenb}" ]; then
            # detected 8bit no parity
            gargs="$gargs -8"
        fi
    fi
    echo "GETTY_BAUD=${speed}" >> "$confname"
    echo "GETTY_TERM=vt100" >> "$confname"
    echo "GETTY_ARGS='$gargs'" >> "$confname"
    # activate the service
    Chimera_Service "agetty-$ttyn"
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

    # chimera-live-*
    for x in /lib/live/data/chimera-live-*; do
        [ -f "$x" ] || continue
        cp $x /root/usr/bin
        chmod 755 "/root/usr/bin/$(basename $x)"
    done

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

    # enable default services
    Chimera_Service rtkit
    Chimera_Service polkitd
    Chimera_Service syslog-ng

    # use networkmanager if installed, e.g. for gnome integration
    if [ -f "/root/etc/dinit.d/networkmanager" ]; then
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
            console=*)
                Chimera_Getty "${_PARAMETER#console=}"
                ;;
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

    # try guessing active consoles, enable their respective gettys
    if [ -f /sys/devices/virtual/tty/console/active ]; then
        for _TTYN in $(cat /sys/devices/virtual/tty/console/active); do
            Chimera_Getty "$_TTYN"
        done
    fi

    # enable user services
    chroot /root mkdir -p "/home/${USERNAME}/.config/dinit.d/boot.d"
    Chimera_Userserv pipewire-pulse "$USERNAME"
    Chimera_Userserv wireplumber "$USERNAME"
    # fix up permissions
    chroot /root chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}"

    log_end_msg
}
