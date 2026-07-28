#!/bin/bash
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          scripts/resume-stage.sh
# Purpose:       Rebuild only our stage, reusing the Raspberry Pi OS stages a
#                previous build already produced. Those three stages take over
#                an hour under emulation and never change between our edits, so
#                paying for them on every iteration is the difference between a
#                ten-minute cycle and a ninety-minute one.
#
#                Our stage's own rootfs is discarded first, so this is a clean
#                run of our stage on top of an untouched stage2, not a re-run
#                over whatever the failed attempt left behind.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=/dev/null
source ./versions.env

PIGEN=work/pi-gen
CONTAINER=pigen_work
STAGE=stage-nightwatcher

die() { printf '[resume] ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "${PIGEN}" ] || die "no pi-gen checkout; run 'make image' for a first build"
docker inspect "${CONTAINER}" >/dev/null 2>&1 ||
	die "no previous build container to resume from; run 'make image'"

WORK_VOL="$(docker inspect "${CONTAINER}" \
	--format '{{range .Mounts}}{{if eq .Destination "/pi-gen/work"}}{{.Name}}{{end}}{{end}}')"
[ -n "${WORK_VOL}" ] || die "the previous build kept no work volume; run 'make image'"

# Confirm the base stages really are there before skipping them, or the build
# starts from a stage2 rootfs that does not exist.
have_stage2="$(docker run --rm -v "${WORK_VOL}":/w alpine \
	sh -c "test -d /w/${IMG_NAME}/stage2/rootfs && echo yes" 2>/dev/null)"
[ "${have_stage2}" = "yes" ] ||
	die "the previous build did not finish stage2; run 'make image' for a full build"

# A resume rebuilds our stage and nothing else, so any setting the Raspberry Pi
# OS stages consume (the account password among them, applied in stage1) would
# be silently ignored. Refuse rather than produce an image whose contents do not
# match its configuration.
FINGERPRINT="$(./scripts/base-fingerprint.sh work/pi-gen.config)"
CACHED="$(docker run --rm -v "${WORK_VOL}":/w alpine \
	cat /w/.base-config-fingerprint 2>/dev/null | tr -d '[:space:]')"
if [ -z "${CACHED}" ]; then
	die "the cached base stages have no fingerprint, so it cannot be shown that
       they match the current settings. Run 'make image' once for a full build."
fi
if [ "${CACHED}" != "${FINGERPRINT}" ]; then
	die "settings owned by the Raspberry Pi OS stages have changed since the base
       was built (hostname, account name or password, SSH, locale, timezone,
       country, or the stage list). Those are applied in stage0-2, which a
       resume skips, so the image would not match versions.env.
       Run 'make image' for a full build."
fi

echo "[resume] base stages match the current settings"
echo "[resume] discarding the previous ${STAGE} rootfs so this run starts clean"
docker run --rm -v "${WORK_VOL}":/w alpine \
	rm -rf "/w/${IMG_NAME}/${STAGE}" >/dev/null 2>&1 ||
	die "could not clear the previous stage rootfs"

echo "[resume] skipping stage0, stage1, stage2 (already built)"
touch "${PIGEN}/stage0/SKIP" "${PIGEN}/stage1/SKIP" "${PIGEN}/stage2/SKIP"

# PRESERVE_CONTAINER keeps the work volume alive for the next iteration, which
# is the entire point of resuming.
echo "[resume] building ${STAGE}"
cd "${PIGEN}" && CONTINUE=1 PRESERVE_CONTAINER=1 ./build-docker.sh -c ../pi-gen.config
