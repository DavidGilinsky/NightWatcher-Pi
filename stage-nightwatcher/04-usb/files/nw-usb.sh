#!/bin/bash
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          /usr/local/lib/nightwatcher-pi/nw-usb.sh
# Purpose:       Mirror the export spool onto a volunteer's USB drive. The
#                drive is a mirror, never a destination the export itself
#                depends on, so a drive that is absent, full, or in somebody's
#                pocket cannot fail an export or stall its watermark.
#
#                The drive is mounted only while writing and unmounted as soon
#                as the write completes, which is what makes it safe to unplug
#                at essentially any moment: an idle drive here is an unmounted
#                drive.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=stage-nightwatcher/02-network/files/nw-common.sh
. /usr/local/lib/nightwatcher-pi/nw-common.sh
nw_load_conf

LOCK=/run/nightwatcher-usb.lock
BY_LABEL="/dev/disk/by-label/${USB_LABEL}"
UNIT="$(hostname)"

usb_device() { readlink -f "${BY_LABEL}" 2>/dev/null; }

# ---- status ---------------------------------------------------------------
cmd_status() {
	local dev size free last files
	dev="$(usb_device)"
	last="$(cat "${NWPI_STATE}/.usb-last-sync" 2>/dev/null || true)"
	files="$(find "${NWPI_SPOOL}" -type f ! -name '*.tmp' 2>/dev/null | wc -l)"

	if [ -z "${dev}" ]; then
		printf 'present=no\nlabel=%s\nspool_files=%s\nlast_sync=%s\n' \
			"${USB_LABEL}" "${files}" "${last}"
		return 0
	fi

	size="$(lsblk -bno SIZE "${dev}" 2>/dev/null | head -1)"
	# Free space needs the filesystem mounted, which it deliberately is not
	# between syncs. The last sync recorded it on its way out.
	free="$(cat "${NWPI_STATE}/.usb-free" 2>/dev/null || true)"
	printf 'present=yes\ndevice=%s\nlabel=%s\nsize=%s\nfree=%s\nspool_files=%s\nlast_sync=%s\n' \
		"${dev}" "${USB_LABEL}" "${size:-}" "${free:-}" "${files}" "${last}"
}

# ---- sync -----------------------------------------------------------------
cmd_sync() {
	local dev dest
	dev="$(usb_device)"
	if [ -z "${dev}" ]; then
		nw_log "no ${USB_LABEL} drive present; nothing to mirror"
		return 0        # not an error: most of the time there is no drive
	fi

	install -d -m 755 "${USB_MOUNT}"
	if ! mount -o rw,noatime "${dev}" "${USB_MOUNT}" 2>/dev/null; then
		nw_warn "could not mount ${dev}; is it formatted? (RPi tab -> Prepare drive)"
		return 1
	fi
	# However this exits, the drive ends up unmounted and safe to pull.
	trap 'sync; umount "${USB_MOUNT}" 2>/dev/null || umount -l "${USB_MOUNT}" 2>/dev/null || true' EXIT

	dest="${USB_MOUNT}/NightWatcher/${UNIT}"
	if ! install -d "${dest}"; then
		nw_warn "could not create ${dest}; the drive may be write-protected or full"
		return 1
	fi

	# A mirror, not a move: the spool stays the authoritative copy, so a drive
	# that is lost or never comes back is an inconvenience and not data loss.
	# Partially written exports are excluded by name.
	if ! rsync -rt --omit-dir-times --exclude '*.tmp' --exclude '.*' \
		"${NWPI_SPOOL}/" "${dest}/" 2>/dev/null; then
		nw_warn "the mirror did not complete; the drive may be full"
		return 1
	fi

	local now files free
	now="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
	files="$(find "${dest}" -type f ! -name '.*' 2>/dev/null | wc -l)"
	free="$(df -B1 --output=avail "${USB_MOUNT}" 2>/dev/null | tail -1 | tr -d ' ')"

	# What the drive itself knows about where it has been, so a volunteer
	# holding it can tell which unit it served and when.
	cat > "${USB_MOUNT}/NightWatcher/.nightwatcher-usb.json" << EOF
{
  "unit": "${UNIT}",
  "site": "${SITE_NAME:-}",
  "last_sync_utc": "${now}",
  "files": ${files},
  "image_version": "${NWPI_VERSION:-0.1.0}"
}
EOF
	cat > "${USB_MOUNT}/NightWatcher/README.txt" << EOF
NightWatcher sky-brightness data
================================

This drive carries Dark Sky Network data files mirrored from a NightWatcher
sky quality meter. One file per site, per month, in the DSN community format.

  Unit:       ${UNIT}
  Site:       ${SITE_NAME:-(unnamed)}
  Last sync:  ${now}
  Files:      ${files}

The unit keeps its own copy of everything here, so this drive can be handed in,
copied, and brought back empty or full without losing anything.

To collect data: unplug the drive (it is unmounted between writes, so no
eject step is needed), copy the NightWatcher folder somewhere safe, and plug
the drive back in. It re-syncs within seconds of being inserted.
EOF

	sync
	printf '%s' "${now}" > "${NWPI_STATE}/.usb-last-sync"
	printf '%s' "${free:-}" > "${NWPI_STATE}/.usb-free"
	nw_log "mirrored ${files} file(s) to ${USB_LABEL} for ${UNIT}"
}

# ---- prepare --------------------------------------------------------------
# Destructive, so it insists on being told exactly which device, insists that
# the device is a removable USB disk, and refuses anything the system is
# running from.
cmd_prepare() {
	local dev="${1:-}" confirm="${2:-}"
	[ -n "${dev}" ] || nw_die "prepare needs a device, e.g. /dev/sda"
	[ -b "${dev}" ] || nw_die "${dev} is not a block device"

	local base tran root_src
	base="$(basename "$(readlink -f "${dev}")")"
	[ "${confirm}" = "${base}" ] || nw_die "confirmation does not match ${base}; refusing to erase ${dev}"

	tran="$(lsblk -dno TRAN "${dev}" 2>/dev/null | tr -d ' ')"
	[ "${tran}" = "usb" ] || nw_die "${dev} is not USB-attached (transport '${tran:-unknown}'); refusing"

	[ "$(cat "/sys/block/${base}/removable" 2>/dev/null || echo 0)" = "1" ] ||
		nw_warn "${dev} does not report itself as removable; continuing because it is USB"

	root_src="$(findmnt -no SOURCE / 2>/dev/null)"
	case "${root_src}" in
		*"${base}"*) nw_die "${dev} holds this unit's root filesystem; refusing" ;;
	esac

	umount "${USB_MOUNT}" 2>/dev/null || true
	for part in "${dev}"?*; do
		[ -b "${part}" ] && umount "${part}" 2>/dev/null || true
	done

	nw_log "formatting ${dev} as exFAT labelled ${USB_LABEL}"
	# Whole-device exFAT: it mounts on Windows, macOS, and Linux without a
	# partition table to disagree about, which is what a drive passed between
	# volunteers and their laptops needs.
	wipefs -a "${dev}" >/dev/null 2>&1 || true
	mkfs.exfat -n "${USB_LABEL}" "${dev}" >/dev/null 2>&1 ||
		nw_die "mkfs.exfat failed on ${dev}"
	udevadm settle 2>/dev/null || true
	nw_log "${dev} is ready; mirroring to it now"
	cmd_sync
}

case "${1:-}" in
	status) cmd_status ;;
	sync)
		# Inserting a drive and the hourly timer can land together; the second
		# one steps aside rather than mounting the same device twice.
		exec 9>"${LOCK}"
		if ! flock -n 9; then
			nw_log "a mirror is already running; leaving it to finish"
			exit 0
		fi
		cmd_sync
		;;
	prepare) cmd_prepare "${2:-}" "${3:-}" ;;
	*) echo "usage: nw-usb.sh status | sync | prepare DEVICE CONFIRM" >&2; exit 2 ;;
esac
