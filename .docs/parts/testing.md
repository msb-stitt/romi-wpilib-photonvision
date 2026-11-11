# Testing — Parts Reference

**Status: superseded** on 2026-11-11 by [ADR-003](../architecture/ADR-003-base-and-network.md)
and `image/`. It was illustrative from 2026-06-18, `bb49e90`, labelled so at `ae008de`: it
describes code not written, and is unchecked.

## Test Philosophy

- **Test at boundaries**: CLI args, base image state, external commands (qemu, dd, systemctl)
- **Fast unit tests** for pure logic (parsing, config, business logic)
- **Integration tests** for component interaction (PhotonVision + Dashboard + NT4)
- **Hardware tests** for physical validation (separate CI, manual trigger)
- **Smoke tests** in QEMU for every image build

## Test Organization

```
tests/
├── unit/
│   ├── shell/              # bats tests for shell scripts
│   ├── python/             # pytest for Python helpers
│   └── java/               # JUnit for Kotlin/Java logic
├── integration/
│   ├── qemu/               # QEMU boot + smoke test
│   └── nt4/                # NT4 bridge integration
├── hardware/               # Manual CI (self-hosted runner)
└── fixtures/               # Test data (sample images, configs)
```

## Shell Script Testing (bats)

```bash
#!/usr/bin/env bats
# tests/unit/shell/03-photonvision.bats

load '../helpers/common'

setup() {
    export DRY_RUN=1
    export PLATFORM=rpi
    export PHOTON_VERSION=v2026.3.4
    source lib/common.sh
    load_platform_profile
}

@test "03-photonvision.sh runs install.sh with correct args" {
    run ./stages/03-photonvision.sh
    assert_success
    assert_output --partial "Would run: ./install.sh --control-networking=yes --arch=aarch64 --version=v2026.3.4"
}

@test "03-photonvision.sh creates systemd override for RPi" {
    run ./stages/03-photonvision.sh
    assert_success
    # Check override file created
    [[ -f /etc/systemd/system/photonvision.service.d/rpi.conf ]]
}
```

```bash
# tests/helpers/common.bash
setup_test_env() {
    export BUILD_LOG="/tmp/test-build.log"
    export DRY_RUN=1
    mkdir -p /tmp/test-platforms
    cat > /tmp/test-platforms/rpi.profile <<'EOF'
BASE_IMG_URL="..."
BOOT_PARTITION=1
ROOT_PARTITION=2
I2C_BUS=1
UART_DEVICE="/dev/ttyAMA0"
EOF
}

teardown_test_env() {
    rm -rf /tmp/test-platforms
}
```

## Python Testing (pytest)

```python
# tests/unit/python/test_image_builder.py
import pytest
from pathlib import Path
from unittest.mock import patch, MagicMock

from scripts.lib.image_utils import mount_image, unmount_image, verify_sha256

class TestImageUtils:
    @pytest.fixture
    def temp_img(self, tmp_path):
        img = tmp_path / "test.img"
        img.write_bytes(b"\x00" * 1024 * 1024)  # 1MB
        return img

    def test_mount_image_returns_loop_device(self, temp_img):
        with patch("subprocess.run") as mock_run:
            mock_run.return_value.stdout = "/dev/loop0\n"
            loop = mount_image(str(temp_img), "/mnt")
            assert loop == "/dev/loop0"

    def test_verify_sha256_matches(self, tmp_path):
        f = tmp_path / "test.txt"
        f.write_text("hello")
        expected = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        assert verify_sha256(str(f), expected)

    def test_verify_sha256_mismatch(self, tmp_path):
        f = tmp_path / "test.txt"
        f.write_text("hello")
        with pytest.raises(ValueError):
            verify_sha256(str(f), "wrong_hash")
```

## Java/Kotlin Testing (JUnit)

```kotlin
// romi-dashboard/src/test/java/org/romi/dashboard/services/FlashServiceTest.kt
package org.romi.dashboard.services

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.extension.ExtendWith
import org.mockito.Mock
import org.mockito.junit.jupiter.MockitoExtension
import org.romi.dashboard.config.DashboardConfig
import org.romi.dashboard.util.ProcessUtil

@ExtendWith(MockitoExtension::class)
class FlashServiceTest {

    @Mock
    lateinit var config: DashboardConfig

    @Mock
    lateinit var processUtil: ProcessUtil

    @Test
    fun `flashFirmware runs avrdude with correct args`() {
        // Given
        val service = FlashService(config)
        val hexPath = "/opt/romi/firmware/Romi32U4.hex"

        whenever(config.flash.programmer).thenReturn("avr109")
        whenever(config.flash.mcu).thenReturn("m32u4")
        whenever(config.flash.device).thenReturn("/dev/ttyAMA0")
        whenever(config.flash.baud).thenReturn(57600)

        // When
        val result = service.flashFirmware(hexPath) { _, _ -> }

        // Then
        verify(processUtil).runWithProgress(
            argThat { it.containsAll(listOf("avrdude", "-c", "avr109", "-p", "m32u4")) },
            any()
        )
    }
}
```

## Integration Tests (QEMU)

```bash
#!/bin/bash
# tests/integration/qemu/smoke_test.sh
# Runs in CI after image build

set -euo pipefail

IMG="$1"
PLATFORM="$2"

# Convert to qcow2
qemu-img convert -f raw -O qcow2 "$IMG" "${IMG%.img}.qcow2"

# Start QEMU
qemu-system-aarch64 \
    -M virt -cpu cortex-a72 -m 2G -smp 4 \
    -drive file="${IMG%.img}.qcow2",format=qcow2,if=virtio \
    -netdev user,id=net0,hostfwd=tcp::5800-:5800,hostfwd=tcp::5801-:5801,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 \
    -display none -serial file:qemu-serial.log \
    -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
    -daemonize -pidfile qemu.pid

PID=$(cat qemu.pid)
trap "kill $PID" EXIT

# Wait for services
wait_for_port 2222 60
wait_for_http "http://localhost:5800" 60
wait_for_http "http://localhost:5801/health" 60

# Verify content
curl -sf http://localhost:5800/ | grep -q "PhotonVision"
curl -sf http://localhost:5801/health | grep -q "OK"

# Verify NT4 bridge (if test NT4 server running)
if curl -sf http://localhost:5801/api/nt4/status | jq -e '.connected == true'; then
    echo "NT4 bridge connected"
fi

echo "INTEGRATION TEST PASSED"
```

## Hardware Tests (Manual CI)

```yaml
# .github/workflows/hardware-test.yml
name: Hardware Validation
on:
  workflow_dispatch:
    inputs:
      platform:
        type: choice
        options: [rpi, opi5]
      image_path:
        type: string

jobs:
  hardware-test:
    runs-on: [self-hosted, macos, arm64]  # MacBook Pro runner
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - name: Download image artifact
        uses: actions/download-artifact@v4
        with:
          name: ${{ github.event.inputs.image_path }}
          path: output/
      - name: Flash DUT
        run: |
          ./scripts/flash-dut.sh output/romi-${{ github.event.inputs.platform }}.img.xz /dev/rdisk4
      - name: Wait for boot
        run: sleep 90
      - name: Run hardware test suite
        run: |
          ssh -o StrictHostKeyChecking=no ubuntu@192.168.100.10 \
            'bash -s' < scripts/hw-test.sh
      - name: Upload results
        uses: actions/upload-artifact@v4
        with:
          name: hw-test-results-${{ github.event.inputs.platform }}
          path: /tmp/hw-test-results.json
```

## Test Commands

```bash
# Unit tests (all)
./gradlew test                    # Java/Kotlin
pytest tests/unit/python/         # Python
bats tests/unit/shell/            # Shell

# Integration tests
./gradlew integrationTest         # Java integration
./tests/integration/qemu/smoke_test.sh output/romi-rpi.img rpi

# Hardware tests (manual)
gh workflow run hardware-test.yml -f platform=rpi -f image_path=romi-rpi.img.xz

# Lint/format
shellcheck scripts/**/*.sh
shfmt -d scripts/
ruff check scripts/
ruff format --check scripts/
./gradlew spotlessCheck
```

## Test Data Fixtures

```
tests/fixtures/
├── base-images/
│   ├── minimal-rpi.img.xz      # Small test image
│   └── minimal-opi5.img.xz
├── configs/
│   ├── photonvision-default.sqlite
│   ├── network-ap.nmconnection
│   └── network-static.nmconnection
└── firmware/
    ├── Romi32U4-v1.0.hex
    └── Romi32U4-v1.1.hex
```

## Coverage Goals

| Layer | Target | Tool |
|-------|--------|------|
| Shell scripts | 80% | bats + kcov |
| Python helpers | 90% | pytest-cov |
| Java/Kotlin | 85% | JaCoCo |
| Integration | Smoke only | QEMU |
| Hardware | Manual checklist | hw-test.sh |

## Continuous Integration

```yaml
# .github/workflows/test.yml
name: Test
on: [push, pull_request]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Shell lint
        run: shellcheck scripts/**/*.sh
      - name: Shell format
        run: shfmt -d scripts/
      - name: Python lint
        run: |
          pip install ruff
          ruff check scripts/
          ruff format --check scripts/
  
  unit-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Java tests
        run: ./gradlew test
      - name: Python tests
        run: |
          pip install pytest pytest-cov
          pytest tests/unit/python/ --cov=scripts
      - name: Shell tests
        run: |
          apt-get install -y bats
          bats tests/unit/shell/
  
  integration-test:
    runs-on: ubuntu-24.04-arm  # ARM runner for QEMU
    needs: [lint, unit-test]
    steps:
      - uses: actions/checkout@v4
      - name: Build test image
        run: ./build-romi-image.sh --platform rpi --dry-run
      - name: Run QEMU smoke test
        run: |
          # Use pre-built minimal image for speed
          ./tests/integration/qemu/smoke_test.sh tests/fixtures/base-images/minimal-rpi.img rpi
```

## Debugging Failed Tests

```bash
# Run single test with verbose output
bats --verbose-run tests/unit/shell/03-photonvision.bats
pytest -xvs tests/unit/python/test_image_builder.py::TestImageUtils::test_mount_image
./gradlew test --tests "org.romi.dashboard.services.FlashServiceTest.flashFirmware" --info

# Inspect QEMU serial log
cat
cat
cat qemu-serial.log | grep -E "ERROR|FAIL|photonvision|romi-dashboard"

# SSH into QEMU for manual debugging
ssh -p 2222 ubuntu@localhost
```