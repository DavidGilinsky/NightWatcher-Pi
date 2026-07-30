#!/bin/bash
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          /usr/local/lib/nightwatcher-pi/nightwatcher-firstboot.sh
# Purpose:       Turn a freshly flashed card into a specific unit: derive its
#                identity from the radio's MAC, generate the secrets that must
#                differ between units, create the database, and record the
#                result where a volunteer can read it. Runs once, and again on
#                demand with --force when a unit needs re-provisioning.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
set -uo pipefail

# shellcheck source=stage-nightwatcher/02-network/files/nw-common.sh
. /usr/local/lib/nightwatcher-pi/nw-common.sh

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

if [ -e "${NWPI_PROVISIONED}" ] && [ "${FORCE}" -eq 0 ]; then
	nw_log "already provisioned; nothing to do"
	exit 0
fi

install -d -m 755 "${NWPI_ETC}"
install -d -m 755 "${NWPI_STATE}"
nw_load_conf

# ---- 1. identity ----------------------------------------------------------
# The radio may not have probed yet. Waiting is worth it: a unit that names
# itself from the fallback serial when wlan0 was merely slow would come up with
# a different SSID than the label on its enclosure.
for _ in $(seq 1 30); do
	[ -r /sys/class/net/wlan0/address ] && break
	sleep 1
done

MAC4="$(nw_mac4)"
SSID="${AP_SSID_PREFIX:-nightwatcher}-${MAC4}"
HOSTNAME="${SSID}"

# ---- 2. the installer's overrides, if any ---------------------------------
# A text file on the boot partition is the only configuration channel that
# works before the unit has a network: an installer with an SD card and a
# laptop can edit it. On eMMC units this needs rpiboot, so it is a fallback
# rather than the main path; the web UI's RPi tab is the main path.
if [ -r "${BOOT_SITE}" ]; then
	nw_log "reading ${BOOT_SITE}"
	# Only known keys, and only simple values: this file is operator-editable
	# and must not be able to run anything.
	while IFS='=' read -r key val; do
		key="$(printf '%s' "${key}" | tr -d '[:space:]')"
		val="$(printf '%s' "${val}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')"
		[ -z "${key}" ] && continue
		case "${key}" in
			\#*) continue ;;
			COUNTRY)        [ -n "${val}" ] && nw_set_conf WIFI_COUNTRY "${val}" ;;
			AP_SSID)        [ -n "${val}" ] && SSID="${val}" ;;
			AP_PASSPHRASE)  [ -n "${val}" ] && nw_set_conf AP_PASSPHRASE "${val}" ;;
			SITE_NAME)      [ -n "${val}" ] && nw_set_conf SITE_NAME "${val}" ;;
			UPLINK_WIFI_SSID) [ -n "${val}" ] && UPLINK_SSID="${val}" ;;
			UPLINK_WIFI_PSK)  [ -n "${val}" ] && UPLINK_PSK="${val}" ;;
			TIMEZONE)       [ -n "${val}" ] && timedatectl set-timezone "${val}" 2>/dev/null || true ;;
			*) nw_warn "ignoring unknown key '${key}' in ${BOOT_SITE}" ;;
		esac
	done < "${BOOT_SITE}"
	nw_load_conf
fi

nw_set_conf AP_SSID "${SSID}"
nw_set_conf MAC4 "${MAC4}"

# hostnamectl needs systemd-hostnamed, which is present; /etc/hosts needs doing
# by hand or sudo complains about resolving the host on every invocation.
hostnamectl set-hostname "${HOSTNAME}" 2>/dev/null || printf '%s\n' "${HOSTNAME}" > /etc/hostname
if grep -q '^127\.0\.1\.1' /etc/hosts; then
	sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME}/" /etc/hosts
else
	printf '127.0.1.1\t%s\n' "${HOSTNAME}" >> /etc/hosts
fi
nw_log "this unit is ${HOSTNAME}"

# ---- 3. per-unit secrets --------------------------------------------------
# The database password differs between units flashed from the same image:
# nobody ever types it, so there is no reason for it to be shared.
#
# The login password deliberately is shared, and is not touched here. It was
# rotated to a per-unit value once, and the result was a unit whose password
# existed only on a boot partition that a Compute Module cannot show you
# without another rpiboot session. A volunteer standing in front of a unit with
# a keyboard has to be able to log in to it.
# Re-provisioning must not invent a password the database has not agreed to.
# Generating one unconditionally, writing it here, and only then asking MariaDB
# to accept it means any failure in between leaves this file and the database
# disagreeing: the daemon cannot connect at all, restarts forever, and never
# serves the web UI. That is a worse state than whatever --force was run to
# repair, so the existing password is kept whenever the database still takes it.
DB_PASS=""
DB_PASS_IS_NEW=0
if [ -f /etc/nightwatcher/nightwatcher.env ]; then
	DB_PASS="$(sed -n 's/^[[:space:]]*NW_DB_PASSWORD=//p' /etc/nightwatcher/nightwatcher.env | tail -1)"
fi
if [ -n "${DB_PASS}" ] && mariadb -u nightwatcher -p"${DB_PASS}" -e 'SELECT 1' >/dev/null 2>&1; then
	nw_log "keeping the existing database password; the database still accepts it"
else
	DB_PASS="$(openssl rand -hex 24)"
	DB_PASS_IS_NEW=1
fi


# ---- 4. the database ------------------------------------------------------
# MariaDB's root account authenticates over the local socket, so this needs no
# stored credential of its own. The daemon builds its tables and seeds the admin
# login the first time it starts.
systemctl start mariadb.service 2>/dev/null || true
for _ in $(seq 1 60); do
	mariadb -e 'SELECT 1' >/dev/null 2>&1 && break
	sleep 1
done

if mariadb -e 'SELECT 1' >/dev/null 2>&1; then
	esc="$(printf '%s' "${DB_PASS}" | sed "s/'/''/g")"
	if mariadb >/dev/null 2>&1 <<SQL
CREATE DATABASE IF NOT EXISTS \`nightwatcher\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'nightwatcher'@'localhost' IDENTIFIED BY '${esc}';
CREATE USER IF NOT EXISTS 'nightwatcher'@'127.0.0.1' IDENTIFIED BY '${esc}';
ALTER USER 'nightwatcher'@'localhost' IDENTIFIED BY '${esc}';
ALTER USER 'nightwatcher'@'127.0.0.1' IDENTIFIED BY '${esc}';
GRANT ALL PRIVILEGES ON \`nightwatcher\`.* TO 'nightwatcher'@'localhost';
GRANT ALL PRIVILEGES ON \`nightwatcher\`.* TO 'nightwatcher'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
	then
		nw_log "database and user are ready"
	else
		nw_warn "could not create the database; the web UI's Database tab can finish this"
	fi

	# Load the tables here rather than leaving the daemon to bootstrap itself.
	# A database with no tables at all was enough to keep nightwatcherd in a
	# restart loop, reporting a connection failure while its credentials were
	# perfectly good, because it recorded a startup event before creating the
	# table that event goes into. That is fixed upstream, but an appliance
	# should not depend on the order in which some future package version does
	# its own setup: the unit that owns the database creates the schema in it.
	# schema.sql is written with CREATE TABLE IF NOT EXISTS, so this is
	# idempotent and safe on every re-provision.
	# Pin the database's collation before loading anything into it. The schema
	# does not depend on this any more, but an appliance may be re-provisioned
	# onto a database some earlier version created under a different server
	# default, and a database holding tables in two collations cannot form the
	# foreign keys between them.
	mariadb -e "ALTER DATABASE \`nightwatcher\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
		>/dev/null 2>&1 || nw_warn "could not pin the database collation"

	# Load the tables here rather than leaving the daemon to bootstrap itself.
	# A database with no tables at all was enough to keep nightwatcherd in a
	# restart loop, reporting a connection failure while its credentials were
	# perfectly good. schema.sql is written with CREATE TABLE IF NOT EXISTS, so
	# this is idempotent and safe on every re-provision.
	SCHEMA="$(sed -n 's/^[[:space:]]*schema_file[[:space:]]*=[[:space:]]*//p' \
		/etc/nightwatcher/nightwatcher.conf 2>/dev/null | tail -1)"
	[ -n "${SCHEMA}" ] || SCHEMA=/usr/local/nightwatcher/sql/schema.sql
	if [ -r "${SCHEMA}" ]; then
		# Keep the error. Discarding it once cost an afternoon: the unit reported
		# only "could not load", while MariaDB had been explaining precisely which
		# constraint it refused and why.
		if schema_err="$(mariadb nightwatcher < "${SCHEMA}" 2>&1)"; then
			nw_log "schema loaded from ${SCHEMA} ($(mariadb -N -B -e \
				"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='nightwatcher';" \
				2>/dev/null || printf '?') tables)"
		else
			nw_warn "could not load ${SCHEMA}:"
			printf '%s\n' "${schema_err}" | head -5 | while IFS= read -r line; do
				nw_warn "  ${line}"
			done
		fi
	else
		nw_warn "no schema file at ${SCHEMA}; leaving the tables to the daemon"
	fi

	# Only record the password once the database has actually accepted it. The
	# env file is what the daemon reads, so writing an unverified value there is
	# how a unit ends up with a running database it cannot log in to.
	if mariadb -u nightwatcher -p"${DB_PASS}" -e 'SELECT 1' >/dev/null 2>&1; then
		if [ "${DB_PASS_IS_NEW}" -eq 1 ]; then
			umask 077
			tmp="$(mktemp /etc/nightwatcher/nightwatcher.env.XXXXXX)"
			if [ -f /etc/nightwatcher/nightwatcher.env ]; then
				grep -v '^[[:space:]]*NW_DB_PASSWORD=' /etc/nightwatcher/nightwatcher.env >> "${tmp}" 2>/dev/null || true
			fi
			printf 'NW_DB_PASSWORD=%s\n' "${DB_PASS}" >> "${tmp}"
			mv "${tmp}" /etc/nightwatcher/nightwatcher.env
			chmod 600 /etc/nightwatcher/nightwatcher.env
			umask 022
			nw_log "database password recorded"
		fi
	else
		nw_warn "the database did not accept the password; leaving /etc/nightwatcher/nightwatcher.env untouched so a working login is not overwritten"
	fi
else
	nw_warn "MariaDB did not become reachable; the daemon will retry as it restarts"
fi

# ---- 5. name and certificate ----------------------------------------------
# A volunteer should be able to type https://nightwatcher and stop. Two things
# have to be true for that: the name has to resolve on the access-point network,
# and the certificate has to claim it.
AP_IP="$(printf '%s' "${AP_ADDRESS:-192.168.4.1/24}" | cut -d/ -f1)"

# NetworkManager's shared mode runs its own dnsmasq for AP clients and reads
# snippets from this directory. A single-label name has no other way to resolve:
# mDNS covers nightwatcher.local, not the bare word.
install -d -m 755 "${NM_DNSMASQ_DIR}"
cat > "${NM_DNSMASQ_DIR}/10-nightwatcher.conf" << EOF
# Generated by NightWatcher-Pi first boot. Resolve this unit's names for
# anything joined to its access point.
address=/nightwatcher/${AP_IP}
# .local belongs to mDNS, and most clients route it there. Answering it here as
# well costs nothing and rescues clients that do not do mDNS at all, Android
# being the usual one.
address=/nightwatcher.local/${AP_IP}
address=/${HOSTNAME}/${AP_IP}
address=/${HOSTNAME}.local/${AP_IP}
EOF
nw_log "access-point DNS will answer for nightwatcher, ${HOSTNAME}, and both .local forms"

# The daemon generates a self-signed certificate itself, but names it after the
# host and the interface addresses it can see, so https://nightwatcher would
# raise a name mismatch on top of the unavoidable untrusted-issuer warning. It
# reuses an existing pair rather than regenerating, so a certificate written
# here is simply adopted.
cert_names_current_host() {
	[ -r "${NWPI_TLS_CERT}" ] || return 1
	openssl x509 -in "${NWPI_TLS_CERT}" -noout -ext subjectAltName 2>/dev/null |
		grep -q "DNS:${HOSTNAME}\b"
}

if [ "${FORCE}" -eq 1 ] || ! cert_names_current_host; then
	install -d -m 755 "${NWPI_TLS_DIR}"
	if openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
		-keyout "${NWPI_TLS_KEY}.new" -out "${NWPI_TLS_CERT}.new" \
		-subj "/O=NightWatcher/CN=${HOSTNAME}" \
		-addext "subjectAltName=DNS:nightwatcher,DNS:nightwatcher.local,DNS:${HOSTNAME},DNS:${HOSTNAME}.local,DNS:localhost,IP:${AP_IP},IP:127.0.0.1" \
		-addext "keyUsage=digitalSignature,keyEncipherment" \
		-addext "extendedKeyUsage=serverAuth" >/dev/null 2>&1
	then
		mv "${NWPI_TLS_CERT}.new" "${NWPI_TLS_CERT}"
		mv "${NWPI_TLS_KEY}.new" "${NWPI_TLS_KEY}"
		chmod 644 "${NWPI_TLS_CERT}"
		# The daemon runs as a DynamicUser in this group and only ever reads it.
		chown root:nightwatcher-pi "${NWPI_TLS_KEY}" 2>/dev/null || true
		chmod 640 "${NWPI_TLS_KEY}"
		nw_set_ini /etc/nightwatcher/nightwatcher.conf api tls_cert "${NWPI_TLS_CERT}"
		nw_set_ini /etc/nightwatcher/nightwatcher.conf api tls_key "${NWPI_TLS_KEY}"
		nw_log "certificate covers nightwatcher, ${HOSTNAME}, both .local forms, and ${AP_IP}"
	else
		rm -f "${NWPI_TLS_CERT}.new" "${NWPI_TLS_KEY}.new"
		# Leave the config pointing at the daemon's own writable state directory,
		# so it generates its own rather than serving plain HTTP.
		nw_warn "could not generate the certificate; the daemon will make its own, without the bare name"
	fi
fi

# ---- 6. the export spool --------------------------------------------------
install -d -o root -g nightwatcher-pi -m 2775 "${NWPI_SPOOL}" "${NWPI_SPOOL}/dsn"

# ---- 7. bring the appliance up -------------------------------------------
# --no-block is not optional here. Both units below are ordered
# After=nightwatcher-firstboot.service, so a blocking `systemctl restart` from
# inside this script waits for a job that systemd will not run until this script
# exits. That deadlock ends at TimeoutStartSec, with the unit killed, no access
# point, and no credentials file: a unit that boots to nothing reachable.
#
# Queuing the job is enough. systemd runs it the moment provisioning finishes,
# and on a manual `nightwatcher-provision --force` run there is no job to wait
# on at all.
systemctl restart --no-block nightwatcher-ap.service 2>/dev/null ||
	nw_warn "could not queue the access point start; check 'journalctl -u nightwatcher-ap'"

# An uplink named in the boot file, where the radio can do both roles at once.
if [ -n "${UPLINK_SSID:-}" ]; then
	/usr/local/lib/nightwatcher-pi/nw-uplink.sh join "${UPLINK_SSID}" "${UPLINK_PSK:-}" ||
		nw_warn "could not join the uplink named in ${BOOT_SITE}"
fi

systemctl reset-failed nightwatcherd.service 2>/dev/null || true
systemctl restart --no-block nightwatcherd.service 2>/dev/null ||
	nw_warn "could not queue the daemon start; check 'journalctl -u nightwatcherd'"

# ---- 8. tell somebody ------------------------------------------------------
# The boot partition is FAT and readable from any laptop, which makes it the
# one place a volunteer can always retrieve these from.
nw_load_conf
{
	cat << EOF
NightWatcher-Pi ${NWPI_VERSION:-0.1.0}
Provisioned:  $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Unit:         ${HOSTNAME}

Wi-Fi network (this unit is its own access point)
  SSID:       ${SSID}
  Passphrase: ${AP_PASSPHRASE:-nightwatcher}

Web UI (join the network above first)
  https://nightwatcher
  https://nightwatcher.local
  https://${HOSTNAME}.local
  https://$(printf '%s' "${AP_ADDRESS:-192.168.4.1/24}" | cut -d/ -f1)
  Plain http:// to any of these redirects to https automatically.
  The certificate is self-signed, so the browser warns once. That is expected.
  Sign in as 'admin' with password 'admin'; you must change it immediately.

Shell account (console and SSH)
  User:       ${FIRST_USER_NAME:-nightwatcher}
  Password:   the fleet default, documented in the deployment guide

  This one is the same on every unit, so that a volunteer with a keyboard can
  always log in to the unit in front of them. Change it per unit with 'passwd'
  where a site needs that.

Keep this file. Deleting it does not change any of the above.
EOF
} > "${BOOT_CREDS}" 2>/dev/null || nw_warn "could not write ${BOOT_CREDS}"

touch "${NWPI_PROVISIONED}"
nw_log "first boot complete: ${HOSTNAME} serving ${SSID}"
