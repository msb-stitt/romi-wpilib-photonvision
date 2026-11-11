#!/bin/bash
# 04-romi-core.sh: the Romi's own functions, as WPILibPi's stage5 gave them, on Trixie.
# I2C on, wpilibws-romi from npm under systemd, and uploadRomi.py with avrdude for the 32U4.
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"
load_platform_profile

ROMI_VERSION="${ROMI_VERSION:-1.4.0}"
NODE_MODULES=/usr/local/lib/node_modules
FILES="$IMAGE_DIR/files"

log "Romi core: wpilibws-romi ${ROMI_VERSION}"

install_packages nodejs npm node-gyp libnode-dev build-essential i2c-tools avrdude python3-serial

ensure_line "$BOOT_MOUNT/config.txt" "dtparam=i2c_arm=on"
ensure_line /etc/modules-load.d/i2c.conf "i2c-dev"

installed="$(node -p "require('$NODE_MODULES/@wpilib/wpilib-ws-robot-romi/package.json').version" \
    2>/dev/null || true)"
if [[ "$installed" == "$ROMI_VERSION" ]]; then
    log "Already installed: @wpilib/wpilib-ws-robot-romi@$ROMI_VERSION"
else
    run npm install -g --unsafe-perm "@wpilib/wpilib-ws-robot-romi@$ROMI_VERSION"
fi
if [[ "$DRY_RUN" != "1" ]]; then
    [[ -e "$NODE_MODULES/@wpilib/wpilib-ws-robot-romi/node_modules/i2c-bus/build/Release/i2c.node" ]] ||
        die "i2c-bus did not build; wpilibws-romi would fall back to its mock I2C"
fi

if [[ ! -f "$BOOT_MOUNT/romi.json" ]]; then
    run install -m 644 "$FILES/romi.json" "$BOOT_MOUNT/romi.json"
else
    log "Kept existing $BOOT_MOUNT/romi.json"
fi

hex="$NODE_MODULES/@wpilib/wpilib-ws-robot-romi/firmware/.pio/build/a-star32U4/firmware.hex"
upload_tmp="$(mktemp)"
sed -e "s,\\\$NVM_BIN/../lib/node_modules/@wpilib/wpilib-ws-robot-romi/firmware/.pio/build/a-star32U4/firmware.hex,$hex," \
    "$FILES/uploadRomi.py" > "$upload_tmp"
install_file 755 "$upload_tmp" /usr/local/sbin/uploadRomi.py
rm -f "$upload_tmp"

install_file 644 "$FILES/wpilibws-romi.service" /etc/systemd/system/wpilibws-romi.service
run systemctl enable wpilibws-romi.service

log "Romi core complete"
