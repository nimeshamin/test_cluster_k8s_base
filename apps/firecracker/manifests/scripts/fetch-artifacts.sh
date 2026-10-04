#!/bin/sh
# Stage a pinned Firecracker release, guest kernel, and the ubuntu base image
# on the node's XFS store (/var/lib/firecracker, mounted by prepare-store.sh),
# then write current.env pointing at them. Idempotent: anything already present
# for the pinned versions is reused.
#
# Layout:
#   release/<FC_VERSION>/{firecracker,jailer}
#   kernels/<ci build>/<FC_KERNEL>
#   images/<FC_ROOTFS>/{rootfs.ext4,image.json}   read-only base image; VM
#                                                 disks are reflink clones of it
# Other base images (e.g. node24) are added to images/ by fc-agent.
#
# Inputs (from the firecracker-artifacts ConfigMap):
#   FC_VERSION, FC_SHA256, FC_CI_PREFIX, FC_KERNEL, FC_ROOTFS
set -eu

ARCH=x86_64
ROOT=/var/lib/firecracker
S3=https://s3.amazonaws.com/spec.ccfc.min
RELEASE_DIR="$ROOT/release/$FC_VERSION"
KERNEL_DIR="$ROOT/kernels/$(basename "$FC_CI_PREFIX")"
KERNEL_PATH="$KERNEL_DIR/$FC_KERNEL"
IMAGE_DIR="$ROOT/images/$FC_ROOTFS"
ROOTFS_PATH="$IMAGE_DIR/rootfs.ext4"

[ "$(stat -f -c %T "$ROOT")" = xfs ] || { echo "ERROR: $ROOT is not the XFS store" >&2; exit 1; }
mkdir -p "$RELEASE_DIR" "$KERNEL_DIR"

# Rebuild the base image when it came from a different CI build.
if [ -f "$IMAGE_DIR/image.json" ] && ! grep -q "\"source\": \"$FC_CI_PREFIX/" "$IMAGE_DIR/image.json"; then
  echo "base image $FC_ROOTFS is from another CI build; rebuilding"
  rm -rf "$IMAGE_DIR"
fi

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
  echo "building base image $FC_ROOTFS"
  tmp="$ROOT/images/.tmp-$FC_ROOTFS"
  rm -rf "$tmp" && mkdir -p "$tmp"
  curl -fsSL -o "$tmp/rootfs.squashfs" "$S3/$FC_CI_PREFIX/$ARCH/$FC_ROOTFS.squashfs"
  unsquashfs -q -d "$tmp/root" "$tmp/rootfs.squashfs"
  truncate -s 1G "$tmp/rootfs.ext4"
  mkfs.ext4 -q -d "$tmp/root" -F "$tmp/rootfs.ext4"
  e2fsck -fn "$tmp/rootfs.ext4" >/dev/null
  rm -rf "$tmp/root" "$tmp/rootfs.squashfs"
  printf '{\n  "name": "%s",\n  "sha256": "%s",\n  "source": "%s"\n}\n' \
    "$FC_ROOTFS" "$(sha256sum "$tmp/rootfs.ext4" | cut -d' ' -f1)" "$FC_CI_PREFIX/$ARCH/$FC_ROOTFS.squashfs" \
    > "$tmp/image.json"
  chmod 0444 "$tmp/rootfs.ext4" "$tmp/image.json"
  chmod 0555 "$tmp"
  mv "$tmp" "$IMAGE_DIR"
fi

cat > "$ROOT/current.env.part" <<ENV
FC_BIN=$RELEASE_DIR/firecracker
FC_JAILER=$RELEASE_DIR/jailer
FC_KERNEL_PATH=$KERNEL_PATH
FC_ROOTFS_PATH=$ROOTFS_PATH
ENV
mv "$ROOT/current.env.part" "$ROOT/current.env"
echo "staged:"; cat "$ROOT/current.env"
