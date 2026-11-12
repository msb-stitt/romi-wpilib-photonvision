#!/bin/bash
# 04-romi-core.sh: the Romi's own functions, as WPILibPi's stage5 gave them, on Trixie.
# I2C on, wpilibws-romi from npm under systemd, and uploadRomi.py with avrdude for the 32U4.
# wpilibws-romi and each of its dependencies are pinned by files/wpilibws-romi/package-lock.json.
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"
load_platform_profile

FILES="$IMAGE_DIR/files"
ROMI_DIR=/opt/wpilibws-romi
ROMI_PACKAGE="$ROMI_DIR/node_modules/@wpilib/wpilib-ws-robot-romi"
ROMI_VERSION="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))
print(d["packages"]["node_modules/@wpilib/wpilib-ws-robot-romi"]["version"])' \
    "$FILES/wpilibws-romi/package-lock.json")"
I2C_NODE="$ROMI_DIR/node_modules/i2c-bus/build/Release/i2c.node"

log "Romi core: wpilibws-romi ${ROMI_VERSION}"

install_packages nodejs npm node-gyp libnode-dev build-essential i2c-tools avrdude python3-serial

ensure_line "$BOOT_MOUNT/config.txt" "dtparam=i2c_arm=on"
ensure_line /etc/modules-load.d/i2c.conf "i2c-dev"

if [[ -d /usr/local/lib/node_modules/@wpilib/wpilib-ws-robot-romi ]]; then
    log "Removing the unpinned global install of wpilibws-romi"
    run npm uninstall -g @wpilib/wpilib-ws-robot-romi
fi

if cmp -s "$FILES/wpilibws-romi/package-lock.json" "$ROMI_DIR/package-lock.json" &&
    [[ -e "$I2C_NODE" ]]; then
    log "Already installed: $ROMI_DIR from its lockfile"
else
    install_file 644 "$FILES/wpilibws-romi/package.json" "$ROMI_DIR/package.json"
    install_file 644 "$FILES/wpilibws-romi/package-lock.json" "$ROMI_DIR/package-lock.json"
    run npm ci --prefix "$ROMI_DIR" --omit=dev --no-audit --no-fund
fi
if [[ "$DRY_RUN" != "1" ]]; then
    [[ -e "$I2C_NODE" ]] || die "i2c-bus did not build; wpilibws-romi would fall back to its mock I2C"
fi

if [[ ! -f "$BOOT_MOUNT/romi.json" ]]; then
    run install -m 644 "$FILES/romi.json" "$BOOT_MOUNT/romi.json"
else
    log "Kept existing $BOOT_MOUNT/romi.json"
fi

hex="$ROMI_PACKAGE/firmware/.pio/build/a-star32U4/firmware.hex"
upload_tmp="$(mktemp)"
sed -e "s,\\\$NVM_BIN/../lib/node_modules/@wpilib/wpilib-ws-robot-romi/firmware/.pio/build/a-star32U4/firmware.hex,$hex," \
    "$FILES/uploadRomi.py" > "$upload_tmp"
install_file 755 "$upload_tmp" /usr/local/sbin/uploadRomi.py
rm -f "$upload_tmp"

install_file 644 "$FILES/wpilibws-romi.service" /etc/systemd/system/wpilibws-romi.service
run systemctl enable wpilibws-romi.service

log "Romi core complete"
