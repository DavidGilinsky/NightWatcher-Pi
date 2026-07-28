#!/bin/bash
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          scripts/preflight.sh
# Purpose:       Check the host can actually build an image before anything
#                slow happens. pi-gen fails on a missing prerequisite only
#                after cloning itself and building a Docker image, and its
#                message names a package without saying what to do about it.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
set -uo pipefail

MODE="${1:-docker}"     # docker | native
fail=0
host_arch="$(uname -m)"

problem() { printf '\n  %s\n' "$*" >&2; fail=1; }

if [ "${MODE}" = "docker" ]; then
	command -v docker >/dev/null 2>&1 || problem "docker is not installed."
	docker info >/dev/null 2>&1 ||
		problem "docker is installed but not usable as this user. Add yourself to the docker group, or build with sudo."
fi

# Emulation is only needed when the host is not already arm64.
case "${host_arch}" in
	aarch64|arm64) ;;
	*)
		# pi-gen wants the dynamically linked qemu-aarch64 specifically, and
		# registers it for binfmt itself. qemu-user-static alone is not enough,
		# even though it looks like it should be.
		if ! command -v qemu-aarch64 >/dev/null 2>&1; then
			problem "qemu-aarch64 is missing, so an arm64 rootfs cannot be built on ${host_arch}.

    sudo apt install qemu-user-binfmt qemu-user-static binfmt-support

  qemu-user-static on its own does not satisfy pi-gen: it looks for the
  dynamically linked qemu-aarch64 and registers that one for binfmt."
		fi
		[ -f /proc/sys/fs/binfmt_misc/register ] ||
			problem "binfmt_misc is not mounted. 'sudo mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc', or install binfmt-support."
		;;
esac

# pi-gen unpacks a full rootfs and then an image of it. Running out of room
# halfway through wastes the whole build.
avail_kb="$(df -Pk . | awk 'NR == 2 { print $4 }')"
if [ -n "${avail_kb}" ] && [ "${avail_kb}" -lt 15000000 ]; then
	problem "only $(( avail_kb / 1024 / 1024 ))GB free here; an image build wants about 15GB."
fi

for tool in git make openssl gh; do
	command -v "${tool}" >/dev/null 2>&1 || problem "${tool} is not installed."
done

if [ "${fail}" -ne 0 ]; then
	printf '\n[preflight] cannot build an image on this host yet (see above).\n' >&2
	printf '[preflight] an arm64 host, or CI, needs none of the emulation pieces.\n' >&2
	exit 1
fi
echo "[preflight] host can build an image (${MODE}, ${host_arch})"
