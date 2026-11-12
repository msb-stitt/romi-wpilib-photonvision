#!/bin/bash
# relabel.sh CANDIDATE_DIR TAG OUT_DIR: a release made from a tested release candidate's image
# without building again. CANDIDATE_DIR holds the candidate's release files: its image,
# image-metadata.json, packages.txt and SOURCES.md. The image is checked against the metadata's
# imageSha256; in a copy, only /etc/romi-image-release changes, its ROMI_IMAGE_DESCRIBE set to TAG
# and ROMI_IMAGE_RELABELLED_FROM added. OUT_DIR gets romi-image-TAG.img.xz, files.txt of the
# relabelled image, the candidate's packages.txt and SOURCES.md, and image-metadata.json naming the
# candidate in relabelledFrom. Runs as root on Linux.
set -euo pipefail

candidate="${1:?usage: relabel.sh CANDIDATE_DIR TAG OUT_DIR}"
tag="${2:?usage: relabel.sh CANDIDATE_DIR TAG OUT_DIR}"
out="${3:?usage: relabel.sh CANDIDATE_DIR TAG OUT_DIR}"
[[ $EUID -eq 0 ]] || { echo "relabel.sh runs as root" >&2; exit 1; }

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { log "ERROR: $*"; exit 1; }

meta="$candidate/image-metadata.json"
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$meta" "$1"; }
from="$(field describe)"
from_image="$(field image)"
from_sha="$(field imageSha256)"
[[ "$from" == *-rc* && "$from" != *-dirty ]] || die "$from is not a release candidate's tag"
echo "$from_sha  $candidate/$from_image" | sha256sum -c --quiet ||
    die "$from_image does not match its imageSha256"
log "Relabelling $from_image, $from, as $tag"

mkdir -p "$out"
img="$out/romi-image-$tag.img"
root="$(mktemp -d /var/tmp/romi-relabel.XXXXXX)"
loop=""
cleanup() {
    umount "$root/boot/firmware" 2>/dev/null || true
    umount "$root" 2>/dev/null || true
    [[ -n "$loop" ]] && losetup -d "$loop"
    rmdir "$root" 2>/dev/null || true
}
trap cleanup EXIT

xz -dc -T0 "$candidate/$from_image" > "$img"
loop="$(losetup -P -f --show "$img")"
mount "${loop}p2" "$root"
release="$root/etc/romi-image-release"
grep -q "^ROMI_IMAGE_DESCRIBE=$from\$" "$release" || die "$release does not name $from"
sed -i "s/^ROMI_IMAGE_DESCRIBE=.*/ROMI_IMAGE_DESCRIBE=$tag/" "$release"
echo "ROMI_IMAGE_RELABELLED_FROM=$from" >> "$release"
umount "$root"
mount -o ro "${loop}p2" "$root"
mount -o ro "${loop}p1" "$root/boot/firmware"
python3 "$(dirname "$0")/manifest.py" "$root" > "$out/files.txt"
umount "$root/boot/firmware"
umount "$root"
losetup -d "$loop"
loop=""

xz -T0 -c "$img" > "$img.xz"
rm -f "$img"
cp "$candidate/packages.txt" "$candidate/SOURCES.md" "$out/"
python3 - "$meta" "$out/image-metadata.json" "$tag" "$(basename "$img.xz")" \
    "$(sha256sum "$img.xz" | cut -d' ' -f1)" <<'EOF'
import json, sys
meta_in, meta_out, tag, image, sha = sys.argv[1:]
data = json.load(open(meta_in))
data["relabelledFrom"] = {"describe": data["describe"], "image": data["image"],
                          "imageSha256": data["imageSha256"]}
data.update(describe=tag, image=image, imageSha256=sha)
json.dump(data, open(meta_out, "w"), indent=4)
print(file=open(meta_out, "a"))
EOF
log "Relabelled: $img.xz"
