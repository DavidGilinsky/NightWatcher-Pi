<!--
---------------------------------------------------------------------------
Author:        David Gilinsky
File:          docs/flashing-cm5.md
Purpose:       Writing the image to a Compute Module's eMMC, which has no card
               slot and so needs rpiboot rather than a card reader.
Created:       2026-07-27
Last Modified: 2026-07-27
Version:       0.1.0
License:       GPL-3.0-or-later
---------------------------------------------------------------------------
-->

# Flashing a Compute Module (eMMC)

A CM5 with eMMC has no card to remove, so the module itself is put into USB
device mode and appears on your computer as a disk.

## Before you start

Confirm the module is a **wireless variant** and that the carrier board's antenna
is connected to its u.FL socket. Without a radio there is no access point, and
therefore no way to reach the unit at all. This is easy to discover far too late.

## Writing the image

1. Fit the module to its IO board. Set the board's **nRPIBOOT** jumper (labelled
   "Fit jumper to disable eMMC boot" on the official IO board), or hold the
   button on carriers that have one.
2. Connect the IO board's USB **slave/OTG** port to your computer, then apply
   power to the board.
3. Run `rpiboot` with mass-storage support:

   ```sh
   sudo apt install rpiboot          # or build from raspberrypi/usbboot
   sudo rpiboot -d /usr/share/rpiboot/mass-storage-gadget64
   ```

   The eMMC appears as a block device, typically `/dev/sdX`.
4. Write the image with Raspberry Pi Imager (choose *Use custom*, select the
   `.img.xz`), or directly:

   ```sh
   xzcat deploy/nightwatcher-pi-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
   sync
   ```

   Check `lsblk` first. `dd` to the wrong device destroys it.
5. Remove the nRPIBOOT jumper, remove power, and reconnect. The module now boots
   from eMMC.

## Editing the site file first

If you want `nightwatcher-site.txt` set before first boot, mount the image's boot
partition while the module is still in mass-storage mode:

```sh
sudo mount /dev/sdX1 /mnt          # partition 1 is the FAT boot partition
sudoedit /mnt/nightwatcher-site.txt
sudo umount /mnt
```

Do it now if you are going to. After deployment, changing that file means another
`rpiboot` session, so everything in it is also reachable from the web UI's **RPi**
tab, which is the practical path once a unit is in the field.

## Retrieving the credentials afterwards

`nightwatcher-credentials.txt` is written to the same boot partition on first
boot. To read it from a deployed unit, either read it over SSH, or bring the
module back to a bench and repeat the `rpiboot` step above. The web UI shows the
same access-point details, so a unit you can still reach never needs this.
