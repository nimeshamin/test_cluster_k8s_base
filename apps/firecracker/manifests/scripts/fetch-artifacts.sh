#!/bin/sh
# Stage a pinned Firecracker release, guest kernel, and ext4 rootfs on the node
# under /var/lib/firecracker, then write current.env pointing at them.
# Idempotent: anything already present for the pinned versions is reused.
#
# Inputs (from the firecracker-artifacts ConfigMap):
#   FC_VERSION, FC_SHA256, FC_CI_PREFIX, FC_KERNEL, FC_ROOTFS
set -eu

ARCH=x86_64
ROOT=/var/lib/firecracker
S3=https://s3.amazonaws.com/spec.ccfc.min
RELEASE_DIR="$ROOT/release/$FC_VERSION"
IMAGE_DIR="$ROOT/images/$(basename "$FC_CI_PREFIX")"
KERNEL_PATH="$IMAGE_DIR/$FC_KERNEL"
ROOTFS_PATH="$IMAGE_DIR/$FC_ROOTFS.ext4"

mkdir -p "$RELEASE_DIR" "$IMAGE_DIR"

if [ ! -x "$RELEASE_DIR/firecracker" ] || [ ! -f "$KERNEL_PATH" ] || [ ! -f "$ROOTFS_PATH" ]; then
  apk add --no-cache curl squashfs-tools e2fsprogs >/dev/null
fi

if [ ! -x "$RELEASE_DIR/firecracker" ]; then
  echo "fetching firecracker $FC_VERSION"
  tmp=$(mktemp -d)
  tgz="firecracker-$FC_VERSION-$ARCH.tgz"
  curl -fsSL -o "$tmp/$tgz" \
    "https://github.com/firecracker-microvm/firecracker/releases/download/$FC_VERSION/$tgz"
  echo "$FC_SHA256  $tmp/$tgz" | sha256sum -c -
  tar -xzf "$tmp/$tgz" -C "$tmp"
  install -m 0755 "$tmp/release-$FC_VERSION-$ARCH/firecracker-$FC_VERSION-$ARCH" "$RELEASE_DIR/firecracker.part"
  install -m 0755 "$tmp/release-$FC_VERSION-$ARCH/jailer-$FC_VERSION-$ARCH" "$RELEASE_DIR/jailer"
  mv "$RELEASE_DIR/firecracker.part" "$RELEASE_DIR/firecracker"
  rm -rf "$tmp"
fi

if [ ! -f "$KERNEL_PATH" ]; then
  echo "fetching kernel $FC_KERNEL"
  curl -fsSL -o "$KERNEL_PATH.part" "$S3/$FC_CI_PREFIX/$ARCH/$FC_KERNEL"
  mv "$KERNEL_PATH.part" "$KERNEL_PATH"
fi

if [ ! -f "$ROOTFS_PATH" ]; then
  echo "building rootfs $FC_ROOTFS.ext4"
  tmp=$(mktemp -d -p "$ROOT")
  curl -fsSL -o "$tmp/rootfs.squashfs" "$S3/$FC_CI_PREFIX/$ARCH/$FC_ROOTFS.squashfs"
  unsquashfs -q -d "$tmp/root" "$tmp/rootfs.squashfs"
  truncate -s 1G "$tmp/rootfs.ext4"
  mkfs.ext4 -q -d "$tmp/root" -F "$tmp/rootfs.ext4"
  e2fsck -fn "$tmp/rootfs.ext4" >/dev/null
  mv "$tmp/rootfs.ext4" "$ROOTFS_PATH"
  rm -rf "$tmp"
fi

cat > "$ROOT/current.env.part" <<ENV
FC_BIN=$RELEASE_DIR/firecracker
FC_JAILER=$RELEASE_DIR/jailer
FC_KERNEL_PATH=$KERNEL_PATH
FC_ROOTFS_PATH=$ROOTFS_PATH
ENV
mv "$ROOT/current.env.part" "$ROOT/current.env"
echo "staged:"; cat "$ROOT/current.env"
