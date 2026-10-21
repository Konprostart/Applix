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
    for match in re.finditer(r'const val (\w+)\s*=\s*"([^"]+)"', text):
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


def replace_all_utf16(data: bytes, placeholder: str, replacement: str) -> bytes:
    """The same algorithm the injector uses (ApkInjector.replaceAllUtf16).

    The binary manifest stores every string with a two byte length prefix and
    a null terminator, so a replacement has to fix the prefix as well.
    """
    ph = placeholder.encode("utf-16-le")
    rep = replacement.encode("utf-16-le")
    if len(rep) > len(ph):
        raise ValueError(f"replacement '{replacement}' is longer than the placeholder")
    result = bytearray(data)
    search_from = 0
    while True:
        idx = result.find(ph, search_from)
        if idx == -1:
            break
        stored = int.from_bytes(result[idx - 2:idx], "little")
        after = idx + len(ph)
        exact = (
            stored == len(placeholder)
            and after + 1 < len(result)
            and result[after] == 0
            and result[after + 1] == 0
        )
        if not exact:
            search_from = idx + len(ph)
            continue
        result[idx - 2:idx] = len(replacement).to_bytes(2, "little")
        result[idx:idx + len(rep)] = rep
        result[idx + len(rep):idx + len(rep) + 2] = b"\x00\x00"
        search_from = idx + len(rep) + 2
    return bytes(result)


def parse_string_pool(manifest: bytes) -> list[str] | None:
    """Reads the string pool of a binary manifest (chunk type 0x0001)."""
    if len(manifest) < 36:
        return None
    # The binary manifest starts with the XML file header, the string pool
    # chunk follows right after it.
    base = 8
    chunk_type = int.from_bytes(manifest[base:base + 2], "little")
    if chunk_type != 0x0001:
        return None
    header_size = int.from_bytes(manifest[base + 2:base + 4], "little")
    string_count = int.from_bytes(manifest[base + 8:base + 12], "little")
    flags = int.from_bytes(manifest[base + 16:base + 18], "little")
    strings_start = int.from_bytes(manifest[base + 20:base + 24], "little")
    if flags & 0x100:  # UTF-8 strings
        return None
    strings: list[str] = []
    for i in range(string_count):
        offset = int.from_bytes(
            manifest[base + header_size + i * 4:base + header_size + i * 4 + 4], "little"
        )
        pos = base + strings_start + offset
        if pos + 2 > len(manifest):
            return None
        length = int.from_bytes(manifest[pos:pos + 2], "little")
        if length & 0x8000:  # the length is stored in two words
            length = ((length & 0x7FFF) << 16) | int.from_bytes(
                manifest[pos + 2:pos + 4], "little"
            )
            pos += 4
        else:
            pos += 2
        data = manifest[pos:pos + length * 2]
        try:
            strings.append(data.decode("utf-16-le"))
        except UnicodeDecodeError:
            return None
    return strings


def check_replacement(found: dict[str, str], template: Path) -> list[str]:
    """Patches the template exactly like the injector and checks the result.

    The order and the targets are the ones from ApkInjector.patchManifest.
    """
    manifest = template_manifest(template)
    if manifest is None:
        return [f"{template.name}: the manifest could not be read"]

    label = "Moj Radio"
    package = "com.applix.gen.radio.a1b2c3"
    targets = {
        "TEMPLATE_DYNPERM": package + ".DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION",
        "TEMPLATE_FIREBASE": package + ".firebaseinitprovider",
        "TEMPLATE_STARTUP": package + ".androidx-startup",
        "TEMPLATE_MLKIT": package + ".mlkitinitprovider",
        "TEMPLATE_AUTHORITY": package + ".provider",
        "TEMPLATE_PACKAGE": package,
        "LABEL_PLACEHOLDER": label,
    }
    problems: list[str] = []
    patched = manifest
    for name in [
        "TEMPLATE_DYNPERM",
        "TEMPLATE_FIREBASE",
        "TEMPLATE_STARTUP",
        "TEMPLATE_MLKIT",
        "TEMPLATE_AUTHORITY",
        "TEMPLATE_PACKAGE",
        "LABEL_PLACEHOLDER",
    ]:
        placeholder = found.get(name)
        if placeholder is None:
            problems.append(f"{template.name}: {name} is missing in the injector")
            continue
        try:
            patched = replace_all_utf16(patched, placeholder, targets[name])
        except ValueError as exc:
            problems.append(f"{template.name}: {exc}")
            return problems

    if label.encode("utf-16-le") not in patched:
        problems.append(f"{template.name}: the app name is not in the patched manifest")
    if found.get("LABEL_PLACEHOLDER", "").encode("utf-16-le") in patched:
        problems.append(f"{template.name}: the label placeholder survived the patch")
    if found.get("TEMPLATE_PACKAGE", "").encode("utf-16-le") in patched:
        problems.append(f"{template.name}: the template package survived the patch")
    if package.encode("utf-16-le") not in patched:
        problems.append(f"{template.name}: the new package is not in the patched manifest")

    # the string pool length of the new name
    idx = patched.find(label.encode("utf-16-le"))
    if idx > 1:
        stored = int.from_bytes(patched[idx - 2:idx], "little")
        if stored != len(label):
            problems.append(
                f"{template.name}: wrong string pool length for the app name "
                f"({stored} instead of {len(label)})"
            )

    # the patched manifest has to stay a valid manifest
    before = parse_string_pool(manifest)
    after = parse_string_pool(patched)
    if before is None or after is None:
        problems.append(f"{template.name}: the string pool could not be read")
    else:
        if len(before) != len(after):
            problems.append(
                f"{template.name}: the string pool lost strings "
                f"({len(before)} -> {len(after)})"
            )
        if label not in after:
            problems.append(f"{template.name}: the app name is not in the string pool")
        if package not in after:
            problems.append(f"{template.name}: the new package is not in the string pool")
        # The values that are built from the template package are replaced on
        # purpose, everything else has to survive the patch untouched.
        template_package = found.get("TEMPLATE_PACKAGE", "")
        for value in before:
            if value == found.get("LABEL_PLACEHOLDER"):
                continue
            if template_package and template_package in value:
                continue
            if value not in after:
                problems.append(
                    f"{template.name}: the string pool lost the value {value!r}"
                )
                break
    return problems


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

    for template, only in templates:
        if only is not None:
            continue
        problems.extend(check_replacement(found, template))

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
