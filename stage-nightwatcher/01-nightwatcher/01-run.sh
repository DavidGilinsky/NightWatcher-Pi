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
# failure is still a build failure rather than a dead unit in the field. Each
# check names itself: a bare `test` under `set -e` ends an hour-long build in
# silence, leaving nothing to debug but the exit status.
fails=0
check() {  # check DESCRIPTION TEST...
	description="$1"
	shift
	if "$@"; then
		printf 'nightwatcher: ok   %s\n' "${description}"
	else
		printf 'nightwatcher: FAIL %s\n' "${description}"
		fails=$((fails + 1))
	fi
}

check "daemon installed"     test -x /usr/local/nightwatcher/bin/nightwatcherd
check "config seeded"        test -f /etc/nightwatcher/nightwatcher.conf
check "systemd unit linked"  test -L /etc/systemd/system/nightwatcherd.service
check "udev rule linked"     test -L /etc/udev/rules.d/99-nightwatcher-sqm.rules
# Whitespace-tolerant: these values travel through debconf and are written back
# by the package's own postinst, so their exact spacing is not ours to assume.
check "web UI bound to every interface" \
	grep -Eq '^[[:space:]]*bind[[:space:]]*=[[:space:]]*0\.0\.0\.0[[:space:]]*$' \
	/etc/nightwatcher/nightwatcher.conf
check "web UI serves TLS" \
	grep -Eq '^[[:space:]]*tls[[:space:]]*=[[:space:]]*on[[:space:]]*$' \
	/etc/nightwatcher/nightwatcher.conf

if [ "${fails}" -ne 0 ]; then
	echo "nightwatcher: ${fails} post-install check(s) failed; see above" >&2
	grep -nE '^\[|^(bind|port|tls|host) ' /etc/nightwatcher/nightwatcher.conf >&2 || true
	exit 1
fi
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
