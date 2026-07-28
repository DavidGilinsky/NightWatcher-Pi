#!/bin/bash -e
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          stage-nightwatcher/06-release/00-run.sh
# Purpose:       Stamp the image with what went into it, and leave the rootfs
#                in the state a first boot expects. A unit in the field can be
#                identified from this file alone, which is what makes a fleet
#                supportable.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------

# Read the installed version straight out of the rootfs: no chroot needed, and
# no chance of chroot noise landing in the value.
NW2_DEB_VERSION="$(awk '/^Package: nightwatcher$/ { found = 1 }
                        found && /^Version:/ { print $2; exit }' \
	"${ROOTFS_DIR}/var/lib/dpkg/status" 2>/dev/null)"
NW2_DEB_VERSION="${NW2_DEB_VERSION:-unknown}"

cat > "${ROOTFS_DIR}/etc/nightwatcher-pi-release" << EOF
# What this image is made of. Report these when asking for help with a unit.
NWPI_VERSION=${NWPI_VERSION:-0.1.0}
NWPI_BUILD_DATE=$(date -u '+%Y-%m-%d')
NW2_RELEASE=${NW2_VERSION:-unknown}
NW2_PACKAGE_VERSION=${NW2_DEB_VERSION}
BASE_OS=Raspberry Pi OS Lite (${RELEASE:-trixie}, arm64)
PIGEN_REF=${PIGEN_REF:-unknown}
EOF
chmod 644 "${ROOTFS_DIR}/etc/nightwatcher-pi-release"
echo "[release] stamped /etc/nightwatcher-pi-release"
cat "${ROOTFS_DIR}/etc/nightwatcher-pi-release"

# The message on the console and over SSH, for whoever ends up there.
cat > "${ROOTFS_DIR}/etc/motd" << 'EOF'

  NightWatcher-Pi sky quality meter appliance

  This unit serves its own Wi-Fi network and the NightWatcher2 web UI.
  Its network name, passphrase, and recovery password are in
  /boot/firmware/nightwatcher-credentials.txt.

    systemctl status nightwatcherd nightwatcher-ap nightwatcher-pi-agent
    journalctl -u nightwatcher-firstboot     what provisioning did
    nightwatcher-provision --force           provision this unit again

EOF

# Anything cached here is dead weight in an image that ships to a mountain top.
on_chroot << 'EOF'
set -e
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/nightwatcher-pi
EOF
