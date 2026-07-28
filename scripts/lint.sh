#!/bin/bash
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          scripts/lint.sh
# Purpose:       Static checks over everything the image runs: shellcheck on the
#                shell, py_compile on the agent, and a syntax check on the tab's
#                JavaScript. An image build takes tens of minutes, so a typo
#                should be caught here rather than on a Pi.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
fail=0

# ---- shell ----------------------------------------------------------------
mapfile -t scripts < <(find scripts stage-nightwatcher -type f -name '*.sh' | sort -u)

if command -v shellcheck >/dev/null 2>&1; then
	echo "[lint] shellcheck (${#scripts[@]} scripts)"
	# The pi-gen stage scripts use ROOTFS_DIR, on_chroot, and install() from the
	# build environment, which shellcheck cannot see: SC2154 and SC1091 are
	# expected there, not defects.
	shellcheck --external-sources --exclude=SC1091,SC2154 "${scripts[@]}" || fail=1
else
	echo "[lint] shellcheck not installed; skipping (apt install shellcheck)"
fi

# bash's own parser catches what shellcheck's absence would miss.
for s in "${scripts[@]}"; do
	bash -n "$s" || { echo "[lint] syntax error in $s"; fail=1; }
done

# The shell library is sourced, never run, so it is checked separately.
bash -n stage-nightwatcher/02-network/files/nw-common.sh ||
	{ echo "[lint] syntax error in nw-common.sh"; fail=1; }

# ---- python ---------------------------------------------------------------
echo "[lint] python"
python3 -m py_compile stage-nightwatcher/05-agent/files/nightwatcher-pi-agent ||
	{ echo "[lint] the agent does not compile"; fail=1; }
find . -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true

# ---- javascript -----------------------------------------------------------
if command -v node >/dev/null 2>&1; then
	echo "[lint] javascript"
	# ui.js is an ES module; node only parses one as such when it ends in .mjs.
	tmp="$(mktemp -t nwpi-ui-XXXXXX.mjs)"
	cp stage-nightwatcher/05-agent/files/ui.js "${tmp}"
	node --check "${tmp}" || { echo "[lint] ui.js does not parse"; fail=1; }
	rm -f "${tmp}"
else
	echo "[lint] node not installed; skipping the ui.js check"
fi

[ "${fail}" -eq 0 ] && echo "[lint] clean"
exit "${fail}"
