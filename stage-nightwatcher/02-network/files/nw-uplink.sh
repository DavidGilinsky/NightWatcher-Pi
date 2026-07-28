#!/bin/bash
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          /usr/local/lib/nightwatcher-pi/nw-uplink.sh
# Purpose:       Join, leave, and report a Wi-Fi uplink on wlan0 while the
#                access point keeps serving on ap0. An uplink is what lets the
#                unit push DSN exports and sync its clock; without one the site
#                data leaves on a USB drive instead.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=stage-nightwatcher/02-network/files/nw-common.sh
. /usr/local/lib/nightwatcher-pi/nw-common.sh

STA="$(nw_sta_iface)"

# One radio serves one channel. While the AP has its own interface the two roles
# coexist (the AP follows the station's channel); where ap0 could not be created
# the AP owns wlan0 outright and joining would take the appliance off the air,
# which is never the right trade for a unit nobody can reach any other way.
require_concurrency() {
	if [ "$(nw_ap_iface)" = "${STA}" ]; then
		nw_die "this radio cannot run the access point and a client at once; use an Ethernet or USB Wi-Fi uplink"
	fi
}

cmd_scan() {
	require_concurrency
	nmcli device wifi rescan ifname "${STA}" >/dev/null 2>&1 || true
	# Tab-separated: ssid, signal, security, frequency. Hidden networks have no
	# SSID to offer, so they are dropped rather than listed as blanks.
	nmcli -t -f SSID,SIGNAL,SECURITY,FREQ device wifi list ifname "${STA}" 2>/dev/null |
		awk -F: 'NF >= 4 && $1 != "" { print }' | sort -t: -k2 -rn | head -40
}

cmd_join() {
	local ssid="$1" psk="${2:-}"
	require_concurrency
	[ -n "${ssid}" ] || nw_die "join needs an SSID"
	if [ -n "${psk}" ] && { [ "${#psk}" -lt 8 ] || [ "${#psk}" -gt 63 ]; }; then
		nw_die "a passphrase is 8 to 63 characters"
	fi

	nmcli connection delete "${UPLINK_CON}" >/dev/null 2>&1 || true
	nmcli connection add type wifi ifname "${STA}" con-name "${UPLINK_CON}" \
		ssid "${ssid}" autoconnect yes connection.autoconnect-priority 50 \
		ipv4.method auto ipv6.method auto >/dev/null || nw_die "could not create the uplink profile"

	if [ -n "${psk}" ]; then
		nmcli connection modify "${UPLINK_CON}" \
			wifi-sec.key-mgmt wpa-psk wifi-sec.psk "${psk}" >/dev/null ||
			nw_die "could not set the uplink passphrase"
	fi

	# The passphrase lives in NetworkManager's own 0600 store, never in the
	# NightWatcher database and never in this unit's configuration file.
	if ! nmcli connection up "${UPLINK_CON}" >/dev/null 2>&1; then
		nmcli connection delete "${UPLINK_CON}" >/dev/null 2>&1 || true
		nw_die "could not join ${ssid}: wrong passphrase, out of range, or the network refused"
	fi
	nw_set_conf UPLINK_SSID "${ssid}"

	# The AP must now follow the station's channel, so re-apply it. Clients drop
	# for a few seconds while the radio retunes; that is the cost of one radio.
	/usr/local/lib/nightwatcher-pi/nw-ap.sh apply || nw_warn "the access point did not come back after retuning"
	nw_log "uplink joined: ${ssid}"
}

cmd_forget() {
	nmcli connection down "${UPLINK_CON}" >/dev/null 2>&1 || true
	nmcli connection delete "${UPLINK_CON}" >/dev/null 2>&1 || true
	nw_set_conf UPLINK_SSID ""
	/usr/local/lib/nightwatcher-pi/nw-ap.sh apply || true
	nw_log "uplink forgotten; the access point is back on its fixed channel"
}

cmd_status() {
	nw_load_conf
	local ssid="" ip="" signal="" state="down"
	if nmcli -t -f NAME connection show --active 2>/dev/null | grep -qx "${UPLINK_CON}"; then
		state="up"
		ssid="${UPLINK_SSID:-}"
		ip="$(ip -4 -o addr show dev "${STA}" 2>/dev/null | awk '{print $4}' | head -1)"
		signal="$(nmcli -t -f IN-USE,SIGNAL device wifi list ifname "${STA}" 2>/dev/null |
			awk -F: '$1 == "*" {print $2; exit}')"
	fi
	printf 'state=%s\nssid=%s\naddress=%s\nsignal=%s\ninternet=%s\nethernet=%s\n' \
		"${state}" "${ssid}" "${ip}" "${signal}" \
		"$(nw_have_uplink && printf yes || printf no)" \
		"$(ip -4 -o addr show dev eth0 2>/dev/null | awk '{print $4}' | head -1)"
}

case "${1:-}" in
	scan)   cmd_scan ;;
	join)   cmd_join "${2:-}" "${3:-}" ;;
	forget) cmd_forget ;;
	status) cmd_status ;;
	*) echo "usage: nw-uplink.sh scan | join SSID [PASSPHRASE] | forget | status" >&2; exit 2 ;;
esac
