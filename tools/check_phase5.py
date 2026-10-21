#!/usr/bin/env python3
"""Static guard for Phase 5: generation quality layer.

Fails when the pieces that make generated apps feel finished drift apart:
  * the prompt keeps one design truth (no legacy palette, no -apple-system)
  * the prompt documents seeding, wiring, charts, icons and the APP PLAN
  * the planner prompt is bundled and the app parses/uses the plan
  * in-app API generation sends the design contract + plan (not just a name)
  * the UI kit ships v2 icons/forms/charts
  * the starter apps are themed with kit tokens and realistic seed data
  * SPEC.md stays identical to the shipped system prompt
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROMPT = ROOT / "src/container_app/assets/system_prompt.md"
SPEC = ROOT / "SPEC.md"
PLANNER = ROOT / "src/container_app/assets/planner_prompt.md"
PUBSPEC = ROOT / "src/container_app/pubspec.yaml"
PLAN_DART = ROOT / "src/container_app/lib/services/app_plan.dart"
BUILDER = ROOT / "src/container_app/lib/services/prompt_builder.dart"
CREATE = ROOT / "src/container_app/lib/screens/create_screen.dart"
PRESETS = ROOT / "src/container_app/lib/services/settings_service.dart"
KIT_CSS = ROOT / "src/container_app/assets/applix-ui.css"
KIT_JS = ROOT / "src/container_app/assets/applix-ui.js"
STARTERS = ROOT / "src/container_app/assets/starters"

errors: list[str] = []


def read(path: Path, label: str) -> str:
    if not path.exists():
        errors.append(f"missing {label}: {path.relative_to(ROOT)}")
        return ""
    return path.read_text(encoding="utf-8")


prompt = read(PROMPT, "system prompt")
spec = read(SPEC, "SPEC.md")
planner = read(PLANNER, "planner prompt")
pubspec = read(PUBSPEC, "pubspec")
plan_dart = read(PLAN_DART, "AppPlan service")
builder = read(BUILDER, "PromptBuilder")
create = read(CREATE, "create screen")
presets = read(PRESETS, "style presets")
kit_css = read(KIT_CSS, "UI kit CSS")
kit_js = read(KIT_JS, "UI kit JS")

# Prompt: one design truth and the quality bar.
for needle in ("## Quality bar", "## App plan", "APP PLAN", "Seed data",
               "Every control is wired", "Never hardcode", "system-ui, Roboto"):
    if needle not in prompt:
        errors.append(f"system_prompt.md is missing {needle!r}")
for legacy in ("-apple-system", "#0d0d1a", "#1a1a2e", "#0f3460", "#4FC3F7",
               "most apps should stay one file", "Max-width 600px"):
    if legacy in prompt:
        errors.append(f"system_prompt.md still contains legacy truth {legacy!r}")
for needle in ("sparkline", "barChart", "donut", "mountIcons", "ax-select",
               "multi-file project"):
    if needle not in prompt:
        errors.append(f"system_prompt.md does not teach {needle!r}")

# SPEC is the canonical public copy.
if spec != prompt:
    errors.append("SPEC.md is out of sync with assets/system_prompt.md")

# Planner prompt + Dart model.
for needle in ("screens", "entities", "acceptance", "seed", "persistence",
               "Return ONLY one JSON object"):
    if needle not in planner:
        errors.append(f"planner_prompt.md is missing {needle!r}")
if "assets/planner_prompt.md" not in pubspec:
    errors.append("pubspec.yaml does not bundle assets/planner_prompt.md")
for needle in ("class AppPlan", "static AppPlan? parse", "toPromptBlock",
               "maxChars", "maxScreens"):
    if needle not in plan_dart:
        errors.append(f"app_plan.dart is missing {needle!r}")

# PromptBuilder: planner + request without duplicating the system prompt.
for needle in ("getPlannerPrompt", "buildPlannerRequest", "buildRequest",
               "plan.toPromptBlock()", "AppPlan? plan"):
    if needle not in builder:
        errors.append(f"prompt_builder.dart is missing {needle!r}")

# create_screen must plan first, then send the contract (not just a title).
for needle in ("AppPlan.parse", "buildPlannerRequest", "buildRequest(",
               "plan: plan", "PromptBuilder.getPlannerPrompt"):
    if needle not in create:
        errors.append(f"create_screen.dart is missing {needle!r}")
if re.search(r"_conversation = \[ChatMessage\(role: 'user', content: 'App name:",
             create):
    errors.append("create_screen.dart still sends only the app name to the model")

# UI kit v2 and one version number everywhere.
if "UI_KIT_VERSION = 2" not in kit_js:
    errors.append("applix-ui.js is not at UI_KIT_VERSION 2")
if "static const version = 2;" not in read(ROOT / "src/container_app/lib/services/ui_kit.dart", "UiKit"):
    errors.append("ui_kit.dart still advertises an old kit version")
if "static const uiKitVersion = 2;" not in read(ROOT / "src/container_app/lib/services/app_project.dart", "AppProject"):
    errors.append("app_project.dart still advertises an old kit version")
for name in ("icon", "mountIcons", "sparkline", "barChart", "donut"):
    if not re.search(rf"export\s+function\s+{name}\s*\(", kit_js):
        errors.append(f"applix-ui.js does not export {name}()")
for selector in (".ax-select", ".ax-check", ".ax-radio", ".ax-search",
                 ".ax-chart__bars", ".ax-sparkline", ".ax-donut", ".ax-icon-btn"):
    if selector not in kit_css:
        errors.append(f"applix-ui.css is missing {selector}")

# Presets must talk tokens only.
for legacy in ("-apple-system", "#0d0d1a", "#1a1a2e", "#0f3460", "#4FC3F7"):
    if legacy in presets:
        errors.append(f"style presets still contain legacy value {legacy!r}")
if presets.count("--ax-") < 10:
    errors.append("style presets do not use --ax-* tokens")

# Starters: kit themed, modern font, no legacy palette.
files = sorted(STARTERS.glob("*.html"))
if len(files) != 8:
    errors.append(f"expected 8 starter apps, found {len(files)}")
for path in files:
    html = path.read_text(encoding="utf-8")
    name = path.name
    if "viewport-fit=cover" not in html:
        errors.append(f"{name} is missing viewport-fit=cover")
    if "system-ui" not in html:
        errors.append(f"{name} is missing system-ui")
    if "-apple-system" in html:
        errors.append(f"{name} still uses -apple-system")
    if "var(--ax-" not in html:
        errors.append(f"{name} does not use kit tokens")
    for legacy in ("#0d0d1a", "#1a1a2e", "#0f3460", "#4FC3F7"):
        if legacy in html:
            errors.append(f"{name} still contains {legacy}")
for name in ("todo.html", "notes.html"):
    html = (STARTERS / name).read_text(encoding="utf-8")
    for needle in ("SEED", "iappyx.save", "ax-empty"):
        if needle not in html:
            errors.append(f"{name} is missing {needle}")

if errors:
    print("Phase 5 check failed:", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    sys.exit(1)

print(f"Phase 5 OK: planner + design contract + kit v2 + {len(files)} starters")
