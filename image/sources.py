#!/usr/bin/env python3
"""sources.py ROOT COMMIT: write SOURCES.md, the upstream source of what is in the image at ROOT.

Each Debian package installed is listed by its source package and version, linked to that source:
snapshot.debian.org for one from Debian's archive, Raspberry Pi's archive pool for one from
theirs. The archive is the one whose apt list, in the image, holds that package at that version,
or by its name alone when the list has moved on to a newer version; both archives keep the older
versions' source. Where both archives list it, it is Raspberry Pi's, which carries its own builds
of packages Debian also has, such as `linux` and `libcamera`.
PhotonVision, wpilibws-romi and this repository follow, at the versions the image records.
"""

import json
import sys
from pathlib import Path
from urllib.parse import quote

DEBIAN = "deb.debian.org"
RASPBERRY_PI = "archive.raspberrypi.com"


def paragraphs(text):
    """Yield each paragraph of a Debian control file as a dict of its fields."""
    fields, key = {}, None
    for line in text.splitlines():
        if not line.strip():
            if fields:
                yield fields
            fields, key = {}, None
        elif line[0] in " \t" and key:
            fields[key] += "\n" + line.strip()
        elif ":" in line:
            key, _, value = line.partition(":")
            fields[key] = value.strip()
    if fields:
        yield fields


def installed(status_text):
    """Return (binary, version, source, source_version) for each installed package."""
    for p in paragraphs(status_text):
        if not p.get("Status", "").endswith(" installed"):
            continue
        source, source_version = p["Package"], p["Version"]
        if "Source" in p:
            source, _, rest = p["Source"].partition(" ")
            if rest.startswith("(") and rest.endswith(")"):
                source_version = rest[1:-1]
        yield p["Package"], p["Version"], source, source_version


def origins(lists_dir):
    """Map (binary, version), and binary alone, to the archive hosts whose apt lists hold it."""
    found = {}
    for path in sorted(Path(lists_dir).glob("*_Packages")):
        host = path.name.split("_", 1)[0]
        for p in paragraphs(path.read_text(errors="replace")):
            found.setdefault((p.get("Package"), p.get("Version")), set()).add(host)
            found.setdefault(p.get("Package"), set()).add(host)
    return found


def pool_prefix(source):
    """Return the pool folder Debian's layout puts a source package in."""
    return source[:4] if source.startswith("lib") else source[0]


def source_link(host, source, version):
    """Return the URL of a source package's source in its archive, or None for an unknown one."""
    if host == DEBIAN:
        return f"https://snapshot.debian.org/package/{source}/{quote(version, safe='')}/"
    if host == RASPBERRY_PI:
        return f"https://{RASPBERRY_PI}/debian/pool/main/{pool_prefix(source)}/{source}/"
    return None


def debian_rows(root):
    """Return one Markdown table row per source package installed in the image."""
    status = (Path(root) / "var/lib/dpkg/status").read_text(errors="replace")
    where = origins(Path(root) / "var/lib/apt/lists")
    sources = {}
    for binary, version, source, source_version in installed(status):
        hosts = where.get((binary, version)) or where.get(binary.split(":")[0], set())
        entry = sources.setdefault((source, source_version), {"hosts": set()})
        entry["hosts"] |= hosts
    rows = []
    for (source, version), entry in sorted(sources.items()):
        host = next((h for h in (RASPBERRY_PI, DEBIAN) if h in entry["hosts"]), None)
        link = source_link(host, source, version)
        where_text = f"[{host}]({link})" if link else "not in the image's apt lists"
        rows.append(f"| `{source}` | `{version}` | {where_text} |")
    return rows


def first_line(path):
    """Return the first line of a file in the image, or None when it is missing."""
    try:
        return Path(path).read_text().splitlines()[0].strip()
    except (FileNotFoundError, IndexError):
        return None


def other_rows(root, commit):
    """Return the rows for what the image holds outside its Debian packages."""
    rows = []
    photon = first_line(Path(root) / "opt/photonvision/romi-image-photon-version")
    if photon:
        tag = photon.split()[0]
        rows.append(f"| PhotonVision | `{tag}` | "
                    f"https://github.com/PhotonVision/photonvision/tree/{tag} |")
    lock = Path(root) / "opt/wpilibws-romi/package-lock.json"
    if lock.exists():
        packages = json.loads(lock.read_text())["packages"]
        romi = packages.get("node_modules/@wpilib/wpilib-ws-robot-romi", {}).get("version")
        if romi:
            rows.append(f"| wpilibws-romi and the 32U4 firmware | `v{romi}` | "
                        f"https://github.com/wpilibsuite/wpilib-ws-robot-romi/tree/v{romi} |")
        rows.append(f"| wpilibws-romi's npm packages | {len(packages) - 1} packages | "
                    f"`image/files/wpilibws-romi/package-lock.json` at this repository's commit |")
    rows.append(f"| This image's build | `{commit}` | "
                f"https://github.com/msb-stitt/romi-wpilib-photonvision/tree/{commit} |")
    return rows


def main(root, commit):
    header = "| Source package | Version | Source |\n| --- | --- | --- |"
    print("# Sources\n")
    print("The upstream source of the programs in this image, at the versions it holds. A Debian")
    print("package's link goes to its source in Debian's snapshot archive, or to its folder in")
    print("Raspberry Pi's pool, which holds its source where Raspberry Pi publishes one.\n")
    print("## Outside the Debian packages\n")
    print("| Program | Version | Source |\n| --- | --- | --- |")
    print("\n".join(other_rows(root, commit)))
    print("\n## Debian packages\n")
    print(header)
    print("\n".join(debian_rows(root)))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: sources.py ROOT COMMIT")
    main(sys.argv[1], sys.argv[2])
