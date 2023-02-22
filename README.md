# chimera-live

This repository contains tooling to manage creation of Chimera images.

This consists of the following scripts right now:

* `mklive.sh` - the live ISO image creator for BIOS, EFI and POWER/PowerPC systems
* `mkrootfs.sh` - root filesystem tarball creator
* `mkimage.sh` - device image creator

And the following auxiliary scripts:

* `mklive-image.sh` - wrapper around `mklive.sh` to create standardized images
* `mkrootfs-platform.sh` - wrapper around `mkrootfs.sh` to create standardized
  rootfs tarballs

More tools may be added over time.

## Bootstrapping the system with apk

In order to bootstrap the system into a directory (e.g. a partitioned and
mounted root file system), you can use just plain `apk`. The tooling here
is generally written around similar methods.

First, bootstrap your root with a package that is safe to install without
pseudo-filesystems mounted in the target. That means `base-bootstrap`
(which is very tiny) or `base-minimal` (which is a bit bigger), typically
this does not really matter.

It is important to use `--initdb`, and it is also very important to have
**at least apk-tools 3aa99faa83d08e45eff8a5cc95c4df16fb5bd257**, as older
versions will mess up permissions on the initial files.

```
# apk add --root /my/root --keys-dir /my/cports/etc/keys --repository /my/cports/packages/main --initdb add base-minimal
# chown -R root:root /my/root
```

Now is a good time to copy your public key in for `apk` so you do not have to pass it.

```
# mkdir -p /my/root/etc/apk/keys
# cp /my/cports/etc/keys/*.pub /my/root/etc/apk/keys
```

More advanced base metapackages may require pseudo-filesystems in their hooks.
If you want to install them, proceed like this:

```
# mount -t proc none /my/root/proc
# mount -t sysfs none /my/root/sys
# mount -t devtmpfs none /my/root/dev
# mount --bind /tmp /my/root/tmp
```

Then you can install e.g. `base-full` if you wish.

```
# apk --root /my/root --repository /my/cports/packages/main add base-full
```

Once you are done, don't forget to clean up.

```
# umount /my/root/tmp
# umount /my/root/dev
# umount /my/root/sys
# umount /my/root/proc
# rm -rf /my/root/run /my/root/var/tmp /my/root/var/cache
# mkdir -p /my/root/run /my/root/var/tmp /my/root/var/cache
# chmod 777 /my/root/var/tmp
```

That's basically all. You can install whatever else you want, of course.

## Creating live images with mklive-image.sh and mklive.sh

The `mklive-image.sh` script is a high level wrapper around `mklive.sh`.

Its basic usage is like this (as root):

```
# ./mklive-image.sh -b base
```

It only takes two optional arguments, `-b IMAGE` and `-p EXTRA_PACKAGES`.
The `IMAGE` is the supported image type (currently `base` for base console-only
images and `gnome` for graphical GNOME images). The other argument lets you
install packages in addition to the set provided by `IMAGE`.

You can also pass-through additional arguments to `mklive.sh` by specifying
them after `--`, e.g. `./mklive-image.sh -b base -- -f myflavor ...`.

It is also possible to use `mklive.sh` raw. You can get the full listing of
supported arguments like this:

```
# ./mklive.sh -h
```

Invoking `mklive.sh` with no arguments will generate a basic ISO for the
current architecture, using remote repositories. The `base-full` metapackage
serves as the base package. Note that this is not equivalent to the `base` image
of `mklive-image.sh`, as that contains some additional packages.

You can specify arguments to do things such as using your own repos with your own
signing key, additional packages and so on.

## Creating rootfs tarballs with mkrootfs-platform.sh and mkrootfs.sh

The `mkrootfs-platform.sh` script is a high level wrapper around `mkrootfs.sh`.

Its basic usage is like this (as root):

```
# ./mkrootfs-platform.sh -P rpi
```

It only takes two optional arguments, `-P PLATFORM` and `-p EXTRA_PACKAGES`.
The `PLATFORM` is the supported platform type (represented by`core` which is the
`mkrootfs.sh` default of using `base-core`, `minimal` which uses `base-minimal`
and then device-specific platform images such as `rpi` and `pbp`).

The `mkrootfs.sh` script takes largely identical arguments to `mklive.sh` (see `-h`)
but instead of ISO images, it creates root file system tarballs. Running it without
arguments will create a basic root file system tarball using remote repositories.
The `base-core` metapackage is the default, but you can override it, e.g.

```
# ./mkrootfs.sh -b base-minimal
```

## Creating device images with mkimage.sh

The `mkimage.sh` script creates device images from platform tarballs. The simplest
usage looks like this:

```
# ./mkimage.sh chimera-linux-aarch64-ROOTFS-20220906-rpi.tar.gz
```

It by default autodetects the device type from the filename. Then it creates a device
image that you can directly write onto removable media (e.g. an SD card for Raspberry
Pi). The image normally contains 2 partitions (by default, a 256MiB `/boot` `vfat`
and the rest an `ext4` partition for `/`, the total being 2GiB). The file system
types and sizes can be overridden, as can the device type.

After partition setup, it unpacks the rootfs tarball and performs additional setup
that is device-specific, typically bootloader setup. It also sets a default hostname,
root password (`chimera`) and enables services necessary for initial function (e.g.
`agetty` for serial console). The output is a `gzip`-compressed image.
