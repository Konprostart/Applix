#!/usr/bin/env python3
"""Checks that the placeholders the injector replaces exist in the shell template.

The generated APK is built from the shell template: the injector replaces the
package name, the app label and the provider/permission names inside the
binary manifest of the template. If a placeholder in the injector does not
match the one in the template, the replacement silently does nothing - the app
keeps the placeholder as its name or shares the package with the shell.

The check reads the built shell template (the binary manifest inside the APK),
because that is the file the injector actually patches.

Run: python3 tools/check_placeholders.py
"""
from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INJECTOR = ROOT / "src/container_app/android/app/src/main/kotlin/com/konprostart/applix/ApkInjector.kt"
# The full shell carries the providers and permissions, the web shell is a
# minimal WebView app - it only needs the package and the label.
TEMPLATES = [
    (ROOT / "src/container_app/assets/shell_template.apk", None),
    (ROOT / "src/container_app/assets/shell_template_web.apk",
     {"LABEL_PLACEHOLDER", "TEMPLATE_PACKAGE"}),
]


def placeholders() -> dict[str, str]:
    text = INJECTOR.read_text(encoding="utf-8")
    found: dict[str, str] = {}
    for match in re.finditer(r'private const val (\w+)\s*=\s*"([^"]+)"', text):
        name, value = match.group(1), match.group(2)
        if "TEMPLATE" in name or "LABEL" in name:
            found[name] = value
    return found


def template_manifest(path: Path) -> bytes | None:
    try:
        with zipfile.ZipFile(path) as apk:
            return apk.read("AndroidManifest.xml")
    except (OSError, KeyError, zipfile.BadZipFile):
        return None


def main() -> int:
    found = placeholders()
    if not found:
        print("ERROR: no placeholders found in the injector", file=sys.stderr)
        return 1

    templates = [(p, only) for p, only in TEMPLATES if p.exists()]
    if not templates:
        print("ERROR: no built shell template found - build the shell first", file=sys.stderr)
        return 1

    problems: list[str] = []
    for template, only in templates:
        manifest = template_manifest(template)
        if manifest is None:
            problems.append(f"{template.name}: the manifest could not be read")
            continue
        for name, value in sorted(found.items()):
            if only is not None and name not in only:
                continue
            if value.encode("utf-16-le") not in manifest:
                problems.append(f"{template.name}: {name} = {value}  (not in the template)")

    if problems:
        print("ERROR: the injector and the shell template do not match:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print(
            "\nThe shell template is what the generated APK is built from - every "
            "placeholder has to exist there, otherwise the replacement is skipped "
            "and the app keeps a placeholder name or shares the shell package.",
            file=sys.stderr,
        )
        return 1

    print(f"all {len(found)} placeholders match the shell template")
    return 0


if __name__ == "__main__":
    sys.exit(main())
