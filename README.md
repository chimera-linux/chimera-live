# chimera-live

This repository contains tooling to manage creation of Chimera images.

This consists of the following scripts right now:

* `mklive.sh` - the live ISO image creator for BIOS, EFI and POWER/PowerPC systems
* `mkrootfs.sh` - root filesystem tarball creator
* `mkpart.sh` - device partitioning tool
* `unrootfs.sh` - rootfs tarball extractor
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
pseudo-filesystems mounted in the target. That means `chimerautils`,
as every base metapackage installs stuff that needs scripts.

It is important to use `--initdb`, and it is also very important to have
**at least apk-tools 3aa99faa83d08e45eff8a5cc95c4df16fb5bd257**, as older
versions will mess up permissions on the initial files.

```
# apk add --root /my/root --keys-dir /my/cports/etc/keys --repository /my/cports/packages/main --initdb add chimerautils
```

More advanced base metapackages may require pseudo-filesystems in their hooks.
If you want to install them, proceed like this:

```
# mount -t proc none /my/root/proc
# mount -t sysfs none /my/root/sys
# mount -t devtmpfs none /my/root/dev
# mount --bind /tmp /my/root/tmp
```

Now is a good time to copy your public key in for `apk` so you do not have to pass it.

```
# mkdir -p /my/root/etc/apk/keys
# cp /my/cports/etc/keys/*.pub /my/root/etc/apk/keys
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

The `mkrootfs.sh` is also capable of creating delta tarballs. The invocation
only differs in that you pass a base tarball (previously created with the same
tool) via `-B some-base.tar.gz`. The new tarball will then only contain newly
added or changed files, creating a tarball that can be extracted over the
base tarball to get the whole thing.

## Setting up specific devices

The `mkpart.sh` and `unrootfs.sh` scripts allow you to prepare e.g. SD cards
of various devices from their rootfs tarballs.

For example, if you have an SD card at `/dev/mmcblk0` and want to install
Chimera for Pinebook Pro on it, you would do something like this:

```
# mkdir -p rootmnt
# ./mkpart.sh -j /dev/mmcblk0 pbp rootmnt
```

This will partition the SD card for the device. Generally for a device to
be supported here, it needs to have a disk layout file, in the `sfdisk`
directory. You can tweak various parameters via options (see `-h`). You
can of course also partition and mount the card manually.

Once that is done, you can perform the installation from the tarball:

```
# ./unrootfs.sh chimera-linux-aarch64-ROOTFS-...-pbp.tar.gz rootmnt /dev/mmcblk0
```

Multiple tarballs can be specified as a single argument, separated by
semicolons. They are extracted in that order. That means if you are using
delta tarballs, you should specify the base first and the overlay second,
like `base-tarball.tar.gz;delta-tarball.tar.gz`.

This will both install the system onto the card and install U-Boot onto the
card (as it's given as the last argument). If you omit the last argument,
no bootloader installation will be done.

After that, you can just unmount the directory and eject the card:

```
# umount -R rootmnt
# sync
```

If you want to create an image instead of setting up a physical storage device,
you can do so thanks to loop devices. First, create storage for the image,
in this example 8G:

```
# truncate -s 8G chimera.img
```

Then attach it with `losetup` and let it show which loop device is used:

```
# losetup --show -fP chimera.img
```

That will print for example `/dev/loop0`. Now all you have to do is pass that
path in place of the device path, e.g. `/dev/loop0` instead of `/dev/mmcblk0`.

Once you are done and have unmounted everything, detach it:

```
# losetup -d /dev/loop0
```

And that's about it.

## Creating device images with mkimage.sh

The `mkimage.sh` script simplifies creation of device images so that you do
not have to manipulate loop devices manually. However, it comes at the cost
of being far less flexible.

It accepts a prepared device rootfs tarball as its file name, or multiple
tarballs when using deltas. Optional arguments can be used to set the output
file name and the image size (by default 2G). It will also automatically
compress the image with `gzip`.

```
# ./mkimage.sh chimera-linux-aarch64-ROOTFS-20220906-rpi.tar.gz -- -j
```

The platform name, architecture and everything else is detected from the
input filename. Additional arguments passed after `--` will be passed as
optional arguments to `mkpart.sh`. In the example above, `-j` is passed
to disable journal for root filesystem.
