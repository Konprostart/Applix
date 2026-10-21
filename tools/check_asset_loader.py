#!/usr/bin/env python3
"""Static guard for Phase 1 (secure asset origin).

Verifies, without an emulator, that both shells are wired to
WebViewAssetLoader and that the iappyx bridge was not touched.
The runtime proof that assets are actually served lives in
src/shell_apk/app/src/test (Robolectric integration test).
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHELLS = {
    "full": ROOT / "src/shell_apk/app/src/main/java/com/applix/generated/placeholder/ShellActivity.java",
    "web": ROOT / "src/shell_apk_web/app/src/main/java/com/applix/generated/placeholder/ShellActivity.java",
}
TASK_SERVICE = ROOT / "src/shell_apk/app/src/main/java/com/applix/generated/placeholder/TaskService.java"
ORIGIN = ROOT / "src/shell_apk/app/src/main/java/com/applix/generated/placeholder/AssetOrigin.java"

REQUIRED = [
    "WebViewAssetLoader",
    "addPathHandler(AssetOrigin.ASSETS_PATH",
    "shouldInterceptRequest",
    "AssetOrigin.FALLBACK_URL",
    "AssetOrigin.APP_URL",
]

errors = []

for name, path in SHELLS.items():
    if not path.exists():
        errors.append(f"{name} shell not found: {path}")
        continue
    text = path.read_text(encoding="utf-8")
    for token in REQUIRED:
        if token not in text:
            errors.append(f"{name} shell is missing {token!r}")
    if 'loadUrl("file:///android_asset/app/index.html")' in text:
        errors.append(f"{name} shell still loads file:// directly")

task = TASK_SERVICE.read_text(encoding="utf-8")
for token in ["WebViewAssetLoader", "AssetOrigin.APP_URL", "AssetOrigin.FALLBACK_URL"]:
    if token not in task:
        errors.append(f"TaskService is missing {token!r}")

origin = ORIGIN.read_text(encoding="utf-8")
if "https://appassets.androidplatform.net" not in origin:
    errors.append("AssetOrigin does not use the WebViewAssetLoader origin")
if '"/assets/"' not in origin:
    errors.append("AssetOrigin does not mount /assets/")

full_shell = SHELLS["full"].read_text(encoding="utf-8")
bridge_count = full_shell.count("webView.addJavascriptInterface")
if bridge_count < 37:
    errors.append(
        f"bridge regression: {bridge_count} addJavascriptInterface calls, expected at least 37"
    )

if errors:
    for e in errors:
        print(f"ERROR: {e}")
    sys.exit(1)

print(f"asset loader wiring OK (bridge calls: {bridge_count})")
