#!/usr/bin/env bash
# Mint a bearer token for the `ppo-trigger` ServiceAccount.
# Webhook callers (curl / GitHub Action / etc.) pass this in
# `Authorization: Bearer <token>` when POSTing or PATCHing Workflow CRs.
#
# Env overrides:
#   KUBE_CONTEXT   kubectl context (default: current)
#   NAMESPACE      SA namespace (default: experiments)
#   SA             ServiceAccount name (default: ppo-trigger)
#   DURATION       Token lifetime (default: 1h; cluster cap usually 24h or
#                  configurable via --service-account-max-token-expiration)
#
# Usage:
#   ./get-trigger-token.sh                # current context, 1h token
#   DURATION=8h ./get-trigger-token.sh    # 8-hour token for a CI job
set -euo pipefail

NAMESPACE="${NAMESPACE:-experiments}"
SA="${SA:-ppo-trigger}"
DURATION="${DURATION:-1h}"

CTX_ARGS=()
[[ -n "${KUBE_CONTEXT:-}" ]] && CTX_ARGS=(--context="$KUBE_CONTEXT")

kubectl "${CTX_ARGS[@]}" -n "$NAMESPACE" create token "$SA" --duration="$DURATION"
