# this sets up the user in the live environment
#
# a part of chimera linux, license: BSD-2-Clause

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

    log_end_msg
}
