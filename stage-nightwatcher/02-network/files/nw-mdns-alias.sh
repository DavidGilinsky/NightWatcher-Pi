#!/bin/bash
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          /usr/local/lib/nightwatcher-pi/nw-mdns-alias.sh
# Purpose:       Hold an mDNS address record for nightwatcher.local pointing at
#                this unit's access-point address, for as long as the service
#                runs. avahi-publish stays in the foreground by design: exiting
#                would withdraw the record.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=stage-nightwatcher/02-network/files/nw-common.sh
. /usr/local/lib/nightwatcher-pi/nw-common.sh
nw_load_conf

# The configured AP address without its prefix length.
addr="${AP_ADDRESS:-192.168.4.1/24}"
addr="${addr%%/*}"

# Wait for the interface to actually carry it, or the record advertises an
# address nothing answers on.
for _ in $(seq 1 60); do
	ip -4 -o addr show 2>/dev/null | grep -q " ${addr}/" && break
	sleep 2
done

nw_log "publishing nightwatcher.local as ${addr}"
exec avahi-publish -a -R nightwatcher.local "${addr}"
