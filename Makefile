# ---------------------------------------------------------------------------
# Author:        David Gilinsky
# File:          Makefile
# Purpose:       Build the NightWatcher-Pi appliance image: fetch the pinned
#                NightWatcher2 package, check out pinned pi-gen, graft our stage
#                onto Raspberry Pi OS Lite, and produce a flashable .img.xz.
# Created:       2026-07-27
# Last Modified: 2026-07-27
# Version:       0.1.0
# License:       GPL-3.0-or-later
# ---------------------------------------------------------------------------
SHELL := /bin/bash
.DEFAULT_GOAL := help

include versions.env
export

ROOT     := $(CURDIR)
WORK     := $(ROOT)/work
PIGEN    := $(WORK)/pi-gen
CONFIG   := $(WORK)/pi-gen.config
DEPLOY   := $(ROOT)/deploy
DEB_DIR  := $(ROOT)/downloads
STAGE    := stage-nightwatcher

.PHONY: help
help:  ## Show the available targets
	@echo "NightWatcher-Pi $(NWPI_VERSION) — Raspberry Pi appliance image"
	@echo
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-14s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "  NightWatcher2 $(NW2_VERSION) · pi-gen $(PIGEN_BRANCH)@$(shell echo $(PIGEN_REF) | cut -c1-7) · Pi OS $(RELEASE)"
	@echo
	@echo "  Build the image in Docker (works on x86_64 via binfmt, native on arm64):"
	@echo "      make image"
	@echo "  Test an unreleased NightWatcher2 package:"
	@echo "      make image NW2_DEB=/path/to/nightwatcher_0.1.0_arm64.deb"

# ---- inputs ---------------------------------------------------------------

.PHONY: deb
deb:  ## Fetch and verify the pinned NightWatcher2 arm64 .deb
	@scripts/fetch-nightwatcher-deb.sh

$(PIGEN)/build.sh:
	@mkdir -p $(WORK)
	@echo "[pi-gen] cloning $(PIGEN_BRANCH)@$$(echo $(PIGEN_REF) | cut -c1-7)"
	@git clone --branch $(PIGEN_BRANCH) $(PIGEN_REPO) $(PIGEN)
	@git -C $(PIGEN) checkout --quiet $(PIGEN_REF)

.PHONY: pi-gen
pi-gen: $(PIGEN)/build.sh  ## Check out the pinned pi-gen tree

# The generated config carries a per-build random account password. pi-gen needs
# one to create the account at all; first boot immediately rotates it to a
# per-unit value, so this never becomes a fleet-wide secret.
$(CONFIG): config/pi-gen.config.in versions.env | pi-gen
	@mkdir -p $(WORK)
	@sed -e 's|@IMG_NAME@|$(IMG_NAME)|g' \
	     -e 's|@RELEASE@|$(RELEASE)|g' \
	     -e 's|@FIRST_USER_NAME@|$(FIRST_USER_NAME)|g' \
	     -e "s|@FIRST_USER_PASS@|$$(openssl rand -hex 16)|g" \
	     -e 's|@ENABLE_SSH@|$(ENABLE_SSH)|g' \
	     -e 's|@LOCALE_DEFAULT@|$(LOCALE_DEFAULT)|g' \
	     -e 's|@KEYBOARD_KEYMAP@|$(KEYBOARD_KEYMAP)|g' \
	     -e 's|@TIMEZONE_DEFAULT@|$(TIMEZONE_DEFAULT)|g' \
	     -e 's|@WIFI_COUNTRY@|$(WIFI_COUNTRY)|g' \
	     -e 's|@NWPI_VERSION@|$(NWPI_VERSION)|g' \
	     -e 's|@NW2_VERSION@|$(NW2_VERSION)|g' \
	     -e 's|@AP_SSID_PREFIX@|$(AP_SSID_PREFIX)|g' \
	     -e 's|@AP_PASSPHRASE@|$(AP_PASSPHRASE)|g' \
	     -e 's|@AP_ADDRESS@|$(AP_ADDRESS)|g' \
	     -e 's|@AP_CHANNEL@|$(AP_CHANNEL)|g' \
	     config/pi-gen.config.in > $(CONFIG)
	@chmod 600 $(CONFIG)
	@echo "[config] wrote $(CONFIG)"

# Graft our stage onto the pi-gen tree and stop stage2 exporting its own image,
# so one build produces one image: ours.
.PHONY: stage
stage: pi-gen deb
	@rm -rf $(PIGEN)/$(STAGE)
	@cp -a $(STAGE) $(PIGEN)/$(STAGE)
	@mkdir -p $(PIGEN)/$(STAGE)/01-nightwatcher/files
	@cp -f $(DEB_DIR)/nightwatcher_*_arm64.deb $(PIGEN)/$(STAGE)/01-nightwatcher/files/
	@touch $(PIGEN)/stage2/SKIP_IMAGES
	@printf '%s\n' "$(NWPI_VERSION)" > $(PIGEN)/$(STAGE)/VERSION
	@echo "[stage] grafted $(STAGE) with $$(basename $$(ls $(DEB_DIR)/nightwatcher_*_arm64.deb))"

# ---- image ----------------------------------------------------------------

.PHONY: image
image: stage $(CONFIG)  ## Build the image in Docker (the usual way)
	@echo "[image] building; this takes a while and needs disk"
	cd $(PIGEN) && ./build-docker.sh -c $(CONFIG)
	@$(MAKE) --no-print-directory collect

.PHONY: image-native
image-native: stage $(CONFIG)  ## Build the image directly (arm64 host, needs root)
	cd $(PIGEN) && sudo -E ./build.sh -c $(CONFIG)
	@$(MAKE) --no-print-directory collect

.PHONY: collect
collect:
	@mkdir -p $(DEPLOY)
	@cp -f $(PIGEN)/deploy/*.img.xz $(PIGEN)/deploy/*.info $(DEPLOY)/ 2>/dev/null || true
	@cd $(DEPLOY) && for f in *.img.xz; do [ -e "$$f" ] && sha256sum "$$f" > "$$f.sha256"; done; true
	@echo "[image] artifacts in $(DEPLOY):"
	@ls -lh $(DEPLOY) 2>/dev/null || true

# ---- checks ---------------------------------------------------------------

.PHONY: lint
lint:  ## shellcheck every shell script, and syntax-check the agent
	@scripts/lint.sh

.PHONY: check
check: lint  ## Everything that can be verified without building an image
	@scripts/check-stage.sh

# ---- cleaning -------------------------------------------------------------

.PHONY: clean
clean:  ## Remove the generated config and the grafted stage
	rm -rf $(CONFIG) $(PIGEN)/$(STAGE)

.PHONY: distclean
distclean:  ## Also remove pi-gen, downloads, and built images
	rm -rf $(WORK) $(DEB_DIR) $(DEPLOY)
	-docker rm -v pigen_work 2>/dev/null || true
