#!/bin/bash -e
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          stage-nightwatcher/01-nightwatcher/01-run.sh
# Purpose:       Install the pinned NightWatcher2 .deb into the image, create
#                the export spool the USB mirror reads from, and relax the
#                daemon's sandbox by exactly the two things the appliance needs:
#                the agent's socket and that spool.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------

DEB="$(find files -maxdepth 1 -name 'nightwatcher_*_arm64.deb' -print -quit)"
if [ -z "${DEB}" ]; then
	echo "ERROR: no nightwatcher_*_arm64.deb in $(pwd)/files (run 'make deb')" >&2
	exit 1
fi
echo "[nightwatcher] installing $(basename "${DEB}")"

# Staged under /var/cache rather than /tmp: on_chroot mounts a tmpfs over the
# chroot's /tmp, which would hide anything placed there beforehand.
install -v -d "${ROOTFS_DIR}/var/cache/nightwatcher-pi"
install -v -m 644 "${DEB}" "${ROOTFS_DIR}/var/cache/nightwatcher-pi/nightwatcher.deb"

on_chroot << 'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get install -y /var/cache/nightwatcher-pi/nightwatcher.deb
rm -f /var/cache/nightwatcher-pi/nightwatcher.deb

# Prove the package landed the way the image depends on it landing, while a
# failure is still a build failure rather than a dead unit in the field.
test -x /usr/local/nightwatcher/bin/nightwatcherd
test -f /etc/nightwatcher/nightwatcher.conf
test -L /etc/systemd/system/nightwatcherd.service
test -L /etc/udev/rules.d/99-nightwatcher-sqm.rules
grep -q '^bind = 0.0.0.0' /etc/nightwatcher/nightwatcher.conf
grep -q '^tls = on' /etc/nightwatcher/nightwatcher.conf
EOF

# The export spool. A "USB destination" is a DSN export target writing here on
# its normal schedule; the drive is a mirror of this directory, not a
# destination the export itself depends on. So a drive that is absent, full, or
# in a volunteer's pocket cannot fail an export or stall its watermark.
# setgid, so files the daemon writes stay readable by the mirror service.
on_chroot << 'EOF'
set -e
install -d -o root -g nightwatcher-pi -m 2775 /var/lib/nightwatcher-pi
install -d -o root -g nightwatcher-pi -m 2775 /var/lib/nightwatcher-pi/spool
install -d -o root -g nightwatcher-pi -m 2775 /var/lib/nightwatcher-pi/spool/dsn
EOF

install -v -d "${ROOTFS_DIR}/etc/systemd/system/nightwatcherd.service.d"
install -v -m 644 files/pi-appliance.conf \
	"${ROOTFS_DIR}/etc/systemd/system/nightwatcherd.service.d/pi-appliance.conf"
