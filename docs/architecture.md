<!--
---------------------------------------------------------------------------
Author:        David Gilinsky
File:          docs/architecture.md
Purpose:       Why the appliance is built the way it is: the decisions, what
               each one rejected, and the constraints that forced them.
Created:       2026-07-27
Last Modified: 2026-07-27
Version:       0.1.0
License:       GPL-3.0-or-later
---------------------------------------------------------------------------
-->

# Architecture

## The constraint that shapes everything

A unit boots as its own access point, at a site with no network. It therefore has
**no route to the internet at first boot**. Anything not already in the image is
missing forever. That single fact rules out the obvious approach (a stock image
plus a provisioning script that installs packages on first boot) and settles the
build tooling: everything is baked, and first boot only configures.

## Decisions

### Image builder: pi-gen, custom stage

[pi-gen](https://github.com/RPi-Distro/pi-gen)'s `arm64` branch, pinned to a
commit in [versions.env](../versions.env), with `stage-nightwatcher` grafted on
after stage2 (Raspberry Pi OS Lite). It is Raspberry Pi's own builder, so the
base is genuinely stock Pi OS, and the stage mechanism is exactly the hook this
project needs.

Rejected: `rpi-image-gen` and CustomPiOS, which buy less than the divergence from
official Pi OS costs; and first-boot provisioning, for the reason above.

Only our stage exports an image (the Makefile drops `SKIP_IMAGES` into stage2),
so a build produces exactly one artifact.

### Access point: NetworkManager, not hostapd

Pi OS Bookworm and Trixie both run NetworkManager. A single connection profile
in AP mode with `ipv4.method shared` gets DHCP, DNS, and (when an uplink exists)
NAT from NetworkManager's own dnsmasq. That removes an entire hostapd and dnsmasq
configuration surface that would otherwise have to be maintained and kept in step
with Pi OS.

### One radio, two roles: a dedicated `ap0`

The requirement is that the access point is **always on**, and that a unit can
also join a local network as a client. `brcmfmac` supports one AP plus one
station, so [`nw-radio-setup.sh`](../stage-nightwatcher/02-network/files/nw-radio-setup.sh)
adds an `ap0` interface at boot with its own locally-administered MAC and leaves
`wlan0` free for the client role.

The hardware limit that cannot be engineered away: **one radio serves one
channel**. When a unit joins an upstream network, the access point has to retune
to that network's channel, and joined clients drop for a few seconds. The tab
says so before you do it, and warns when the chosen network is 5 GHz. Where the
firmware refuses a second interface, the AP falls back to `wlan0` and the uplink
is refused outright rather than taking the appliance off the air. Ethernet, and a
USB Wi-Fi dongle, are both free of this constraint.

### Identity: derived, not assigned

[`nw_mac4`](../stage-nightwatcher/02-network/files/nw-common.sh) takes the last 4
bytes of the wlan0 MAC. The SSID and hostname are both
`nightwatcher-<mac4>`, so two units in radio range of each other never collide,
with no per-unit build and no serial-number registry. If the radio has not probed
yet, first boot waits for it; if there is no radio at all, the Pi's own serial
stands in, so the unit is still nameable.

### Secrets: per unit, generated on first boot

The **database password** is generated per unit in
[`nightwatcher-firstboot.sh`](../stage-nightwatcher/03-firstboot/files/nightwatcher-firstboot.sh),
because nobody ever types it, so there is no reason for it to be shared. The
NightWatcher2 preseed leaves `db_password` blank and sets `db_create=false` and
`start_now=false`, deferring both to the unit that actually exists.

The two credentials a **human types** are documented fleet defaults instead: the
**access-point passphrase** and the **shell account password**. Both were
considered as per-unit random values and both failed the same test. A generated
password can only be read from the boot partition, and on a Compute Module that
means another `rpiboot` session, so a volunteer standing in front of a unit with
a monitor and keyboard cannot log in to the machine in front of them. This was
not theoretical: an early image did rotate the login password on first boot, and
the result was an unreachable unit on a bench with a console attached.

The cost is real and worth stating plainly: one password opens every unit built
from an image, and SSH is on. Anyone within radio range who knows the defaults
has a sudo-capable shell. Sites needing better change it per unit with `passwd`,
or disable password authentication and deploy keys. The access-point passphrase
is changeable per unit from the RPi tab.

### Configuration channels

1. **`/boot/firmware/nightwatcher-site.txt`**, edited on any computer that can
   read the card, before first boot. The only channel that works before a unit
   has any network. Parsed with a strict key allowlist, so an operator-editable
   file can never execute anything.
2. **The RPi tab**, once the unit is running. On a Compute Module with eMMC,
   reaching the boot partition again means another `rpiboot` session, so this is
   the practical path after deployment.

### The RPi tab: a privileged agent, not a relaxed daemon

`nightwatcherd` runs as a `DynamicUser` under `ProtectSystem=strict`. It cannot
run `nmcli`, mount a drive, or set the clock, and relaxing that on a
field-deployed unit to get a settings page would be the wrong trade.

Instead, [`nightwatcher-pi-agent`](../stage-nightwatcher/05-agent/files/nightwatcher-pi-agent)
runs as root and exposes a **fixed verb list** as JSON over a unix socket at
`/run/nightwatcher-platform.sock`, mode 0660, group `nightwatcher-pi`. The daemon
is put in that group by a drop-in, and nothing else on the appliance is. No
caller string is ever passed to a shell; SSIDs, passphrases, device paths, and
timestamps are validated in the agent.

NightWatcher2 proxies `/api/v1/platform/*` to that socket for admin sessions
only, and the agent serves the tab's own JavaScript through it. The tab therefore
rides the daemon's origin, session, and certificate: one port, one login, one
certificate warning. Upstream gained roughly sixty lines and no knowledge of
Raspberry Pi hardware; a NightWatcher install without the socket has no such tab.

### The USB drive: a mirror of a spool, not an export destination

The user-facing requirement is a USB drive as a periodic destination for DSN
data, resilient to being swapped by a volunteer. The obvious implementation, an
export target that writes to the drive, fails badly: every run with the drive
absent fails, and the export watermark becomes entangled with whether somebody
happened to be carrying the drive that week.

Instead:

- NightWatcher2's existing `dsn` export target already supports `outbox_dir`, so
  the tab configures a nightly target writing to
  `/var/lib/nightwatcher-pi/spool/dsn`. That directory is always present, so the
  export always succeeds and its watermark always advances. **No new export
  target type was needed upstream at all.**
- [`nw-usb.sh`](../stage-nightwatcher/04-usb/files/nw-usb.sh) mirrors that spool
  onto any drive labelled `NWDATA`, triggered by udev on insertion and by an
  hourly timer while one stays plugged in.
- The drive is **mounted only while writing** and unmounted immediately after,
  which is what makes it safe to unplug at essentially any moment. There is no
  eject step because there is almost never a mount.
- The spool is the authoritative copy, so a drive that is lost, full, or never
  returned costs nothing. A drive gone for six weeks receives six weeks of files
  on its next insertion.
- exFAT, whole-device, so the same drive mounts on Windows, macOS, and Linux.

### Clock

Timestamps are what make sky-brightness readings worth collecting. `timesyncd`
handles units with an uplink, `fake-hwclock` stops an offline unit coming back in
1970, and the tab offers **set the clock from this browser**, which makes a
visiting volunteer's phone the time source at a site that has never seen an NTP
server. When RTC or GPS hardware lands, `chrony` with a GPS refclock replaces the
source and the tab's panel is unchanged.

### Storage

The first test unit is a CM5 with eMMC. The journal is capped
([journald drop-in](../stage-nightwatcher/00-base/files/journald-nightwatcher-pi.conf))
because a unit runs for months unattended and an uncapped journal is both a wear
problem and a full-disk problem.

## What is verified without building an image

`make check` runs [`lint.sh`](../scripts/lint.sh) (shellcheck, `bash -n`,
`py_compile`, and an ES-module parse of the tab) and
[`check-stage.sh`](../scripts/check-stage.sh), which asserts the structural
invariants that a build would not catch: that every stage script is still
executable (pi-gen silently skips one that is not, producing a successful build
of a wrong image), that the spool path is identical in the four places that name
it, that the socket path still matches what NightWatcher2 looks for, that the
group joins all three parties, and that the preseed still defers the database.

Upstream, `platform_test` covers the proxy itself: forwarding, query strings,
POST bodies, status pass-through, the 401 for unauthenticated callers,
path-traversal rejection, and the socket-absent case. It needs no database.

## Known limits

- **Access point and client share a channel.** Joining an upstream network
  briefly drops AP clients, and a 5 GHz uplink may leave the AP unable to follow.
  Ethernet or a USB Wi-Fi dongle avoids it entirely.
- **The `.deb` is pinned to a release** and verified against its checksum. Where
  no such release exists, `fetch-nightwatcher-deb.sh` falls back to a CI artifact
  and says so loudly, and the release stamp records which of the two was used.
- **The CM5 must be a wireless variant with an antenna attached.** Without a
  radio the entire access-point premise is moot, and the failure is easy to
  discover late.
- **Not everything has run on hardware.** Confirmed on a CM5: first boot and
  provisioning, the access point, reading a real SQM over USB, the web UI,
  joining an upstream Wi-Fi network from the RPi tab (which exercises the whole
  platform chain: the agent's socket, the daemon's proxy, and the tab's own
  module), and `https://nightwatcher` from a tablet joined to the access point,
  on 443 with no port suffix. Still unexercised: the USB data mirror end to end,
  setting the clock from a browser, and changing the access point's SSID or
  passphrase from the tab.
- **A domain-joined Windows client is not a good test device.** Network Location
  Awareness tries to authenticate the appliance's network against a domain
  controller it cannot reach, which leaves the network unclassifiable and can
  make the client drop it every twenty seconds. Nothing on the unit causes it
  and nothing on the unit can fix it.

## What hardware found that static checks did not

Seven defects surfaced only by putting an image on a Compute Module and reading
its journal: a masked `fake-hwclock.service` that failed the build, debconf
column padding that silently prefixed every value with a space, a systemd
deadlock between first boot and the units ordered after it, a re-provision that
replaced a working database password with an unverified one, a daemon that could
not bootstrap an empty database, a unit identity one character too long, and a
USB mirror that reported a drive on every unit that had none.

The structural checks in `make check` caught none of these, and now guard all of
them. That is the pattern worth keeping: each hardware finding becomes an
assertion that runs in a second, so the next regression is caught before a
build, not after a drive to a dark site.
