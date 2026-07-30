# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          /usr/local/lib/nightwatcher-pi/nw-common.sh
# Purpose:       Shared shell library for the appliance scripts: paths, logging,
#                the unit's derived identity, and the effective configuration.
#                Sourced, never executed.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
# shellcheck shell=bash
# These are the appliance's shared constants; each is used by some script that
# sources this file, which shellcheck cannot see from here.
# shellcheck disable=SC2034

NWPI_ETC=/etc/nightwatcher-pi
NWPI_CONF="${NWPI_ETC}/appliance.conf"          # effective settings, rewritten in place
NWPI_DEFAULTS="${NWPI_ETC}/appliance.defaults"  # what the image was built with
NWPI_STATE=/var/lib/nightwatcher-pi
NWPI_SPOOL="${NWPI_STATE}/spool"
NWPI_PROVISIONED="${NWPI_STATE}/.provisioned"
NWPI_SOCKET=/run/nightwatcher-platform.sock
NWPI_TLS_DIR="${NWPI_ETC}/tls"
NWPI_TLS_CERT="${NWPI_TLS_DIR}/nightwatcher-cert.pem"
NWPI_TLS_KEY="${NWPI_TLS_DIR}/nightwatcher-key.pem"
NM_DNSMASQ_DIR=/etc/NetworkManager/dnsmasq-shared.d
BOOT_DIR=/boot/firmware
BOOT_SITE="${BOOT_DIR}/nightwatcher-site.txt"
BOOT_CREDS="${BOOT_DIR}/nightwatcher-credentials.txt"
AP_CON=nightwatcher-ap
UPLINK_CON=nightwatcher-uplink
USB_LABEL=NWDATA
USB_MOUNT=/media/nightwatcher

# Log to the journal and to stderr, so the same line is visible whether the
# caller is a systemd unit or a person over SSH.
nw_log() { logger -t nightwatcher-pi -p daemon.info -- "$*"; printf '%s\n' "$*" >&2; }
nw_warn() { logger -t nightwatcher-pi -p daemon.warning -- "$*"; printf 'WARNING: %s\n' "$*" >&2; }
nw_die() { logger -t nightwatcher-pi -p daemon.err -- "$*"; printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# The image's build-time defaults, then whatever this unit has settled on.
nw_load_conf() {
	# shellcheck source=/dev/null
	[ -r "${NWPI_DEFAULTS}" ] && . "${NWPI_DEFAULTS}"
	# shellcheck source=/dev/null
	[ -r "${NWPI_CONF}" ] && . "${NWPI_CONF}"
	return 0
}

# Set KEY=value in appliance.conf, replacing any existing line for that key.
# Values are single-quoted, so a passphrase containing shell metacharacters
# survives the round trip.
nw_set_conf() {
	local key="$1" val="$2" tmp
	install -d -m 755 "${NWPI_ETC}"
	[ -f "${NWPI_CONF}" ] || : > "${NWPI_CONF}"
	tmp="$(mktemp "${NWPI_CONF}.XXXXXX")"
	grep -v "^${key}=" "${NWPI_CONF}" > "${tmp}" 2>/dev/null || true
	printf "%s='%s'\n" "${key}" "$(printf '%s' "${val}" | sed "s/'/'\\\\''/g")" >> "${tmp}"
	chmod 600 "${tmp}"
	mv "${tmp}" "${NWPI_CONF}"
}

# Set KEY = VALUE inside [SECTION] of an INI file. Section-aware because
# [database] and [api] both carry a `port`, and a blind sed rewrites the wrong
# one. Mirrors what NightWatcher2's own postinst does to the same file.
nw_set_ini() {  # nw_set_ini FILE SECTION KEY VALUE
	awk -v sec="$2" -v key="$3" -v val="$4" '
		/^[[:space:]]*\[/ { insec = ($0 ~ ("^[[:space:]]*\\[" sec "\\]")) }
		insec && $0 ~ ("^[[:space:]]*" key "[[:space:]]*=") { print key " = " val; next }
		{ print }
	' "$1" > "$1.nwtmp" && mv "$1.nwtmp" "$1"
}

# The wireless interface that carries the access point. The image adds a
# dedicated ap0 so wlan0 stays free to be a client; where the radio or its
# firmware will not do two interfaces, the AP falls back to wlan0 and the
# uplink simply is not available.
nw_ap_iface() {
	if [ -d /sys/class/net/ap0 ]; then printf 'ap0'; else printf 'wlan0'; fi
}

nw_sta_iface() { printf 'wlan0'; }

# Last 4 bytes of the wlan0 MAC, lowercase hex, no separators: the unit's
# identity, and the thing that makes every SSID in a network unique.
nw_mac4() {
	local mac hex serial
	mac="$(cat /sys/class/net/wlan0/address 2>/dev/null || true)"
	if [ -n "${mac}" ]; then
		hex="$(printf '%s' "${mac}" | tr -d ':' | tr '[:upper:]' '[:lower:]')"
		# Exactly 8 characters: 4 bytes. `tail -c 9` looks like the idiom for
		# this and is not: it counts bytes, and the string has no trailing
		# newline to absorb one, so it yields 9 hex digits and a unit named
		# nightwatcher-f67fb3777 instead of nightwatcher-67fb3777.
		printf '%s' "${hex: -8}"
		return 0
	fi
	# No radio yet (or at all). The Pi's own serial keeps the unit nameable
	# rather than leaving it as a generic "raspberrypi" on the network.
	serial="$(sed -n 's/^Serial\s*:\s*0*//p' /proc/cpuinfo | tail -1)"
	[ -n "${serial}" ] || serial="00000000"
	serial="$(printf '%s' "${serial}" | tr '[:upper:]' '[:lower:]')"
	printf '%s' "${serial: -8}"
}

# Whether this unit has an internet path right now, whatever carries it.
nw_have_uplink() {
	ip route show default 2>/dev/null | grep -qv "dev $(nw_ap_iface)"
}
