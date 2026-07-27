# NightWatcher-Pi

NightWatcher-Pi builds a **headless Raspberry Pi 5 appliance image** that runs
NightWatcher2 and boots as a **self-contained Wi-Fi access point**. Power it on,
join its network, and the NightWatcher2 web UI is right there, with no monitor,
keyboard, router, or existing network required.

## The brief

- **Target:** Raspberry Pi 5, headless (no display or keyboard).
- **Output:** a flashable Raspberry Pi OS (Raspbian) image with NightWatcher2
  preinstalled and set to run on boot.
- **Networking:** on boot the Pi comes up as a **wireless access point**, not a
  Wi-Fi client. SSID = `nightwatcher-<mac4>`, where `<mac4>` is the **last 4
  bytes of the wlan0 MAC address in hex** (8 hex chars, e.g.
  `nightwatcher-a1b2c3d4`), derived on first boot so every unit is unique.
- **Access:** a client joins that SSID and reaches the NightWatcher2 web UI
  (served by `nightwatcherd`) over the AP network, via the Pi's AP gateway IP
  and/or an mDNS hostname such as `nightwatcher.local`.

## Relation to the ecosystem

This is a **delivery / packaging** project: it bundles NightWatcher2 (and its
MariaDB backend) into a turnkey Pi image. It depends on NightWatcher2's **arm64
`.deb`** (NightWatcher2 already builds arm64 in CI) but ships no application code
of its own. It is image build tooling plus system configuration.

> **Approach: TBD in this session.** Open design points to settle first:
> - **Image build tooling:** the official **pi-gen** (Raspberry Pi OS's own image
>   builder, custom stage) vs `rpi-image-gen` / `CustomPiOS` vs a first-boot
>   provisioning script layered on a stock image. pi-gen is closest to "official
>   Raspberry Pi OS + our stage".
> - **AP stack:** Raspberry Pi OS **Bookworm uses NetworkManager**, which can run
>   an access point via `nmcli` (cleanest on current Pi OS); `hostapd` +
>   `dnsmasq` is the older alternative.
> - **First-boot unit** that reads the wlan0 MAC, sets the `nightwatcher-<mac4>`
>   SSID, brings up the AP + DHCP, and ensures MariaDB + `nightwatcherd` are
>   running with the web UI reachable on the AP interface.
> - **Web UI reachability:** AP gateway IP (e.g. `192.168.4.1`) and/or Avahi mDNS
>   (`nightwatcher.local`). NightWatcher2 serves HTTPS with a self-signed cert, so
>   expect a one-time browser warning.

## Conventions

Follow the global `~/.claude/CLAUDE.md`: a file-header block on every source file
(author, file, purpose, created/last-modified, version, and a GPL-3.0-or-later
license line) -- shell scripts, systemd units, and config templates included;
lean, no-em-dash writing voice; autonomous execution (run ordinary commands,
report back; confirm only irreversible or outward-facing actions).

## Sibling repos (reference, under /home/gilinsky/devel/astronomy/)

- **NightWatcher-v2** -- the app this image delivers: a C++ SQM daemon + web UI
  over MariaDB, shipped as an arm64 `.deb` with debconf + a systemd unit. The
  image installs that `.deb`. Its `.deb`/debconf and systemd-hardening patterns
  are worth mirroring.
- **nightwatcher-ingest**, **NightWatcher-AirWatcher**, **StarBase** -- other
  ecosystem tools; not required on the Pi image unless you choose to add them.
