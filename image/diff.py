#!/usr/bin/env python3
"""diff.py [--repo DIR] [--label-only] OLD NEW: what differs between two images, to show what a
card test of NEW has to cover.

OLD and NEW are each a directory holding an image's files.txt and packages.txt, as build.sh
writes them beside the image or record.sh makes them from it, and its image-metadata.json or
romi-image-release. The report gives, in order: this repository's changes to image/ and the
workflow between the two commits, by git in DIR; the packages added, removed or at another
version; and the files added, removed or changed, those a package owns by package and then those
no package owns.

With --label-only it exits 1 unless the one difference is /etc/romi-image-release, as when NEW is
OLD relabelled.
"""

import argparse
import json
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

LABEL = "/etc/romi-image-release"
FIELDS = ("type", "mode", "owner", "content")


def identity(directory):
    """Return (describe, commit) from image-metadata.json, or else romi-image-release."""
    metadata = directory / "image-metadata.json"
    if metadata.exists():
        data = json.loads(metadata.read_text())
        return data.get("describe", "unrecorded"), data.get("commit", "unrecorded")
    values = {}
    release = directory / "romi-image-release"
    if release.exists():
        for line in release.read_text().splitlines():
            key, _, value = line.partition("=")
            values[key] = value
    return values.get("ROMI_IMAGE_DESCRIBE", "unrecorded"), values.get("ROMI_IMAGE_COMMIT", "unrecorded")


def files(directory):
    """Map each path in files.txt to its (type, mode, owner, content) and owning package."""
    found = {}
    for line in (directory / "files.txt").read_text().splitlines():
        path, kind, mode, owner, content, package = line.split("\t")
        found[path] = ((kind, mode, owner, content), package)
    return found


def packages(directory):
    found = {}
    for line in (directory / "packages.txt").read_text().splitlines():
        name, _, version = line.partition(" ")
        found[name] = version
    return found


def file_changes(old, new):
    """Yield (path, package, what) for each path added, removed or changed."""
    for path in sorted(old.keys() | new.keys()):
        if path not in old:
            yield path, new[path][1], "added"
        elif path not in new:
            yield path, old[path][1], "removed"
        elif old[path][0] != new[path][0]:
            changed = [f for f, a, b in zip(FIELDS, old[path][0], new[path][0]) if a != b]
            yield path, new[path][1], ", ".join(changed)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", type=Path, help="this repository, for git's diff of image/")
    parser.add_argument("--label-only", action="store_true")
    parser.add_argument("old", type=Path)
    parser.add_argument("new", type=Path)
    args = parser.parse_args()

    old_id, new_id = identity(args.old), identity(args.new)
    print(f"Old: {old_id[0]} at {old_id[1]}")
    print(f"New: {new_id[0]} at {new_id[1]}")

    print("\n## This repository's changes to image/ and the workflow")
    if "unrecorded" in (old_id[1], new_id[1]):
        print("Not read: both images must record their commit.")
    elif old_id[1] == new_id[1]:
        print("None: the same commit.")
    elif args.repo:
        stat = subprocess.run(
            ["git", "-C", str(args.repo), "diff", "--stat", old_id[1], new_id[1], "--",
             "image", ".github/workflows/image.yml"],
            check=True, capture_output=True, text=True).stdout
        print(stat.rstrip() or "None.")
    else:
        print("Not read: give --repo.")

    old_packages, new_packages = packages(args.old), packages(args.new)
    package_lines = []
    for name in sorted(old_packages.keys() | new_packages.keys()):
        a, b = old_packages.get(name), new_packages.get(name)
        if a != b:
            package_lines.append(f"{name}: {a or 'not installed'} -> {b or 'not installed'}")
    print("\n## Packages added, removed or at another version")
    print("\n".join(package_lines) if package_lines else "None.")

    changes = list(file_changes(files(args.old), files(args.new)))
    by_package = defaultdict(list)
    for path, package, what in changes:
        by_package[package].append(f"{path}: {what}")
    print("\n## Files changed, by the package that owns them")
    owned = sorted(p for p in by_package if p != "-")
    for package in owned:
        print(f"{package}:")
        for line in by_package[package]:
            print(f"    {line}")
    if not owned:
        print("None.")
    print("\n## Files changed that no package owns")
    print("\n".join(by_package["-"]) if by_package["-"] else "None.")

    if args.label_only:
        if package_lines or [path for path, _, _ in changes] != [LABEL]:
            print(f"\nNOT only the label: more differs than {LABEL}")
            return 1
        print(f"\nOnly the label differs: {LABEL}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
