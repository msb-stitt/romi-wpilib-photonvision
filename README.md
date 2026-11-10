# romi-wpilib-photonvision

> Build bootable Romi robot images for Raspberry Pi 4/5 and Orange Pi 5, integrating WPILib 2026/2027 with PhotonVision 2026/2027.

## What This Produces

Flashable `.img.xz` files that boot on hardware and provide:

| Component | Port | Description |
|-----------|------|-------------|
| **PhotonVision** | 5800 | Camera streaming, AprilTag detection, ML inference |
| **Romi Dashboard** | 5801 | Network config, 32U4 firmware flash, system monitoring |
| **NT4 Bridge** | 5810 | NetworkTables 4.x WebSocket to robot code/simulator |
| **AP Mode** | WiFi | Default SSID `WPILibPi-<serial>`, password `WPILib2026!` |

## Supported Platforms

| Platform | Base OS | Kernel/Firmware | Status |
|----------|---------|-----------------|--------|
| **Raspberry Pi 4/5** | Raspberry Pi OS Trixie (64-bit, Debian 13) | RPi kernel + bootloader | ✅ Primary |
| **Orange Pi 5** | Ubuntu 24.04 Noble + Rockchip kernel (Joshua Riek) | Rockchip kernel + U-Boot | ✅ Primary |

## Quick Start

### Prerequisites

- **Build host**: Linux (native or Docker) with QEMU aarch64
- **macOS host** (for hardware flashing/debugging): Docker Desktop, USB-C SD reader, USB-Serial adapters
- **Hardware**: RPi 4/5 or Orange Pi 5, microSD (32GB+), Romi 32U4 control board

### Build Images

```bash
# Clone
git clone https://github.com/your-org/romi-wpilib-photonvision.git
cd romi-wpilib-photonvision

# Build for Raspberry Pi (2026 season)
./build-romi-image.sh --platform rpi --wpilib-version 2026

# Build for Orange Pi 5 (2026 season)
./build-romi-image.sh --platform opi5 --wpilib-version 2026

# Dry run (prints commands without executing)
./build-romi-image.sh --platform rpi --dry-run
```

**Output**: `output/romi-rpi-2026.0.0.img.xz`, `output/romi-opi5-2026.0.0.img.xz` + checksums + manifest

### Flash to microSD (macOS)

```bash
# Find disk
diskutil list
# e.g., /dev/rdisk4

# Flash
./scripts/flash-dut.sh output/romi-rpi-2026.0.0.img.xz /dev/rdisk4
```

### Hardware Debugging

```bash
# Serial console (via ser2net on macOS host)
nc 192.168.100.1 3323  # RPi
nc 192.168.100.1 3324  # Orange Pi 5

# SSH
ssh ubuntu@192.168.100.10   # RPi (static IP)
ssh ubuntu@192.168.100.20   # Orange Pi 5

# Web UIs
open http://192.168.100.10:5800  # PhotonVision
open http://192.168.100.10:5801  # Romi Dashboard
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Platform-Specific Base Images                              │
│  ├─ RPi: Raspberry Pi OS Trixie (MBR + Pi firmware)        │
│  └─ OPI5: Ubuntu 24.04 Rockchip (GPT + EFI + U-Boot)       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Image Modifier Pipeline (photon-image-modifier style)      │
│  ├─ 01-base-setup: users, ssh, hostname                     │
│  ├─ 02-network: NetworkManager, AP mode, static IPs         │
│  ├─ 03-photonvision: PhotonVision JAR + systemd             │
│  ├─ 04-romi-core: avrdude, i2c-tools, 32U4 flash util      │
│  ├─ 05-romi-dashboard: Javalin+Vue web server               │
│  ├─ 06-romi-integration: NT4 WebSocket bridge               │
│  └─ 07-finalize: cleanup, checksums, manifest.json          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
              Bootable .img.xz + .sha256 + manifest.json
```

## Development Workflow

### QEMU Development (No Hardware Needed)

```bash
# Start QEMU with Ubuntu 24.04 cloud image
./scripts/qemu-boot.sh

# Access from Docker container (network_mode: host)
# PhotonVision:  http://localhost:5800
# Romi Dashboard: http://localhost:5801
# SSH:           ssh -p 2222 ubuntu@localhost
```

### Dual-Track Testing

| Track | Purpose | Environment |
|-------|---------|-------------|
| **Dev** | Dashboard, NT4 bridge, pipeline logic | QEMU (Ubuntu 24.04 cloudimg) |
| **HW Validation** | Camera, GPIO, 32U4 I2C, bootloader | Real RPi 4/5 / Orange Pi 5 |

## Project Structure

```
.
├── .docs/
│   ├── requirements.md           # Requirements
│   ├── integration-plan.md       # 13-week implementation plan
│   ├── architecture/             # ADRs (decision records)
│   │   ├── ADR-001-base-os-selection.md
│   │   └── ADR-002-32u4-flashing-approach.md
│   └── parts/                    # Detailed technical references
│       ├── image-builder.md
│       ├── romi-dashboard.md
│       ├── photonvision.md
│       ├── wpilib.md
│       ├── hardware-testing.md
│       └── testing.md
├── scripts/
│   ├── build-romi-image.sh       # Main orchestrator
│   ├── stages/                   # Pipeline stages (01-07)
│   ├── lib/                      # Shared bash functions
│   ├── platforms/                # Platform profiles (rpi, opi5)
│   ├── qemu-boot.sh              # QEMU launcher
│   └── flash-dut.sh              # macOS SD flasher
├── romi-dashboard/               # Javalin + Vue project (Gradle)
│   ├── build.gradle.kts
│   ├── src/main/kotlin/...
│   └── dashboard-ui/             # Vue + TypeScript + Vite
├── tests/
│   ├── unit/                     # bats, pytest, JUnit
│   ├── integration/              # QEMU smoke tests
│   └── hardware/                 # Manual hardware validation
├── .github/workflows/            # CI/CD (build, test, release)
├── build.ninja / Makefile        # Quality gates
└── scratch/                      # Throwaway probes (gitignored)
```

## Configuration

### Build-Time (build-romi-image.sh)

```bash
# Required
--platform rpi|opi5
--wpilib-version 2026|2027

# Optional
--photon-version v2026.3.4    # Pin PhotonVision version
--dry-run                     # Print commands only
--output-dir ./output         # Output directory
```

### Runtime (on DUT)

| Config | Location | Override Via |
|--------|----------|--------------|
| NT4 server IP | `/opt/romi-dashboard/application.yml` | `NT4_SERVER` env var |
| AP credentials | NetworkManager connection | Dashboard UI / `nmcli` |
| 32U4 firmware | `/opt/romi/firmware/` | Dashboard upload |
| PhotonVision config | SQLite at `/opt/photonvision/...` | PhotonVision UI |

## CI/CD

GitHub Actions (`.github/workflows/`):

| Workflow | Trigger | Actions |
|----------|---------|---------|
| `build.yml` | Push, PR, tag | Matrix build (rpi/opi5 × 2026/2027), QEMU smoke test, upload artifacts |
| `test.yml` | Push, PR | Lint (shellcheck, shfmt, ruff, spotless), unit tests |
| `hardware-test.yml` | Manual | Flash DUT, run hw-test.sh, upload results |
| `release.yml` | Tag `v*` | Create GitHub Release with `.img.xz` + manifests |

## Versioning

| Component | Version Scheme |
|-----------|----------------|
| **Romi Image** | `2026.0.0`, `2026.1.0`, `2027.0.0-alpha.1` |
| **PhotonVision** | Pinned in build (e.g., `v2026.3.4`) |
| **WPILib** | Pinned in build (e.g., `2026.2.1`) |
| **Dashboard** | Same as Romi Image |
| **Manifest** | Records all versions + git SHA |

## Documentation

| Doc | Purpose |
|-----|---------|
| `.docs/requirements.md` | Requirements |
| `.docs/integration-plan.md` | 13-week plan with phases |
| `.docs/architecture/ADR-*.md` | Architecture Decision Records |
| `.docs/parts/*.md` | Detailed technical references |

## Contributing

1. Read ftc-claude's `.claude/rules/constitution.md`, which governs this project
2. Check `.docs/integration-plan.md` for current phase
3. Create feature branch: `git switch -c feat/<short-name>`
4. Make surgical changes, update docs in same commit
5. Run quality gates: `./gradlew check && shellcheck scripts/**/*.sh && ruff check scripts/`
6. Push and open PR with conventional commit message

## License

- **This project**: MIT (see `LICENSE`)
- **PhotonVision**: MIT (upstream, configured not forked)
- **WPILib**: BSD-3-Clause (upstream, used as library)
- **Raspberry Pi OS / Ubuntu**: Their respective licenses

## Acknowledgments

- **PhotonVision** team for excellent vision software and image modifier approach
- **WPILib** team for robot control framework
- **WPILibPi** for original Romi image foundation
- **Joshua Riek** for Ubuntu Rockchip images

## Links

- PhotonVision: https://photonvision.org / https://github.com/PhotonVision
- WPILib: https://github.com/wpilibsuite/allwpilib
- Romi Robot: https://docs.wpilib.org/en/stable/docs/romi-robot/
- PhotonVision Image Modifier: https://github.com/PhotonVision/photon-image-modifier
- Ubuntu Rockchip (Joshua Riek): https://github.com/Joshua-Riek/ubuntu-rockchip