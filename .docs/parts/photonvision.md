# PhotonVision Install & Configure — Parts Reference

**Status: superseded** on 2026-11-11 by [ADR-003](../architecture/ADR-003-base-and-network.md)
and `image/`. It was illustrative from 2026-06-18, `bb49e90`, labelled so at `ae008de`: it
describes code not written, and is unchecked.

## Overview

PhotonVision is installed via its **official install.sh script** (from `photon-image-modifier`). We do not fork or modify PhotonVision source — we configure it via:
- Generated config files (network, camera, pipeline)
- Systemd service overrides
- Environment variables

## Installation Method

```bash
# From photon-image-modifier/install.sh
./install.sh \
  --arch=aarch64 \
  --version=v2026.3.4 \
  --control-networking=yes \
  --quiet
```

**What install.sh does:**
1. Detects OS (Debian/Ubuntu) and architecture (aarch64)
2. Installs dependencies: `avahi-daemon`, `libatomic1`, `v4l-utils`, `sqlite3`, `openjdk-25-jre-headless`, `usbtop`
3. Creates CPU governor service (`performance` mode)
4. If `--control-networking=yes`: installs `network-manager`, configures `netplan` for NetworkManager
5. Downloads `photonvision-v<version>-linuxarm64.jar` from GitHub releases
6. Creates `/lib/systemd/system/photonvision.service`
7. Enables and starts service

## PhotonVision Service

```ini
# /lib/systemd/system/photonvision.service
[Unit]
Description=Service that runs PhotonVision
After=network.target

[Service]
WorkingDirectory=/opt/photonvision
Nice=-10
# For big.LITTLE CPUs (RK3588): use big cores
# AllowedCPUs=4-7
ExecStart=/usr/bin/java -Xmx512m -jar /opt/photonvision/photonvision.jar
ExecStop=/bin/systemctl kill photonvision
Type=simple
Restart=on-failure
RestartSec=1

[Install]
WantedBy=multi-user.target
```

**RPi-specific override** (disable big cores, adjust memory):
```ini
# /etc/systemd/system/photonvision.service.d/rpi.conf
[Service]
ExecStart=/usr/bin/java -Xmx512m -jar /opt/photonvision/photonvision.jar
# No AllowedCPUs on RPi
```

**Orange Pi 5 override** (enable RK3588 big cores):
```ini
# /etc/systemd/system/photonvision.service.d/opi5.conf
[Service]
AllowedCPUs=4-7
```

## Configuration Files

PhotonVision stores config in SQLite: `/opt/photonvision/photonvision_config/photon.sqlite`

**Key config tables:**
- `HardwareConfig` — camera, LED, GPIO settings
- `NetworkConfig` — IP mode (static/DHCP/AP), hostname
- `PipelineConfig` — pipeline settings per camera
- `NeuralNetworkModelsSettings` — ML model config

**Pre-seeding config for image build:**
```bash
# Stage 03-photonvision.sh
# After install.sh, inject default config:
sqlite3 /opt/photonvision/photonvision_config/photon.sqlite <<'SQL'
INSERT OR REPLACE INTO NetworkConfig (key, value) VALUES
  ('networkMode', 'ap'),
  ('apSsid', 'WPILibPi-<serial>'),
  ('apPassword', 'WPILib2026!'),
  ('hostname', 'photonvision'),
  ('staticIp', '10.0.0.3'),
  ('netmask', '255.255.255.0'),
  ('gateway', '10.0.0.1'),
  ('dns', '8.8.8.8');
SQL
```

## Camera Configuration

**RPi Camera Module (libcamera):**
```json
{
  "cameraId": "front",
  "driver": "libcamera",
  "width": 640,
  "height": 480,
  "fps": 30,
  "pixelFormat": "YUV420",
  "libcamera": {
    "tuningFile": "/usr/share/libcamera/ipa/raspberrypi/vc4/imx477.json"
  }
}
```

**USB Camera (V4L2):**
```json
{
  "cameraId": "front",
  "driver": "v4l2",
  "devicePath": "/dev/video0",
  "width": 640,
  "height": 480,
  "fps": 30,
  "pixelFormat": "MJPG"
}
```

## AprilTag / Pipeline Config

```json
{
  "pipelineId": "apriltag",
  "pipelineType": "APRILTAG",
  "cameraId": "front",
  "apriltag": {
    "tagFamily": "tag36h11",
    "tagSize": 0.165,
    "decimate": 1.0,
    "blur": 0.0,
    "refineEdges": true,
    "refineDecode": true,
    "refinePose": true,
    "multiTag": true,
    "multiTagMaxHamming": 2
  }
}
```

## Network Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `ap` | Access Point (default) | Initial setup, competition field |
| `client` | Connect to existing WiFi | Practice, home network |
| `static` | Static Ethernet IP | Wired competition field |

**AP Mode Defaults:**
- SSID: `WPILibPi-<last 4 of MAC>` → We use `WPILibPi-<serial>`
- Password: `WPILib2026!`
- IP: `10.0.0.3/24`
- Gateway: `10.0.0.1`

## Hardware Acceleration

| Platform | GPU/ISP | Video Encode | ML Accel |
|----------|---------|--------------|----------|
| **RPi 4/5** | VC4/V3D (Mesa) | V4L2 H.264/H.265 | None (CPU) |
| **Orange Pi 5** | Mali-G610 | RKVENC (RK3588) | RKNN (NPU) |

**RPi libcamera tuning files** (required for ISP):
```bash
apt-get install -y libcamera-dev libcamera-tools
# Tuning files in /usr/share/libcamera/ipa/raspberrypi/
```

**Orange Pi 5 RKNN:**
```bash
# PhotonVision bundles RKNN libs for RK3588
# Requires: librockchip-mpp, librknnrt
apt-get install -y librockchip-mpp1 librknnrt1
```

## Systemd Drop-ins for Romi

```bash
# /etc/systemd/system/photonvision.service.d/romi.conf
[Service]
# Lower memory for Pi (shared with dashboard)
MemoryLimit=768M
# Ensure PhotonVision starts before dashboard
Before=romi-dashboard.service
# Environment for NT4
Environment=NT4_SERVER=10.0.0.2
Environment=NT4_PORT=5810
```

## Version Pinning

```bash
# In build script
PHOTONVISION_VERSION="v2026.3.4"
PHOTONVISION_SHA256="..."  # Verify download
```

**Check for updates:**
```bash
curl -s https://api.github.com/repos/PhotonVision/photonvision/releases/latest \
  | jq -r '.tag_name'
```

## Testing PhotonVision on Image

The checks are in ftc-claude's `romi-image` skill.

## Upgrading PhotonVision in Image

```bash
# 1. Stop service
systemctl stop photonvision

# 2. Download new JAR
wget -q "https://github.com/PhotonVision/photonvision/releases/download/v2026.3.5/photonvision-v2026.3.5-linuxarm64.jar" \
  -O /opt/photonvision/photonvision.jar.new

# 3. Verify
sha256sum /opt/photonvision/photonvision.jar.new

# 4. Swap
mv /opt/photonvision/photonvision.jar.new /opt/photonvision/photonvision.jar

# 5. Restart
systemctl start photonvision
```

## References

- PhotonVision install.sh: https://github.com/PhotonVision/photon-image-modifier/blob/main/install.sh
- PhotonVision releases: https://github.com/PhotonVision/photonvision/releases
- PhotonVision config schema: https://github.com/PhotonVision/photonvision/tree/main/photon-core/src/main/resources/config
- libcamera RPi tuning: https://libcamera.org/ipa/raspberrypi.html
- RKNN docs: https://github.com/rockchip-linux/rknn-toolkit2