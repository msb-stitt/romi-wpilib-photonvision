#!/bin/bash
# 05-cockpit.sh: Cockpit from Trixie's packages, without its recommended packages. The Romi
# page is added by a later stage.
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"
load_platform_profile

log "Cockpit from Trixie's packages"

install_packages cockpit-ws cockpit-system cockpit-bridge cockpit-networkmanager
run systemctl enable cockpit.socket

log "Cockpit complete"
