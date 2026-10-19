#!/usr/bin/env python3
"""Validate and extract sections from CHANGELOG.md.

Usage:
  python3 tools/changelog.py --check [--version X.Y.Z]
  python3 tools/changelog.py --extract X.Y.Z
  python3 tools/changelog.py --list

--check    requires an "## [Unreleased]" section plus a non-empty section for the
           given version (defaults to the version in the VERSION file)
--extract  prints the body of a version section (used as GitHub release notes)
--list     prints the version headings in document order
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHANGELOG = ROOT / "CHANGELOG.md"
VERSION_FILE = ROOT / "VERSION"
HEADING_RE = re.compile(r"(?m)^## \[([^\]]+)\][^\n]*$")


def read_changelog() -> str:
    if not CHANGELOG.exists():
        sys.exit(f"ERROR: missing {CHANGELOG}")
    return CHANGELOG.read_text(encoding="utf-8")


def read_default_version() -> str:
    if not VERSION_FILE.exists():
        sys.exit(f"ERROR: missing {VERSION_FILE}")
    raw = VERSION_FILE.read_text(encoding="utf-8").strip()
    return raw.split("+")[0]


def sections(text: str) -> list[tuple[str, str]]:
    matches = list(HEADING_RE.finditer(text))
    result: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        result.append((match.group(1), text[start:end].strip("\n")))
    return result


def main() -> int:
    args = sys.argv[1:]
    text = read_changelog()
    parsed = sections(text)

    if "--list" in args:
        for name, _ in parsed:
            print(name)
        return 0

    if "--extract" in args:
        index = args.index("--extract")
        if index + 1 >= len(args):
            sys.exit("ERROR: --extract requires a version argument")
        wanted = args[index + 1]
        for name, body in parsed:
            if name == wanted:
                print(body.strip())
                return 0
        print(f"ERROR: no CHANGELOG section for version {wanted}", file=sys.stderr)
        return 1

    version = None
    if "--version" in args:
        index = args.index("--version")
        if index + 1 >= len(args):
            sys.exit("ERROR: --version requires an argument")
        version = args[index + 1]
    else:
        version = read_default_version()

    problems: list[str] = []
    names = [name for name, _ in parsed]
    if "Unreleased" not in names:
        problems.append("missing '## [Unreleased]' section")
    if version not in names:
        problems.append(f"missing '## [{version}]' section")
    else:
        body = dict(parsed)[version].strip()
        if not body:
            problems.append(f"section '## [{version}]' is empty")

    if problems:
        print("ERROR: CHANGELOG.md is not release-ready:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    print(f"CHANGELOG.md documents {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
