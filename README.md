# chimera-live

This repository contains tooling to manage creation of Chimera images.

Currently this just means live ISO images, but later also rootfs tarballs,
pre-made SBC board SD card images and so on.

## Examples:

`mklive-image.sh` is a convenience script for generating different kinds of
live images, currently `base` and `gnome` are supported. E.g.

    sudo ./mklive-image.sh -b base -- -r /path/to/cports/packages/main -k path/to/cports/etc/keys/your-key.rsa.pub

`mklive.sh` does the actual building. You can call it directly. E.g.

    sudo ./mklive.sh -p "base-full linux pekwm xserver-xorg-minimal rxvt-unicode neofetch" \
      -f base -r /path/to/cports/packages/main -k path/to/cports/etc/keys/your-key.rsa.pub
