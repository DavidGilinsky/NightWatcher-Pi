#!/bin/bash
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          scripts/check-stage.sh
# Purpose:       Structural checks on the pi-gen stage: the things that would
#                otherwise be discovered forty minutes into a build, or worse,
#                on a unit that boots without an access point. Nothing here
#                needs root, Docker, or an image.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
STAGE=stage-nightwatcher
fail=0

check() {  # check DESCRIPTION TEST...
	local desc="$1"; shift
	if "$@"; then
		printf '  ok    %s\n' "${desc}"
	else
		printf '  FAIL  %s\n' "${desc}"
		fail=1
	fi
}

echo "[check] stage layout"
# pi-gen runs a sub-stage's NN-run.sh only when it is executable. A stage script
# that lost its bit is silently skipped, which is the worst possible failure:
# the build succeeds and the image is wrong.
for s in "${STAGE}"/*/[0-9][0-9]-run.sh "${STAGE}/prerun.sh"; do
	check "executable: ${s}" test -x "${s}"
done
check "stage exports an image" test -f "${STAGE}/EXPORT_IMAGE"
check "prerun.sh copies the previous stage" grep -q copy_previous "${STAGE}/prerun.sh"

echo "[check] units"
mapfile -t units < <(find "${STAGE}" -name '*.service' -o -name '*.timer' | sort)
for u in "${units[@]}"; do
	check "has [Install] or is timer-started: $(basename "${u}")" \
		bash -c "grep -q '^\[Install\]' '${u}' || [[ '${u}' == *usb-sync.service ]]"
	check "no Restart= on a Type=oneshot with always: $(basename "${u}")" \
		bash -c "! (grep -q '^Type=oneshot' '${u}' && grep -q '^Restart=always' '${u}')"
done

# Every unit the stage enables must actually be installed by some stage script,
# and every unit installed should be enabled or explicitly started by something.
echo "[check] enabled units exist"
# Unit names are not all lowercase (NetworkManager.service), and a pattern that
# assumes they are matches the prefix and yields an empty name.
mapfile -t enabled < <(grep -rho 'systemctl enable [A-Za-z0-9.@_-]*' "${STAGE}" |
	awk 'NF == 3 { print $3 }' | sort -u)
for e in "${enabled[@]}"; do
	case "${e}" in
		# Stock Raspberry Pi OS units, not ours to ship.
		mariadb.service|avahi-daemon.service|systemd-timesyncd.service|\
		fake-hwclock.service|NetworkManager.service) continue ;;
	esac
	check "shipped: ${e}" bash -c "find '${STAGE}' -name '${e}' | grep -q ."
done

echo "[check] runtime paths agree"
# The three places that have to name the same spool directory: the stage that
# creates it, the drop-in that lets the daemon write it, and the tab that
# configures the export target to point at it.
SPOOL=/var/lib/nightwatcher-pi/spool
check "stage creates ${SPOOL}/dsn" \
	grep -q "${SPOOL}/dsn" "${STAGE}/01-nightwatcher/01-run.sh"
check "drop-in makes ${SPOOL} writable" \
	grep -q "ReadWritePaths=${SPOOL}" "${STAGE}/01-nightwatcher/files/pi-appliance.conf"
check "the tab points the export target at ${SPOOL}/dsn" \
	grep -q "SPOOL_DIR = '${SPOOL}/dsn'" "${STAGE}/05-agent/files/ui.js"
check "the agent reports the same spool" \
	grep -q "\"spool_dir\": \"${SPOOL}/dsn\"\|'spool_dir': '${SPOOL}/dsn'\|${SPOOL}/dsn" \
	"${STAGE}/05-agent/files/nightwatcher-pi-agent"

# The socket path is a contract with NightWatcher2, which defaults to exactly
# this. If one side moves, the tab quietly stops existing.
SOCK=/run/nightwatcher-platform.sock
check "agent listens on ${SOCK}" grep -q "${SOCK}" "${STAGE}/05-agent/files/nightwatcher-pi-agent"
check "library agrees on ${SOCK}" grep -q "${SOCK}" "${STAGE}/02-network/files/nw-common.sh"

# The group that joins the sandboxed daemon to the agent and the spool.
check "group created in the image" \
	grep -q 'groupadd .*nightwatcher-pi' "${STAGE}/00-base/01-run.sh"
check "daemon joins the group" \
	grep -q 'SupplementaryGroups=nightwatcher-pi' "${STAGE}/01-nightwatcher/files/pi-appliance.conf"
check "agent gives the socket to the group" \
	grep -q 'SOCKET_GROUP = "nightwatcher-pi"' "${STAGE}/05-agent/files/nightwatcher-pi-agent"

echo "[check] first boot"
check "provisioning is gated by a sentinel" \
	grep -q 'ConditionPathExists=!/var/lib/nightwatcher-pi/.provisioned' \
	"${STAGE}/03-firstboot/files/nightwatcher-firstboot.service"
# Literal source text: the single quotes are the point, nothing expands here.
# shellcheck disable=SC2016
check "the sentinel the script writes matches the unit's" \
	grep -q 'NWPI_PROVISIONED="\${NWPI_STATE}/.provisioned"' \
	"${STAGE}/02-network/files/nw-common.sh"
# shellcheck disable=SC2016
check "the database password is generated, not baked" \
	grep -q 'DB_PASS="\$(openssl rand' "${STAGE}/03-firstboot/files/nightwatcher-firstboot.sh"
# The login password is a documented fleet default and must survive first boot.
# Rotating it to a per-unit value once produced a unit that could not be logged
# in to from its own console, because the new password existed only on a boot
# partition a Compute Module cannot show you without rpiboot.
check "first boot does not rotate the login password" \
	bash -c "! grep -q 'chpasswd' '${STAGE}/03-firstboot/files/nightwatcher-firstboot.sh'"
# nightwatcher-ap and nightwatcherd are both ordered After=firstboot, so a
# blocking restart from inside first boot waits for a job systemd will not run
# until first boot exits. The unit then dies at TimeoutStartSec having brought
# up no access point, which is a unit nobody can reach.
check "first boot never blocks on a unit ordered after it" \
	bash -c "! grep -E '^[[:space:]]*systemctl restart ' '${STAGE}/03-firstboot/files/nightwatcher-firstboot.sh' | grep -qv -- '--no-block'"
check "the login password is pinned, not generated" \
	grep -qE '^FIRST_USER_PASS=.+' versions.env
check "the database password is still per unit" \
	grep -q 'openssl rand' "${STAGE}/03-firstboot/files/nightwatcher-firstboot.sh"
check "the preseed does not carry a password" \
	bash -c "grep -q '^nightwatcher nightwatcher/db_password password\$' '${STAGE}/01-nightwatcher/00-debconf'"
check "the preseed defers database creation" \
	grep -q 'db_create boolean false' "${STAGE}/01-nightwatcher/00-debconf"
# debconf-set-selections takes the whole remainder of the line as the value, so
# padding used to line values up ends up inside them: "string  0.0.0.0" becomes
# a bind address with a leading space. Every directive is single-spaced, and is
# owner, question, type, and at most one value.
check "no padding hiding inside a preseed value" \
	bash -c "! grep -qE '^nightwatcher .*[[:space:]]{2,}' '${STAGE}/01-nightwatcher/00-debconf'"
check "every preseed line is well formed" \
	bash -c "! grep -qvE '^(#.*)?\$|^nightwatcher nightwatcher/[a-z_]+ (password|string|boolean)( [^[:space:]]+)?\$' '${STAGE}/01-nightwatcher/00-debconf'"

echo "[check] provenance"
# /etc/nightwatcher-pi-release is only worth writing if it can be trusted, so
# it must report the package source the fetch recorded, never the version the
# build merely asked for.
# shellcheck disable=SC2016
check "the release stamp reports the real package source" \
	grep -q 'NW2_SOURCE=\${NW2_SOURCE}' "${STAGE}/06-release/00-run.sh"
check "the release stamp does not claim the requested release" \
	bash -c "! grep -q 'NW2_RELEASE=' '${STAGE}/06-release/00-run.sh'"
check "the fetch records what it used, on every path" \
	bash -c "[ \"\$(grep -c '^ *provenance ' scripts/fetch-nightwatcher-deb.sh)\" -eq 3 ]"

echo "[check] usb"
check "udev rule and script agree on the label" \
	bash -c "grep -q 'ID_FS_LABEL}==\"NWDATA\"' '${STAGE}/04-usb/files/99-nightwatcher-usb.rules' &&
	         grep -q 'USB_LABEL=NWDATA' '${STAGE}/02-network/files/nw-common.sh'"
check "the mirror always unmounts" \
	grep -q "trap 'sync; umount" "${STAGE}/04-usb/files/nw-usb.sh"

if [ "${fail}" -eq 0 ]; then
	echo "[check] stage looks sound"
else
	echo "[check] problems found" >&2
fi
exit "${fail}"
