<!--
---------------------------------------------------------------------------
Author:        David Gilinsky
File:          docs/field-deployment.md
Purpose:       What a volunteer does: install a unit, collect its data, and
               get out of trouble. Written to be read at a dark site on a
               phone, so it says exactly what to type.
Created:       2026-07-27
Last Modified: 2026-07-27
Version:       0.1.0
License:       GPL-3.0-or-later
---------------------------------------------------------------------------
-->

# Field deployment

## Installing a unit

1. Flash the image (Raspberry Pi Imager, or
   [flashing-cm5.md](flashing-cm5.md) for a Compute Module).
2. Optional, and only possible before first boot: edit
   `nightwatcher-site.txt` on the card's boot partition to set the site name,
   the regulatory country, or an upstream Wi-Fi network. Everything in it is
   optional, and all of it can be changed later from the web UI.
3. Connect the SQM to USB, power the unit on, and wait about two minutes.
4. On a phone or laptop, join the Wi-Fi network **`nightwatcher-XXXXXXXX`**.
   The passphrase is the fleet default `nightwatcher` unless your network
   changed it.
5. Open **`https://nightwatcher`**. Accept the certificate warning once:
   the unit signs its own certificate, because there is no authority to ask at a
   site with no internet.
6. Sign in as `admin` / `admin`. You are required to change the password
   immediately.
7. On the **Sensors** tab, add the SQM. On the **RPi** tab, set anything the
   site needs: an upstream network, the USB drive, the clock.

The unit's SSID, passphrase, and web address are also written to
`nightwatcher-credentials.txt` on the boot partition, readable from any computer
that can read the card. The shell account uses the fleet default password, the
same on every unit, so a console is always a way in; change it per unit with
`passwd` where a site requires that.

## Collecting data on a USB drive

**Once, to prepare a drive:** on the **RPi** tab, under *USB data drive*, choose
**Prepare a drive**. This erases the drive and formats it as exFAT labelled
`NWDATA`. Any drive with that label works on any unit, which is what makes
rotation possible.

**To turn on nightly collection:** on the same panel, pick the sensor and choose
**Turn on**. A DSN file per month is written every night and mirrored to the
drive whenever one is present.

**On each visit:** unplug the drive, plug in the spare, and take the first one
home. There is nothing to eject: the drive is mounted only while writing, so an
idle drive is already unmounted. Copy the `NightWatcher` folder somewhere safe.
The drive can go back into any unit afterwards, empty or not.

The unit keeps its own copy of everything, so a drive that is lost or damaged is
an inconvenience and not lost data. A drive that has been away for weeks receives
everything it missed the next time it is inserted.

## Connecting a unit to the internet

Only needed if the site should upload to the DSN Google Drive or push to
WordPress. Data collection itself never needs it.

- **Ethernet** is best: plug it in, and it works with no configuration and no
  effect on the access point.
- **Wi-Fi** is on the **RPi** tab under *Internet uplink*. Scan, pick a network,
  enter the passphrase, join. Prefer a 2.4 GHz network. The unit has one radio,
  so the access point retunes to the network you join and every device connected
  to the unit, including yours, drops for a few seconds and then reconnects.

## When something is wrong

Everything below runs as the `nightwatcher` user, over SSH or at a console with
a monitor and keyboard, using the fleet default password (`nightwatcher` unless
your network changed it).

| Symptom | What to check |
|---|---|
| No `nightwatcher-...` network | `systemctl status nightwatcher-radio nightwatcher-ap`, then `journalctl -u nightwatcher-ap`. A wrong or unset Wi-Fi country stops the radio transmitting at all. |
| Network is there, web UI is not | `systemctl status nightwatcherd`, then `journalctl -u nightwatcherd`. Try `https://192.168.4.1` directly, which skips mDNS. `journalctl -u nightwatcher-webcheck` says whether the daemon got port 443 or fell back to 8080. |
| A **domain-joined Windows laptop** behaves oddly on the unit's network | Expected, and not the unit's doing. Windows hands classification to Network Location Awareness, which tries to authenticate against a domain controller it cannot reach here; the Private/Public toggle is unavailable and the laptop may drop the network repeatedly. `Get-NetConnectionProfile` shows the domain association. Use a phone, a tablet, or a non-domain machine. |
| `nightwatcher` does not resolve | The access point's own DNS answers it; `journalctl -u nightwatcher-webcheck` says if NetworkManager ignored that setting. Fall back to `https://nightwatcher.local` or `https://192.168.4.1`. |
| Web UI says the database is unreachable | `journalctl -u nightwatcher-firstboot` shows what provisioning did. `sudo nightwatcher-provision --force` runs it again. |
| USB drive is not picking anything up | The drive must be labelled `NWDATA`. `sudo /usr/local/lib/nightwatcher-pi/nw-usb.sh status`, then `journalctl -u nightwatcher-usb-sync`. |
| Times look wrong | **RPi** tab, *Clock*, **Set clock from this device**. |
| Which image is this? | `cat /etc/nightwatcher-pi-release` |

## What to record for each installed unit

The unit name (`nightwatcher-<mac4>`), the site, the install date, and the image
version from `/etc/nightwatcher-pi-release`. That is enough to identify any unit
in the fleet from a support request later.
