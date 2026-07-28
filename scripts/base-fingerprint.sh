#!/bin/bash
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          scripts/base-fingerprint.sh
# Purpose:       Fingerprint the settings that Raspberry Pi OS's own stages
#                consume, so a resumed build can tell whether the base it is
#                about to reuse was built with the settings now configured.
#
#                This exists because of a real failure: the account password is
#                applied in stage1, a resumed build skips stage1, and four
#                images in a row therefore carried a password nobody had any
#                record of, while the config file said something else entirely.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
set -uo pipefail

CONFIG="${1:?usage: base-fingerprint.sh PI_GEN_CONFIG}"

# Everything below is consumed by stage0, stage1, or stage2 and cannot be
# changed by rebuilding our stage alone. Our own appliance variables are
# deliberately absent: those are read by our stage, which a resume does re-run.
grep -E "^(IMG_NAME|RELEASE|TARGET_HOSTNAME|FIRST_USER_NAME|FIRST_USER_PASS|DISABLE_FIRST_BOOT_USER_RENAME|ENABLE_SSH|PUBKEY_ONLY_SSH|PUBKEY_SSH_FIRST_USER|LOCALE_DEFAULT|KEYBOARD_KEYMAP|KEYBOARD_LAYOUT|TIMEZONE_DEFAULT|WPA_COUNTRY|STAGE_LIST)=" \
	"${CONFIG}" | sort | sha256sum | cut -d' ' -f1
