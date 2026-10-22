#!/usr/bin/env python3
"""Static guard for the shared UI kit (Phase 3).

Fails when the kit drifts from what the prompt promises or stops being shipped
into built apps:
  * assets/applix-ui.css and assets/applix-ui.js exist and are non-trivial
  * the CSS defines the documented components (tabs, bottom nav, tables, ...)
  * the JS is a self-contained ES module exporting the documented functions
  * pubspec.yaml bundles both files
  * AppGenerator reads both and adds them to the app root
  * system_prompt.md documents the module and the imports
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CSS = ROOT / "src/container_app/assets/applix-ui.css"
JS = ROOT / "src/container_app/assets/applix-ui.js"
PROMPT = ROOT / "src/container_app/assets/system_prompt.md"
PUBSPEC = ROOT / "src/container_app/pubspec.yaml"
GENERATOR = ROOT / "src/container_app/android/app/src/main/kotlin/com/konprostart/applix/AppGenerator.kt"

REQUIRED_CSS = [
    ".ax-tabs", ".ax-tab--active", ".ax-bottom-nav", ".ax-bottom-nav__item--active",
    ".ax-segmented", ".ax-segmented__item--active", ".ax-table", ".ax-num",
    ".ax-sheet__title", ".ax-sheet__body", ".ax-sheet__actions",
    ".ax-toast__action", ".ax-anim-in", ".ax-press", "prefers-reduced-motion",
    ".ax-icon", ".ax-icon-btn", ".ax-select", ".ax-check", ".ax-radio",
    ".ax-search", ".ax-stepper", ".ax-chart__bars", ".ax-bar", ".ax-sparkline",
    ".ax-donut", ".ax-stat-row",
]
REQUIRED_JS = [
    "UI_KIT_VERSION", "toast", "openSheet", "confirmDialog",
    "mountTabs", "mountBottomNav", "mountSegmented", "stagger",
    "icon", "mountIcons", "sparkline", "barChart", "donut",
]

errors: list[str] = []


def read(path: Path, label: str) -> str:
    if not path.exists():
        errors.append(f"missing {label}: {path.relative_to(ROOT)}")
        return ""
    text = path.read_text(encoding="utf-8")
    if len(text.strip()) < 200:
        errors.append(f"{label} looks empty: {path.relative_to(ROOT)}")
    return text


css = read(CSS, "UI kit CSS")
js = read(JS, "UI kit JS")
prompt = read(PROMPT, "system prompt")
pubspec = read(PUBSPEC, "pubspec")
generator = read(GENERATOR, "AppGenerator.kt")

for selector in REQUIRED_CSS:
    if selector not in css:
        errors.append(f"CSS is missing {selector}")

if "tabular-nums" not in css:
    errors.append("CSS tables must use tabular numbers")

if not re.search(r"^\s*const\s+UI_KIT_VERSION\s*=", js, re.M):
    errors.append("JS must declare UI_KIT_VERSION")
if re.search(r"\bexport\b", js):
    errors.append("JS must not contain the word 'export' (it is a classic script)")
for name in REQUIRED_JS[1:]:
    if not re.search(rf"^\s*function\s+{name}\s*\(", js, re.M):
        errors.append(f"JS must define function {name}()")
    if f"window.AppliX" not in js or name not in js:
        errors.append(f"JS must expose {name} on window")
if re.search(r"^\s*import\s", js, re.M) or "require(" in js:
    errors.append("UI kit JS must stay dependency-free (no import/require)")
if "addEventListener" not in js or "document.createElement" not in js:
    errors.append("UI kit JS does not look like a DOM module")

for asset in ("assets/applix-ui.css", "assets/applix-ui.js"):
    if asset not in pubspec:
        errors.append(f"pubspec.yaml does not bundle {asset}")

if 'flutter_assets/assets/applix-ui.css' not in generator:
    errors.append("AppGenerator does not read the UI kit CSS from the asset bundle")
if 'flutter_assets/assets/applix-ui.js' not in generator:
    errors.append("AppGenerator does not read the UI kit JS from the asset bundle")
if len(re.findall(r"\baddUiKitFiles\(assets\)", generator)) < 2:
    errors.append("AppGenerator must add the UI kit files to both asset builders")
if 'assets["applix-ui.js"]' not in generator:
    errors.append("AppGenerator does not ship applix-ui.js next to index.html")

for needle in ("applix-ui.js", "applix-ui.css", "mountBottomNav", "mountTabs",
               "confirmDialog", "stagger", "sparkline", "barChart", "donut",
               "mountIcons", ".ax-select"):
    if needle not in prompt:
        errors.append(f"system_prompt.md does not document {needle}")

if errors:
    print("UI kit check failed:", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    sys.exit(1)

print(f"UI kit OK: {len(REQUIRED_CSS)} CSS components, {len(REQUIRED_JS)} JS exports")
