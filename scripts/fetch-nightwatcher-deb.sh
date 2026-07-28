#!/bin/bash
# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          scripts/fetch-nightwatcher-deb.sh
# Purpose:       Put exactly one verified NightWatcher2 arm64 .deb into
#                downloads/ for the image build. Prefers a published release
#                (checksum-verified); falls back to a CI artifact or a local
#                file for work that has not been released yet, and says loudly
#                which one it used.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/versions.env"

DEST="${REPO_ROOT}/downloads"
mkdir -p "${DEST}"

log() { printf '[fetch-deb] %s\n' "$*"; }
die() { printf '[fetch-deb] ERROR: %s\n' "$*" >&2; exit 1; }

# ---- 1. an explicit local package wins, for pre-release testing ----
if [ -n "${NW2_DEB:-}" ]; then
    [ -f "${NW2_DEB}" ] || die "NW2_DEB=${NW2_DEB} does not exist"
    case "${NW2_DEB}" in
        *_arm64.deb) ;;
        *) die "NW2_DEB must be an arm64 package (got $(basename "${NW2_DEB}"))" ;;
    esac
    rm -f "${DEST}"/nightwatcher_*.deb
    cp -f "${NW2_DEB}" "${DEST}/"
    log "using local package $(basename "${NW2_DEB}") (UNVERIFIED: no release checksum)"
    exit 0
fi

command -v gh >/dev/null || die "the gh CLI is required to download the package"

# ---- 2. the pinned release, verified against its SHA256SUMS ----
if gh release view "${NW2_VERSION}" --repo "${NW2_REPO}" >/dev/null 2>&1; then
    log "downloading ${NW2_REPO} ${NW2_VERSION} (arm64)"
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT
    gh release download "${NW2_VERSION}" --repo "${NW2_REPO}" \
        --pattern 'nightwatcher_*_arm64.deb' --pattern 'SHA256SUMS' --dir "${tmp}"

    deb="$(find "${tmp}" -maxdepth 1 -name 'nightwatcher_*_arm64.deb' -print -quit)"
    [ -n "${deb}" ] || die "release ${NW2_VERSION} has no arm64 .deb asset"
    [ -f "${tmp}/SHA256SUMS" ] || die "release ${NW2_VERSION} has no SHA256SUMS asset"

    # Check only the file we took, so an amd64 line in the manifest is not a
    # missing-file failure.
    ( cd "${tmp}" && grep " $(basename "${deb}")\$" SHA256SUMS | sha256sum -c - ) \
        || die "checksum mismatch on $(basename "${deb}")"
    log "checksum verified"

    rm -f "${DEST}"/nightwatcher_*.deb
    cp -f "${deb}" "${DEST}/"
    log "using $(basename "${deb}") from release ${NW2_VERSION}"
    exit 0
fi

# ---- 3. no such release: fall back to the newest successful CI build ----
# NightWatcher2 published CI artifacts before it published releases. This keeps
# image builds possible in that window, but it pins nothing, so it warns.
log "no release ${NW2_VERSION} in ${NW2_REPO}; falling back to a CI artifact"
run_id="${NW2_RUN_ID:-}"
if [ -z "${run_id}" ]; then
    run_id="$(gh run list --repo "${NW2_REPO}" --workflow CI --branch main \
        --status success --limit 1 --json databaseId --jq '.[0].databaseId')"
fi
[ -n "${run_id}" ] || die "no successful CI run found; build the .deb yourself and pass NW2_DEB="

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
gh run download "${run_id}" --repo "${NW2_REPO}" --name nightwatcher-arm64-deb --dir "${tmp}"
deb="$(find "${tmp}" -maxdepth 1 -name 'nightwatcher_*.deb' -print -quit)"
[ -n "${deb}" ] || die "CI run ${run_id} has no arm64 .deb artifact"

rm -f "${DEST}"/nightwatcher_*.deb
cp -f "${deb}" "${DEST}/"
log "using $(basename "${deb}") from CI run ${run_id} (UNPINNED: tag a release for reproducible images)"
