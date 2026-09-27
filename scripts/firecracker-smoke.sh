#!/usr/bin/env bash
# Boot a throwaway microVM on each firecracker-host pod (or just $POD) and
# wait for the guest to reach a login prompt on its serial console.
# Exits non-zero if any boot fails.
#
# Env overrides:
#   KUBE_CONTEXT   kubectl context (default: current)
#   NAMESPACE      firecracker namespace (default: firecracker)
#   POD            run on a single firecracker-host pod only
#   TIMEOUT        seconds to wait for the login prompt (default: 60)
set -euo pipefail

NAMESPACE="${NAMESPACE:-firecracker}"
TIMEOUT="${TIMEOUT:-60}"
SELECTOR="app.kubernetes.io/name=firecracker-host"

CTX_ARGS=()
[[ -n "${KUBE_CONTEXT:-}" ]] && CTX_ARGS=(--context="$KUBE_CONTEXT")
k() { kubectl "${CTX_ARGS[@]}" "$@"; }

pods="${POD:-$(k -n "$NAMESPACE" get pods -l "$SELECTOR" \
  --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}')}"
if [[ -z "$pods" ]]; then
  echo "FAIL  no running firecracker-host pods; run scripts/firecracker-check.sh" >&2
  exit 1
fi

status=0
for pod in $pods; do
  node=$(k -n "$NAMESPACE" get pod "$pod" -o jsonpath='{.spec.nodeName}')
  echo "== $pod on $node"
  k -n "$NAMESPACE" exec "$pod" -c host -- sh /opt/firecracker/scripts/smoke.sh "$TIMEOUT" || status=1
done
exit "$status"
