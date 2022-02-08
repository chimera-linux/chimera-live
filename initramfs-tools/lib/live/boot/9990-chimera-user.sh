# this sets up the user in the live environment
#
# a part of chimera linux, license: BSD-2-Clause

Chimera_Service() {
    if [ -f /root/etc/dinit.d/$1 ]; then
        ln -sf ../$1 /root/etc/dinit.d/$2.d/$1
    fi
}

Chimera_Userserv() {
    if [ -f /root/etc/dinit.d/user/$1 ]; then
        ln -sf ../$1 /root/home/$2/.config/dinit.d/boot.d/$1
    fi
}

Chimera_User() {
    log_begin_msg "Setting up user"

    [ -x /root/usr/bin/mksh ] && USERSHELL="/usr/bin/mksh"
    [ -z "$USERSHELL" ] && USERSHELL="/bin/sh"

    chroot /root useradd -m -c anon -G audio,video,wheel -s "$USERSHELL" anon

    chroot /root sh -c 'echo "root:chimera"|chpasswd -c SHA512'
    chroot /root sh -c 'echo "anon:chimera"|chpasswd -c SHA512'

    if [ -x /root/usr/bin/doas ]; then
        echo "permit persist :wheel" >> /root/etc/doas.conf
        chmod 600 /root/etc/doas.conf
    fi

    if [ -f /root/etc/sudoers ]; then
        echo "%wheel ALL=(ALL) ALL" >> /root/etc/sudoers
    fi

    # enable services
    Chimera_Service dinit-userservd login
    Chimera_Service dbus login
    Chimera_Service elogind login
    Chimera_Service syslog-ng login
    Chimera_Service sshd boot

    # enable user services
    chroot /root mkdir -p /home/anon/.config/dinit.d/boot.d
    Chimera_Userserv dbus anon
    Chimera_Userserv pipewire-pulse anon
    Chimera_Userserv pipewire anon
    Chimera_Userserv wireplumber anon
    # fix up permissions
    chroot /root chown -R anon:anon /home/anon

    log_end_msg
}
