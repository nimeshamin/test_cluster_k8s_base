#!/usr/bin/env bash
# Print the Grafana admin user and password from the chart-managed Secret.
# Outputs `user=<x>` and `password=<y>` so the result can be `eval`-ed:
#   eval "$(./get-grafana-credentials.sh)"; echo $user $password
#
# Env overrides:
#   KUBE_CONTEXT   kubectl context (default: current)
#   NAMESPACE      Grafana namespace (default: observability)
#   SECRET         Secret name (default: grafana)
set -euo pipefail

NAMESPACE="${NAMESPACE:-observability}"
SECRET="${SECRET:-grafana}"

CTX_ARGS=()
[[ -n "${KUBE_CONTEXT:-}" ]] && CTX_ARGS=(--context="$KUBE_CONTEXT")

USER=$(kubectl "${CTX_ARGS[@]}" -n "$NAMESPACE" get secret "$SECRET" \
  -o jsonpath='{.data.admin-user}' | base64 -d)
PASS=$(kubectl "${CTX_ARGS[@]}" -n "$NAMESPACE" get secret "$SECRET" \
  -o jsonpath='{.data.admin-password}' | base64 -d)

printf 'user=%s\n' "$USER"
printf 'password=%s\n' "$PASS"
