#!/bin/bash
# 06-romi-page.sh: the Romi page, first in Cockpit's menu: wpilibws-romi's status, log and restart,
# the external IO, the gyro calibration, the 32U4's firmware written, the WiFi and Ethernet
# settings, and romi.json edited.
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"
load_platform_profile

PAGE_DIR=/usr/share/cockpit/romi

log "Romi page in Cockpit at $PAGE_DIR"

for f in manifest.json index.html romi.js romi.css; do
    install_file 644 "$IMAGE_DIR/files/cockpit-romi/$f" "$PAGE_DIR/$f"
done

log "Romi page complete"
