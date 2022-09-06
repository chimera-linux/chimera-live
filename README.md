# chimera-live

This repository contains tooling to manage creation of Chimera images.

This consists of the following scripts right now:

* `mklive.sh` - the live ISO image creator for BIOS, EFI and POWER/PowerPC systems
* `mkrootfs.sh` - root filesystem tarball creator

And the following auxiliary scripts:

* `mklive-image.sh` - wrapper around `mklive.sh` to create standardized images
* `mkrootfs-platform.sh` - wrapper around `mkrootfs.sh` to create standardized
  rootfs tarballs

More tools may be added over time.

## Bootstrapping the system with apk

In order to bootstrap the system into a directory (e.g. a partitioned and
mounted root file system), you can use just plain `apk`. The tooling here
is generally written around similar methods.

The bootstrap process typically needs a few stages.

Install `base-files` first. This is needed because of limitations of the
current `apk` version (`apk` will read the `passwd` and `group` files from
the target root to set file permissions, so this needs to be available
ahead of time).

The `--initdb` argument is important. You also need to fix up its permissions
manually.

```
# apk add --root /my/root --keys-dir /my/cports/etc/keys --repository /my/cports/packages/main --initdb add base-files
# chown -R root:root /my/root
```

Then you can install `base-minimal`. This is small enough that it is safe to
install without pseudo-filesystems mounted.

```
# apk add --root /my/root --keys-dir /my/cports/etc/keys --repository /my/cports/packages/main add base-minimal
```

The layout of `base-minimal` is set up so that it first depends on `base-bootstrap`,
which installs a very basic set of core packages that do not require running
any scripts. That means that by the time any scripts are executed, a reasonable
system is already present to run them.

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
# ./mkrootfs-platform.sh -P rpi4
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
