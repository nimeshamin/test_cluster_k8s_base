#!/bin/sh
# Mount a reflink-capable XFS filesystem at /var/lib/firecracker on the node.
#
# Each VM's disk is a reflink (copy-on-write) clone of a read-only base image,
# which needs XFS (reflink=1) or btrfs. The node's boot disk is ext4, so:
#
#   - if the node has a raw local NVMe SSD (GKE local_nvme_ssd_block_config),
#     the first one is formatted XFS (once) and mounted;
#   - otherwise a sparse XFS file on the boot disk is loop-mounted.
#
# Either way the store persists across pod restarts (the mount stays on the
# host) and node reboots (this script re-mounts it). Local SSD contents do not
# survive the node being recreated.
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

# Prints the first raw GCE local NVMe SSD (e.g. nvme1n1), or nothing. Local
# SSDs report the model "nvme_card"; NVMe persistent disks (including an NVMe
# boot disk) report "nvme_card-pd". Devices that are mounted or partitioned are
# skipped, so this can never pick the boot disk.
local_ssd() {
  for sys in /sys/block/nvme*n*; do
    [ -e "$sys" ] || continue
    dev=$(basename "$sys")
    model=$(tr -d ' \n' < "$sys/device/model" 2>/dev/null || true)
    [ "$model" = nvme_card ] || continue
    partitioned=no
    for part in "$sys/${dev}p"*; do
      [ -e "$part" ] && partitioned=yes
    done
    [ "$partitioned" = no ] || continue
    grep -qE "^/dev/${dev}( |p)" /proc/mounts && continue
    echo "$dev"
    return
  done
}

apk add --no-cache -q xfsprogs util-linux coreutils >/dev/null

if [ "$(fstype)" != xfs ]; then
  mkdir -p "$MNT"
  # Anything in the bare directory predates the store (or was written while it
  # was unmounted) and would sit hidden under the mount, using boot-disk space.
  if [ -n "$(ls -A "$MNT")" ]; then
    echo "removing contents of the unmounted $MNT: $(ls -A "$MNT" | tr '\n' ' ')"
    find "$MNT" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  fi
  ssd=$(local_ssd)
  if [ -n "$ssd" ]; then
    dev="/dev/$ssd"
    if [ "$(blkid -s TYPE -o value "$dev" 2>/dev/null || true)" != xfs ]; then
      echo "formatting local NVMe SSD $dev ($(($(cat "/sys/block/$ssd/size") / 2097152)) GiB) as XFS"
      mkfs.xfs -q -f -m reflink=1 -L fcstore "$dev"
    fi
    echo "mounting local NVMe SSD $dev at $MNT"
    mount -t xfs -o noatime "$dev" "$MNT"
  else
    if [ ! -f "$STORE_FILE" ]; then
      echo "no local NVMe SSD; creating $SIZE sparse XFS store at $STORE_FILE"
      truncate -s "$SIZE" "$STORE_FILE"
      mkfs.xfs -q -m reflink=1 -L fcstore "$STORE_FILE"
    fi
    loop=$(losetup -j "$STORE_FILE" | cut -d: -f1 | head -n1)
    [ -n "$loop" ] || loop=$(losetup -f --show "$STORE_FILE")
    echo "no local NVMe SSD; mounting $STORE_FILE ($loop) at $MNT"
    mount -t xfs -o noatime "$loop" "$MNT"
  fi
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
echo "store ready on $(awk -v m="$MNT" '$2 == m {print $1}' /proc/mounts): $(df -h "$MNT" | awk 'NR==2 {print $2 " total, " $3 " used"}'), reflink ok"
