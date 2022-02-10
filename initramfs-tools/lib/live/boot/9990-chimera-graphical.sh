# this sets up graphical autologin
#
# a part of chimera linux, license: BSD-2-Clause

Chimera_Graphical() {
    log_begin_msg "Setting up display manager"

    for _PARAMETER in ${LIVE_BOOT_CMDLINE}; do
        case "${_PARAMETER}" in
            nowayland) FORCE_X11=1;;
            nogui) FORCE_CONSOLE=1;;
        esac
    done

    # GUI disabled, do not enable any DM
    if [ -n "$FORCE_CONSOLE" ]; then
        log_end_msg
        return
    fi

    if [ -f "/root/etc/dinit.d/gdm" ]; then
        # enable service
        Chimera_Service gdm boot
        # autologin
        cat > /root/etc/gdm/custom.conf << EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=anon
EOF
        # possibly force X11
        if [ -n "$FORCE_X11" ]; then
            echo "WaylandEnable=false" >> /root/etc/gdm/custom.conf
        fi
    fi

    log_end_msg
}
