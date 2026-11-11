#!/bin/bash
# lib/common.sh: shared functions for the stage scripts. A stage runs as root on the target
# system, either the running Pi or the image's root mounted as a chroot.

BUILD_LOG="${BUILD_LOG:-/var/log/romi-image-build.log}"
DRY_RUN="${DRY_RUN:-1}"
IMAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$BUILD_LOG"
}

die() {
    log "ERROR: $*"
    exit 1
}

load_platform_profile() {
    local profile="$IMAGE_DIR/platforms/${PLATFORM:-rpi}.profile"
    [[ -f "$profile" ]] || die "Platform profile not found: $profile"
    # shellcheck source=/dev/null
    source "$profile"
    log "Loaded platform profile: ${PLATFORM:-rpi}"
}

# run CMD ARGS...: run a command, or with DRY_RUN=1 print it and run nothing.
run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        log "[DRY-RUN] $*"
        return 0
    fi
    log "+ $*"
    local status=0
    "$@" 2>&1 | tee -a "$BUILD_LOG" || true
    status=${PIPESTATUS[0]}
    [[ $status -eq 0 ]] || die "Command failed (exit $status): $*"
}

# ensure_line FILE LINE: append LINE to FILE unless FILE already holds it.
ensure_line() {
    local file="$1" line="$2"
    if grep -qxF -- "$line" "$file" 2>/dev/null; then
        log "Already in $file: $line"
        return 0
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        log "[DRY-RUN] append to $file: $line"
        return 0
    fi
    log "Append to $file: $line"
    printf '%s\n' "$line" >> "$file"
}

# install_file MODE SRC DEST: copy SRC to DEST with MODE unless DEST already matches.
install_file() {
    local mode="$1" src="$2" dest="$3"
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        log "Already installed: $dest"
        return 0
    fi
    run install -D -m "$mode" "$src" "$dest"
}

# install_packages PKG...: install the packages not already installed.
install_packages() {
    local missing=() pkg
    for pkg in "$@"; do
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" ||
            missing+=("$pkg")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        log "Already installed: $*"
        return 0
    fi
    run apt-get -q update
    run env DEBIAN_FRONTEND=noninteractive apt-get -q -y --no-install-recommends install "${missing[@]}"
}
