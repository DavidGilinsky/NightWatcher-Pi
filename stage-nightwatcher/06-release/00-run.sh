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

# Where the package actually came from, recorded by the fetch script rather
# than assumed here. NW2_VERSION is what the build asked for; when no such
# release exists the fetch falls back to a CI artifact, and a stamp that named
# the release regardless would make an unpinned image indistinguishable from a
# reproducible one. This file exists to be trusted or it is not worth writing.
NW2_SOURCE="unknown"
NW2_VERIFIED="no"
if [ -r files/deb-source.env ]; then
	# shellcheck source=/dev/null
	. files/deb-source.env
fi

cat > "${ROOTFS_DIR}/etc/nightwatcher-pi-release" << EOF
# What this image is made of. Report these when asking for help with a unit.
NWPI_VERSION=${NWPI_VERSION:-0.1.0}
NWPI_BUILD_DATE=$(date -u '+%Y-%m-%d')
NW2_PACKAGE_VERSION=${NW2_DEB_VERSION}
NW2_SOURCE=${NW2_SOURCE}
NW2_CHECKSUM_VERIFIED=${NW2_VERIFIED}
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
