#!/usr/bin/env bash
# Durability target: 192 GB of NCCL allreduce on the 3-node TB chain
# (3000 iterations × 64 MiB). Pre-fix wedges in <1 GB. Post-fix completes
# with mask_count == unmask_count on every NHI.
#
# Drives the same hostnetwork LWS as run-smoke.sh, but uses an inline
# patched ConfigMap that overrides the default sweep with 3000 × 64 MiB.
#
# Usage:
#   tests/run-durability.sh
#   tests/run-durability.sh --teardown

set -euo pipefail

KCTX="${KCTX:-local}"
NS="${NS:-default}"
LWS_NAME="tb-chain-nccl-smoke-hostnet"

if [ "${1:-}" = "--teardown" ]; then
  kubectl --context="$KCTX" delete -f - 2>/dev/null <<EOF || true
apiVersion: v1
kind: ConfigMap
metadata:
  name: tb-chain-nccl-smoke-hostnet-script
  namespace: $NS
EOF
  kubectl --context="$KCTX" delete leaderworkerset.x-k8s.io/$LWS_NAME -n "$NS" --ignore-not-found
  exit 0
fi

# Patched run.py: 3000 iterations × 64 MiB.
kubectl --context="$KCTX" apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: tb-chain-nccl-smoke-hostnet-script
  namespace: default
data:
  run.py: |
    import os, time
    import torch
    import torch.distributed as dist

    rank_env = int(os.environ["RANK"])
    print(f"[rank{rank_env}-boot] starting", flush=True)
    dist.init_process_group(backend="nccl")
    rank = dist.get_rank(); world = dist.get_world_size()
    torch.cuda.set_device(0)
    device = torch.device("cuda:0")
    print(f"[rank{rank}] init ok, world={world}", flush=True)

    warm = torch.ones(1024, device=device)
    dist.all_reduce(warm); torch.cuda.synchronize(); dist.barrier()

    nbytes = 64 * 1024 * 1024
    nelem = nbytes // 4
    t = torch.ones(nelem, device=device)
    iters = 3000  # 3000 * 64 MiB == 192 GiB allreduce volume

    dist.all_reduce(t); torch.cuda.synchronize(); dist.barrier()
    t0 = time.time(); last = t0
    for i in range(iters):
        dist.all_reduce(t)
        if rank == 0 and (i+1) % 100 == 0:
            torch.cuda.synchronize()
            now = time.time()
            print(f"[rank0] iter={i+1}/{iters} dt100={now-last:.1f}s elapsed={now-t0:.1f}s", flush=True)
            last = now
    torch.cuda.synchronize(); dist.barrier()
    if rank == 0:
        dt = time.time() - t0
        gib = (nbytes * iters) / (1024**3)
        print(f"[RESULT] iters={iters} size_mib=64 total={gib:.1f} GiB elapsed={dt:.1f}s", flush=True)
    dist.destroy_process_group()
EOF

# Now apply the LWS itself
MANIFEST="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/../appmana-cluster/src/hacking/tb-chain-nccl-smoke-hostnet.yaml"
# The LWS references the same ConfigMap above; we just replaced it. Reapply
# the LWS to bounce the pods so they pick up the new script.
kubectl --context="$KCTX" delete leaderworkerset.x-k8s.io/$LWS_NAME -n "$NS" --ignore-not-found
kubectl --context="$KCTX" apply -f "$MANIFEST"

for _ in $(seq 1 30); do
  if kubectl --context="$KCTX" -n "$NS" get pod "${LWS_NAME}-0" >/dev/null 2>&1; then break; fi
  sleep 2
done

echo "tailing rank-0 (durability target: 192 GiB; expected ~30 min)..."
kubectl --context="$KCTX" -n "$NS" logs -f "${LWS_NAME}-0" \
  | grep --line-buffered -E 'iter=|RESULT|Error|Traceback|wedged'
