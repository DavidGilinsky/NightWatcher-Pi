# NightWatcher-Pi

A build system for a **headless Raspberry Pi 5 appliance image** that runs
NightWatcher2 and boots as its own Wi-Fi access point.

Flash the image, power the Pi on, and it comes up as a wireless network named
`nightwatcher-<mac4>` (the last 4 bytes of its Wi-Fi MAC address, in hex). Join
that network from a phone or laptop and the NightWatcher2 web UI is served right
there, with no monitor, keyboard, router, or internet required.

## Status

Bootstrapped 2026-07-26. The image build tooling and the access-point stack are
still to be chosen; see [CLAUDE.md](CLAUDE.md) for the brief and the open design
points.

## License

GPL-3.0-or-later (matching the NightWatcher toolset).
