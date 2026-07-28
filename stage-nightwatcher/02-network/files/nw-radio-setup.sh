#!/bin/bash
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          /usr/local/lib/nightwatcher-pi/nw-radio-setup.sh
# Purpose:       Prepare the radio before NetworkManager takes it: set the
#                regulatory domain, unblock the transmitter, and add the ap0
#                interface that lets the access point stay up while wlan0 joins
#                someone else's network.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=stage-nightwatcher/02-network/files/nw-common.sh
. /usr/local/lib/nightwatcher-pi/nw-common.sh
nw_load_conf

COUNTRY="${WIFI_COUNTRY:-US}"

# An AP will not start in an unset regulatory domain: the driver has no channel
# it is permitted to transmit on.
rfkill unblock wifi 2>/dev/null || nw_warn "rfkill unblock failed"
if ! iw reg set "${COUNTRY}" 2>/dev/null; then
	nw_warn "could not set the regulatory domain to ${COUNTRY}"
fi

# The radio may not have probed yet on a cold boot.
for _ in $(seq 1 30); do
	[ -d /sys/class/net/wlan0 ] && break
	sleep 1
done
if [ ! -d /sys/class/net/wlan0 ]; then
	nw_warn "no wlan0 after 30s: this unit has no usable wireless interface"
	exit 0        # not fatal: the rest of the appliance still comes up
fi

if [ -d /sys/class/net/ap0 ]; then
	exit 0        # already added this boot
fi

# One radio, two roles. brcmfmac allows a second virtual interface in AP mode;
# where the firmware refuses, the AP script falls back to running on wlan0 and
# the unit is simply access-point-only.
if ! iw dev wlan0 interface add ap0 type __ap 2>/dev/null; then
	nw_warn "this radio will not run a second AP interface; the AP will use wlan0 and no Wi-Fi uplink is possible"
	exit 0
fi

# Give ap0 its own address, or the two interfaces collide on the air. XOR of the
# locally-administered bit rather than OR: OR leaves the address unchanged when
# the base MAC already has that bit set.
base="$(cat /sys/class/net/wlan0/address)"
first="${base%%:*}"
rest="${base#*:}"
newfirst="$(printf '%02x' $(( 0x${first} ^ 0x02 )))"
if ! ip link set ap0 address "${newfirst}:${rest}" 2>/dev/null; then
	nw_warn "could not set the ap0 MAC address; continuing with the driver's"
fi
ip link set ap0 up 2>/dev/null || nw_warn "could not bring ap0 up"
nw_log "ap0 ready (${newfirst}:${rest}); wlan0 is free for an uplink"
