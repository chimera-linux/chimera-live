#!/bin/sh
#
# Convenience script for publishing Docker images
#
# Needs podman set up

# architectures we have an overlap with docker
ARCHS="aarch64 ppc64le riscv64 x86_64"
MANIFEST="chimeralinux/chimera:latest"

if command -v sudo > /dev/null 2>&1; then
    AS_ROOT=sudo
else
    AS_ROOT=doas
fi

if ! command -v podman > /dev/null 2>&1; then
    echo "Podman must be set up"
    exit 1
fi

if [ -z "$1" -o -d "$1" ]; then
    echo "Target directory must be given and must not exist"
    exit 1
fi

ARCHS="aarch64 ppc64le riscv64 x86_64"
TARGET_DIR="$1"

mkdir -p "$TARGET_DIR"

for archn in $ARCHS; do
    $AS_ROOT ./mkrootfs-platform.sh -P bootstrap -- -a "$archn" -o "${TARGET_DIR}/bootstrap-${archn}.tar.gz" "${TARGET_DIR}/build-${archn}"
    if [ $? -ne 0 ]; then
        echo "Failed to bootstrap rootfs for $archn"
        exit 1
    fi
    # generate dockerfiles
    cat << EOF > "${TARGET_DIR}/Dockerfile.$archn"
FROM scratch
ADD bootstrap-${archn}.tar.gz /
CMD ["/bin/sh"]
EOF
done

cd "$TARGET_DIR"

drop_manifest() {
    podman manifest rm "$MANIFEST"
    for archn in $ARCHS; do
        podman rmi "${MANIFEST}-$archn"
    done
}

# just in case
podman login

# now generate a dockerfile for each tarball and build
for archn in $ARCHS; do
    # mappings for all known archs
    case "$archn" in
        aarch64) DOCKER_ARCH="linux/arm64/v8";;
        ppc64le) DOCKER_ARCH="linux/ppc64le";;
        riscv64) DOCKER_ARCH="linux/riscv64";;
        x86_64) DOCKER_ARCH="linux/amd64";;
        *)
            echo "Unknown Docker arch: $archn"
            exit 1
            ;;
    esac
    podman build --tag "${MANIFEST}-$archn" \
        --platform "$DOCKER_ARCH" \
        --manifest "$MANIFEST" \
        -f Dockerfile.$archn .
    if [ $? -ne 0 ]; then
        echo "Failed to build image for $DOCKER_ARCH"
        drop_manifest
        exit 1
    fi
done

podman manifest push "$MANIFEST"
if [ $? -ne 0 ]; then
    echo "Failed to push manifest $MANIFEST"
    drop_manifest
    exit 1
fi

drop_manifest

echo "Successfully generated and published Docker images."
exit 0
