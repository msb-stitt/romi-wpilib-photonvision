# Romi WPILib + PhotonVision Integration Plan

**Status: superseded** on 2026-11-11 by [ADR-003](architecture/ADR-003-base-and-network.md)
and ftc-claude's plan *One Pi image for the Romi and PhotonVision*. It was illustrative from
2026-06-17, `b29d872`, to then: nothing past Phase 0's partial spike was built.

## Goals

1. **2026 Season (Primary)**: Produce bootable Romi images (RPi 4/5 + Orange Pi 5) running WPILib 2026.2.x + PhotonVision 2026.x with full Romi feature parity
2. **2027 Season (Secondary)**: Validate/update for WPILib 2027 alpha/beta when stable
3. **Simulator-First Development**: Debug boot and integration on QEMU before hardware
4. **Simplified Image Building**: Replace pi-gen with photon-image-modifier-style script pipeline

---

## Requirements Summary

| Aspect | Decision |
|--------|----------|
| **Target Hardware** | **Raspberry Pi 4/5** (primary); Orange Pi 5 deferred |
| **Base OS** | **Raspberry Pi OS Trixie (64-bit, Debian 13)** — matches PhotonVision CI for RPi |
| **WPILib Version** | 2026.2.x (stable) → 2027.x (alpha/beta later) |
| **PhotonVision Version** | 2026.3.x (current stable) |
| **Romi Features (v1)** | 32U4 firmware flash, NT4 WebSocket bridge, AP mode, full dashboard, WiFi client mode |
| **Web Framework** | **Primary**: Upgrade existing C++ configServer (CMake, CivetWeb/Boost.Beast) — **Fallback**: Javalin + Vue/TypeScript if C++ rebuild blocked |
| **Build Approach** | photon-image-modifier style: base OS image → modification scripts → output image |
| **Simulator** | **QEMU: Ubuntu 24.04 cloud image (virt machine)** for development; **Hardware: RPi OS Trixie on RPi 4/5** for validation |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Base Image: Raspberry Pi OS Trixie (2025-10-01)                │
│  Source: downloads.raspberrypi.com/raspios_lite_arm64           │
│  Boot: MBR + FAT32 boot partition (Pi firmware)                 │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│  Image Modifier Pipeline (stages)                            │
│  ├─ 01-base-setup: users, ssh, hostname, packages           │
│  ├─ 02-network: NetworkManager + netplan                    │
│  │   └─ AP mode config, MAC-based static IP                 │
│  ├─ 03-photonvision: install.sh --control-networking=yes    │
│  │   └─ WiFi preserved: NO blacklist, NO nmcli radio off    │
│  ├─ 04-romi-core: avrdude, i2c-tools, gpiod, 32U4 flash     │
│  │   └─ I2C bus 1 (pins 3/5) for 32U4 at address 0x08       │
│  ├─ 05-romi-dashboard: Upgraded configServer (C++)          │
│  │   └─ Fallback: Javalin+Vue if C++ blocked                │
│  ├─ 06-romi-integration: NT4 WebSocket bridge (ntcore C++)  │
│  └─ 07-finalize: cleanup, resize, checksums, manifest       │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
Bootable .img.xz + .sha256 + manifest.json (RPi 4/5)
```

### QEMU Development Track

| Track | Base Image | Machine | Use For |
|-------|------------|---------|---------|
| **Dev (Docker)** | Ubuntu 24.04 cloudimg | `virt` + UEFI | Dashboard dev, NT4 bridge, pipeline logic, CI |
| **HW Validation (RPi)** | Raspberry Pi OS Trixie | Real RPi 4/5 | Camera, libcamera, 32U4 I2C, GPIO, bootloader |

---

## Documentation Map (.docs/)

All project documentation lives in `.docs/`:

| Path | Purpose | Read When |
|------|---------|-----------|
| `requirements.md` | Requirements | Every task |
| `integration-plan.md` | This file — 13-week implementation plan with task checklist | Planning, progress tracking |
| `README.md` | Project overview, quick start, architecture, contributing | Onboarding |
| `architecture/ADR-001-base-os-selection.md` | Base OS decision: RPi OS Trixie for RPi 4/5 | Architecture decisions |
| `architecture/ADR-002-32u4-flashing-approach.md` | 32U4 flashing via avrdude + systemd + Javalin REST | 32U4 implementation |
| `architecture/ADR-003-photonvision-wifi-preservation.md` | WiFi preservation strategy for PhotonVision install | PhotonVision integration |
| `parts/image-builder.md` | Image builder pipeline: stages, platform profiles, QEMU smoke test | Image building |
| `parts/romi-dashboard.md` | Romi dashboard: Javalin+Vue, Gradle, NT4 bridge, FlashService | Dashboard development |
| `parts/photonvision.md` | PhotonVision install, config, camera, hardware acceleration | PhotonVision integration |
| `parts/wpilib.md` | WPILib/NT4 integration: NT4 client, topics, simulator setup | NT4 bridge development |
| `parts/hardware-testing.md` | QEMU + hardware validation: serial/TCP bridge, checklists, CI | Testing & validation |
| `parts/testing.md` | Testing strategy: bats/pytest/JUnit, CI integration, fixtures | Writing tests |
| `research/xrp-vs-romi-analysis.md` | XRP vs Romi protocol comparison (corrected architecture) | Protocol decisions |
| `research/wpiromi-component-analysis.md` | Factual WPILib component inventory on Pi (what runs where) | Component inventory |
| `bibliography.md` | Source traceability: all claims → source files/URLs, assumptions | Audit trail |
| `2026-11-10-restarting-romi-wpilib-photonvision.md` | Where earlier work lives (2024 VM, OpenCode session export), repo history repair | Resuming work, history questions |

---

## Hardware Debugging Infrastructure

### Physical Network Topology (MacBook Pro M3, November 2023)

```
┌─────────────────────────────────────────────────────────────────┐
│                    MacBook Pro M3 (macOS)                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Docker Desktop (Linux VM)                  │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │           opencode agent container              │   │   │
│  │  │  - Build scripts (build-romi-image.sh)          │   │   │
│  │  │  - QEMU testing (Ubuntu 24.04 cloud image)      │   │   │
│  │  │  - Cross-compilation (if needed)                │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                          │                                      │
│          ┌───────────────┼───────────────┐                     │
│          ▼               ▼               ▼                     │
│    ┌──────────┐    ┌──────────┐    ┌──────────┐               │
│    │ USB-C/   │    │ USB-C/   │    │ Ethernet │               │
│    │ Thunderbolt    │ Thunderbolt    │ Adapter  │               │
│    │ Port 1   │    │ Port 2   │    │ (opt)    │               │
│    └────┬─────┘    └────┬─────┘    └────┬─────┘               │
└─────────┼──────────────┼──────────────┼───────────────────────┘
          │              │              │
          ▼              ▼              ▼
    ┌────────────┐ ┌────────────┐ ┌────────────┐
    │ SD Card    │ │ USB-Serial │ │ Network    │
    │ Reader     │ │ Adapter    │ │ Switch/    │
    │ (UHS-II)   │ │ (×2, CP2104│ │ Router     │
    │            │ │  / FTDI)   │ │            │
    └─────┬──────┘ └─────┬──────┘ └─────┬──────┘
          │              │              │
          ▼              ▼              ▼
    ┌────────────┐ ┌────────────┐ ┌────────────┐
    │ Raspberry  │ │ Orange Pi  │ │ Both DUTs  │
    │ Pi 4/5     │ │ 5          │ │ (Ethernet) │
    │ (DUT)      │ │ (DUT)      │ │            │
    └────────────┘ └────────────┘ └────────────┘
```

### Required Hardware

| Component | Qty | Purpose | Recommendation |
|-----------|-----|---------|----------------|
| **USB-C SD Card Reader** | 1 | Flash images to microSD | UHS-II (SanDisk Extreme Pro, OWC) |
| **USB-Serial Adapter** | 2 | UART console (3.3V logic) | CP2104 or FTDI FT232RL |
| **USB-C to Ethernet Adapter** | 1 | Wired test network | Thunderbolt 3/4 or USB 3.0 Gigabit |
| **Network Switch** | 1 | Isolated test network | 5-port Gigabit unmanaged (Netgear GS305) |
| **MicroSD Cards** | 2+ | Boot media for DUTs | 32GB+ UHS-I A2 (SanDisk Extreme) |
| **Jumper Wires (F-F)** | 6+ | UART connections (GPIO) | Dupont 2.54mm |

### Network Configuration (Isolated Test Network)

```
Subnet: 192.168.100.0/24
Gateway (macOS): 192.168.100.1 (static on USB-Ethernet adapter)
DHCP: dnsmasq on macOS host (leases 192.168.100.10-50)
RPi 4/5:      192.168.100.10 (static/DHCP reservation, MAC b8:27:eb:*)
Orange Pi 5:  192.168.100.20 (static/DHCP reservation, add MAC when known)
```

**macOS host setup**:
```bash
# Configure test network interface
TEST_IFACE=$(networksetup -listallhardwareports | awk '/USB.*Ethernet|Thunderbolt.*Ethernet/{getline; print $2}' | head -1)
sudo networksetup -setmanual "$TEST_IFACE" 192.168.100.1 255.255.255.0

# dnsmasq config (/usr/local/etc/dnsmasq.d/test-lab.conf)
interface=$TEST_IFACE
dhcp-range=192.168.100.10,192.168.100.50,255.255.255.0,1h
dhcp-host=b8:27:eb:*,192.168.100.10,rpi4-5
# dhcp-host=<opi5-mac>,192.168.100.20,orangepi5
```

### Serial Console Access (Bidirectional from Docker)

**macOS host: `ser2net` TCP bridge**
```bash
brew install ser2net

# /usr/local/etc/ser2net.yaml
connection: &rpi_serial
  accepter: tcp,192.168.100.1,3323
  enable: on
  connector: serialdev,/dev/cu.usbserial-RPI,115200n81,local

connection: &opi_serial
  accepter: tcp,192.168.100.1,3324
  enable: on
  connector: serialdev,/dev/cu.usbserial-OPI,1500000n81,local

brew services start ser2net
```

**UART Wiring**

| DUT | Header Pin | Signal | USB-Serial Pin |
|-----|------------|--------|----------------|
| **RPi 4/5** | Pin 6 | GND | GND |
| | Pin 8 (GPIO 14) | UART0 TXD | RX |
| | Pin 10 (GPIO 15) | UART0 RXD | TX |
| **Orange Pi 5** | Pin 6 | GND | GND |
| | Pin 8 (UART2_TX) | UART2 TXD | RX |
| | Pin 10 (UART2_RX) | UART2 RXD | TX |

> Orange Pi 5 uses UART2 (not UART0) for debug console. Kernel cmdline: `console=ttyS2,1500000`

**Docker container access** (network_mode: host or bridge with port mapping):
```bash
# Raw TCP (best for automation)
nc 192.168.100.1 3323

# With logging + PTY for screen
socat TCP:192.168.100.1:3323 PTY,link=/tmp/rpi-console,raw,echo=0
screen /tmp/rpi-console 115200

# Python automation (telnetlib)
import telnetlib
tn = telnetlib.Telnet("192.168.100.1", 3323)
```

### Flashing Workflow (macOS Host)

```bash
# flash-dut.sh
IMG="output/romi-rpi.img.xz"
DISK="/dev/rdisk4"  # Check with: diskutil list

diskutil unmountDisk "$DISK"
xz -dc "$IMG" | sudo dd of="$DISK" bs=4M status=progress conv=fsync
sync && diskutil eject "$DISK"
```

### Debugging Checklist Per Boot

| Step | RPi 4/5 | Orange Pi 5 |
|------|---------|-------------|
| **Serial console** | `nc 192.168.100.1 3323` | `nc 192.168.100.1 3324` |
| **Boot logs** | Kernel → systemd → cloud-init | U-Boot → kernel → systemd |
| **Network** | `ip addr show eth0` | `ip addr show eth0` |
| **PhotonVision** | `systemctl status photonvision` | `systemctl status photonvision` |
| **Web UI** | `http://192.168.100.10:5800` | `http://192.168.100.20:5800` |
| **Romi Dashboard** | `http://192.168.100.10:5801` (TBD) | `http://192.168.100.20:5801` (TBD) |
| **32U4 I2C** | `i2cdetect -y 1` (addr 0x08?) | `i2cdetect -y 3` (check pinout) |

### Docker Container Network Access

```yaml
# docker-compose.yml
services:
  opencode:
    build: .
    network_mode: "host"  # Direct access to macOS host TCP ports
    volumes:
      - ./output:/workspace/output
      - ./logs:/workspace/logs
    environment:
      - RPI_SERIAL_HOST=192.168.100.1
      - RPI_SERIAL_PORT=3323
      - OPI_SERIAL_HOST=192.168.100.1
      - OPI_SERIAL_PORT=3324
      - RPI_SSH_HOST=192.168.100.10
      - OPI_SSH_HOST=192.168.100.20
```

---

## CI/CD Hardware Integration (Future)

For automated hardware testing:
- **Serial console server**: `ser2net` on dedicated Pi exposing UART over TCP
- **Power control**: USB hub with per-port switching (YKUSH, uhubctl)
- **GitHub Actions self-hosted runner** on MacBook Pro for hardware tests

---

## Phase 0: Spike — PhotonVision on QEMU (Week 0-1) 🔄 REOPENED (2026-11-10)

**Goal**: Validate PhotonVision 2026.3.x runs on target platforms and establish QEMU development workflow.

> **Correction (2026-11-10)**: This phase was marked ✅ COMPLETED on 2026-06-17,
> but the session's tool output does not support that. The PhotonVision
> install test and JAR run happened in the **danno sandbox container (Ubuntu
> 26.04)**, not in the QEMU Ubuntu 24.04 guest. Every SSH login to the guest
> failed, so nothing was ever run inside QEMU. Items below are re-marked
> against that evidence. Details:
> [`2026-11-10-restarting-romi-wpilib-photonvision.md`](2026-11-10-restarting-romi-wpilib-photonvision.md#phase-0-spike-what-actually-ran).

### Findings (2026-06-17/18, corrected 2026-11-10)

| Platform | Base OS (PhotonVision CI) | QEMU Result Observed | Status |
|----------|---------------------------|----------------------|--------|
| **Raspberry Pi 4/5** | Raspberry Pi OS Trixie (Debian 13) | ❓ `raspi4b` run timed out with **no serial output**; direct `-kernel`/`-dtb` boot never tried | Undetermined |
| **Orange Pi 5** | Ubuntu 24.04 Noble + Rockchip kernel (Joshua Riek) | ❌ UEFI on `virt` finds no bootable device | Expected (needs U-Boot on hardware) |
| **QEMU Dev** | Ubuntu 24.04 cloudimg | ⚠️ Guest boots (sshd answers) but **SSH login always failed** | **Not validated** |

### 0.1 Research PhotonVision Supported OS
- [x] PhotonVision CI uses **Raspberry Pi OS Trixie** for RPi builds (`photon-image-modifier/.github/workflows/main.yml`)
- [x] PhotonVision CI uses **Ubuntu 24.04 Rockchip** for Orange Pi 5 builds
- [ ] PhotonVision 2026.3.4 runs on Java 25 on the target OSes. *Java 25.0.3 was observed only in the sandbox container (Ubuntu 26.04); nothing is known about Ubuntu 24.04 or RPi OS.*
- [ ] `install.sh` works on both Debian (RPi OS) and Ubuntu. *Only run in `--test` mode in the Ubuntu 26.04 container.*

### 0.2 QEMU Environment Setup
- [x] QEMU aarch64 installed in the sandbox container (TCG; no `/dev/kvm`)
- [x] Ubuntu 24.04 cloud image boots in `virt` machine with UEFI + cloud-init seed ISO
- [ ] Log in to the guest. *Password and SSH-key cloud-init configs both ended in `Permission denied (publickey,password)`.*
- [x] Port forwarding configured: 5800 (PhotonVision), 2222 (SSH), 8080 (HTTP)
- [ ] Serial console via `ser2net` TCP bridge from macOS host. *Designed in the Hardware Debugging section; never set up.*

### 0.3 PhotonVision Install Test on Ubuntu 24.04 (in QEMU)
- [ ] `install.sh --test` resolves all dependencies **inside the guest**. *It completed in the Ubuntu 26.04 container, which shows nothing about 24.04.*
- [ ] PhotonVision JAR starts and serves its UI on port 5800. *In the container, Javalin/Jetty failed with `BindException: Address already in use` (QEMU's `hostfwd` held 5800), and it logged `Cannot manage network without root!`.*
- [ ] Systemd service created and enabled. *`--test` only printed the unit file.*
- [ ] NetworkManager + netplan configuration works

### 0.4 Spike Decision Gate
- [ ] **Decision**: Dual-track approach (see Architecture Overview). *Proposed; pending 0.3.*
- [ ] **QEMU Dev Track**: Ubuntu 24.04 cloud image for development. *Pending 0.2 login and 0.3.*
- [x] **HW Validation Track**: Platform-native OS on real hardware (follows from 0.1, not from QEMU)
- [x] Recorded in ADR-001 (Base OS Selection) and ADR-002 (32U4 Flashing). ADR-001 was corrected 2026-11-10.

### 0.5 To Close Phase 0
- [ ] Fix guest login: read `/tmp/qemu-serial.log` for whether cloud-init consumed the `cidata` seed, then retry
- [ ] Run `install.sh` (not `--test`) inside the guest and record `/etc/os-release`, `java -version` and `systemctl status photonvision` **from the guest**
- [ ] Start PhotonVision without a port clash (do not forward 5800 while also running it on the container) and fetch `http://localhost:5800`
- [ ] Try RPi OS Trixie on `raspi4b`/`raspi3b` with the kernel and DTB extracted from the boot partition and passed via `-kernel`/`-dtb`. This method booted WPILibPi and RPi OS Bookworm on the Debian VM in 2024.
- [ ] Recover the spike scripts (`boot-*-qemu.sh`, `test-photonvision.sh`) from the session export into the repo
- [ ] Update ADR-001 Validation with the evidence (rule 12)

---

## Phase 1: Foundation & Prototype (Weeks 1-3)

### 1.1 Environment Setup
- [ ] Set up build VM/container with QEMU aarch64 support
- [ ] Fork/clone photon-image-modifier as reference
- [ ] Download base image: RPi OS Trixie 64-bit lite (2025-10-01)
- [ ] Verify QEMU boot for base image
- [ ] **Create `docs/architecture/` folder + initial ADR template**

### 1.2 Minimal PhotonVision Install on Simulator — WiFi Preservation Analysis
- [ ] **Analyze PhotonVision WiFi disabling**: Examine `photon-image-modifier/install_pi.sh` and `install.sh` to identify how WiFi is disabled
  - Check: `install_pi.sh` line 39 — `install -v files/rpi-blacklist.conf /etc/modprobe.d/blacklist.conf`
  - Check: `install.sh` — `systemctl disable wpa_supplicant` (RPi path)
  - Check: `install_pi.sh` — NetworkManager handling for RPi
- [ ] **Create PhotonVision WiFi-preserving install variant**:
  - Fork `photon-image-modifier` → `romi-photon-image-modifier`
  - Modify `install.sh` to accept `--preserve-wifi` flag
  - Remove `systemctl disable wpa_supplicant` / `nmcli radio all off`
  - Remove blacklist of WiFi modules (`rpi-blacklist.conf`)
  - Preserve NetworkManager for both AP and client modes
- [ ] Test PhotonVision install with WiFi preserved on Ubuntu 24.04 QEMU
- [ ] Verify: AP mode works, client mode works, PhotonVision UI accessible
- [ ] **Write ADR-003: PhotonVision WiFi preservation strategy**

### 1.3 Romi Core Package Installation
- [ ] Identify required packages: `avrdude`, `i2c-tools`, `python3-smbus`, `gpiod`
- [ ] Add 32U4 flash utility (from WPILibPi `configServer` deps or standalone)
- [ ] Test avrdude can detect 32U4 in QEMU (simulated or passthrough)
- [ ] **Write ADR-002: 32U4 flashing approach (avrdude vs custom)**
- [ ] **Document RPi ↔ 32U4 I2C communication path + pinout**
- [ ] **RPi I2C mapping**: Document I2C bus 1 (pins 3/5, GPIO 2/3) for 32U4 at address 0x08

---

## Phase 2: Romi Dashboard & WebSocket Bridge (Weeks 4-6)

### 2.1 Primary: Upgrade Existing C++ configServer (Weeks 4-5)
**Goal**: Modernize the existing C++ configServer (CivetWeb/Boost.Beast) to WPILib 2026.2.x, add NT4 bridge, preserve all existing features.

- [ ] **Rebuild configServer against WPILib 2026.2.x**:
  - Update `deps/tools/configServer/Makefile` to use WPILib 2026 `cscore`, `wpinet`, `wpiutil` via pkg-config
  - Build on Ubuntu 24.04 (glibc 2.39, libstdc++13, C++20)
  - Resolve any API changes in `cscore`/`wpinet`/`wpiutil` between 2023→2026
- [ ] **Migrate network stack to NetworkManager**:
  - Replace `dhcpcd`/`hostapd`/`dnsmasq`/`wpa_supplicant` calls with `nmcli` / `libnm` D-Bus API
  - Implement AP mode, WiFi client, static Ethernet via NetworkManager
  - Preserve existing `romi.json` config format for backward compatibility
- [ ] **Add NT4 WebSocket Bridge (C++)**:
  - Use `ntcore` C++ API (`nt::NetworkTableInstance::StartClient4`)
  - Connect to robot NT4 server (PC) on port 5810
  - Expose Romi status (network, 32U4, system) as NT4 topics
  - Subscribe to robot commands via NT4
- [ ] **Add 32U4 Flash Endpoint**:
  - Integrate `avrdude` via `std::process` (reuse `uploadRomi.py` logic in C++)
  - REST endpoint: `POST /api/firmware/flash` with multipart .hex upload
  - Progress via WebSocket or Server-Sent Events
- [ ] **System Monitoring Endpoints**:
  - `/api/system/status` — CPU temp, disk, memory, uptime
  - `/api/network/status` — interfaces, IP, AP/client mode, signal strength
  - `/api/services/status` — systemd unit status (photonvision, configServer, romi-dashboard)
- [ ] **Modernize WebSocket Server**:
  - Upgrade from CivetWeb to Boost.Beast or `websocketpp` for better standards compliance
  - Add `/ws/romi-status` for real-time updates to browser
- [ ] **Testing & Validation**:
  - Unit tests for each new endpoint (Catch2)
  - Integration test: configServer ↔ 32U4 I2C (mock or hardware)
  - Integration test: configServer ↔ PhotonVision NT4
  - Load test: 10 concurrent WebSocket connections

### 2.2 Fallback: Javalin + Vue Project (If C++ Proves Difficult)
**Trigger**: If C++ rebuild takes >2 weeks or blocking issues with `cscore`/`wpinet` APIs

- [ ] Create `romi-dashboard/` Gradle project (mirroring PhotonVision structure)
- [ ] Configure Javalin server with Vue/TypeScript frontend (Vite)
- [ ] Set up shared Gradle build with PhotonVision version alignment
- [ ] Create systemd service template for romi-dashboard
- [ ] Implement same feature set as 2.1 in Kotlin/Java

### 2.3 Romi Dashboard Pages (Both Approaches)
- [ ] **Network Page**: AP mode config, WiFi client config, hostname
- [ ] **Firmware Page**: 32U4 flash upload + progress (reuse PhotonVision file upload pattern)
- [ ] **System Page**: CPU temp, disk usage, service status, logs
- [ ] **Camera Page**: Link/embed PhotonVision camera stream
- [ ] **Settings Page**: Timezone, keyboard, overscan, SSH toggle

### 2.4 NT4 WebSocket Bridge to Desktop Robot Code
- [ ] **Leverage WPILib NT4 WebSocket support**: Use `ntcore` (Java/Kotlin or C++) built-in WebSocket client/server
- [ ] Implement dashboard as **NT4 client** connecting to robot's NT4 server (desktop/sim)
- [ ] Expose NetworkTables topics via REST/WebSocket for dashboard UI consumption
- [ ] Reuse PhotonVision's NT4 integration patterns (they already bridge camera data to NT)
- [ ] Test with WPILib simulator (RobotSim) and real robot code
- [ ] Document: NT4 connection flow, topic naming conventions, reconnection logic

### 2.5 configServer API Compatibility (Both Approaches)
- [ ] Map existing configServer REST endpoints to new routes (backward compatible)
- [ ] Ensure backward compatibility for any existing tooling
- [ ] Deprecate old C++ configServer endpoints with 301 redirects

---

## Phase 3: Image Builder Pipeline (Weeks 7-9)

### 3.1 Script-Based Image Modifier
- [ ] Create `build-romi-image.sh` orchestrator
- [ ] Modular stage scripts (01-base, 02-network, 03-photonvision, 04-romi-core, 05-dashboard, 06-integration, 07-finalize)
- [ ] Each stage: idempotent, testable independently, logs to build log
- [ ] Support `--wpilib-version 2026|2027` (single platform: Raspberry Pi 4/5)

### 3.2 Raspberry Pi 4/5 Specific Handling
- [ ] Base: Raspberry Pi OS Trixie 64-bit (2025-10-01)
- [ ] Boot: MBR + FAT32 boot partition (Pi firmware: bootcode.bin, start4.elf, fixup.dat)
- [ ] I2C bus 1 (pins 3/5, GPIO 2/3) for 32U4 at address 0x08
- [ ] UART0 (pins 8/10, GPIO 14/15) for serial console
- [ ] Camera: libcamera + RPi ISP tuning files for PhotonVision

### 3.3 Network Configuration
- [ ] NetworkManager (replace wpa_supplicant/dhcpcd)
- [ ] AP mode: SSID `WPILibPi-<serial>`, passphrase `WPILib2026!`
- [ ] Fallback to client mode when configured
- [ ] mDNS: `wpilibpi.local` and `romi-<serial>.local`

### 3.4 Image Output & Validation
- [ ] Output: `.img.xz` + `.img.xz.sha256` + `manifest.json` (versions, git SHA)
- [ ] QEMU boot test in CI pipeline (Ubuntu 24.04 cloudimg for dev; RPi OS on hardware)
- [ ] Basic smoke test: SSH, PhotonVision UI, Romi dashboard, 32U4 detect

---

## Phase 4: Feature Parity & Polish (Weeks 10-12)

### 4.1 32U4 Firmware Flashing
- [ ] Integrate avrdude with proper Romi 32U4 fuse/settings
- [ ] Web UI: drag-drop .hex → flash → verify → reboot 32U4
- [ ] Bundle latest 32U4 firmware in image
- [ ] Support manual firmware upload for custom builds

### 4.2 Advanced Dashboard Features
- [ ] Real-time NetworkTables variable view/edit
- [ ] Camera calibration helper (link to PhotonVision calibration)
- [ ] System update checker (GitHub releases)
- [ ] Factory reset / safe mode

### 4.3 Documentation & Migration Guide
- [ ] **Architecture Decision Records (ADRs)** for each major choice (base OS, web framework, NT4 bridge, image builder)
- [ ] **System Architecture Doc**: Component diagram, communication paths (RPi ↔ 32U4 via I2C, Romi dashboard ↔ Robot via NT4 WebSocket, PhotonVision ↔ NT4, dashboard ↔ PhotonVision via HTTP)
- [ ] **WPILib Components Used**: `ntcore` (NT4), `wpilibj` (sim), `cameraserver` (multiCameraServer), `networktables` — versions pinned
- [ ] **Added Libraries/Tools**: Javalin, Vue/Vite, avrdude, photonvision JAR, NetworkManager, custom flash utility
- [ ] **Build Process Doc**: `build-romi-image.sh` usage, stage scripts, platform matrix, CI/CD pipeline, QEMU test matrix
- [ ] **Maintenance Guide**: How to update PhotonVision version, WPILib version, base OS, add new platform, debug boot failures
- [ ] **User-Facing Imaging Guide**: Flashing, first boot, AP mode, dashboard access, firmware update, WiFi client config
- [ ] **Developer Guide**: Building images locally, adding stages, testing in QEMU, contributing
- [ ] **Migration Guide**: From WPILibPi v2023 images (what changes, what's preserved, migration steps)

---

## Phase 5: 2027 Season Preparation (Ongoing)

### 5.1 WPILib 2027 Alpha/Beta Tracking
- [ ] Monitor allwpilib releases for 2027 alpha
- [ ] Update Gradle dependencies when 2027 MTA available
- [ ] Test NetworkTables 4.x compatibility
- [ ] Validate PhotonVision 2027 compatibility

### 5.2 CI/CD Pipeline
- [ ] GitHub Actions: build on schedule + on tag
- [ ] Single-platform build (Raspberry Pi 4/5 only)
- [ ] Release artifacts to GitHub Releases (`.img.xz`, `.sha256`, `manifest.json`)
- [ ] Automated QEMU smoke tests (Ubuntu 24.04 cloudimg for dev)

---

## Technical Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| PhotonVision JAR conflicts with WPILib version | Medium | High | Pin PhotonVision version; test NT4 compatibility early |
| Javalin + Vue build complexity | Low | Medium | Copy PhotonVision's proven Gradle/Vite setup |
| RPi hardware differences (I2C, GPIO, camera) | Medium | Medium | Abstract platform layer; test on hardware early |
| QEMU 32U4 passthrough unreliable | High | Medium | Develop flash logic on hardware; simulate in QEMU |
| NetworkManager vs wpa_supplicant migration issues | Low | High | Follow PhotonVision's proven NM config |
| pi-gen users expect exact image layout | Low | Medium | Document differences; provide migration path |
| **PhotonVision disables WiFi by default** | **High** | **High** | **Fork photon-image-modifier; create `--preserve-wifi` flag; remove `nmcli radio all off`, blacklist, `systemctl disable wpa_supplicant`** |
| **configServer C++ rebuild fails (API breaks)** | **Medium** | **High** | **Fallback to Javalin+Vue; timebox C++ effort to 2 weeks** |
| **WPILib 2026 `cscore`/`wpinet` API incompatible** | **Medium** | **High** | **Test build early in Phase 1.3; maintain compatibility shims** |
| **RPi libcamera/ISP tuning not working for PhotonVision** | **Medium** | **High** | **Use official RPi ISP tuning files; test AprilTag detection early** |
| **I2C bus 1 not accessible in QEMU** | **High** | **Medium** | **Mock I2C in QEMU; validate on hardware early** |

---

## Success Criteria

### 2026 Season Release (v2026.0.0) — Raspberry Pi 4/5
- [ ] RPi 4/5 image boots in QEMU (Ubuntu 24.04 cloudimg) and on hardware
- [ ] PhotonVision UI accessible, camera streaming works (libcamera + ISP tuning)
- [ ] WiFi preserved: AP mode works, client mode works, both simultaneously
- [ ] Romi dashboard (upgraded configServer or Javalin): network config, 32U4 flash, system info all functional
- [ ] NT4 bridge passes NetworkTables data to/from simulator (SmartDashboard/Glass)
- [ ] AP mode works out of box with default credentials (`WPILibPi-<serial>` / `WPILib2026!`)
- [ ] 32U4 firmware flash via web UI: upload .hex → flash → verify → reboot
- [ ] Images pass quality gates (shellcheck, shfmt, cppcheck, Gradle check)
- [ ] Build time < 30 min on CI (GitHub Actions ARM64 runner)

### 2027 Season Readiness
- [ ] Build script parameterized for WPILib version (2026|2027)
- [ ] PhotonVision 2027.x compatible
- [ ] NetworkTables 4.x validated
- [ ] Documentation updated for 2027 changes
- [ ] Orange Pi 5 support evaluated and planned

---

## Next Steps

1. **Week 0 (Spike)**: QEMU + Ubuntu 24.04, test PhotonVision install with WiFi preserved (Phase 1.2)
2. **Week 1**: Phase 1.1 environment + ADRs + PhotonVision WiFi-preserving fork
3. **Week 2**: Romi core packages + 32U4 flash capability + I2C mapping for RPi (Phase 1.3)
4. **Week 3-4**: **Phase 2.1 Primary** — Upgrade configServer C++ to WPILib 2026 + NetworkManager + NT4 bridge
5. **Week 5-6**: If C++ blocked → **Phase 2.2 Fallback** — Javalin+Vue dashboard
6. **Week 7-9**: Phase 3 — Image builder pipeline for RPi OS Trixie
7. **Week 10-12**: Phase 4 — Hardware validation on RPi 4/5, feature parity, polish

---

*Plan created: 2026-06-17 | Target 2026 release: ~13 weeks (incl. spike)*