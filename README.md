# chimera-live

This repository contains tooling to manage creation of Chimera images.

This consists of the following scripts right now:

* `mklive.sh` - the live ISO image creator for BIOS, EFI and POWER/PowerPC systems
* `mkrootfs.sh` - root filesystem tarball creator

And the following auxiliary scripts:

* `mklive-image.sh` - wrapper around `mklive.sh` to create standardized images

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
