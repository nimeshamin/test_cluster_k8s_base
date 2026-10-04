#!/bin/sh
# Verify this node can run Firecracker. Exits non-zero on the first failure.
# --quiet prints failures only (used by the readiness probe).
set -u

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
ok() { [ "$QUIET" = 1 ] || echo "ok    $*"; }
fail() { echo "FAIL  $*" >&2; exit 1; }

ROOT=/var/lib/firecracker
[ "$(stat -f -c %T "$ROOT" 2>/dev/null)" = xfs ] || fail "$ROOT is not the XFS image store (prepare-store.sh)"
ok "$ROOT is XFS (reflink store)"

ENV_FILE=$ROOT/current.env
[ -f "$ENV_FILE" ] || fail "artifacts not staged ($ENV_FILE missing)"
. "$ENV_FILE"

[ -c /dev/kvm ] || fail "/dev/kvm is not a character device"
( exec 3<>/dev/kvm ) 2>/dev/null || fail "/dev/kvm is not readable and writable"
ok "/dev/kvm usable"

grep -qwE 'vmx|svm' /proc/cpuinfo || fail "no vmx/svm CPU flag (nested virtualization disabled?)"
ok "cpu virtualization flag present"

version=$("$FC_BIN" --version 2>&1 | head -1) || fail "firecracker binary did not run: $version"
ok "$version"

[ -f "$FC_KERNEL_PATH" ] || fail "kernel missing: $FC_KERNEL_PATH"
ok "kernel $FC_KERNEL_PATH"
[ -f "$FC_ROOTFS_PATH" ] || fail "base image missing: $FC_ROOTFS_PATH"
ok "base image $FC_ROOTFS_PATH"
ok "cached images: $(ls "$ROOT/images" | grep -v '^\.' | tr '\n' ' ')"
