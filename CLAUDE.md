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

> **Approach: settled 2026-07-27.** See `docs/architecture.md` for the reasoning
> and what each decision rejected.
> - **Image build tooling:** **pi-gen**, `arm64` branch pinned in `versions.env`,
>   with `stage-nightwatcher` grafted on after stage2 (Pi OS Lite). First-boot
>   provisioning of packages was ruled out: an access-point-only unit has no
>   internet at first boot, so everything must be baked in.
> - **AP stack:** **NetworkManager**, one AP profile with `ipv4.method shared`
>   (DHCP, DNS, and NAT come with it). A dedicated `ap0` interface keeps the AP up
>   while `wlan0` is free to join an upstream network; one radio still means one
>   channel, so the AP follows the client.
> - **First boot** derives `nightwatcher-<mac4>` from the wlan0 MAC, generates the
>   per-unit database and SSH passwords, creates the database, applies the AP, and
>   writes `/boot/firmware/nightwatcher-credentials.txt`.
> - **Web UI reachability:** `https://nightwatcher.local` (Avahi alias, with a
>   best-effort 443 to 8080 redirect) and `https://192.168.4.1:8080`. The
>   self-signed certificate warns once.
> - **RPi tab:** a root agent on `/run/nightwatcher-platform.sock` exposing a fixed
>   verb list, proxied by NightWatcher2's `/api/v1/platform/*` for admin sessions.
>   All Pi-specific code, including the tab's JavaScript, lives here.
> - **USB data drive:** a nightly `dsn` export target writes to a local spool;
>   `nw-usb.sh` mirrors that spool onto any `NWDATA`-labelled drive, mounted only
>   while writing so it is always safe to unplug.

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
