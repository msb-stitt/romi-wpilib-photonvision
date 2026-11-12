# Where the image came from, and how it compares with WPILibPi's

**Status: illustrative.** Describes `romi-photonvision-image` at `e924ab4`, its CI build at
`8101712`, and WPILibPi's Romi image at `v2023.2.1`, `42f5fcd`, read 2026-11-11.

## Where it came from

`msb-stitt/romi-wpilib-photonvision` is a fork of `MikeStitt/romi-wpilib-photonvision`, created
2026-11-10. Its `main`, at `9af6a05`, holds only `LICENSE`, `README.md` and `.docs/`, the earlier
plans and design notes. The code is new on `romi-photonvision-image`. Its design follows two
upstream projects: WPILibPi's Romi stage, `stage5`, and PhotonVision's `photon-image-modifier`.

## The kinds of code and configuration

- **Bash:** `image/build.sh`, `image/lib/common.sh` and the stages in `image/stages/`. They run as
  root, either in the image's root as a chroot or on a running Pi.
- **JavaScript, HTML, CSS and JSON:** the Cockpit page in `image/files/cockpit-romi/`, with
  `romi.js` as most of it.
- **Python:** `image/files/uploadRomi.py`, identical to WPILibPi's
  `stage5/01-sys-tweaks/files/uploadRomi.py`. The stage rewrites one firmware path in it while
  installing.
- **System configuration:**
  - a NetworkManager keyfile, `WPILibPi.nmconnection`;
  - a systemd unit, `wpilibws-romi.service`;
  - `romi.json`, identical to WPILibPi's;
  - the platform profile, `rpi.profile`.
- **npm:** `package.json` and `package-lock.json` for `wpilibws-romi`.
- **GitHub Actions:** `.github/workflows/image.yml`.

## How it differs from WPILibPi's Romi image

- **Build:** stages run in a chroot over a stock Raspberry Pi OS Lite image. WPILibPi built its
  whole OS with `pi-gen`.
- **Base:** Trixie, not Bullseye.
- **Network:** NetworkManager, in place of hostapd, dnsmasq and dhcpcd.
- **Services:** systemd, in place of daemontools.
- **Node:** Debian's Node 20, with a lockfile and `npm ci`, in place of Node 14 from nvm and an
  unpinned global install.
- **Dashboard:** Cockpit with our page, in place of WPILibPi's C++ `configServer`. There are no
  vision tabs and no file or service uploads.
- **Vision:** PhotonVision, by its own `install.sh`, in place of WPILib's vision programs.
- **The card:** read-write. WPILibPi's was read-only.
- **`romi.json`:** in `/etc/romi/` on the ext4 root, not in the FAT boot partition.
- **Running Pi:** each stage also runs on a Pi that is already up.

It differs from this repository's own earlier plan too: no Javalin dashboard and no fork of
`install.sh`. ADR-001 and ADR-002 still describe that earlier plan.

## Software versions

Ours are read from run `43128312291`'s build log and the base image's package list,
`2026-10-06-raspios-trixie-arm64-lite.info`. WPILibPi's are read from its source at `v2023.2.1`;
where it pinned nothing, the version is the one its package source carried on 2023-02-20, the
release date, or is marked not read. WPILibPi's image itself was not opened.

| Component | Ours, at `8101712` | WPILibPi Romi, `v2023.2.1` | The difference |
| --- | --- | --- | --- |
| OS | Raspberry Pi OS Trixie Lite `2026-10-06`, Debian 13, 64-bit | Built by `pi-gen` from Debian 11 Bullseye, 32-bit and 64-bit images | Two Debian releases later; 64-bit only |
| Kernel | `6.18.50+rpt-rpi-v8` | not read | not compared |
| Network | NetworkManager 1.52.1-1+rpt4 | hostapd, dnsmasq and `dhcpcd5` from Bullseye; versions not read | NetworkManager makes the access point |
| Services | systemd 257.13-1~deb13u1 | daemontools, from Bullseye | systemd units in place of `/service` |
| Java | `openjdk-25-jre-headless` 25.0.5+8-1~deb13u1 | `openjdk-17-jdk` from Bullseye | Java 25 runtime in place of the Java 17 JDK |
| Python | 3.13.5, from the base image | 3.9, from Bullseye | Newer; `uploadRomi.py` runs on it |
| Node | `nodejs` 20.19.2+dfsg-1+deb13u3 and `npm` 9.2.0~ds1-3, from Debian | 14.15.0, from nvm v0.37.0 | From Debian, not nvm |
| `wpilibws-romi` | 1.4.0, pinned by `package-lock.json` | Unpinned; 1.4.0 was the newest on 2023-02-20 | Same version, now pinned |
| `i2c-bus` | 5.2.3, pinned by `package-lock.json` | Unpinned; 5.2.2 was the newest on 2023-02-20 | One patch release later |
| 32U4 firmware | The `firmware.hex` in `wpilibws-romi` 1.4.0 | The same package's | Same file, if WPILibPi got 1.4.0 |
| avrdude | 7.1+dfsg-3+b3 | from Bullseye; version not read | not compared |
| pyserial | `python3-serial` 3.5-2 | `python3-serial` from Bullseye; version not read | not compared |
| Vision | PhotonVision v2026.3.4, by `install.sh` from `photon-image-modifier` v2027.2.3 | WPILib 2023.4.1, OpenCV 4.6.0 built from source, RobotPy 2023.4.1 wheels and `multiCameraServer` | PhotonVision in place of WPILib's libraries and examples |
| Dashboard | Cockpit 337-1+deb13u2 and our Romi page | `configServer`, built from WPILibPi's `deps/tools` | Cockpit in place of `configServer` |
| Image download | `romi-image.img.xz`, 900821588 bytes | `WPILibPi_64_image-v2023.2.1-Romi.zip`, 1711066940 bytes | About half the size |

## Differences in capabilities

What WPILibPi's Romi image did is read from its `v2023.2.1` release notes and `stage5`; what ours
does is what `img.dashboard`, `img.photon` and `img.host` in the plan watched working.

- **Kept:** the WebSocket link to robot code on port 3300; the access point at `10.0.0.2` with
  passphrase `WPILib2021!` and a DHCP server; `romi.json`'s external IO; the gyro calibration.
- **Kept, not yet watched working on ours:** WPILibPi's "bridge" mode, which joins another WiFi
  network, done on ours as a NetworkManager WiFi client; the 32U4 firmware write.
- **Added:**
  - PhotonVision, with its AprilTag pipelines, publishing to the simulation's NetworkTables
    without a server address set;
  - Cockpit's own pages, such as Services;
  - an editor for the whole of `romi.json`, where WPILibPi's page changed it only through the
    external IO and the gyro calibration;
  - the build that made the card, on the Romi page;
  - an image built and checked by GitHub Actions, its dependencies pinned and its packages
    recorded.
- **Left out, at the Developer's words:** WPILib's vision programs and their camera and
  NetworkTables settings; the vision program upload; the `wpilibws-romi` upload; the file upload;
  the dashboard's start and stop of `wpilibws-romi`.
- **Lost, not decided:**
  - A name for each Romi's access point. WPILibPi's first boot renamed it `WPILibPi-` and an ID
    from the Pi, in `resize2fs_once`, and `romi-sayid.sh` spoke that name through `espeak`. Ours
    is `WPILibPi` on each Romi.
  - The read-only card and its Writable and Read-Only switch; `img.readonly` in the plan holds
    the research.
  - WPILibPi's "DHCP with static fallback"; `img.q.static_fallback` in the plan.
  - A Pi camera on the CSI connector: PhotonVision v2026.3.4's libcamera binding does not load on
    Trixie, so ours needs a USB camera.
  - The C++, Java and Python vision libraries for writing a vision program on the Pi.

## Differences in performance

Ours was measured on the Romi's Raspberry Pi 3 Model B Plus, 905 MiB of memory, as the plan
records. WPILibPi's was not measured here; its release notes claim a boot in under 20 s, and
ours was not timed.

- **Memory available:** 470 MiB with PhotonVision and `wpilibws-romi` running, read after the
  simulation drove the Romi; 405 MiB to 415 MiB with Cockpit's page open as well; 340 MiB with
  PhotonVision at 640×480. zram swap was unused each time it was read.
- **PhotonVision, AprilTag pipeline, no tag in view:** at 320×240, 29 FPS to 33 FPS processed,
  PhotonVision at 121 % CPU; at 640×480, 11 FPS at 89 ms latency, 200 % CPU.
- **Temperature:** `get_throttled` read `0x80008` with the pipeline running, at 65.0 °C and
  67.7 °C: the soft temperature limit active.
- **Build:** 6 min 6 s on GitHub's `ubuntu-24.04-arm` runner. WPILibPi's build time was not read.

## Where to push

The work sits on `msb-stitt`'s `romi-photonvision-image`. Proposed: a pull request from it into
`msb-stitt/romi-wpilib-photonvision`'s `main`, which is a merge to the default branch and needs
the Developer's word. It would also let Dependabot see the lockfile.

- **`MikeStitt` is fetch-only**, by the push policy.
- **`wpilibsuite` and `PhotonVision`:** offering anything to either upstream would be a separate
  decision. WPILibPi has had no push since 2024-03-09.
