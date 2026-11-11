#!/bin/bash
# 03-photonvision.sh: PhotonVision by its own install.sh, unchanged, with networking left to
# NetworkManager and 02-network.sh. install.sh is fetched at a fixed tag and checked.
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"
load_platform_profile

PHOTON_VERSION="${PHOTON_VERSION:-v2026.3.4}"
MODIFIER_TAG="${MODIFIER_TAG:-v2027.2.3}"
INSTALL_SH_SHA256="${INSTALL_SH_SHA256:-badb1df46166546648e84a9e332762daf66525181d7ce4ba681fa4b8324a47b7}"
INSTALL_SH_URL="https://raw.githubusercontent.com/PhotonVision/photon-image-modifier/$MODIFIER_TAG/install.sh"

log "PhotonVision $PHOTON_VERSION by photon-image-modifier $MODIFIER_TAG's install.sh"

if [[ -f /opt/photonvision/photonvision.jar ]] &&
    systemctl is-enabled photonvision.service >/dev/null 2>&1 &&
    grep -qF "$PHOTON_VERSION" /opt/photonvision/romi-image-photon-version 2>/dev/null; then
    log "Already installed: PhotonVision $PHOTON_VERSION"
    exit 0
fi

work="$(mktemp -d)"
run curl -fsSL -o "$work/install.sh" "$INSTALL_SH_URL"
if [[ "$DRY_RUN" != "1" ]]; then
    echo "$INSTALL_SH_SHA256  $work/install.sh" | sha256sum -c --quiet ||
        die "install.sh at $MODIFIER_TAG does not match its recorded SHA-256"
fi
run bash "$work/install.sh" -q -v "$PHOTON_VERSION" -a aarch64
if [[ "$DRY_RUN" != "1" ]]; then
    echo "$PHOTON_VERSION installed by photon-image-modifier $MODIFIER_TAG" \
        > /opt/photonvision/romi-image-photon-version
fi
rm -rf "${work:?}"

log "PhotonVision complete"
