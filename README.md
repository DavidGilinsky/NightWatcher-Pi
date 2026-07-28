# NightWatcher-Pi

A flashable **Raspberry Pi appliance image** that runs NightWatcher2 and boots as
its own Wi-Fi access point. Flash it, power it on, join the network it creates,
and the NightWatcher2 web UI is right there. No monitor, keyboard, router, or
internet required at any point.

Built for the **Southern Arizona Dark Sky Network**: a sky quality meter a
volunteer can install at a remote site in an afternoon, and whose data can be
collected either over the internet or on a USB drive carried home.

## What a unit does

- Comes up as a wireless access point named **`nightwatcher-<mac4>`**, where
  `<mac4>` is the last 4 bytes of its own Wi-Fi MAC, so every unit in a network
  is distinct. The passphrase is the fleet default, changeable per unit.
- Serves the NightWatcher2 web UI over HTTPS at **`https://nightwatcher.local`**
  (also `https://192.168.4.1:8080`). The certificate is self-signed, so the
  browser warns once.
- Adds an **RPi tab** to that web UI, present only on this hardware, covering
  everything the appliance owns: joining an upstream Wi-Fi network while the
  access point stays up, the USB data drive, and the clock.
- Writes its DSN data to a local spool nightly and **mirrors that spool onto any
  USB drive labelled `NWDATA`** the moment one is plugged in. The drive is
  mounted only while writing, so it can be swapped without ejecting anything.
- Generates its own database password, SSH password, and identity on first boot,
  and writes the ones a human needs to
  `/boot/firmware/nightwatcher-credentials.txt`.

## Building an image

Needs Docker, `git`, `make`, `openssl`, and the `gh` CLI. Everything else is
pinned in [versions.env](versions.env).

On an **x86_64** host, pi-gen checks for `/usr/bin/qemu-aarch64` before it will
start, which `qemu-user-static` does not provide:

```sh
sudo apt install qemu-user
```

Not `qemu-user-binfmt`, which is what pi-gen's own error message suggests: that
package **conflicts with `qemu-user-static`**, which Docker's multi-arch support
uses, so installing it means removing that. `qemu-user` ships the same binary and
conflicts with nothing. The emulation that does the real work happens inside
pi-gen's container, which carries its own qemu; the host binary only satisfies
the precondition check.

An **arm64** host (including CI on `ubuntu-24.04-arm`, which is how release
images are built) needs none of that.

```sh
make preflight                                       # is this host able to build at all?
make image                                           # the usual way: pi-gen in Docker
make image NW2_DEB=./nightwatcher_0.1.0_arm64.deb    # test an unreleased package
make check                                           # lint and structural checks, no build
```

The result lands in `deploy/` as an `.img.xz` with a checksum. Flash it with
Raspberry Pi Imager, or see [docs/flashing-cm5.md](docs/flashing-cm5.md) for
Compute Module eMMC.

Builds run natively on arm64 (including in CI on `ubuntu-24.04-arm`) and under
qemu on x86_64.

## How it is put together

| Piece | What it does |
|---|---|
| [stage-nightwatcher/](stage-nightwatcher/) | A pi-gen stage grafted onto Raspberry Pi OS Lite |
| [`00-base`](stage-nightwatcher/00-base/) | Packages, the `nightwatcher-pi` group, a journal sized for flash |
| [`01-nightwatcher`](stage-nightwatcher/01-nightwatcher/) | Installs the pinned `.deb` unattended, creates the export spool, grants the sandboxed daemon exactly two new things |
| [`02-network`](stage-nightwatcher/02-network/) | The shared shell library, the `ap0` interface, the access-point and uplink scripts, mDNS, the 443 redirect |
| [`03-firstboot`](stage-nightwatcher/03-firstboot/) | Per-unit identity and secrets, the database, the credentials file |
| [`04-usb`](stage-nightwatcher/04-usb/) | The `NWDATA` mirror: udev trigger, service, hourly timer |
| [`05-agent`](stage-nightwatcher/05-agent/) | The privileged agent and the RPi tab it serves |
| [`06-release`](stage-nightwatcher/06-release/) | Stamps `/etc/nightwatcher-pi-release` with what went into the image |

The design, including what was considered and rejected, is in
[docs/architecture.md](docs/architecture.md). Deployment and field procedures are
in [docs/field-deployment.md](docs/field-deployment.md).

## Relation to NightWatcher2

This project ships no application code. It installs NightWatcher2's arm64 `.deb`,
pinned by release tag and verified against that release's checksum.

Two small, generic additions were made upstream in NightWatcher2 so that an
appliance is possible without putting any Raspberry Pi knowledge into it: a
**platform socket proxy** (`/api/v1/platform/*`, admin-only, 404 wherever no
helper socket exists) and the UI hook that turns a helper's probe response into a
tab. Every Pi-specific line, including the tab's own JavaScript, lives in this
repository and is served by the agent here.

## License

GPL-3.0-or-later, matching the NightWatcher toolset.
