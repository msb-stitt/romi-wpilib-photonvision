#!/bin/bash
# record.sh IMAGE.img.xz DIR: the record diff.py reads, made from an image: files.txt by
# manifest.py, packages.txt as build.sh lists them, and romi-image-release, the image's
# /etc/romi-image-release. For an image built before build.sh wrote files.txt. Runs as root on
# Linux; the image's partitions are mounted read-only from a decompressed copy, deleted after.
set -euo pipefail

xz_image="${1:?usage: record.sh IMAGE.img.xz DIR}"
dir="${2:?usage: record.sh IMAGE.img.xz DIR}"
[[ $EUID -eq 0 ]] || { echo "record.sh runs as root" >&2; exit 1; }
work="$(mktemp -d /var/tmp/romi-record.XXXXXX)"
loop=""

cleanup() {
    umount "$work/root/boot/firmware" 2>/dev/null || true
    umount "$work/root" 2>/dev/null || true
    [[ -n "$loop" ]] && losetup -d "$loop"
    rm -rf "${work:?}"
}
trap cleanup EXIT

mkdir -p "$dir" "$work/root"
xz -dc -T0 "$xz_image" > "$work/image.img"
loop="$(losetup -P -r -f --show "$work/image.img")"
mount -o ro "${loop}p2" "$work/root"
mount -o ro "${loop}p1" "$work/root/boot/firmware"
python3 "$(dirname "$0")/manifest.py" "$work/root" > "$dir/files.txt"
dpkg-query --admindir="$work/root/var/lib/dpkg" -W -f='${binary:Package} ${Version}\n' \
    > "$dir/packages.txt"
cp "$work/root/etc/romi-image-release" "$dir/romi-image-release" 2>/dev/null ||
    echo "ROMI_IMAGE_DESCRIBE=unrecorded" > "$dir/romi-image-release"
echo "Recorded $(wc -l < "$dir/files.txt") entries and $(wc -l < "$dir/packages.txt") packages from $xz_image in $dir"
