#!/bin/bash
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          scripts/patch-pigen.sh
# Purpose:       Give the exported image enough headroom for this appliance.
#                pi-gen sizes the root partition as rootfs + 20% + 200MB, which
#                suits Raspberry Pi OS Lite. Our stage adds MariaDB, so the
#                rootfs is around 2GB and that margin leaves only a couple of
#                hundred megabytes free. export-image then runs apt-get update
#                *inside* the image, writing tens of megabytes of package
#                lists, and a build that succeeded yesterday fails today
#                because the archive published a few more packages.
#
#                The margin only matters at build time: Raspberry Pi OS expands
#                the root filesystem to fill the medium on first boot.
#
#                Idempotent, and it verifies the edit took rather than trusting
#                a sed that silently matched nothing.
# Created:       2026-07-28
# Last Modified: 2026-07-28
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
set -uo pipefail

PIGEN="${1:?usage: patch-pigen.sh PI_GEN_DIR}"
PRERUN="${PIGEN}/export-image/prerun.sh"
STOCK='200 \* 1024 \* 1024'
WANTED='900 * 1024 * 1024'

[ -f "${PRERUN}" ] || { echo "[patch-pigen] no ${PRERUN}" >&2; exit 1; }

if grep -q "900 \* 1024 \* 1024" "${PRERUN}"; then
	echo "[patch-pigen] image margin already raised"
	exit 0
fi

if ! grep -q "${STOCK}" "${PRERUN}"; then
	echo "[patch-pigen] ERROR: pi-gen's margin expression is not what this patch expects." >&2
	echo "[patch-pigen] Check export-image/prerun.sh against the pinned PIGEN_REF." >&2
	exit 1
fi

sed -i "s/${STOCK}/${WANTED}/" "${PRERUN}"
grep -q "900 \* 1024 \* 1024" "${PRERUN}" ||
	{ echo "[patch-pigen] ERROR: the margin edit did not apply" >&2; exit 1; }
echo "[patch-pigen] raised the image margin to 900MB (stock 200MB) for the appliance rootfs"
