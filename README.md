# forks-thunderbolt

AppMana fork of the Linux kernel `drivers/thunderbolt` and
`drivers/net/thunderbolt` subsystems with two patches that fix a silent
wedge under sustained two-port NCCL load on a 3-node Thunderbolt chain.

```
upstream  = git://git.kernel.org/pub/scm/linux/kernel/git/westeri/thunderbolt.git
origin    = git@github.com:AppMana/forks-thunderbolt.git
branch    = tbfix/v6.17        (deployed on the AppMana fleet)
base      = v6.17 + 3 backports already in linux-hwe-6.17
```

## What's here

```
drivers/thunderbolt/        full subsystem source (patched)
drivers/net/thunderbolt/    tbnet driver source (patched)
dkms/                       DKMS scaffolding (dkms.conf, Makefile)
scripts/
  oot-build.sh              fast iteration: stage at ~/src/tb-oot, build, hot-swap
  export-dkms-payload.sh    write byte-identical DKMS bundle into the appmana repo
tests/
  run-smoke.sh              60-s NCCL hostnet sweep on the 3-node chain
  run-durability.sh         192 GiB allreduce reproducer (~30 min, the wedge gate)
```

## How to use

Read `docs/thunderbolt_fix.md` in the parent `appmana` repo. It covers:

1. Building OOT for fast iteration (`scripts/oot-build.sh --swap`).
2. Building the DKMS payload for fleet deploy (`scripts/export-dkms-payload.sh`).
3. Running the smoke + durability tests.
4. Deploying via Ansible (`playbook_worker.yaml`).
5. Reverting to in-tree drivers.
6. Rebasing on a newer kernel when the fleet bumps.
7. Sending the patches upstream via `git send-email`.

## Branches

- `tbfix/v6.17` — the deployed branch. Three commits on top of `v6.17`:
  - `e0598358ba01 backport: Ubuntu HWE 6.17 kernel-source thunderbolt deltas`
  - `c0350c90d0d1 thunderbolt: drop start_poll guard in tb_ring_poll_complete()`  ← H6 + H7
  - `c35e822e5e6c net: thunderbolt: enlarge RX/TX ring and set NAPI weight ...`    ← H5 + H5a
  Plus an overlay commit adding `dkms/`, `scripts/`, `tests/`, `README.md`.
- `master` — local mirror of `upstream/master` (Mika Westerberg's tree).

## Why patches not a submodule

`forks-*` siblings of the appmana monorepo are independent git repos by
convention (see `forks-sglang`, `forks-vllm-ampere`). Ansible deploys
from a flat in-repo copy of the DKMS payload at
`appmana-management/src/appmana_management/files/thunderbolt_net/tbfix-dkms/`.

The `scripts/export-dkms-payload.sh` script in this fork rewrites that
copy from `HEAD`. If the fork advances, run the script and commit the
appmana-side change; `diff -r` between fork export and appmana copy must
be empty before deploy.

## License

Linux kernel sources are GPL-2.0-only; the DKMS/scripts overlay matches.
