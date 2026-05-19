#!/usr/bin/env bash
# Print the ArgoCD initial admin password. User is always `admin`.
# Outputs `user=admin` and `password=<x>` so the result can be `eval`-ed.
#
# Note: ArgoCD deletes `argocd-initial-admin-secret` after the password is
# rotated through `argocd account update-password`, so this script is for
# the first login. After rotation, use the credentials you set yourself.
#
# Env overrides:
#   KUBE_CONTEXT   kubectl context (default: current)
#   NAMESPACE      ArgoCD namespace (default: argocd)
set -euo pipefail

NAMESPACE="${NAMESPACE:-argocd}"

CTX_ARGS=()
[[ -n "${KUBE_CONTEXT:-}" ]] && CTX_ARGS=(--context="$KUBE_CONTEXT")

PASS=$(kubectl "${CTX_ARGS[@]}" -n "$NAMESPACE" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)

printf 'user=admin\n'
printf 'password=%s\n' "$PASS"
