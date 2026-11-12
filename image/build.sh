#!/bin/bash
# build.sh: the platform profile's Raspberry Pi OS Trixie Lite image made into the Romi's, by
# running each stage in the image's root as a chroot. Runs as root on Linux; a host that is not
# arm64 needs qemu-user-static's binfmt for aarch64. With DRY_RUN=1, the default, it prints each
# command and runs none. The result is $OUT_DIR/romi-image.img.xz with image-metadata.json and
# packages.txt; the card holds the same record in /etc/romi-image-release and
# /etc/romi-image-packages.txt. RUNNER_IMAGE names the machine image the build ran on, if any.
set -euo pipefail

OUT_DIR="${OUT_DIR:-/var/tmp/romi-image}"
GROW_MB="${GROW_MB:-3072}"
if [[ "${DRY_RUN:-1}" == "1" ]]; then
    export BUILD_LOG="${BUILD_LOG:-/dev/null}"
else
    mkdir -p "$OUT_DIR"
    export BUILD_LOG="${BUILD_LOG:-$OUT_DIR/build.log}"
fi

source "$(dirname "$0")/lib/common.sh"
load_platform_profile

BASE="$OUT_DIR/$(basename "$BASE_IMG_URL")"
IMG="$OUT_DIR/romi-image.img"
ROOT="$OUT_DIR/root"
STAGE_DIR=/tmp/romi-image
COMMIT="$(git -C "$IMAGE_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
BUILD_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
RUNNER_IMAGE="${RUNNER_IMAGE:-not recorded}"
loop=""
mounts=()

log "Romi image from $(basename "$BASE_IMG_URL"), grown by $GROW_MB MB, in $OUT_DIR"

if [[ "$DRY_RUN" != "1" ]]; then
    [[ $EUID -eq 0 ]] || die "build.sh runs as root"
    if [[ "$(uname -m)" != "aarch64" && ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
        die "this host is $(uname -m) and has no binfmt for aarch64; install qemu-user-static"
    fi
fi

# mount_at ARGS... TARGET: mount, and remember TARGET to unmount it on exit.
mount_at() {
    run mount "$@"
    mounts+=("${!#}")
}

cleanup() {
    local i
    [[ "$DRY_RUN" == "1" ]] && return 0
    for ((i = ${#mounts[@]} - 1; i >= 0; i--)); do
        umount "${mounts[$i]}" || log "Could not unmount ${mounts[$i]}"
    done
    [[ -n "$loop" ]] && { losetup -d "$loop" || log "Could not detach $loop"; }
    return 0
}
trap cleanup EXIT

if [[ -f "$BASE" ]]; then
    log "Already downloaded: $BASE"
else
    run curl -fL -o "$BASE" "$BASE_IMG_URL"
fi
if [[ "$DRY_RUN" != "1" ]]; then
    echo "$BASE_IMG_SHA256  $BASE" | sha256sum -c --quiet || die "$BASE does not match its SHA-256"
fi

run bash -c "xz -dc '$BASE' > '$IMG'"
run truncate -s "+${GROW_MB}M" "$IMG"
run parted -s "$IMG" resizepart 2 100%

if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY-RUN] losetup -f --show -P $IMG"
    loop=/dev/loopN
else
    loop="$(losetup -f --show -P "$IMG")"
    log "Attached $IMG at $loop"
fi
run e2fsck -p -f "${loop}p2"
run resize2fs "${loop}p2"

run mkdir -p "$ROOT"
mount_at "${loop}p2" "$ROOT"
mount_at "${loop}p1" "$ROOT$BOOT_MOUNT"
for dir in /dev /dev/pts /proc /sys /etc/resolv.conf; do
    mount_at --bind "$dir" "$ROOT$dir"
done

run rm -rf "${ROOT:?}$STAGE_DIR"
run cp -a "$IMAGE_DIR" "$ROOT$STAGE_DIR"
for stage in "$IMAGE_DIR"/stages/[0-9]*.sh; do
    run chroot "$ROOT" env DRY_RUN=0 BUILD_LOG=/var/log/romi-image-build.log \
        bash "$STAGE_DIR/stages/$(basename "$stage")"
done
run chroot "$ROOT" apt-get clean
run rm -rf "${ROOT:?}$STAGE_DIR"

if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY-RUN] write $ROOT/etc/romi-image-release and the package list"
else
    cat > "$ROOT/etc/romi-image-release" <<EOF
ROMI_IMAGE_COMMIT=$COMMIT
ROMI_IMAGE_BUILD_DATE=$BUILD_DATE
ROMI_IMAGE_BASE=$(basename "$BASE_IMG_URL")
ROMI_IMAGE_RUNNER=$RUNNER_IMAGE
EOF
    chroot "$ROOT" dpkg-query -W -f='${binary:Package} ${Version}\n' > "$OUT_DIR/packages.txt"
    install -m 644 "$OUT_DIR/packages.txt" "$ROOT/etc/romi-image-packages.txt"
    log "Wrote $ROOT/etc/romi-image-release and $(wc -l < "$OUT_DIR/packages.txt") packages"
fi

cleanup
mounts=()
loop=""

run bash -c "xz -T0 -c '$IMG' > '$IMG.xz'"
if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY-RUN] write $OUT_DIR/image-metadata.json"
else
    cat > "$OUT_DIR/image-metadata.json" <<EOF
{
    "buildDate": "$BUILD_DATE",
    "commit": "$COMMIT",
    "runnerImage": "$RUNNER_IMAGE",
    "baseImage": "$(basename "$BASE_IMG_URL")",
    "baseImageSha256": "$BASE_IMG_SHA256",
    "imageSha256": "$(sha256sum "$IMG.xz" | cut -d' ' -f1)"
}
EOF
    log "Wrote $OUT_DIR/image-metadata.json"
fi

log "Romi image complete: $IMG.xz"
