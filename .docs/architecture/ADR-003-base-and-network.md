# ADR-003: The base and the network for the Romi image

## Status

Accepted 2026-11-11, by the Developer's agreement to the plan *One Pi image for the Romi and
PhotonVision*, `.docs/2026-11-10-romi-photonvision-image.md` in `ftc-claude`. It takes the place
of the planned *ADR-003: PhotonVision WiFi preservation*, and supersedes ADR-001 and ADR-002.

## Context

The goal is to run Romi robot code in simulation on a host PC and get AprilTag poses from
PhotonVision on the Romi's Pi, over the links the Romi and PhotonVision normally use. WPILibPi's
last Romi image, v2023.2.1, is built on Bullseye, and no Bookworm or Trixie Romi image was found.

## Decision

- **Base:** Raspberry Pi OS Trixie Lite, 64-bit, the 2026-10-06 release, on the Romi's
  Raspberry Pi 3 Model B Plus. Raspberry Pi OS, not Ubuntu, as it carries the Pi's own boot
  firmware, kernel and camera stack, and WPILibPi's and PhotonVision's Pi images are built on it.
- **PhotonVision:** its own `install.sh`, unchanged, run with `-q` so it leaves networking to
  NetworkManager. WiFi stays on without a fork; nothing more is needed to preserve it.
- **The Romi's own functions:** `wpilibws-romi` from npm, on Debian's Node, under systemd as
  `pi`, with I2C on.
- **The network:** NetworkManager makes the access point `WPILibPi`, passphrase `WPILib2021!`,
  at `10.0.0.2/24`, with `ipv4.method shared` giving addresses to what joins it. WiFi is the
  access point or a client, one profile switched between the two, not both at once. Ethernet
  takes an address by DHCP and, with no answer, a `169.254` address, as WPILibPi's dhcpcd did;
  the Romi page also sets a static address, or DHCP with a static fallback, the last by a DHCP
  profile that gives up after 30 s and a static profile after it.
- **Each Romi's access point is named `WPILibPi-` and its serial number's last 8 hex digits**,
  as WPILibPi's first boot named it. `romi-ssid.service`, before NetworkManager at each boot,
  renames a keyfile still named exactly `WPILibPi`, and makes `/boot/firmware/default-ssid.txt`
  and `default-ssid.wav` by `espeak` when they are missing. `romi-sayid.service` plays the name,
  and WPILibPi's ROT13 line, through the headphone jack while the access point keeps that name;
  a renamed Romi is silent.
- **The host PC joins the access point.** Its robot program connects to `wpilibws-romi` on port
  3300 by `halsim_ws_client`. PhotonVision's NetworkTables client, at team 0, asks
  `wpilibws-romi` on port 1742 for the server's address, and gets the host PC's.
- **The dashboard:** Cockpit from Trixie's packages, with the Romi page first in its menu.
- **The 32U4's firmware:** written from the Romi page by WPILibPi's `uploadRomi.py`, which opens
  `/dev/ttyACM0`, the 32U4's USB port, at 1200 baud to reset it into its bootloader, then runs
  `avrdude -patmega32u4 -cavr109 -b57600` with the `firmware.hex` npm installs with
  `wpilibws-romi`.
- **The card stays writable, and `romi.json` is in `/etc/romi/` on the ext4 root**, where
  WPILibPi kept it in the FAT boot partition. FAT has no journal, so a power-off during a save
  could damage the partition the Pi boots from; ext4's journal and Cockpit's write of a
  temporary file, `fdatasync` and rename keep a save from doing that.
- **The account:** `pi`, password `raspberry`, with passwordless `sudo`; cloud-init off, so its
  first boot does not lock that password.

## Versions used

| Part | Version |
| --- | --- |
| Raspberry Pi OS | `2026-10-06-raspios-trixie-arm64-lite`, Debian 13, kernel `6.18.50+rpt-rpi-v8` |
| PhotonVision | v2026.3.4, by `photon-image-modifier` v2027.2.3's `install.sh` |
| Java | OpenJDK 25.0.5, `openjdk-25-jre-headless` 25.0.5+8-1~deb13u1 |
| `wpilibws-romi` | `@wpilib/wpilib-ws-robot-romi` 1.4.0, its 32U4 firmware built from v1.4.0 |
| `i2c-bus` | 5.2.3, with the rest of `wpilibws-romi`'s dependencies pinned by `image/files/wpilibws-romi/package-lock.json` |
| Node | 20.19.2, npm 9.2.0 |
| NetworkManager | 1.52.1-1+rpt4 |
| Cockpit | `cockpit-ws` 337-1+deb13u2 |
| avrdude | 7.1+dfsg-3+b3 |
| espeak | 1.48.15+dfsg-3+b2 |
| Host PC robot code | `romiPyKitTiny` with `robotpy` 2026.2.2 |

## Consequences

- A Pi camera on the CSI connector does not work: PhotonVision v2026.3.4's libcamera binding
  wants `libcamera.so.0.5`, and Trixie has `libcamera.so.0.7`. A USB camera works without it.
- `photon-image-modifier`'s 2026 tags' `install.sh` asks for Java 17, which Trixie lacks;
  v2027.2.3's installs Java 25, and PhotonVision v2026.3.4 runs on it.
- The access point's passphrase is what keeps others off the Pi, as the account is known.
- The Romi page changes NetworkManager's keyfiles, and the build keeps a keyfile already there.
- `romi.json` can no longer be edited from a PC's card reader, as the boot partition allowed.
  `04-romi-core.sh` moves one it finds in `/boot/firmware/` to `/etc/romi/`.
- The Debian packages are not pinned: Debian's mirrors keep only the current version. Each build
  records them in `packages.txt` and on the card in `/etc/romi-image-packages.txt`.
- `npm audit` of `image/files/wpilibws-romi/package-lock.json`, read 2026-11-11, reports two
  packages with advisories, and four flagged through them: `node-ntcore`,
  `@wpilib/node-wpilib-ws`, `@wpilib/wpilib-ws-robot` and `@wpilib/wpilib-ws-robot-romi`. Its only
  fix is `wpilibws-romi` 1.0.4, an older release. Whether `wpilibws-romi` calls the affected
  functions, or passes them input from the network, is not checked. Dependabot alerts are on for
  the repository.
  - `ip-address` 7.1.0, high, required as `^7.1.0` by `wpilibws-romi` and
    `@wpilib/node-wpilib-ws`; fixed after 10.7.3: GHSA-v2v4-37r5-5v8g, GHSA-mwp4-54f8-5fhr,
    GHSA-rpw4-54j3-4h4q, GHSA-j6r3-76f7-8jcv, GHSA-h3mg-xc3c-68pw and GHSA-rxp7-6hxx-x8q5.
  - `uuid` 8.3.2, moderate, required as `^8.3.2` by `node-ntcore`; GHSA-w5hq-g745-h8pq, fixed in
    11.1.1.
