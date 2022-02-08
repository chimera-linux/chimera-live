# this sets up graphical autologin
#
# a part of chimera linux, license: BSD-2-Clause

Chimera_Graphical() {
    log_begin_msg "Setting up display manager"

    if [ -f "/root/etc/dinit.d/gdm" ]; then
        # enable service
        Chimera_Service gdm boot
        # autologin
        cat > /root/etc/gdm/custom.conf << EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=anon
EOF
    fi

    log_end_msg
}
