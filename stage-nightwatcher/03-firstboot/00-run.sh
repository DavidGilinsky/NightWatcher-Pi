#!/bin/bash -e
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          stage-nightwatcher/03-firstboot/00-run.sh
# Purpose:       Install the first-boot provisioning script, its unit, and the
#                operator-editable site file on the boot partition.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------

install -v -m 755 files/nightwatcher-firstboot.sh \
	"${ROOTFS_DIR}/usr/local/lib/nightwatcher-pi/nightwatcher-firstboot.sh"
install -v -m 644 files/nightwatcher-firstboot.service \
	"${ROOTFS_DIR}/etc/systemd/system/nightwatcher-firstboot.service"

# On the FAT boot partition, where any laptop can edit it before first boot.
install -v -m 644 files/nightwatcher-site.txt \
	"${ROOTFS_DIR}/boot/firmware/nightwatcher-site.txt"

# A convenience for anyone who ends up on the console or over SSH.
install -v -d "${ROOTFS_DIR}/usr/local/bin"
ln -sf /usr/local/lib/nightwatcher-pi/nightwatcher-firstboot.sh \
	"${ROOTFS_DIR}/usr/local/bin/nightwatcher-provision"

on_chroot << 'EOF'
set -e
systemctl enable nightwatcher-firstboot.service
EOF
