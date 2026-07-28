#!/bin/bash
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          /usr/local/lib/nightwatcher-pi/nw-ap.sh
# Purpose:       Own the access point's NetworkManager profile. `apply` is
#                idempotent and runs on every boot; the agent calls the setters
#                when an operator changes the SSID or passphrase from the web
#                UI. NetworkManager's shared IPv4 mode supplies DHCP, DNS, and
#                (when an uplink exists) NAT, so there is no dnsmasq or hostapd
#                configuration of our own to drift.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=stage-nightwatcher/02-network/files/nw-common.sh
. /usr/local/lib/nightwatcher-pi/nw-common.sh

usage() {
	cat <<'EOF'
usage: nw-ap.sh apply | status | set-ssid SSID | set-psk PASSPHRASE | channel N|auto
EOF
}

# The AP tracks the client's channel when this unit has an uplink: one radio
# cannot serve two channels, and the client role dictates it.
ap_channel() {
	nw_load_conf
	if nmcli -t -f NAME connection show --active 2>/dev/null | grep -qx "${UPLINK_CON}"; then
		printf '0'          # 0 = let NetworkManager follow the station
	else
		printf '%s' "${AP_CHANNEL:-6}"
	fi
}

cmd_apply() {
	nw_load_conf
	local iface ssid psk addr chan
	iface="$(nw_ap_iface)"
	ssid="${AP_SSID:-}"
	psk="${AP_PASSPHRASE:-nightwatcher}"
	addr="${AP_ADDRESS:-192.168.4.1/24}"
	chan="$(ap_channel)"

	if [ -z "${ssid}" ]; then
		nw_warn "no AP_SSID configured yet; first boot has not run"
		return 1
	fi
	if [ "${#psk}" -lt 8 ] || [ "${#psk}" -gt 63 ]; then
		nw_die "AP passphrase must be 8 to 63 characters"
	fi

	if ! nmcli -t -f NAME connection show 2>/dev/null | grep -qx "${AP_CON}"; then
		nw_log "creating the access point profile on ${iface} as ${ssid}"
		nmcli connection add type wifi ifname "${iface}" con-name "${AP_CON}" \
			autoconnect yes ssid "${ssid}" >/dev/null || nw_die "could not create ${AP_CON}"
	fi

	# Set every field every time: this is also the repair path for a profile an
	# operator edited by hand, and for settings added by a later image version.
	nmcli connection modify "${AP_CON}" \
		connection.interface-name "${iface}" \
		connection.autoconnect yes \
		connection.autoconnect-priority 100 \
		802-11-wireless.mode ap \
		802-11-wireless.ssid "${ssid}" \
		802-11-wireless.band bg \
		802-11-wireless.channel "${chan}" \
		wifi-sec.key-mgmt wpa-psk \
		wifi-sec.proto rsn \
		wifi-sec.pairwise ccmp \
		wifi-sec.group ccmp \
		wifi-sec.pmf 1 \
		wifi-sec.psk "${psk}" \
		ipv4.method shared \
		ipv4.addresses "${addr}" \
		ipv6.method ignore >/dev/null || nw_die "could not configure ${AP_CON}"

	# Bringing up an already-active profile is how a changed SSID or passphrase
	# takes effect, so this is not conditional on it being down.
	if ! nmcli connection up "${AP_CON}" >/dev/null 2>&1; then
		nw_warn "the access point did not come up; check 'nmcli connection up ${AP_CON}'"
		return 1
	fi
	nw_log "access point ${ssid} is up on ${iface} at ${addr}"
}

cmd_status() {
	nw_load_conf
	local iface state
	iface="$(nw_ap_iface)"
	state="down"
	nmcli -t -f NAME connection show --active 2>/dev/null | grep -qx "${AP_CON}" && state="up"
	printf 'iface=%s\nssid=%s\nstate=%s\naddress=%s\nchannel=%s\nclients=%s\n' \
		"${iface}" "${AP_SSID:-}" "${state}" "${AP_ADDRESS:-}" "$(ap_channel)" \
		"$(iw dev "${iface}" station dump 2>/dev/null | grep -c '^Station' || printf 0)"
}

case "${1:-}" in
	apply)  cmd_apply ;;
	status) cmd_status ;;
	set-ssid)
		[ -n "${2:-}" ] || nw_die "set-ssid needs an SSID"
		[ "${#2}" -le 32 ] || nw_die "an SSID is at most 32 characters"
		nw_set_conf AP_SSID "$2"; cmd_apply ;;
	set-psk)
		[ -n "${2:-}" ] || nw_die "set-psk needs a passphrase"
		[ "${#2}" -ge 8 ] && [ "${#2}" -le 63 ] || nw_die "a passphrase is 8 to 63 characters"
		nw_set_conf AP_PASSPHRASE "$2"; cmd_apply ;;
	channel)
		case "${2:-}" in
			auto) nw_set_conf AP_CHANNEL 0 ;;
			[0-9]|[0-9][0-9]) nw_set_conf AP_CHANNEL "$2" ;;
			*) nw_die "channel takes 1-14 or 'auto'" ;;
		esac
		cmd_apply ;;
	*) usage; exit 2 ;;
esac
