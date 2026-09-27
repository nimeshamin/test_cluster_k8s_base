#!/usr/bin/env bash
# Report whether every firecracker-host pod is ready and its node can run
# Firecracker (/dev/kvm, CPU virtualization flags, binary, kernel, rootfs).
# Exits non-zero if there are no pods or any check fails.
#
# Env overrides:
#   KUBE_CONTEXT   kubectl context (default: current)
#   NAMESPACE      firecracker namespace (default: firecracker)
set -euo pipefail

NAMESPACE="${NAMESPACE:-firecracker}"
SELECTOR="app.kubernetes.io/name=firecracker-host"

CTX_ARGS=()
[[ -n "${KUBE_CONTEXT:-}" ]] && CTX_ARGS=(--context="$KUBE_CONTEXT")
k() { kubectl "${CTX_ARGS[@]}" "$@"; }

echo "== nodes labelled firecracker=true"
k get nodes -l firecracker=true -o wide
echo
echo "== firecracker-host pods"
k -n "$NAMESPACE" get pods -l "$SELECTOR" -o wide

pods=$(k -n "$NAMESPACE" get pods -l "$SELECTOR" -o jsonpath='{.items[*].metadata.name}')
if [[ -z "$pods" ]]; then
  echo "FAIL  no firecracker-host pods; DaemonSet status and recent events:" >&2
  k -n "$NAMESPACE" describe daemonset firecracker-host >&2 || true
  exit 1
fi

status=0
for pod in $pods; do
  node=$(k -n "$NAMESPACE" get pod "$pod" -o jsonpath='{.spec.nodeName}')
  echo
  echo "== $pod on $node"
  phase=$(k -n "$NAMESPACE" get pod "$pod" -o jsonpath='{.status.phase}')
  if [[ "$phase" != "Running" ]]; then
    echo "FAIL  pod is $phase; recent events:" >&2
    k -n "$NAMESPACE" get events --field-selector "involvedObject.name=$pod" \
      --sort-by=.lastTimestamp | tail -n 10 >&2
    status=1
    continue
  fi
  k -n "$NAMESPACE" exec "$pod" -c host -- sh /opt/firecracker/scripts/check.sh || status=1
done
exit "$status"
