#!/usr/bin/env bash
# Install and verify a thunderbolt-tbfix-dkms .deb without loading modules.

set -euo pipefail

target="${1:-}"
if [[ -z "$target" || "$target" == "-h" || "$target" == "--help" ]]; then
	cat <<'EOF'
Usage:
  tools/ci/distro-install.sh <thunderbolt-tbfix-dkms.deb>
EOF
	[[ -n "$target" ]] && exit 0
	exit 1
fi

shopt -s nullglob
# shellcheck disable=SC2206
artefacts=( $target )
shopt -u nullglob
if [[ ${#artefacts[@]} -ne 1 ]]; then
	printf 'error: expected exactly one artefact, got %d\n' "${#artefacts[@]}" >&2
	exit 1
fi

artefact="$(realpath "${artefacts[0]}")"
[[ -f "$artefact" ]] || { printf 'error: not a file: %s\n' "$artefact" >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
	build-essential ca-certificates dkms file kmod linux-headers-amd64 make
apt-get install -y -qq "$artefact"

modname=thunderbolt-tbfix
src_dir="$(find /usr/src -maxdepth 1 -type d -name "${modname}-*" -print -quit)"
[[ -n "$src_dir" ]] || { printf 'error: %s source not found under /usr/src\n' "$modname" >&2; exit 1; }
version="$(awk -F'"' '/^PACKAGE_VERSION=/ { print $2; exit }' "$src_dir/dkms.conf")"
kver="$(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -n 1)"
[[ -n "$kver" && -d "/lib/modules/$kver/build" ]] || { printf 'error: no kernel headers found\n' >&2; exit 1; }

printf '==> Source dir: %s\n' "$src_dir"
printf '==> Version:    %s\n' "$version"
printf '==> Kernel:     %s\n' "$kver"

if ! dkms build -m "$modname" -v "$version" -k "$kver" --force; then
	cat "/var/lib/dkms/$modname/$version/build/make.log" >&2 || true
	exit 1
fi

for ko in thunderbolt.ko thunderbolt_net.ko; do
	built="$(find "/var/lib/dkms/$modname/$version" -name "$ko" -print -quit)"
	[[ -n "$built" ]] || { printf 'error: DKMS build did not produce %s\n' "$ko" >&2; exit 1; }
	file "$built"
	modinfo "$built" | sed -n '1,12p'
done

printf '==> thunderbolt-tbfix DKMS verification OK\n'
