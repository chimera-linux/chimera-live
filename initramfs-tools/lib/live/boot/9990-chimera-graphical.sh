# this sets up graphical autologin
#
# a part of chimera linux, license: BSD-2-Clause

Chimera_Graphical() {
    log_begin_msg "Setting up display manager"

    for _PARAMETER in ${LIVE_BOOT_CMDLINE}; do
        case "${_PARAMETER}" in
            nogui) FORCE_CONSOLE=1;;
        esac
    done

    if [ -x /root/usr/bin/dconf ]; then
        # default dconf profile for custom tweaks
        chroot /root mkdir -p /etc/dconf/profile /etc/dconf/db/local.d
        cat << EOF > /root/etc/dconf/profile/user
user-db:user
system-db:local
EOF
        # disable gnome autosuspend in live environment
        cat << EOF > /root/etc/dconf/db/local.d/01-no-suspend
[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
power-button-action='interactive'
EOF
        # set appropriate homepage for GNOME Web
        cat << EOF > /root/etc/dconf/db/local.d/02-epiphany-homepage
[org/gnome/epiphany]
homepage-url='https://chimera-linux.org'
EOF
        # refresh
        chroot /root dconf update
    fi

    # GUI disabled, do not enable any DM
    if [ -n "$FORCE_CONSOLE" ]; then
        log_end_msg
        return
    fi

    if [ -f "/root/etc/dinit.d/gdm" ]; then
        # enable service
        Chimera_Service gdm
        # autologin
        cat > /root/etc/gdm/custom.conf << EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=anon
EOF
    fi

    if [ -f "/root/etc/dinit.d/sddm" ]; then
        # enable service
        Chimera_Service sddm
        # autologin
        mkdir -p /root/etc/sddm.conf.d
        cat > /root/etc/sddm.conf.d/autologin.conf << EOF
[Autologin]
User=anon
Session=plasma
EOF
    fi

    log_end_msg
}
