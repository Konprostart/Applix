#!/usr/bin/env python3
"""Generate the bridge method index for the static linter from SPEC.md.

The index is the allowlist used by lib/services/bridge_linter.dart. SPEC.md
remains the single source of truth; this script only extracts documented
calls and fails CI when the committed asset is stale.

Usage:
  python3 tools/gen_bridge_index.py           # rewrite the asset
  python3 tools/gen_bridge_index.py --check   # fail if the asset is stale
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC_PATH = ROOT / "SPEC.md"
OVERRIDES_PATH = ROOT / "tools" / "bridge_index_overrides.json"
OUTPUT_PATH = ROOT / "src" / "container_app" / "assets" / "bridge_index.json"

START_MARKER = "## Bridge reference"
END_MARKER = "## Native URI schemes"

BRIDGE = r"(?:window\.)?(?:iappyx|applix)"
MODULE_CALL = re.compile(BRIDGE + r"\.([A-Za-z_$][\w$]*)\.([A-Za-z_$][\w$]*)")
TOP_LEVEL_CALL = re.compile(BRIDGE + r"\.([A-Za-z_$][\w$]*)\s*\(")
PIPE_SHORTHAND = re.compile(r"\|\s*`?\.([A-Za-z_$][\w$]*)\s*\(")


def build_index() -> str:
    spec = SPEC_PATH.read_text(encoding="utf-8")
    start = spec.find(START_MARKER)
    if start < 0:
        raise SystemExit("SPEC.md: '## Bridge reference' section not found")
    end = spec.find(END_MARKER, start)
    body = spec[start : end if end > start else len(spec)]

    modules: dict[str, set[str]] = {}
    for match in MODULE_CALL.finditer(body):
        modules.setdefault(match.group(1), set()).add(match.group(2))

    top_level: set[str] = set()
    for match in TOP_LEVEL_CALL.finditer(body):
        name = match.group(1)
        if name not in modules:
            top_level.add(name)

    # Methods documented as `iappyx.module.method()` | `.otherMethod()`.
    context = None
    for line in body.splitlines():
        refs = MODULE_CALL.findall(line)
        if refs:
            context = refs[-1][0]
        if context:
            for match in PIPE_SHORTHAND.finditer(line):
                modules[context].add(match.group(1))

    if OVERRIDES_PATH.exists():
        overrides = json.loads(OVERRIDES_PATH.read_text(encoding="utf-8"))
        for module, methods in overrides.get("modules", {}).items():
            modules.setdefault(module, set()).update(methods)
        top_level.update(overrides.get("topLevel", []))

    data = {
        "version": 1,
        "source": "SPEC.md",
        "modules": {name: sorted(methods) for name, methods in sorted(modules.items())},
        "topLevel": sorted(top_level),
    }
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if the committed bridge index differs from SPEC.md",
    )
    args = parser.parse_args()

    expected = build_index()
    if args.check:
        actual = OUTPUT_PATH.read_text(encoding="utf-8") if OUTPUT_PATH.exists() else ""
        if actual != expected:
            print(
                f"{OUTPUT_PATH.relative_to(ROOT)} is out of date; "
                "run python3 tools/gen_bridge_index.py",
                file=sys.stderr,
            )
            return 1
        print(f"{OUTPUT_PATH.relative_to(ROOT)} is up to date")
        return 0

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(expected, encoding="utf-8")
    print(f"Wrote {OUTPUT_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
