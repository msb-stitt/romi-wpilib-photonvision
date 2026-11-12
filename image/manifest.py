#!/usr/bin/env python3
"""manifest.py ROOT: write files.txt, one line for each file, link and special file in the image at
ROOT, its boot partition included at /boot/firmware, sorted by path.

Each line is tab-separated: the path; the type, `f` file, `l` link or `o` other; the mode in
octal and the owner as `uid:gid`, each `-` on the boot partition; the file's SHA-256, the link's
target, or nothing; and the Debian package that owns the path by dpkg's lists, or `-`. The boot
partition is FAT, which stores no mode or owner: the mount makes them up from its options, so
they are not the image's. Directories are left out. So is anything on a file system other than
the root's and the boot partition's, such as the /dev, /proc and /sys a chroot binds in, and
their contents.
"""

import hashlib
import os
import stat
import sys
from pathlib import Path

# The directories Debian's merged /usr makes links into /usr; dpkg's lists name either form.
MERGED = ("bin", "sbin", "lib", "lib64")


def owners(root):
    """Map each path in dpkg's lists, in both its merged and unmerged form, to its package."""
    found = {}
    for listing in sorted((root / "var/lib/dpkg/info").glob("*.list")):
        package = listing.stem.split(":")[0]
        for line in listing.read_text(errors="replace").splitlines():
            path = line.strip()
            if not path or path == "/.":
                continue
            found.setdefault(path, package)
            parts = path.split("/", 2)
            if len(parts) > 2 and parts[1] in MERGED:
                found.setdefault("/usr" + path, package)
            elif path.startswith("/usr/") and path.split("/")[2] in MERGED:
                found.setdefault(path[len("/usr"):], package)
    return found


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def entries(root):
    """Yield (path, type, mode, owner, detail) for each entry under root, skipping directories."""
    root_device = root.stat().st_dev
    devices = {root_device}
    boot = root / "boot/firmware"
    if boot.is_dir():
        devices.add(boot.stat().st_dev)
    for top, dirs, files in os.walk(root):
        kept = []
        for name in sorted(dirs):
            full = os.path.join(top, name)
            st = os.lstat(full)
            if stat.S_ISLNK(st.st_mode):
                files.append(name)
            elif st.st_dev in devices:
                kept.append(name)
        dirs[:] = kept
        for name in files:
            full = os.path.join(top, name)
            st = os.lstat(full)
            if st.st_dev not in devices:
                continue
            path = "/" + os.path.relpath(full, root)
            if st.st_dev == root_device:
                mode, owner = f"{stat.S_IMODE(st.st_mode):o}", f"{st.st_uid}:{st.st_gid}"
            else:
                mode, owner = "-", "-"
            if stat.S_ISLNK(st.st_mode):
                yield path, "l", mode, owner, os.readlink(full)
            elif stat.S_ISREG(st.st_mode):
                yield path, "f", mode, owner, sha256(full)
            else:
                yield path, "o", mode, owner, ""


def main(root):
    root = Path(root)
    owned = owners(root)
    lines = [
        "\t".join((path, kind, mode, owner, detail, owned.get(path, "-")))
        for path, kind, mode, owner, detail in entries(root)
    ]
    for line in sorted(lines):
        print(line)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: manifest.py ROOT > files.txt")
    main(sys.argv[1])
