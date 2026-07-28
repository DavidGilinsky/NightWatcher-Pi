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
# recover from a missed enable. They come either with Raspberry Pi OS or with
# the packages installed above, whose postinst scripts already enable them, so
# this asserts the state rather than forcing it. Forcing is actively wrong for
# a unit the distribution ships masked: fake-hwclock.service is a tombstone
# symlinked to /dev/null, its work having moved to fake-hwclock-load.service
# and fake-hwclock-save.timer, both already enabled. Asking to enable it fails,
# and failing here throws away an hour of build over a unit that was never
# ours to enable.
on_chroot << 'EOF'
set -e
for unit in mariadb avahi-daemon systemd-timesyncd NetworkManager; do
	state="$(systemctl is-enabled "${unit}" 2>/dev/null || true)"
	case "${state}" in
		enabled|enabled-runtime|static|indirect|alias|generated)
			echo "nightwatcher-pi: ${unit} is ${state}" ;;
		masked|masked-runtime)
			echo "nightwatcher-pi: WARNING ${unit} is masked in this image; leaving it alone" ;;
		*)
			echo "nightwatcher-pi: enabling ${unit}"
			systemctl enable "${unit}" ;;
	esac
done

# The clock units the appliance actually depends on. Not enabled here (the
# package does that); checked, because a unit whose readings are timestamped
# from a 1970 clock is worse than one with no readings.
systemctl is-enabled fake-hwclock-save.timer >/dev/null 2>&1 ||
	echo "nightwatcher-pi: WARNING fake-hwclock-save.timer is not enabled"
EOF
