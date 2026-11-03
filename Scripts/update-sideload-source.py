#!/usr/bin/env python3
"""Adds a release to the SideStore/AltStore source file.

Run from the release step, after packaging the .ipa:

    Scripts/update-sideload-source.py --ipa Omnia-0.3.5-iPhone-iPad.ipa --notes notes.md

Updates store.json at the repository root. Everything about the version is read from the
.ipa itself. Commit and push the result after the release is published, so
SideStore never offers a version whose download isn't there yet.
"""
import argparse
import datetime
import hashlib
import json
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_FOLDER = ROOT / "altstore"
# Every signed app has these; they say nothing about what the app can do.
ROUTINE_ENTITLEMENTS = {
    "application-identifier",
    "com.apple.developer.team-identifier",
    "get-task-allow",
    "keychain-access-groups",
}


def read_ipa(path):
    with zipfile.ZipFile(path) as archive:
        name = next(n for n in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n))
        info = plistlib.loads(archive.read(name))
        with tempfile.TemporaryDirectory() as folder:
            archive.extractall(folder, [n for n in archive.namelist() if n.startswith(name.rsplit("/", 1)[0])])
            signed = subprocess.run(
                ["codesign", "-d", "--entitlements", "-", "--xml", str(Path(folder) / name.rsplit("/", 1)[0])],
                capture_output=True, check=True,
            ).stdout
    entitlements = plistlib.loads(signed) if signed.strip() else {}
    return info, sorted(set(entitlements) - ROUTINE_ENTITLEMENTS)


def user_facing_notes(text):
    """The notes without their Downloads and Versions sections or Markdown marks."""
    kept = re.split(r"^## (?:Downloads|Versions)\s*$", text, flags=re.M)[0]
    return re.sub(r"\*\*|^## ", "", kept, flags=re.M).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--ipa", type=Path, required=True)
    parser.add_argument("--notes", type=Path, required=True)
    parser.add_argument("--repo", default="Laviora/Omnia")
    parser.add_argument("--branch", default="main")
    args = parser.parse_args()

    info, entitlements = read_ipa(args.ipa)
    version = info["CFBundleShortVersionString"]
    raw = f"https://raw.githubusercontent.com/{args.repo}/{args.branch}"

    source_file = ROOT / "store.json"
    template = (SOURCE_FOLDER / "store.template.json").read_text().replace("{{RAW}}", raw)
    source = json.loads(source_file.read_text() if source_file.exists() else template)
    app = source["apps"][0]
    if app["bundleIdentifier"] != info["CFBundleIdentifier"]:
        sys.exit(f"This .ipa is {info['CFBundleIdentifier']}, not {app['bundleIdentifier']}.")

    data = args.ipa.read_bytes()
    entry = {
        "version": version,
        "buildVersion": info["CFBundleVersion"],
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "localizedDescription": user_facing_notes(args.notes.read_text()),
        "downloadURL": f"https://github.com/{args.repo}/releases/download/v{version}/{args.ipa.name}",
        "size": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "minOSVersion": info["MinimumOSVersion"],
    }
    # Newest first. Running again for a version replaces its entry.
    app["versions"] = [entry] + [v for v in app["versions"] if v["version"] != version]
    app["appPermissions"] = {
        "entitlements": entitlements,
        "privacy": {k: v for k, v in info.items() if k.endswith("UsageDescription")},
    }

    source_file.write_text(json.dumps(source, indent=2, ensure_ascii=False) + "\n")
    print(f"Added Omnia {version} ({entry['buildVersion']}) to {source_file}")


if __name__ == "__main__":
    main()
