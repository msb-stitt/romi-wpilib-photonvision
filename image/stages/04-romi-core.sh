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
NPM_CACHE=/tmp/romi-npm-cache

log "Romi core: wpilibws-romi ${ROMI_VERSION}"

install_packages nodejs npm node-gyp libnode-dev build-essential i2c-tools avrdude python3-serial

ensure_line "$BOOT_MOUNT/config.txt" "dtparam=i2c_arm=on"
ensure_line /etc/modules-load.d/i2c.conf "i2c-dev"

export npm_config_cache="$NPM_CACHE"

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
# npm's cache and logs are not needed once the lockfile's tree is installed, so they go to a
# folder removed after it, and none is left in root's home as earlier builds left it.
for dir in "$NPM_CACHE" /root/.npm; do
    if [[ -d "$dir" ]]; then
        run rm -rf "${dir:?}"
    fi
done
if [[ "$DRY_RUN" != "1" ]]; then
    [[ -e "$I2C_NODE" ]] || die "i2c-bus did not build; wpilibws-romi would fall back to its mock I2C"
fi

# romi.json lives on the ext4 root, not in the FAT boot partition as WPILibPi kept it: the card
# stays writable, and FAT has no journal, so a power-off during a save could damage the
# partition the Pi boots from. One left in the boot partition by an earlier card is moved.
ROMI_JSON=/etc/romi/romi.json
if [[ -f "$ROMI_JSON" ]]; then
    log "Kept existing $ROMI_JSON"
elif [[ -f "$BOOT_MOUNT/romi.json" ]]; then
    run install -D -m 644 "$BOOT_MOUNT/romi.json" "$ROMI_JSON"
    if [[ "$DRY_RUN" != "1" ]]; then
        cmp -s "$BOOT_MOUNT/romi.json" "$ROMI_JSON" || die "romi.json was not copied to $ROMI_JSON"
    fi
    run rm "$BOOT_MOUNT/romi.json"
else
    run install -D -m 644 "$FILES/romi.json" "$ROMI_JSON"
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
