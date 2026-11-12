#!/bin/bash
# 03-photonvision.sh: PhotonVision by its own install.sh, unchanged, with networking left to
# NetworkManager and 02-network.sh. install.sh is fetched at its tag's commit and checked, and
# the jar it downloads is checked.
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"
load_platform_profile

PHOTON_VERSION="${PHOTON_VERSION:-v2026.3.4}"
MODIFIER_TAG="${MODIFIER_TAG:-v2027.2.3}"
MODIFIER_COMMIT="${MODIFIER_COMMIT:-2852eb01bea977bd1300428edd71cc9c4716da26}"
INSTALL_SH_SHA256="${INSTALL_SH_SHA256:-badb1df46166546648e84a9e332762daf66525181d7ce4ba681fa4b8324a47b7}"
# photonvision-$PHOTON_VERSION-linuxarm64.jar, the release asset install.sh picks for aarch64.
JAR_SHA256="${JAR_SHA256:-ccaf5e862a4427c90cb063953903e4967e2041747b1d3f9d0f04b68e1cd975dc}"
INSTALL_SH_URL="https://raw.githubusercontent.com/PhotonVision/photon-image-modifier/$MODIFIER_COMMIT/install.sh"

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
    echo "$JAR_SHA256  /opt/photonvision/photonvision.jar" | sha256sum -c --quiet ||
        die "photonvision.jar does not match the recorded SHA-256 of $PHOTON_VERSION's arm64 jar"
    echo "$PHOTON_VERSION installed by photon-image-modifier $MODIFIER_TAG" \
        > /opt/photonvision/romi-image-photon-version
fi
rm -rf "${work:?}"

log "PhotonVision complete"
