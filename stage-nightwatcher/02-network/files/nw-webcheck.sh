#!/bin/bash
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          /usr/local/lib/nightwatcher-pi/nw-webcheck.sh
# Purpose:       Make sure the web UI is actually reachable, and repair it if it
#                is not.
#
#                The appliance asks nightwatcherd to bind 443, which an
#                unprivileged process can only do with CAP_NET_BIND_SERVICE.
#                If that grant ever fails -- a systemd version that treats
#                ambient capabilities differently, a drop-in that did not
#                apply -- the daemon's own anti-lockout logic retries and then
#                falls back to 127.0.0.1, which on an appliance means nobody can
#                reach it from the access point at all. Silently.
#
#                So: watch for a listener, and if none appears, put the port
#                back to 8080 and restart. An ugly URL beats a dark unit.
# Created:       2026-07-29
# Last Modified: 2026-07-29
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=stage-nightwatcher/02-network/files/nw-common.sh
. /usr/local/lib/nightwatcher-pi/nw-common.sh
nw_load_conf

CONF=/etc/nightwatcher/nightwatcher.conf
PORT="${NW_WEB_PORT:-443}"
FALLBACK_PORT=8080

# Set KEY = VALUE inside [SECTION]. Section-aware because [database] and [api]
# both have a `port`, and a blind sed would rewrite the wrong one.
set_ini() {  # set_ini FILE SECTION KEY VALUE
	awk -v sec="$2" -v key="$3" -v val="$4" '
		/^[[:space:]]*\[/ { insec = ($0 ~ ("^[[:space:]]*\\[" sec "\\]")) }
		insec && $0 ~ ("^[[:space:]]*" key "[[:space:]]*=") { print key " = " val; next }
		{ print }
	' "$1" > "$1.nwtmp" && mv "$1.nwtmp" "$1"
}

listening_on() { ss -tlnH "sport = :$1" 2>/dev/null | grep -q .; }

# The daemon has to start, connect to the database, and generate a certificate
# before it binds anything, so give it a couple of minutes on a cold boot.
for _ in $(seq 1 60); do
	if listening_on "${PORT}"; then
		nw_log "web UI is listening on port ${PORT}"
		exit 0
	fi
	sleep 2
done

nw_warn "nothing is listening on port ${PORT} two minutes after the daemon started"

if [ "${PORT}" = "${FALLBACK_PORT}" ]; then
	nw_warn "already on the fallback port; see 'journalctl -u nightwatcherd'"
	exit 0
fi

# A port set from the web UI's Server tab lives in the database and overrides
# the config file, so rewriting the file would not take effect. Say so rather
# than looping.
if [ -r /etc/nightwatcher/nightwatcher.env ] &&
	mariadb -N -B -e "SELECT value FROM settings WHERE name='api_port';" nightwatcher 2>/dev/null | grep -q .; then
	nw_warn "an api_port is set in the database and overrides the config file; not changing it"
	exit 0
fi

nw_warn "falling back to port ${FALLBACK_PORT} so the unit stays reachable"
if [ -w "${CONF}" ]; then
	set_ini "${CONF}" api port "${FALLBACK_PORT}"
	nw_set_conf NW_WEB_PORT "${FALLBACK_PORT}"
	systemctl restart --no-block nightwatcherd.service
	nw_warn "the web UI will come back at https://<unit>:${FALLBACK_PORT} — check that CAP_NET_BIND_SERVICE reached nightwatcherd"
else
	nw_warn "cannot write ${CONF}; leaving the port alone"
fi
exit 0
