# forks-thunderbolt

AppMana fork of the Linux kernel Thunderbolt drivers. The fleet branch
contains two independent workstreams: Thunderbolt networking fixes for
the 3-node NCCL chain and ICM/PCIe hotplug diagnostics for HP FlexIO
Thunderbolt storage.

```
upstream  = git://git.kernel.org/pub/scm/linux/kernel/git/westeri/thunderbolt.git
origin    = git@github.com:AppMana/forks-thunderbolt.git
branch    = pub/tbfix-v6.17    (deployed on the AppMana fleet)
base      = v6.17 + 3 backports already in linux-hwe-6.17
```

## What's here

```
drivers/thunderbolt/        full subsystem source (patched)
drivers/net/thunderbolt/    tbnet driver source (patched)
dkms/                       DKMS scaffolding (dkms.conf, Makefile)
packaging/debian/           Debian package metadata for thunderbolt-tbfix-dkms
scripts/
  oot-build.sh              fast iteration: stage at ~/src/tb-oot, build, hot-swap
  export-dkms-payload.sh    write byte-identical DKMS bundle into the appmana repo
tools/ci/
  distro-package.sh         build thunderbolt-tbfix-dkms_<version>_all.deb
  distro-install.sh         verify the .deb can build through DKMS
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
7. Preparing upstream topic patches for manual review.

## Debian / Ubuntu package

Build the DKMS `.deb` locally:

```bash
tools/ci/distro-package.sh ubuntu
```

The artifact is written to `dist/thunderbolt-tbfix-dkms_<version>_all.deb`.
Installing it stages the DKMS source under
`/usr/src/thunderbolt-tbfix-<version>` and runs `dkms autoinstall`.
The package intentionally does not reload `thunderbolt` or
`thunderbolt_net`; fleet reload ordering remains owned by Ansible.

Tags matching `v*` publish the `.deb` and its `.sha256` file to GitHub
Releases in `AppMana/thunderbolt-tbfix`. The public apt repository in
`AppMana/apt` consumes those release assets.

## Branches

- `pub/tbfix-v6.17` — deployed DKMS branch. Includes the Ubuntu HWE
  backport alignment, Thunderbolt networking/ring reliability work,
  DKMS packaging, and ICM hotplug diagnostics.
- `pub/tbfix-v6.17-hotplug` — storage-hotplug split branch. Carries
  only the `drivers/thunderbolt/icm.c` hotplug work on top of the DKMS
  packaging point; no `drivers/net/thunderbolt` changes.
- `master` — local mirror of `upstream/master` (Mika Westerberg's tree).

Do not submit the fleet branch upstream. For upstream work, create a
fresh topic branch from `upstream/master` and apply only the minimal
subsystem-specific change. Thunderbolt networking changes touch netdev;
storage hotplug changes should not.

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
