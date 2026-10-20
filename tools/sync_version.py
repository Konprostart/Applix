#!/usr/bin/env python3
"""Keep every version reference in the repo in sync with the VERSION file.

VERSION holds "<major>.<minor>.<patch>" (e.g. "0.1.10") and is the single
source of truth for the whole project.

The Android version code is derived from that semantic version
(major * 100000000 + minor * 100000 + patch) so it always grows - Android
refuses an update with a lower version code.

Synced targets:
  * src/container_app/pubspec.yaml     -> version: X.Y.Z+N  (drives Android versionCode/versionName)
  * src/shell_apk/app/build.gradle     -> versionCode N / versionName "X.Y.Z"
  * src/shell_apk_web/app/build.gradle -> versionCode N / versionName "X.Y.Z"
  * src/container_app/lib/version.dart -> generated constants (kAppVersion, kAppBuildNumber)

Usage:
  python3 tools/sync_version.py          # write changes
  python3 tools/sync_version.py --check  # exit 1 if anything is out of sync
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSION_FILE = ROOT / "VERSION"
PUBSPEC = ROOT / "src/container_app/pubspec.yaml"
GRADLE_FILES = (
    ROOT / "src/shell_apk/app/build.gradle",
    ROOT / "src/shell_apk_web/app/build.gradle",
)
VERSION_DART = ROOT / "src/container_app/lib/version.dart"

SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$")


def version_code(major: int, minor: int, patch: int) -> int:
    """The Android version code for a semantic version (always growing)."""
    return major * 100000000 + minor * 100000 + patch


def read_version() -> tuple[str, int]:
    """Returns the semantic version and the matching Android version code."""
    if not VERSION_FILE.exists():
        sys.exit(f"ERROR: missing {VERSION_FILE}")
    raw = VERSION_FILE.read_text(encoding="utf-8").strip()
    match = SEMVER_RE.match(raw)
    if not match:
        sys.exit(f"ERROR: invalid VERSION '{raw}' (expected <major>.<minor>.<patch>)")
    major, minor, patch, _build = match.groups()
    return f"{major}.{minor}.{patch}", version_code(int(major), int(minor), int(patch))


def sync_pubspec(text: str, version: str) -> str:
    new_text, count = re.subn(r"(?m)^version:[^\n]*$", f"version: {version}", text, count=1)
    if count == 0:
        sys.exit("ERROR: no 'version:' line found in src/container_app/pubspec.yaml")
    return new_text


def sync_gradle(text: str, name: str, build: int) -> str:
    new_text, code_count = re.subn(
        r"(?m)^([ \t]*)versionCode[ \t]+\d+[ \t]*$",
        rf"\g<1>versionCode {build}",
        text,
        count=1,
    )
    new_text, name_count = re.subn(
        r'(?m)^([ \t]*)versionName[ \t]+"[^"]*"[ \t]*$',
        rf'\g<1>versionName "{name}"',
        new_text,
        count=1,
    )
    if code_count == 0 or name_count == 0:
        sys.exit("ERROR: versionCode/versionName not found in gradle file")
    return new_text


def version_dart(name: str, build: int) -> str:
    return (
        "// GENERATED FILE - do not edit by hand.\n"
        "// Regenerate with: python3 tools/sync_version.py\n"
        "\n"
        f"const String kAppVersion = '{name}';\n"
        f"const int kAppVersionCode = {build};\n"
    )


def released_versions() -> list[tuple[int, int, int, str]]:
    """The semantic versions of the existing release tags (newest last)."""
    import subprocess

    try:
        out = subprocess.run(
            ["git", "tag", "-l", "v*"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=20,
        ).stdout
    except Exception:
        return []
    found = []
    for tag in out.split():
        match = SEMVER_RE.match(tag.lstrip("v"))
        if match:
            major, minor, patch, _build = match.groups()
            found.append((int(major), int(minor), int(patch), tag))
    found.sort()
    return found


def main() -> int:
    check = "--check" in sys.argv[1:]
    name, build = read_version()
    version = name

    # A release may never be lower than a version that is already published:
    # Android would refuse the update with "App not installed".
    released = released_versions()
    if released:
        newest = released[-1]
        current = tuple(int(x) for x in name.split("."))
        if current < newest[:3]:
            print(
                f"ERROR: version {name} is older than the released {newest[3]} - "
                "Android refuses an update with a lower version code",
                file=sys.stderr,
            )
            return 1

    targets: list[tuple[Path, str]] = []
    targets.append((PUBSPEC, sync_pubspec(PUBSPEC.read_text(encoding="utf-8"), version)))
    for gradle in GRADLE_FILES:
        targets.append((gradle, sync_gradle(gradle.read_text(encoding="utf-8"), name, build)))
    targets.append((VERSION_DART, version_dart(name, build)))

    changed: list[Path] = []
    for path, expected in targets:
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current == expected:
            continue
        changed.append(path)
        if not check:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(expected, encoding="utf-8")
            print(f"updated: {path.relative_to(ROOT)}")

    if check and changed:
        print("ERROR: version metadata is out of sync:", file=sys.stderr)
        for path in changed:
            print(f"  - {path.relative_to(ROOT)}", file=sys.stderr)
        print("Fix with: python3 tools/sync_version.py", file=sys.stderr)
        return 1
    if check:
        print("version metadata is up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main())
