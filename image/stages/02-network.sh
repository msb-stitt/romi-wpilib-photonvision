#!/bin/bash
# 02-network.sh: the WPILibPi access point from NetworkManager at 10.0.0.2, with its own DHCP,
# and the WiFi country. Ethernet keeps NetworkManager's default DHCP client, with a link-local
# address while DHCP gives none. A keyfile already there is kept, as the Romi page changes it.
# WiFi is unblocked as raspi-config's do_wifi_country does in a chroot. Each radio boots
# soft-blocked, by raspberrypi-sys-mods' rfkill default_state=0, and the stock image's
# NetworkManager state leaves WiFi off until a country is set; a Pi that has booted also keeps the
# block in systemd's saved rfkill state.
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

# Ethernet's profile retries DHCP forever, by autoconnect-retries=0: NetworkManager's default
# of 4 stops after four 45 s DHCP timeouts and holds the profile down for 300 s, taking the
# link-local address with it. In place of the one NetworkManager makes in /run at each boot.
ETH_KEYFILE="/etc/NetworkManager/system-connections/Wired connection 1.nmconnection"
if [[ -f "$ETH_KEYFILE" ]]; then
    log "Kept existing $ETH_KEYFILE"
else
    install_file 600 "$IMAGE_DIR/files/Wired connection 1.nmconnection" "$ETH_KEYFILE"
fi

install_file 644 "$IMAGE_DIR/files/romi-ethernet.conf" /etc/NetworkManager/conf.d/romi-ethernet.conf

if grep -q "cfg80211.ieee80211_regdom=" "$CMDLINE"; then
    log "Already set in $CMDLINE: a WiFi country"
elif [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY-RUN] add cfg80211.ieee80211_regdom=$WIFI_COUNTRY to $CMDLINE"
else
    log "Add cfg80211.ieee80211_regdom=$WIFI_COUNTRY to $CMDLINE"
    sed -i "1 s/\$/ cfg80211.ieee80211_regdom=$WIFI_COUNTRY/" "$CMDLINE"
fi

NM_STATE=/var/lib/NetworkManager/NetworkManager.state
if [[ -f "$NM_STATE" ]] && grep -q '^WirelessEnabled=false' "$NM_STATE"; then
    run sed -i 's/^WirelessEnabled=.*/WirelessEnabled=true/' "$NM_STATE"
else
    log "Already on, or not recorded: WiFi in $NM_STATE"
fi
for rfkill in /var/lib/systemd/rfkill/*:wlan; do
    [[ -e "$rfkill" ]] || continue
    if [[ "$(cat "$rfkill")" == 0 ]]; then
        log "Already unblocked: $rfkill"
    elif [[ "$DRY_RUN" == "1" ]]; then
        log "[DRY-RUN] write 0 to $rfkill"
    else
        log "Write 0 to $rfkill"
        echo 0 > "$rfkill"
    fi
done

log "Network complete"
