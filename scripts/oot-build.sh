#!/usr/bin/env bash
# Stage the patched thunderbolt + thunderbolt_net source as an out-of-tree
# build tree, build against the running kernel, and (optionally) hot-swap
# the loaded modules with the freshly-built ones.
#
# Faster iteration loop than DKMS: ~15 s build + rmmod + modprobe.
# Use this on a single chain node to test driver changes before exporting
# to the DKMS payload + ansible-deploying to the fleet.
#
# Usage:
#   scripts/oot-build.sh                    # build only
#   scripts/oot-build.sh --install          # build + install to /lib/modules/.../updates/
#   scripts/oot-build.sh --swap             # build + install + rmmod + modprobe
#
# Sudo prompts on --install / --swap.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
OOT="$HOME/src/tb-oot"
KREL="$(uname -r)"
KDIR="/lib/modules/$KREL/build"

if [ ! -d "$KDIR" ]; then
  echo "kernel build dir missing: $KDIR (install linux-headers-$KREL)" >&2
  exit 1
fi

mode="build"
case "${1:-}" in
  --install) mode="install";;
  --swap)    mode="swap";;
  --build|"") mode="build";;
  -h|--help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  *) echo "unknown arg: $1" >&2; exit 1;;
esac

mkdir -p "$OOT/thunderbolt" "$OOT/thunderbolt_net"
rsync -a --delete "$REPO_ROOT/drivers/thunderbolt/" "$OOT/thunderbolt/"
rsync -a --delete "$REPO_ROOT/drivers/net/thunderbolt/" "$OOT/thunderbolt_net/"

cat > "$OOT/Makefile" <<MAKEFILE
KDIR ?= /lib/modules/\$(shell uname -r)/build
.PHONY: all clean
all:
	\$(MAKE) -C \$(KDIR) M=\$(CURDIR)/thunderbolt modules
	\$(MAKE) -C \$(KDIR) M=\$(CURDIR)/thunderbolt_net modules
clean:
	\$(MAKE) -C \$(KDIR) M=\$(CURDIR)/thunderbolt clean
	\$(MAKE) -C \$(KDIR) M=\$(CURDIR)/thunderbolt_net clean
MAKEFILE

make -C "$OOT" -j"$(nproc)"

if [ "$mode" = "build" ]; then
  echo "OOT build complete at $OOT"
  ls -la "$OOT/thunderbolt/thunderbolt.ko" "$OOT/thunderbolt_net/thunderbolt_net.ko"
  exit 0
fi

sudo install -D -m 0644 "$OOT/thunderbolt/thunderbolt.ko" \
  "/lib/modules/$KREL/updates/thunderbolt.ko"
sudo install -D -m 0644 "$OOT/thunderbolt_net/thunderbolt_net.ko" \
  "/lib/modules/$KREL/updates/thunderbolt_net.ko"
sudo depmod -a

if [ "$mode" = "install" ]; then
  echo "Installed to /lib/modules/$KREL/updates/. Reboot or hot-swap manually."
  exit 0
fi

echo "=== hot-swap thunderbolt modules ==="
sudo rmmod thunderbolt_net 2>/dev/null || true
sudo rmmod thunderbolt 2>/dev/null || true
sudo modprobe thunderbolt
sudo modprobe thunderbolt_net
lsmod | grep -E '^thunderbolt'
modinfo thunderbolt | head -3
