#!/bin/bash
# 02-network.sh: the WPILibPi access point from NetworkManager at 10.0.0.2, with its own DHCP,
# and the WiFi country. Ethernet keeps NetworkManager's default DHCP client. A keyfile already
# there is kept, as the Romi page changes it.
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"
load_platform_profile

WIFI_COUNTRY="${WIFI_COUNTRY:-US}"
CMDLINE="$BOOT_MOUNT/cmdline.txt"

log "Network: access point WPILibPi, WiFi country $WIFI_COUNTRY"

KEYFILE=/etc/NetworkManager/system-connections/WPILibPi.nmconnection
if [[ -f "$KEYFILE" ]]; then
    log "Kept existing $KEYFILE"
else
    install_file 600 "$IMAGE_DIR/files/WPILibPi.nmconnection" "$KEYFILE"
fi

if grep -q "cfg80211.ieee80211_regdom=" "$CMDLINE"; then
    log "Already set in $CMDLINE: a WiFi country"
elif [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY-RUN] add cfg80211.ieee80211_regdom=$WIFI_COUNTRY to $CMDLINE"
else
    log "Add cfg80211.ieee80211_regdom=$WIFI_COUNTRY to $CMDLINE"
    sed -i "1 s/\$/ cfg80211.ieee80211_regdom=$WIFI_COUNTRY/" "$CMDLINE"
fi

log "Network complete"
