#!/bin/sh
# Mount a reflink-capable XFS filesystem at /var/lib/firecracker on the node.
#
# Each VM's disk is a reflink (copy-on-write) clone of a read-only base image,
# which needs XFS (reflink=1) or btrfs. The node's boot disk is ext4, so the
# store is a sparse XFS file on the boot disk, loop-mounted. It persists across
# pod restarts (the mount stays on the host) and node reboots (the file stays;
# this script re-attaches it). A local NVMe SSD formatted XFS would replace the
# file in production.
#
# The host's /var/lib is mounted at /host/var/lib with Bidirectional mount
# propagation, so the mount made here appears on the node and in every pod that
# mounts /var/lib/firecracker with HostToContainer propagation (firecracker-host
# itself, fc-agent).
#
# Inputs: FC_STORE_SIZE (default 60G, sparse).
set -eu

HOST_VAR_LIB=/host/var/lib
STORE_FILE="$HOST_VAR_LIB/firecracker-store.xfs"
MNT="$HOST_VAR_LIB/firecracker"
SIZE="${FC_STORE_SIZE:-60G}"

fstype() { stat -f -c %T "$MNT" 2>/dev/null || true; }

apk add --no-cache -q xfsprogs util-linux coreutils >/dev/null

if [ "$(fstype)" != xfs ]; then
  mkdir -p "$MNT"
  # Anything in the bare directory predates the store (or was written while it
  # was unmounted) and would sit hidden under the mount, using boot-disk space.
  if [ -n "$(ls -A "$MNT")" ]; then
    echo "removing contents of the unmounted $MNT: $(ls -A "$MNT" | tr '\n' ' ')"
    find "$MNT" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  fi
  if [ ! -f "$STORE_FILE" ]; then
    echo "creating $SIZE sparse XFS store at $STORE_FILE"
    truncate -s "$SIZE" "$STORE_FILE"
    mkfs.xfs -q -m reflink=1 -L fcstore "$STORE_FILE"
  fi
  loop=$(losetup -j "$STORE_FILE" | cut -d: -f1 | head -n1)
  [ -n "$loop" ] || loop=$(losetup -f --show "$STORE_FILE")
  echo "mounting $STORE_FILE ($loop) at $MNT"
  mount -t xfs -o noatime "$loop" "$MNT"
fi

[ "$(fstype)" = xfs ] || { echo "ERROR: $MNT is not XFS after mounting" >&2; exit 1; }
probe="$MNT/.reflink-probe"
echo probe > "$probe"
if ! cp --reflink=always "$probe" "$probe.clone"; then
  rm -f "$probe" "$probe.clone"
  echo "ERROR: $MNT does not support reflink clones" >&2
  exit 1
fi
rm -f "$probe" "$probe.clone"
echo "store ready: $(df -h "$MNT" | awk 'NR==2 {print $2 " total, " $3 " used"}'), reflink ok"
