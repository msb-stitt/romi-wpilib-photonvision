# Hardware Testing & QEMU — Parts Reference

**Status: superseded** on 2026-11-11 by [ADR-003](../architecture/ADR-003-base-and-network.md)
and `image/`. It was illustrative from 2026-06-18, `bb49e90`, labelled so at `ae008de`: it
describes code not written, and is unchecked.

## Overview

Testing strategy follows **dual-track**: QEMU for development iteration, real hardware for validation.

## QEMU Testing (Development Track)

### Base Image
- **Ubuntu 24.04 cloud image** (`ubuntu-24.04-server-cloudimg-arm64.img`)
- **Machine**: `virt` + UEFI + cloud-init
- **Runs in**: Docker container (network_mode: host)

### QEMU Boot Script
```bash
#!/bin/bash
# qemu-boot.sh — boots built image in QEMU for smoke testing

IMG="${1:-output/romi-rpi.img}"
PLATFORM="${2:-rpi}"

case "$PLATFORM" in
    rpi)
        QEMU_IMG="${IMG%.img}.qcow2"
        qemu-img convert -f raw -O qcow2 "$IMG" "$QEMU_IMG"
        ;;
    opi5)
        QEMU_IMG="$IMG"  # Already has EFI partition
        ;;
esac

# Boot parameters
CPU="cortex-a72"
MEM="2G"
SMP="4"

qemu-system-aarch64 \
    -M virt \
    -cpu "$CPU" \
    -m "$MEM" \
    -smp "$SMP" \
    -drive file="$QEMU_IMG",format=qcow2,if=virtio \
    -netdev user,id=net0,hostfwd=tcp::5800-:5800,hostfwd=tcp::5801-:5801,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 \
    -display none \
    -serial file:qemu-serial.log \
    -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
    -daemonize \
    -pidfile qemu.pid

echo "QEMU PID: $(cat qemu.pid)"
echo "Serial log: qemu-serial.log"
echo "PhotonVision: http://localhost:5800"
echo "Romi Dashboard: http://localhost:5801"
echo "SSH: ssh -p 2222 ubuntu@localhost"
```

### QEMU Smoke Test (Automated)

```bash
#!/bin/bash
# qemu-smoke-test.sh — runs after image build

set -euo pipefail

IMG="$1"
PLATFORM="$2"
TIMEOUT=120

# Start QEMU
./qemu-boot.sh "$IMG" "$PLATFORM"
PID=$(cat qemu.pid)

# Cleanup on exit
trap "kill $PID 2>/dev/null || true" EXIT

# Wait for SSH
for i in $(seq 1 $TIMEOUT); do
    if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       -p 2222 ubuntu@localhost "echo ok" 2>/dev/null; then
        echo "SSH ready"
        break
    fi
    sleep 1
done

# Test PhotonVision UI
for i in $(seq 1 30); do
    if curl -sf http://localhost:5800/ >/dev/null; then
        echo "PhotonVision UI accessible"
        break
    fi
    sleep 1
done

# Test Romi Dashboard
for i in $(seq 1 30); do
    if curl -sf http://localhost:5801/health >/dev/null; then
        echo "Romi Dashboard accessible"
        break
    fi
    sleep 1
done

# Test NT4 bridge (if robot sim running)
if curl -sf http://localhost:5801/api/nt4/status | grep -q connected; then
    echo "NT4 bridge connected"
fi

echo "Smoke test PASSED"
```

### Serial Console Access (from Docker)

The steps are in ftc-claude's `romi-image` skill.

## Hardware Validation (Validation Track)

### Required Hardware

| Component | RPi 4/5 | Orange Pi 5 |
|-----------|---------|-------------|
| Board | RPi 4B/5 8GB | Orange Pi 5 8GB/16GB |
| microSD | 32GB+ UHS-I A2 | 32GB+ UHS-I A2 |
| Power | 5V 3A USB-C | 5V 3A USB-C / 12V barrel |
| Camera | RPi Camera Module 3 | USB Camera / MIPI CSI |
| 32U4 Board | Romi 32U4 Control Board | Same (via I2C) |
| UART Adapter | CP2104 (3.3V) | CP2104 (3.3V) |
| Network | Ethernet or WiFi | Ethernet or WiFi |

### Flashing Workflow

The steps are in ftc-claude's `romi-image` skill.

### Per-Boot Validation Checklist

| Step | RPi 4/5 | Orange Pi 5 | Pass Criteria |
|------|---------|-------------|---------------|
| **1. Serial console** | `nc host 3323` | `nc host 3324` | U-Boot → kernel → systemd → login |
| **2. Boot time** | < 60s | < 60s | Login prompt appears |
| **3. Network** | `ip addr show eth0` | `ip addr show eth0` | IP assigned (DHCP/static) |
| **4. PhotonVision** | `systemctl status photonvision` | `systemctl status photonvision` | Active (running) |
| **5. PhotonVision UI** | `curl http://IP:5800` | `curl http://IP:5800` | HTML response |
| **6. Romi Dashboard** | `curl http://IP:5801/health` | `curl http://IP:5801/health` | "OK" |
| **6. Camera** | `libcamera-hello -t 0` | `v4l2-ctl --list-devices` | Camera detected |
| **7. AprilTag** | Point at tag, check UI | Point at tag, check UI | Tags detected |
| **8. 32U4 I2C** | `i2cdetect -y 1` (0x08) | `i2cdetect -y 3` (check) | Device at expected address |
| **9. 32U4 Flash** | Dashboard → upload .hex → flash | Dashboard → upload .hex → flash | Verify passes |
| **10. NT4 Bridge** | Dashboard NT4 status | Dashboard NT4 status | Connected to robot |
| **11. AP Mode** | Connect to `WPILibPi-xxx` | Connect to `WPILibPi-xxx` | IP assigned, UI accessible |
| **12. WiFi Client** | Configure via dashboard | Configure via dashboard | Connects to network |

### 32U4 I2C Addresses

| Board | I2C Bus | Address | Notes |
|-------|---------|---------|-------|
| **RPi 4/5** | 1 (`/dev/i2c-1`) | 0x08 | Default Romi 32U4 address |
| **Orange Pi 5** | 3 (`/dev/i2c-3`) | 0x08 | Check schematic |

```bash
# Scan I2C
i2cdetect -y 1  # RPi
i2cdetect -y 3  # OPI5

# Test communication
i2cget -y 1 0x08 0x00  # Read register 0
```

### UART Configuration

| Board | Device | Baud | Kernel Cmdline |
|-------|--------|------|----------------|
| **RPi 4/5** | `/dev/ttyAMA0` | 115200 | `console=serial0,115200` |
| **Orange Pi 5** | `/dev/ttyS2` | 1500000 | `console=ttyS2,1500000` |

### Automated Hardware Test Script

```bash
#!/bin/bash
# hw-test.sh — runs on DUT via SSH, outputs JSON results

set -euo pipefail

results=()

check() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        results+=("{\"test\":\"$name\",\"status\":\"PASS\"}")
        echo "✓ $name"
    else
        results+=("{\"test\":\"$name\",\"status\":\"FAIL\"}")
        echo "✗ $name"
    fi
}

check "PhotonVision service" "systemctl is-active photonvision"
check "PhotonVision UI" "curl -sf http://localhost:5800/"
check "Romi Dashboard" "curl -sf http://localhost:5801/health"
check "Camera (libcamera)" "libcamera-hello --list-cameras 2>/dev/null | grep -q 'Camera'"
check "I2C 32U4" "i2cdetect -y 1 | grep -q '08'"
check "NT4 bridge" "curl -sf http://localhost:5801/api/nt4/status | grep -q connected"
check "AP mode" "nmcli -t -f TYPE,STATE device | grep -q 'wifi:connected'"
check "Avahi (mDNS)" "avahi-browse -t _http._tcp | grep -q photonvision"

# Output JSON
echo "["$(IFS=,; echo "${results[*]}")"]" > /tmp/hw-test-results.json
cat /tmp/hw-test-results.json
```

### CI Integration

```yaml
# .github/workflows/hardware-test.yml (manual trigger)
name: Hardware Validation
on:
  workflow_dispatch:
    inputs:
      platform:
        type: choice
        options: [rpi, opi5]
      image_artifact:
        type: string

jobs:
  test:
    runs-on: self-hosted  # MacBook Pro runner
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: ${{ github.event.inputs.image_artifact }}
      - name: Flash DUT
        run: ./scripts/flash-dut.sh romi-${{ github.event.inputs.platform }}.img.xz /dev/rdisk4
      - name: Wait for boot
        run: sleep 90
      - name: Run hardware tests
        run: |
          ssh ubuntu@192.168.100.10 'bash -s' < scripts/hw-test.sh
      - name: Upload results
        uses: actions/upload-artifact@v4
        with:
          name: hw-test-results
          path: /tmp/hw-test-results.json
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| No serial output | Wrong baud / wiring | Check UART pins, baud rate |
| QEMU hangs at boot | Missing UEFI / cloud-init | Verify QEMU_EFI.fd, cloud-init ISO |
| PhotonVision UI not loading | Port conflict / service failed | `journalctl -u photonvision` |
| Camera not detected | Missing kernel driver / firmware | Install `libcamera-dev`, `raspberrypi-kernel` |
| 32U4 not on I2C | Wrong bus / address | Check schematic, `i2cdetect -l` |
| NT4 not connecting | Wrong robot IP / firewall | Verify NT4_SERVER, port 5810 open |
| AP mode not working | NetworkManager config | Check `/etc/NetworkManager/system-connections/` |

## References

- QEMU ARM64: https://wiki.qemu.org/Documentation/Platforms/ARM
- ser2net: https://github.com/cminyard/ser2net
- RPi UART: https://www.raspberrypi.com/documentation/computers/configuration.html#uart-configuration
- Orange Pi 5 UART: http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/service-and-support/Orange-Pi-5/2022/1107/365.html
- libcamera: https://libcamera.org/