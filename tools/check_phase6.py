#!/usr/bin/env python3
"""Static guard for Phase 6: updates without full rewrites and runtime checks.

Fails when:
  * the prompt no longer documents the targeted patch format
  * follow-ups stopped asking for / applying patches
  * the preview stopped injecting the runtime probe before app code
  * the build gate stopped checking the runtime report
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROMPT = ROOT / "src/container_app/assets/system_prompt.md"
SPEC = ROOT / "SPEC.md"
CREATE = ROOT / "src/container_app/lib/screens/create_screen.dart"
PREVIEW = ROOT / "src/container_app/lib/screens/preview_screen.dart"
PATCH = ROOT / "src/container_app/lib/services/app_patch.dart"
PROBE = ROOT / "src/container_app/lib/services/runtime_probe.dart"
PATCH_TEST = ROOT / "src/container_app/test/app_patch_test.dart"
PROBE_TEST = ROOT / "src/container_app/test/runtime_probe_test.dart"

errors: list[str] = []


def read(path: Path, label: str) -> str:
    if not path.exists():
        errors.append(f"missing {label}: {path.relative_to(ROOT)}")
        return ""
    return path.read_text(encoding="utf-8")


prompt = read(PROMPT, "system prompt")
spec = read(SPEC, "SPEC.md")
create = read(CREATE, "create screen")
preview = read(PREVIEW, "preview screen")
patch = read(PATCH, "AppPatch service")
probe = read(PROBE, "RuntimeProbe service")
read(PATCH_TEST, "AppPatch tests")
read(PROBE_TEST, "RuntimeProbe tests")

if spec != prompt:
    errors.append("SPEC.md is out of sync with assets/system_prompt.md")

for needle in ("## Targeted updates (PATCH MODE)", '"applix_patch":1',
               '"op":"replace"', '"op":"insert_after"', '"op":"delete"'):
    if needle not in prompt:
        errors.append(f"system_prompt.md is missing {needle!r}")

for needle in ("class AppPatch", "applyToProject", "applyToHtml",
               "occur once", "maxEdits"):
    if needle not in patch:
        errors.append(f"app_patch.dart is missing {needle!r}")

for needle in ("class RuntimeReport", "fatalErrors", "blank", "bootstrap",
               "window.__applixRuntime", "unhandledrejection"):
    if needle not in probe:
        errors.append(f"runtime_probe.dart is missing {needle!r}")

for needle in ("RuntimeProbe.bootstrap", "verifyOnly", "_checkRuntime",
               "RuntimeReport.parse"):
    if needle not in preview:
        errors.append(f"preview_screen.dart is missing {needle!r}")

for needle in ("AppPatch.applyToProject", "AppPatch.instruction",
               "_runRuntimeCheck", "_showRuntimeFailure", "report.fatal"):
    if needle not in create:
        errors.append(f"create_screen.dart is missing {needle!r}")

# The old duplicate output-shape paragraph must stay gone.
if prompt.count("This also applies when updating or polishing") != 1:
    errors.append("system_prompt.md has a duplicated update paragraph")

if errors:
    for error in errors:
        print(f"ERROR: {error}")
    sys.exit(1)
print("Phase 6 checks passed.")
