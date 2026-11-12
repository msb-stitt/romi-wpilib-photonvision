#!/bin/bash
# 07-ssid.sh: each Romi's access point named from its Pi's serial number at boot, and the name
# spoken through the headphone jack while it is the default, as WPILibPi's were.
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"
load_platform_profile

log "Access point name from the serial number, and the spoken name"

install_packages espeak
install_file 755 "$IMAGE_DIR/files/romi-ssid" /usr/local/sbin/romi-ssid
install_file 644 "$IMAGE_DIR/files/romi-ssid.service" /etc/systemd/system/romi-ssid.service
install_file 755 "$IMAGE_DIR/files/romi-sayid" /usr/local/sbin/romi-sayid
install_file 644 "$IMAGE_DIR/files/romi-sayid.service" /etc/systemd/system/romi-sayid.service
run systemctl enable romi-ssid.service romi-sayid.service

log "Access point name complete"
