# Image Builder — Parts Reference

**Status: illustrative.** It describes code not yet written, and is unchecked.

## Overview

The image builder is a **shell script pipeline** (`build-romi-image.sh` + modular stage scripts) that takes a base OS image and produces a bootable Romi image for a specific platform.

This follows the **photon-image-modifier pattern**: base image → modification scripts → output image. Unlike pi-gen (stage-based, Debian-host only, slow), this approach:
- Works on any Linux host (including macOS via Docker)
- Fast iteration (modify running image, re-package)
- Platform-aware (RPi OS Trixie for RPi, Ubuntu 24.04 Rockchip for Orange Pi 5)
- Idempotent stages (safe to re-run)

## Pipeline Structure

```
build-romi-image.sh --platform rpi|opi5 --wpilib-version 2026|2027 [--dry-run]
    │
    ├─ 01-base-setup.sh        # users, ssh, hostname, base packages
    ├─ 02-network.sh           # NetworkManager, netplan, AP mode, static IPs
    ├─ 03-photonvision.sh      # PhotonVision install.sh wrapper
    ├─ 04-romi-core.sh         # avrdude, i2c-tools, gpiod, 32U4 flash util
    ├─ 05-romi-dashboard.sh    # Javalin+Vue JAR + systemd service
    ├─ 06-romi-integration.sh  # NT4 WebSocket bridge, configServer API compat
    └─ 07-finalize.sh          # cleanup, resize, checksums, manifest.json
```

## Platform Abstraction

Each platform has a **platform profile** (`platforms/rpi.profile`, `platforms/opi5.profile`):

```bash
# platforms/rpi.profile
BASE_IMG_URL="https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2025-10-02/2025-10-01-raspios-trixie-arm64-lite.img.xz"
BASE_IMG_SHA256="..."
BOOT_PARTITION=1
ROOT_PARTITION=2
BOOT_MOUNT="/boot/firmware"
KERNEL_PKG="raspberrypi-kernel"
FIRMWARE_PKGS="raspberrypi-bootloader raspberrypi-firmware rpi-eeprom"
I2C_BUS=1
UART_DEVICE="/dev/ttyAMA0"
UART_BAUD=115200
```

```bash
# platforms/opi5.profile
BASE_IMG_URL="https://github.com/Joshua-Riek/ubuntu-rockchip/releases/download/v2.4.0/ubuntu-24.04-preinstalled-server-arm64-orangepi-5.img.xz"
BASE_IMG_SHA256="..."
BOOT_PARTITION=1   # EFI System Partition
ROOT_PARTITION=2=2
BOOT_MOUNT="/boot/efi"
KERNEL_PKG="linux-image-rockchip"
FIRMWARE_PKGS="linux-firmware rockchip-firmware u-boot-tools"
I2C_BUS=3
UART_DEVICE="/dev/ttyS2"
UART_BAUD=1500000
```

## Stage Script Conventions

A stage script follows the conventions in ftc-claude's `romi-image` skill.

```bash
#!/bin/bash
# 03-photonvision.sh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"
load_platform_profile

log "Installing PhotonVision ${PHOTON_VERSION} for ${PLATFORM}"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log "[DRY-RUN] Would run: ./install.sh --control-networking=yes --arch=aarch64 --version=${PHOTON_VERSION}"
    exit 0
fi

# Actual installation
cd /tmp/photon-image-modifier
./install.sh --control-networking=yes --arch=aarch64 --version="${PHOTON_VERSION}" --quiet

# Platform-specific post-install
case "${PLATFORM}" in
    rpi)
        # RPi-specific: disable wifi, enable ssh, copy config.txt
        systemctl disable wpa_supplicant || true
        systemctl enable ssh
        ;;
    opi5)
        # OPI5-specific: enable big cores, mask bluetooth
        sed -i 's/# AllowedCPUs=4-7/AllowedCPUs=4-7/' /lib/systemd/system/photonvision.service
        systemctl mask "$(systemctl list-unit-files *bluetooth.service | awk '{print $1}')" || true
        ;;
esac

log "PhotonVision installation complete"
```

## Common Library (`lib/common.sh`)

```bash
#!/bin/bash
# lib/common.sh — shared functions for all stages

BUILD_LOG="${BUILD_LOG:-/tmp/build-$(date +%Y%m%d-%H%M%S).log}"
DRY_RUN="${DRY_RUN:-0}"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$BUILD_LOG"
}

die() {
    log "ERROR: $*"
    exit 1
}

load_platform_profile() {
    local profile="platforms/${PLATFORM}.profile"
    [[ -f "$profile" ]] || die "Platform profile not found: $profile"
    # shellcheck source=/dev/null
    source "$profile"
    log "Loaded platform profile: $PLATFORM"
}

run_cmd() {
    if [[ "$DRY_RUN" == "1" ]]; then
        log "[DRY-RUN] $*"
    else
        log "+ $*"
        eval "$@" 2>&1 | tee -a "$BUILD_LOG"
        local status=${PIPESTATUS[0]}
        [[ $status -eq 0 ]] || die "Command failed (exit $status): $*"
    fi
}

mount_image() {
    local img="$1"
    local mnt="$2"
    # Uses losetup + kpartx or mount -o loop,offset
    # Returns loop device path
}

unmount_image() {
    local loop_dev="$1"
    # Cleanup loop device
}
```

## QEMU Testing Integration

Stage `07-finalize.sh` can optionally run QEMU smoke test:

```bash
qemu_smoke_test() {
    local img="$1"
    local platform="$2"

    # Convert to qcow2 for QEMU
    qemu-img convert -f raw -O qcow2 "$img" "${img%.img}.qcow2"

    # Boot in background
    local pid
    qemu-system-aarch64 \
        -M virt -cpu cortex-a72 -m 2G -smp 4 \
        -drive file="${img%.img}.qcow2",format=qcow2,if=virtio \
        -netdev user,id=net0,hostfwd=tcp::5800-:5800,hostfwd=tcp::2222-:22 \
        -device virtio-net-pci,netdev=net0 \
        -display none -serial file:qemu-serial.log \
        -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
        -daemonize -pidfile qemu.pid
    pid=$(cat qemu.pid)

    # Wait for SSH + test PhotonVision UI
    wait_for_ssh 2222
    curl -sf "http://localhost:5800/" >/dev/null || die "PhotonVision UI not accessible"

    kill "$pid"
    log "QEMU smoke test passed"
}
```

## Output Artifacts

```
output/
├── romi-rpi-2026.0.0.img.xz
├── romi-rpi-2026.0.0.img.xz.sha256
├── romi-rpi-2026.0.0.manifest.json
├── romi-opi5-2026.0.0.img.xz
├── romi-opi5-2026.0.0.img.xz.sha256
└── romi-opi5-2026.0.0.manifest.json
```

**manifest.json**:
```json
{
  "platform": "rpi",
  "version": "2026.0.0",
  "git_sha": "abc123...",
  "build_date": "2026-06-18T12:00:00Z",
  "base_image": "2025-10-01-raspios-trixie-arm64-lite.img.xz",
  "base_image_sha256": "...",
  "photonvision_version": "2026.3.4",
  "wpilib_version": "2026.2.1",
  "packages": ["avrdude", "i2c-tools", "network-manager", "openjdk-25-jre-headless", ...]
}
```

## CI Integration

GitHub Actions workflow (`.github/workflows/build.yml`):
- Matrix: `platform: [rpi, opi5]`, `wpilib_version: [2026, 2027]`
- Runs on `ubuntu-24.04-arm` (GitHub ARM runners)
- Artifacts: `.img.xz`, `.sha256`, `manifest.json`
- Optional: QEMU smoke test on each build
- Release: on tag `v2026.x.x`, upload to GitHub Releases