# chimera-live

This repository contains tooling to manage creation of Chimera images.

Currently this just means live ISO images, but later also rootfs tarballs,
pre-made SBC board SD card images and so on.

## Bootstrapping the system with apk

In order to bootstrap the system into a directory (e.g. a partitioned and
mounted root file system), you can use just plain `apk`. The tooling here
is generally written around similar methods.

The bootstrap process typically needs a few stages.

First, install the `base-bootstrap` package into your target root. This is
a special minimal metapackage that creates a tiny, incomplete, but working
system and does not need to run any hooks. That is important, because the
environment is not yet set up to run hooks until that is installed.

The `--initdb` argument is important.

```
# apk add --root /my/root --keys-dir /my/cports/etc/keys --repository /my/cports/packages/main --initdb add base-bootstrap
```

This will install a relatively small number of packages. Such system already
has a shell so it can be chrooted into. Of course, we want to install a real,
mostly complete metapackage:

```
# apk add --root /my/root --keys-dir /my/cports/etc/keys --repository /my/cports/packages/main add base-minimal
```

This gets you `base-minimal`. This is already far more complete and contains
things like `util-linux` as well as `apk-tools`.

Now is a good time to copy your public key in for `apk` and delete `base-bootstrap`.
You no longer have to pass the keys directory after that.

```
# mkdir -p /my/root/etc/apk/keys
# cp /my/cports/etc/keys/*.pub /my/root/etc/apk/keys
# apk del --root /my/root --repository /my/cports/packages/main del base-bootstrap
```

More advanced base metapackages may require pseudo-filesystems in their hooks.
If you want to install them, proceed like this:

```
# mount -t proc none /my/root/proc
# mount -t sysfs none /my/root/sys
# mount -t devtmpfs none /my/root/dev
```

Then you can install e.g. `base-full` if you wish.

```
# apk del --root /my/root --repository /my/cports/packages/main add base-full
```

Once you are done, don't forget to clean up.

```
# umount /my/root/dev
# umount /my/root/sys
# umount /my/root/proc
# rm -rf /my/root/run /my/root/tmp /my/root/var/cache /my/root/var/run
# mkdir -p /my/root/run /my/root/tmp /my/root/var/cache /my/root/var/run
```

That's basically all. You can install whatever else you want, of course.
