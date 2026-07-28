#!/bin/bash -e
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          stage-nightwatcher/04-usb/00-run.sh
# Purpose:       Install the USB data-drive mirror: the script, the udev rule
#                that fires it on insertion, the service, and the timer that
#                keeps a resident drive current.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------

install -v -m 755 files/nw-usb.sh "${ROOTFS_DIR}/usr/local/lib/nightwatcher-pi/nw-usb.sh"
install -v -m 644 files/99-nightwatcher-usb.rules \
	"${ROOTFS_DIR}/etc/udev/rules.d/99-nightwatcher-usb.rules"
install -v -m 644 files/nightwatcher-usb-sync.service \
	"${ROOTFS_DIR}/etc/systemd/system/nightwatcher-usb-sync.service"
install -v -m 644 files/nightwatcher-usb-sync.timer \
	"${ROOTFS_DIR}/etc/systemd/system/nightwatcher-usb-sync.timer"

install -v -d -m 755 "${ROOTFS_DIR}/media/nightwatcher"

on_chroot << 'EOF'
set -e
systemctl enable nightwatcher-usb-sync.timer
EOF
