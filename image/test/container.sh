#!/bin/bash
# container.sh: the built image's root booted as a container by systemd-nspawn, on the host's
# kernel and network, and its services checked. Runs as root on an arm64 Linux host with
# systemd-container. The container works on a decompressed copy of the image, which `down`
# deletes; the .img.xz is left alone.
#
#   container.sh up IMAGE.img.xz   decompress, mount, boot, wait for the services
#   container.sh check             check the services, their ports, userconfig off, pi's shell, WiFi
#   container.sh host DIR          run the robot project in DIR in simulation against the container,
#                                  and check PhotonVision's AprilTag pose reaches it
#   container.sh down              stop the container and the simulation, unmount, delete the copy
#
# The container shares the host's network, so the copy masks what would act on the host's own
# interfaces and ports: NetworkManager, wpa_supplicant, avahi, sshd and nftables. PhotonVision
# runs with -t, its test mode, on the field image its v2026.3.4 source names, in place of a camera;
# the image is fetched by that tag's commit and checked by its SHA-256.
#
# `host` puts 10.0.0.2, the Pi's access point address the robot project connects to, on the
# host's loopback, so the simulation reaches the container's port 3300. DIR is a RobotPy project,
# such as romiPyKitTiny, already synced by `uv sync --locked`.
set -euo pipefail

WORK="${WORK:-/var/tmp/romi-container}"
MACHINE=romi
IMG="$WORK/romi-image.img"
ROOT="$WORK/root"
MASKED=(NetworkManager.service NetworkManager-wait-online.service wpa_supplicant.service
    avahi-daemon.service avahi-daemon.socket ssh.service ssh.socket sshswitch.service
    rpi-eeprom-update.service nftables.service)
PV_COMMIT=a5be3d062ce5c145f4a759b0207057f218cda6b3 # PhotonVision v2026.3.4
PV_RAW=https://raw.githubusercontent.com/PhotonVision/photonvision
TEST_IMAGE=testimages/2026/BlueOutpostFuelSpread.jpg
TEST_IMAGE_SHA256=fee50b8efaa34c5a443ed7511bae50ebbe566f5afd8f7f48b0bbd46866b8bfe1

SIM_UNIT=romi-sim
PI_ADDRESS=10.0.0.2
TEST_CAMERA=WPI2026

log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { log "ERROR: $*"; exit 1; }

up() {
    local xz="$1"
    [[ $EUID -eq 0 ]] || die "container.sh runs as root"
    [[ "$(uname -m)" == "aarch64" ]] || die "the image is arm64 and this host is $(uname -m)"
    [[ -f "$xz" ]] || die "no image at $xz"
    [[ ! -e "$ROOT/etc" ]] || die "$ROOT is already mounted; run down first"
    mkdir -p "$WORK" "$ROOT"
    log "Decompressing $xz"
    xz -dc -T0 "$xz" > "$IMG"
    local loop
    loop="$(losetup -P -f --show "$IMG")"
    echo "$loop" > "$WORK/loop"
    mount "${loop}p2" "$ROOT"
    mount "${loop}p1" "$ROOT/boot/firmware"
    log "Mounted $loop at $ROOT; $(grep COMMIT "$ROOT/etc/romi-image-release")"

    local unit
    for unit in "${MASKED[@]}"; do
        ln -sf /dev/null "$ROOT/etc/systemd/system/$unit"
    done
    local jpg="$WORK/$(basename "$TEST_IMAGE")"
    if [[ ! -f "$jpg" ]]; then
        log "Fetching $TEST_IMAGE"
        curl -sSfL -o "$jpg.part" "$PV_RAW/$PV_COMMIT/test-resources/$TEST_IMAGE"
        mv "$jpg.part" "$jpg"
    fi
    echo "$TEST_IMAGE_SHA256  $jpg" | sha256sum -c --quiet || die "$jpg does not match its SHA-256"
    install -D -m 644 "$jpg" "$ROOT/opt/photonvision/test-resources/$TEST_IMAGE"
    mkdir -p "$ROOT/etc/systemd/system/photonvision.service.d"
    cat > "$ROOT/etc/systemd/system/photonvision.service.d/test-mode.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/java -Xmx512m -jar /opt/photonvision/photonvision.jar -n -t
EOF

    log "Booting $MACHINE"
    systemd-run --unit="nspawn-$MACHINE" --collect \
        systemd-nspawn --boot --directory="$ROOT" --machine="$MACHINE" --console=passive
    local i state
    for i in $(seq 1 60); do
        state="$(systemctl -M "$MACHINE" is-system-running 2>/dev/null || true)"
        case "$state" in running|degraded) break ;; esac
        sleep 2
    done
    log "System state: ${state:-not reached}"
    systemctl -M "$MACHINE" --no-pager --failed || true
    [[ "$state" == running || "$state" == degraded ]] || die "$MACHINE did not finish booting"
}

check() {
    local failed=0 unit
    for unit in wpilibws-romi.service photonvision.service cockpit.socket; do
        if systemctl -M "$MACHINE" is-active --quiet "$unit"; then
            log "active: $unit"
        else
            log "NOT active: $unit"; failed=1
        fi
    done
    # The first boot's presets would turn Raspberry Pi's rename of pi back on.
    local rename
    rename="$(systemctl -M "$MACHINE" is-enabled userconfig.service 2>/dev/null || true)"
    if [[ "$rename" == disabled ]]; then
        log "disabled after the first boot: userconfig.service"
    else
        log "NOT disabled after the first boot: userconfig.service"; failed=1
    fi
    local shell
    shell="$(grep '^pi:' "$ROOT/etc/passwd" | cut -d: -f7)"
    if [[ "$shell" == /bin/bash ]]; then
        log "pi's shell: /bin/bash"
    else
        log "pi's shell is NOT /bin/bash: $shell"; failed=1
    fi
    local blocked nm_state="$ROOT/var/lib/NetworkManager/NetworkManager.state"
    blocked="$(grep -l -v '^0$' "$ROOT"/var/lib/systemd/rfkill/*:wlan 2>/dev/null || true)"
    grep -q '^WirelessEnabled=true' "$nm_state" || blocked="${blocked:+$blocked }$nm_state"
    if [[ -z "$blocked" ]]; then
        log "WiFi not blocked by rfkill's saved state or NetworkManager's"
    else
        log "WiFi blocked by $blocked"; failed=1
    fi
    wait_http "wpilibws-romi status" http://127.0.0.1:9001/status || failed=1
    wait_http "PhotonVision" http://127.0.0.1:5800/ || failed=1
    wait_http "Cockpit" https://127.0.0.1:9090/ || failed=1
    if timeout 5 bash -c '</dev/tcp/127.0.0.1/3300'; then
        log "port 3300 accepts a connection"
    else
        log "port 3300 refused"; failed=1
    fi
    [[ $failed -eq 0 ]] || die "a check failed"
    log "All checks passed"
}

host_check() {
    local dir="$1" i
    [[ $EUID -eq 0 ]] || die "container.sh runs as root"
    [[ -x "$dir/.venv/bin/robotpy" ]] || die "no synced .venv in $dir; run uv sync --locked there"
    ip -4 addr show dev lo | grep -qF " $PI_ADDRESS/" || ip addr add "$PI_ADDRESS/32" dev lo
    systemctl stop "$SIM_UNIT" 2>/dev/null || true
    log "Starting the simulation in $dir"
    systemd-run --unit="$SIM_UNIT" --collect --working-directory="$dir" \
        "$dir/.venv/bin/robotpy" sim --ws-client --nogui
    for i in $(seq 1 60); do
        journalctl -u "$SIM_UNIT" --no-pager | grep -q "HALSimWS: WebSocket Connected" && break
        sleep 1
    done
    journalctl -u "$SIM_UNIT" --no-pager | grep -q "HALSimWS: WebSocket Connected" ||
        die "the simulation did not connect to port 3300"
    log "The simulation connected to ws://$PI_ADDRESS:3300"
    for i in $(seq 1 60); do
        journalctl -M "$MACHINE" -u photonvision --no-pager |
            grep -q "CONNECTED NT4 to $PI_ADDRESS" && break
        sleep 1
    done
    journalctl -M "$MACHINE" -u photonvision --no-pager | grep -q "CONNECTED NT4 to $PI_ADDRESS" ||
        die "PhotonVision did not connect to the simulation's NetworkTables"
    log "PhotonVision connected to the simulation's NetworkTables at $PI_ADDRESS"
    "$dir/.venv/bin/python" "$(dirname "$0")/photon-pose.py" "$TEST_CAMERA" ||
        die "no AprilTag pose reached the simulation"
    log "Host checks passed"
}

# wait_http NAME URL: wait up to 90 s for URL to answer 200.
wait_http() {
    local name="$1" url="$2" code="" i
    for i in $(seq 1 45); do
        code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$url" || true)"
        [[ "$code" == 200 ]] && break
        sleep 2
    done
    if [[ "$code" == 200 ]]; then log "$name answers 200 at $url"; return 0; fi
    log "$name did not answer 200 at $url (last: ${code:-none})"; return 1
}

down() {
    [[ $EUID -eq 0 ]] || die "container.sh runs as root"
    systemctl stop "$SIM_UNIT" 2>/dev/null || true
    ip addr del "$PI_ADDRESS/32" dev lo 2>/dev/null || true
    machinectl poweroff "$MACHINE" 2>/dev/null || true
    local i
    for i in $(seq 1 30); do
        machinectl show "$MACHINE" > /dev/null 2>&1 || break
        sleep 1
    done
    machinectl terminate "$MACHINE" 2>/dev/null || true
    umount "$ROOT/boot/firmware" 2>/dev/null || true
    umount "$ROOT" 2>/dev/null || true
    if [[ -f "$WORK/loop" ]]; then
        losetup -d "$(cat "$WORK/loop")" || true
        rm -f "${WORK:?}/loop"
    fi
    rm -f "${IMG:?}"
    log "Stopped $MACHINE and deleted $IMG"
}

case "${1:-}" in
    up) up "${2:?usage: container.sh up IMAGE.img.xz}" ;;
    check) check ;;
    host) host_check "${2:?usage: container.sh host DIR}" ;;
    down) down ;;
    *) die "usage: container.sh up IMAGE.img.xz | check | host DIR | down" ;;
esac
