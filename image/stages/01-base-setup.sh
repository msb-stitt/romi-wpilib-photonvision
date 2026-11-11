#!/bin/bash
# 01-base-setup.sh: the one account, pi/raspberry with sudo, SSH, the host name, the serial
# console on the PL011 UART, and cloud-init off, as its first boot would lock pi's password.
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"
load_platform_profile

HOSTNAME_WANTED="${HOSTNAME_WANTED:-wpilibpi}"
GROUPS_WANTED="adm,dialout,sudo,audio,video,plugdev,users,input,netdev,gpio,i2c,spi"

log "Base setup: account pi, host name $HOSTNAME_WANTED"

if id pi >/dev/null 2>&1; then
    log "Already exists: user pi"
else
    run useradd -m -s /bin/bash pi
fi
for group in ${GROUPS_WANTED//,/ }; do
    getent group "$group" >/dev/null || run groupadd -r "$group"
done
run usermod -a -G "$GROUPS_WANTED" pi
if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY-RUN] set the password of pi to raspberry"
else
    log "Set the password of pi to raspberry"
    echo 'pi:raspberry' | chpasswd
fi

sudoers_tmp="$(mktemp)"
echo 'pi ALL=(ALL) NOPASSWD:ALL' > "$sudoers_tmp"
visudo -c -q -f "$sudoers_tmp" || die "sudoers rule does not parse"
install_file 440 "$sudoers_tmp" /etc/sudoers.d/010_pi-nopasswd
rm -f "$sudoers_tmp"

run systemctl enable ssh.service

if [[ "$(cat /etc/hostname 2>/dev/null)" != "$HOSTNAME_WANTED" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
        log "[DRY-RUN] write $HOSTNAME_WANTED to /etc/hostname and /etc/hosts"
    else
        log "Write $HOSTNAME_WANTED to /etc/hostname and /etc/hosts"
        old="$(cat /etc/hostname 2>/dev/null || true)"
        echo "$HOSTNAME_WANTED" > /etc/hostname
        [[ -n "$old" ]] && sed -i "s/\b$old\b/$HOSTNAME_WANTED/g" /etc/hosts
    fi
else
    log "Already set: host name $HOSTNAME_WANTED"
fi
if grep -qE "^127\.0\.1\.1[[:space:]].*\b$HOSTNAME_WANTED\b" /etc/hosts; then
    log "Already in /etc/hosts: 127.0.1.1 $HOSTNAME_WANTED"
else
    ensure_line /etc/hosts "127.0.1.1	$HOSTNAME_WANTED"
fi

if [[ -f /etc/cloud/cloud-init.disabled ]]; then
    log "Already off: cloud-init"
else
    run touch /etc/cloud/cloud-init.disabled
fi

ensure_line "$BOOT_MOUNT/config.txt" "enable_uart=1"
ensure_line "$BOOT_MOUNT/config.txt" "dtoverlay=disable-bt"

log "Base setup complete"
