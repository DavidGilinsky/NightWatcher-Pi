#!/bin/bash -e
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          stage-nightwatcher/prerun.sh
# Purpose:       pi-gen stage entry: start from the previous stage's rootfs
#                (Raspberry Pi OS Lite, stage2) rather than rebuilding it.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------

if [ ! -d "${ROOTFS_DIR}" ]; then
	copy_previous
fi
