#!/bin/bash -e
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          stage-nightwatcher/05-agent/00-run.sh
# Purpose:       Install the platform agent and the RPi tab it serves.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------

install -v -m 755 files/nightwatcher-pi-agent \
	"${ROOTFS_DIR}/usr/local/lib/nightwatcher-pi/nightwatcher-pi-agent"
install -v -m 644 files/ui.js "${ROOTFS_DIR}/usr/local/lib/nightwatcher-pi/ui.js"
install -v -m 644 files/nightwatcher-pi-agent.service \
	"${ROOTFS_DIR}/etc/systemd/system/nightwatcher-pi-agent.service"

on_chroot << 'EOF'
set -e
python3 -m py_compile /usr/local/lib/nightwatcher-pi/nightwatcher-pi-agent
rm -rf /usr/local/lib/nightwatcher-pi/__pycache__
systemctl enable nightwatcher-pi-agent.service
EOF
