# Bibliography & Research Sources

**Created**: 2026-06-18  
**Purpose**: Document all external sources consulted during research phase, with findings and validation status.

---

## Official Documentation

### WPILib Documentation
| Source | URL | Accessed | Key Findings |
|--------|-----|----------|--------------|
| **Romi Imaging** | https://docs.wpilib.org/en/stable/docs/romi-robot/imaging-romi.html | 2026-06-17 | Romi has 2 boards: Pi (high-level comms with robot program on desktop) + 32U4 (low-level motor/sensor). Robot code runs on **desktop**, not Pi. |
| **Romi Programming** | https://docs.wpilib.org/en/stable/docs/romi-robot/programming-romi.html | 2026-06-17 | "Code is not deployed directly to the Romi. Instead, a Romi project runs on your development computer and leverages the WPILib simulation framework to communicate with the Romi robot." Uses `HALSIMWS_HOST` env var (port 3300). |
| **Zero to Robot** | https://docs.wpilib.org/en/stable/docs/zero-to-robot/step-4/creating-test-drivetrain-program-cpp-java-python.html | 2026-06-18 | Standard FRC robot code structure; Romi uses same templates but runs on PC. |
| **NetworkTables 4** | https://docs.wpilib.org/en/stable/docs/software/networktables/networktables-4.html | 2026-06-17 | NT4 is a library (`ntcore`), transport-agnostic. Works over WebSocket, UDP, TCP. |

### PhotonVision Documentation
| Source | URL | Accessed | Key Findings |
|--------|-----|----------|--------------|
| **PhotonVision Releases** | https://github.com/PhotonVision/photonvision/releases | 2026-06-17 | v2026.3.4 latest; assets include `photonvision-v2026.3.4-linuxarm64_RaspberryPi.img.xz` and Orange Pi 5 variants. |
| **PhotonVision Image Modifier** | https://github.com/PhotonVision/photon-image-modifier | 2026-06-17 | Install scripts for multiple platforms. `install.sh` installs deps, downloads JAR, creates systemd service. `install_pi.sh` for RPi, `install_opi5.sh` for Orange Pi 5. |
| **PhotonVision CI** | https://github.com/PhotonVision/photon-image-modifier/blob/main/.github/workflows/main.yml | 2026-06-17 | **RPi builds use Raspberry Pi OS Trixie** (2025-10-01). **Orange Pi 5 builds use Ubuntu 24.04 Rockchip** (Joshua Riek ubuntu-rockchip). |

---

## Source Code Repositories

### WPILibPi (Current Romi Image)
| File | Path | Key Findings |
|------|------|--------------|
| **wpilibws-romi run script** | `stage5/01-sys-tweaks/files/wpilibws-romi_run` | Runs Node.js `@wpilib/wpilib-ws-robot-romi` on port 3300, bridges HALSim WS → 32U4 I2C |
| **Romi config** | `stage5/01-sys-tweaks/files/romi.json` | I/O config: `["dio", "ain", "ain", "pwm", "pwm"]` |
| **configServer Makefile** | `deps/tools/configServer/Makefile` | Builds C++ dashboard linking `cscore`, `wpinet`, `wpiutil` via pkg-config |
| **configServer source** | `deps/tools/configServer/src/*.cpp` | Web dashboard: network, firmware upload (avrdude), system status, Romi I/O status |
| **multiCameraServer build.gradle** | `deps/examples/java-multiCameraServer/build.gradle` | Bundles: `cameraserver`, `cscore`, `ntcore`, `wpimath`, `wpiutil`, `wpilibj`, `wpiHal`, `opencv-460`, `apriltag` |
| **uploadRomi.py** | `stage5/01-sys-tweaks/files/uploadRomi.py` | Uses `avrdude -patmega32u4 -cavr109 -P/dev/ttyACM0 -b57600` for 32U4 firmware |
| **Packages list** | `stage5/01-sys-tweaks/00-packages` | `avrdude`, `hostapd`, `dnsmasq`, `espeak`, `python3-serial` |

### PhotonVision Image Modifier
| File | Path | Key Findings |
|------|------|--------------|
| **install.sh** | `install.sh` | Main installer: detects OS/arch, installs deps (`avahi-daemon`, `libatomic1`, `v4l-utils`, `sqlite3`, `openjdk-25-jre-headless`, `usbtop`), creates CPU governor, NetworkManager config, downloads JAR, creates systemd service |
| **install_pi.sh** | `install_pi.sh` | RPi-specific: mounts boot partition, runs install.sh, copies `config.txt`, `userconf.txt`, sets hostname, disables `wpa_supplicant`, enables SSH, purges dev packages, installs `network-manager`, `libcamera-dev`, `libgbm1` |
| **install_opi5.sh** | `install_opi5.sh` | Orange Pi 5: purges snaps/bluez, runs install.sh, configures NetworkManager via cloud-init (`OPi5_CIDATA/user-data`), enables big cores (RK3588), masks bluetooth services |
| **OPi5_CIDATA/user-data** | `OPi5_CIDATA/user-data` | Cloud-init: `runcmd: [nmcli radio all off, touch /etc/cloud/cloud-init.disabled]` — **disables WiFi** |
| **CI workflow** | `.github/workflows/main.yml` | Matrix builds: RPi uses `raspios-trixie-arm64-lite.img.xz`; OPI5 uses `ubuntu-24.04-preinstalled-server-arm64-orangepi-5.img.xz` from Joshua Riek |

### WPILib allwpilib (HALSim & XRP)
| File | Path | Key Findings |
|------|------|--------------|
| **HALSim WebSocket API** | `simulation/halsim_ws_core/doc/hardware_ws_api.md` | JSON over WebSocket (port 3300). Messages: `type` (AI, DIO, PWM, Encoder, Gyro, etc.), `device`, `data` with `<`/`>`/`<>` prefixes. |
| **HALSimWS Client** | `simulation/halsim_ws_client/src/main/native/cpp/HALSimWSClient.cpp` | C++ client connecting to HALSim WS server. Registers providers for Analog, DIO, DriverStation, Encoder, HAL, PWM, etc. |
| **XRP Protocol** | `simulation/halsim_xrp/README.md` | UDP binary protocol (port 3540). Packet: `[seq:2][control:1][tagged data]`. Tags: 0x12=Motor, 0x13=Servo, 0x14=DIO, 0x15=Analog, 0x16=Gyro, 0x18=Encoder. |
| **HALSimXRP Client** | `simulation/halsim_xrp/src/main/native/cpp/HALSimXRPClient.cpp` | C++ UDP client. `Initialize()` reads `HALSIMXRP_HOST`/`PORT`. `Start()` connects UDP, registers providers. `SendStateToXRP()` sends motor/servo/DIO outputs. |
| **XRP Device Handling** | `simulation/halsim_xrp/src/main/native/cpp/XRP.cpp` | Handles WPILib simulation updates (DriverStation, Motor, Servo, DIO, Gyro, Encoder) → sends to XRP via UDP. Parses incoming XRP packets (Gyro, DIO, Encoder, Analog). |

### Joshua Riek Ubuntu Rockchip
| Source | URL | Key Findings |
|--------|-----|--------------|
| **Releases** | https://github.com/Joshua-Riek/ubuntu-rockchip/releases | Ubuntu 24.04 preinstalled server images for Orange Pi 5/5B/5Plus/5Pro/5Max, Rock 5C, etc. Used by PhotonVision CI. |

---

## Key Research Conclusions (Validated)

| Conclusion | Validation Method | Source |
|------------|-------------------|--------|
| **Romi robot code runs on PC (desktop), not on Pi** | WPILib docs + `wpilibws-romi` source | `imaging-romi.html`, `programming-romi.html`, `wpilibws-romi_run` |
| **Romi uses HALSim WebSocket (port 3300) for Pi↔PC communication** | `wpilibws-romi` source + WPILib docs | `wpilibws-romi_run`, `hardware_ws_api.md` |
| **PhotonVision CI uses Raspberry Pi OS Trixie for RPi builds** | PhotonVision CI workflow | `.github/workflows/main.yml` |
| **PhotonVision CI uses Ubuntu 24.04 Rockchip for Orange Pi 5 builds** | PhotonVision CI workflow | `.github/workflows/main.yml` |
| **PhotonVision install.sh disables WiFi via `nmcli radio all off` and blacklist** | `install_opi5.sh`, `OPi5_CIDATA/user-data` | Source code inspection |
| **RPi 32U4 I2C: bus 1 (pins 3/5, GPIO 2/3), address 0x08** | `romi.json` ioConfig + RPi pinout | `romi.json`, RPi docs |
| **configServer is C++ linking cscore/wpinet/wpiutil** | Makefile + source | `configServer/Makefile`, `configServer/src/*.cpp` |
| **multiCameraServer bundles WPILib JARs (2023.x in current image)** | build.gradle | `multiCameraServer/build.gradle` |
| **NT4 is a library (`ntcore`), transport-agnostic** | NT4 docs + source | `networktables-4.html`, `ntcore` source |
| **XRP architecture = PC as brain, board as remote I/O (UDP)** | XRP README + HALSimXRP source | `halsim_xrp/README.md`, `HALSimXRP.cpp` |
| **Romi architecture ≈ XRP: PC as brain, Pi as remote I/OPI5 as remote I/O bridge** | Comparative analysis | Cross-referenced both architectures |

---

## Assumptions Requiring Hardware Validation

| Assumption | Validation Needed | Priority |
|------------|-------------------|----------|
| RPi OS Trixie boots on RPi 4/5 with PhotonVision + configServer | Flash image, boot, test camera + 32U4 | High |
| PhotonVision `install.sh --preserve-wifi` works on RPi OS Trixie | Fork modifier, test on hardware | High |
| configServer C++ rebuilds against WPILib 2026.2.x | Build on RPi OS Trixie | High |
| NT4 bridge (ntcore C++) works between Pi and PC | Test with RobotSim | Medium |
| 32U4 firmware flash via avrdude works on RPi 4/5 | Test with real 32U4 board | High |
| libcamera + RPi ISP tuning works for PhotonVision AprilTag | Test camera detection | High |
| QEMU Ubuntu 24.04 cloudimg boots and runs PhotonVision | Log in to the guest, run `install.sh` and the JAR **in the guest** (2026-06-17 test actually ran in the Ubuntu 26.04 sandbox container; see Phase 0 correction) | High |

---

## Files in This Project (.docs/)

| File | Purpose |
|------|---------|
| `requirements.md` | Requirements |
| `integration-plan.md` | 13-week implementation plan with task checklist; superseded |
| `README.md` | Project overview |
| `architecture/ADR-001-base-os-selection.md` | Base OS decision (RPi OS Trixie for RPi) |
| `architecture/ADR-002-32u4-flashing-approach.md` | 32U4 flashing via avrdude |
| `architecture/ADR-003-base-and-network.md` | The base, the network and the versions used |
| `parts/image-builder.md` | Image builder pipeline reference; superseded |
| `parts/romi-dashboard.md` | Romi dashboard (Javalin+Vue) reference; superseded |
| `parts/photonvision.md` | PhotonVision install/configure reference; superseded |
| `parts/wpilib.md` | WPILib/NT4 integration reference; superseded |
| `parts/hardware-testing.md` | QEMU + hardware validation reference; superseded |
| `parts/testing.md` | Testing strategy reference; superseded |
| `research/xrp-vs-romi-analysis.md` | XRP vs Romi protocol comparison |
| `research/wpiromi-component-analysis.md` | Factual WPILib component inventory on Pi |
| `bibliography.md` | This file |

---

*All conclusions above are traceable to specific source files/URLs. Assumptions not yet validated are marked for hardware testing.*