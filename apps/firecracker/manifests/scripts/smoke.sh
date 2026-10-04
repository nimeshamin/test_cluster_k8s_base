#!/bin/sh
# Boot one throwaway microVM from the staged kernel and rootfs, wait for the
# guest to reach a login prompt on the serial console, then tear it down.
#
# Usage: smoke.sh [timeout_seconds]   (default 60)
set -eu

TIMEOUT="${1:-60}"
. /var/lib/firecracker/current.env

RUN_DIR="/var/lib/firecracker/runs/smoke-$(date +%s)-$$"
FC_PID=
cleanup() {
  [ -n "$FC_PID" ] && kill "$FC_PID" 2>/dev/null || true
  rm -rf "$RUN_DIR"
}
trap cleanup EXIT INT TERM

mkdir -p "$RUN_DIR"
# Each run gets its own writable reflink clone (copy-on-write, instant) so the
# read-only base image stays pristine. Needs GNU cp (coreutils).
cp --reflink=always "$FC_ROOTFS_PATH" "$RUN_DIR/rootfs.ext4"
chmod 0644 "$RUN_DIR/rootfs.ext4"

cat > "$RUN_DIR/vm.json" <<JSON
{
  "boot-source": {
    "kernel_image_path": "$FC_KERNEL_PATH",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"
  },
  "drives": [
    {
      "drive_id": "rootfs",
      "path_on_host": "$RUN_DIR/rootfs.ext4",
      "is_root_device": true,
      "is_read_only": false
    }
  ],
  "machine-config": { "vcpu_count": 1, "mem_size_mib": 512 }
}
JSON

echo "booting microVM (timeout ${TIMEOUT}s)"
start=$(date +%s)
"$FC_BIN" --no-api --id smoke --config-file "$RUN_DIR/vm.json" >"$RUN_DIR/serial.log" 2>&1 &
FC_PID=$!

while :; do
  elapsed=$(( $(date +%s) - start ))
  if grep -q 'login:' "$RUN_DIR/serial.log"; then
    echo "PASS  guest reached login prompt in ~${elapsed}s"
    grep -m1 'Linux version' "$RUN_DIR/serial.log" || true
    exit 0
  fi
  if ! kill -0 "$FC_PID" 2>/dev/null; then
    echo "FAIL  firecracker exited after ${elapsed}s; last serial output:" >&2
    tail -n 40 "$RUN_DIR/serial.log" >&2
    exit 1
  fi
  if [ "$elapsed" -ge "$TIMEOUT" ]; then
    echo "FAIL  no login prompt within ${TIMEOUT}s; last serial output:" >&2
    tail -n 40 "$RUN_DIR/serial.log" >&2
    exit 1
  fi
  sleep 1
done
