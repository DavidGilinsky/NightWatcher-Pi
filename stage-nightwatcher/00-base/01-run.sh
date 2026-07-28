#!/bin/bash -e
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          stage-nightwatcher/00-base/01-run.sh
# Purpose:       System groundwork the later sub-stages build on: the shared
#                group that lets the sandboxed daemon reach the agent socket and
#                the export spool, a journal sized for flash, and the services
#                the appliance depends on enabled ahead of first boot.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------

install -v -d "${ROOTFS_DIR}/etc/systemd/journald.conf.d"
install -v -m 644 files/journald-nightwatcher-pi.conf \
	"${ROOTFS_DIR}/etc/systemd/journald.conf.d/nightwatcher-pi.conf"

# The one group that joins the three parties: nightwatcherd (a DynamicUser, put
# in this group by a drop-in) reads the agent's socket and writes the export
# spool; the agent and the USB mirror run as root and own both.
on_chroot << 'EOF'
set -e
groupadd --force --system nightwatcher-pi
EOF

# The appliance is useless without these, and first boot has no network to
# recover from a missed enable.
on_chroot << 'EOF'
set -e
systemctl enable mariadb.service
systemctl enable avahi-daemon.service
systemctl enable systemd-timesyncd.service
systemctl enable fake-hwclock.service
systemctl enable NetworkManager.service
EOF
