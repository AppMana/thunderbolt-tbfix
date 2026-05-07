#!/usr/bin/env bash
# 60-second NCCL smoke test on the 3-node TB chain (hostnetwork flavor).
# Pass criterion: each MiB size in {4, 16, 64, 256, 1024} produces a
# [RESULT] line; no rank hangs.
#
# Pre-fix (without H6/H7) the chain wedges before the 64 MiB iteration
# completes. With the fix loaded (DKMS or OOT), the full sweep completes.
#
# Usage:
#   tests/run-smoke.sh                  # run, tail until done, print results
#   tests/run-smoke.sh --apply-only     # apply manifest only, exit
#   tests/run-smoke.sh --teardown       # delete the LWS

set -euo pipefail

KCTX="${KCTX:-local}"
NS="${NS:-default}"
LWS_NAME="tb-chain-nccl-smoke-hostnet"
MANIFEST="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/../appmana-cluster/src/hacking/tb-chain-nccl-smoke-hostnet.yaml"

case "${1:-}" in
  --teardown)
    kubectl --context="$KCTX" delete -f "$MANIFEST" --ignore-not-found
    exit 0
    ;;
  --apply-only)
    kubectl --context="$KCTX" apply -f "$MANIFEST"
    exit 0
    ;;
esac

echo "applying $MANIFEST"
kubectl --context="$KCTX" apply -f "$MANIFEST"

# Wait for rank-0 pod to exist
for _ in $(seq 1 30); do
  if kubectl --context="$KCTX" -n "$NS" get pod "${LWS_NAME}-0" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "tailing rank-0 for [RESULT] lines (Ctrl-C to stop early)..."
kubectl --context="$KCTX" -n "$NS" logs -f "${LWS_NAME}-0" \
  | grep --line-buffered -E '\[RESULT\]|\[rank0\] done|Error|Traceback|wedged|hang'
