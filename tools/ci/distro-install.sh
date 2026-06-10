#!/usr/bin/env bash
# Install and verify a thunderbolt-tbfix-dkms .deb without loading modules.
# By default this verifies package/source staging only. Set
# TBFIX_VERIFY_DKMS_BUILD=1 in an environment with matching 6.17 kernel headers
# to compile the modules too.

set -euo pipefail

target="${1:-}"
if [[ -z "$target" || "$target" == "-h" || "$target" == "--help" ]]; then
	cat <<'EOF'
Usage:
  tools/ci/distro-install.sh <thunderbolt-tbfix-dkms.deb>

Environment:
  TBFIX_VERIFY_DKMS_BUILD=1  Also run dkms build against installed headers.
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
headers_pkg=linux-headers-amd64
if grep -qi '^ID=ubuntu' /etc/os-release; then
	headers_pkg=linux-headers-generic
fi
apt-get install -y -qq --no-install-recommends \
	build-essential ca-certificates dkms file kmod "$headers_pkg" make
apt-get install -y -qq "$artefact"

modname=thunderbolt-tbfix
src_dir="$(find /usr/src -maxdepth 1 -type d -name "${modname}-*" -print -quit)"
[[ -n "$src_dir" ]] || { printf 'error: %s source not found under /usr/src\n' "$modname" >&2; exit 1; }
version="$(awk -F'"' '/^PACKAGE_VERSION=/ { print $2; exit }' "$src_dir/dkms.conf")"
printf '==> Source dir: %s\n' "$src_dir"
printf '==> Version:    %s\n' "$version"

for required in dkms.conf Makefile thunderbolt thunderbolt_net; do
	[[ -e "$src_dir/$required" ]] ||
		{ printf 'error: missing %s in %s\n' "$required" "$src_dir" >&2; exit 1; }
done

if [[ "${TBFIX_VERIFY_DKMS_BUILD:-0}" != "1" ]]; then
	printf '==> Package install/source verification OK\n'
	printf '==> Skipping DKMS build; set TBFIX_VERIFY_DKMS_BUILD=1 with matching 6.17 headers\n'
	exit 0
fi

kver="$(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -n 1)"
[[ -n "$kver" && -d "/lib/modules/$kver/build" ]] || { printf 'error: no kernel headers found\n' >&2; exit 1; }
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
