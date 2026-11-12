# ADR-002: 32U4 Firmware Flashing Approach

## Status
**Superseded** on 2026-11-11 by [ADR-003](ADR-003-base-and-network.md). It was controlling
from 2026-06-18, `bb49e90`, to then, accepted; none of its Javalin design was built.

## Context
The Romi 32U4 control board needs firmware updates via the web dashboard. The current WPILibPi uses a custom C++ `configServer` that calls `avrdude` directly. We need to decide on the approach for the new Javalin-based dashboard.

## Decision
**Use `avrdude` via systemd service + Javalin REST API, with pre-bundled firmware hex files**

## Rationale

### Why avrdude?
- **Standard tool**: Used by WPILibPi, Arduino IDE, PlatformIO
- **Supports ATmega32U4**: `-c avr109 -p m32u4 -P /dev/ttyACM0 -b 57600`
- **Available in Ubuntu/Debian repos**: `apt-get install avrdude`
- **Scriptable**: Can be called from Java via `ProcessBuilder`

### Architecture
```
Web Dashboard (Vue) → Javalin REST API → FlashService → systemd-run → avrdude
                                                      → /usr/bin/avrdude -c avr109 -p m32u4 -U flash:w:firmware.hex:i
```

### Implementation Details

#### 1. Firmware Bundle
- Pre-bundle latest Romi 32U4 firmware (`Romi32U4-Firmware.hex`) in `/opt/romi/firmware/`
- Support manual upload via dashboard for custom firmware
- Version tracking in `/opt/romi/firmware/version.json`

#### 2. Flash Service (Java)
```java
@Component
class FlashService {
    void flash(String hexPath, FlashProgressCallback callback) {
        // Validate hex file (Intel HEX format)
        // Run avrdude with progress parsing
        // Callback: progress %, status messages
        // Return success/failure with details
    }
}
```

#### 3. Javalin Endpoints
- `POST /api/firmware/flash` - Upload .hex file, start flash
- `GET /api/firmware/status` - Poll for progress (WebSocket or SSE)
- `GET /api/firmware/list` - List bundled firmware versions
- `POST /api/firmware/bundle` - Add uploaded firmware to bundle

#### 4. Permissions
- Create `romi-flash` systemd service with `User=romi`, `Group=dialout`
- `avrdude` needs access to `/dev/ttyACM*` (dialout group)
- Polkit rule for passwordless `systemctl start romi-flash`

#### 5. QEMU Testing
- Simulate 32U4 with virtual serial port (`socat` or `tty0tty`)
- Mock `avrdude` for CI testing
- Real hardware testing required for validation

### Alternative Considered: Custom Java AVR Programmer
- **Pros**: Pure Java, no external dependency
- **Cons**: Complex, untested, bootloader protocol (avr109) is tricky
- **Decision**: Not worth the risk; avrdude is battle-tested

### Alternative Considered: Python Script Wrapper
- **Pros**: Easier progress parsing
- **Cons**: Extra dependency, same subprocess complexity
- **Decision**: Java ProcessBuilder is sufficient

## Consequences

### Positive
- Reuses proven WPILibPi approach
- Minimal code - just wrapper around avrdude
- Supports both bundled and custom firmware
- Progress reporting via WebSocket/SSE for good UX

### Negative
- Requires `avrdude` package (small, ~500KB)
- Needs `dialout` group access (security consideration)
- Hardware-dependent (can't fully test in QEMU)

### Mitigation
- Mock avrdude in CI with test double
- Hardware validation in Phase 4
- Document fallback: manual avrdude via SSH

## Hardware Interface

### RPi ↔ 32U4 Connection
| Signal | RPi Pin | 32U4 Pin | Notes |
|--------|---------|----------|-------|
| TXD0 (UART) | GPIO 14 (Pin 8) | PD3 (RX) | 3.3V logic |
| RXD0 (UART) | GPIO 15 (Pin 10) | PD2 (TX) | 3.3V logic |
| RESET | GPIO 4 (Pin 7) | RESET | Active low, 3.3V |
| GND | Pin 6/9/14/20/25/30/34/39 | GND | Common ground |
| 5V | Pin 2/4 | VCC | Power from RPi |

### Flash Sequence
1. Assert RESET (GPIO 4 low) for 100ms
2. Release RESET, wait 500ms for bootloader
3. Run `avrdude -c avr109 -p m32u4 -P /dev/ttyAMA0 -b 57600 -U flash:w:firmware.hex:i`
4. Verify with `-U flash:v:firmware.hex:i`
5. Assert RESET again to start application

## Validation
- [ ] avrdude package installs on Ubuntu 24.04 arm64
- [ ] avrdude detects 32U4 on real RPi hardware
- [ ] Flash + verify cycle completes successfully
- [ ] Progress parsing works (percentage from avrdude output)
- [ ] WebSocket progress updates to dashboard UI

## References
- WPILibPi configServer flash code: `deps/tools/configServer/src/main.cpp`
- avrdude ATmega32U4 docs: https://www.nongnu.org/avrdude/user-manual/avrdude_6.html
- Romi 32U4 firmware: https://github.com/wpilibsuite/Romi32U4Firmware

## Date
2026-06-17

## Authors
Spike implementation by agent