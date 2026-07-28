#!/bin/bash
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          /usr/local/lib/nightwatcher-pi/nw-portal.sh
# Purpose:       Redirect port 443 on the access-point interface to the web UI's
#                8080, so a volunteer can type https://nightwatcher.local and
#                not https://nightwatcher.local:8080. Strictly best effort: the
#                daemon keeps its own port, and a unit whose nftables rule did
#                not take is still fully usable at :8080.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=stage-nightwatcher/02-network/files/nw-common.sh
. /usr/local/lib/nightwatcher-pi/nw-common.sh

iface="$(nw_ap_iface)"

# Our own table, so flushing it can never disturb NetworkManager's shared-mode
# masquerade rules living in theirs.
if ! nft list table ip nightwatcher >/dev/null 2>&1; then
	nft add table ip nightwatcher 2>/dev/null || {
		nw_warn "nftables unavailable; the web UI is reachable at :8080 only"
		exit 0
	}
fi

nft add chain ip nightwatcher prerouting \
	'{ type nat hook prerouting priority dstnat; policy accept; }' 2>/dev/null || true
nft flush chain ip nightwatcher prerouting 2>/dev/null || true

if nft add rule ip nightwatcher prerouting iifname "${iface}" tcp dport 443 redirect to :8080 2>/dev/null; then
	nw_log "https://nightwatcher.local (443) redirects to the web UI on 8080"
else
	nw_warn "could not install the 443 redirect; the web UI is reachable at :8080"
fi
exit 0
