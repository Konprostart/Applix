#!/usr/bin/env python3
"""Static guard for the Phase 4 security and local-data wiring.

Fails when the Keystore vault, the WebView storage settings or the bridge
contract drift:
  * vault class exists, uses AndroidKeyStore + AES-GCM, stores ciphertext only
  * the shell exposes it to pages and background tasks as iappyx.secure
  * DOM storage and database storage are enabled for both webviews
  * the prompt documents the API and forbids secrets in plain storage
  * the bridge index lists every documented vault method
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHELL = ROOT / "src/shell_apk/app/src/main/java/com/applix/generated/placeholder"
VAULT = SHELL / "SecureVault.java"
ACTIVITY = SHELL / "ShellActivity.java"
TASK = SHELL / "TaskService.java"
PROMPT = ROOT / "src/container_app/assets/system_prompt.md"
INDEX = ROOT / "src/container_app/assets/bridge_index.json"

VAULT_METHODS = {"set", "get", "has", "remove", "clear", "keys", "size", "isAvailable"}

errors: list[str] = []


def read(path: Path) -> str:
    if not path.exists():
        errors.append(f"missing {path.relative_to(ROOT)}")
        return ""
    return path.read_text(encoding="utf-8")


vault = read(VAULT)
activity = read(ACTIVITY)
task = read(TASK)
prompt = read(PROMPT)
try:
    index = json.loads(INDEX.read_text(encoding="utf-8"))
except Exception as exc:  # noqa: BLE001 - explicit failure below
    index = {}
    errors.append(f"bridge_index.json is not valid JSON: {exc}")

for needle in (
    "AndroidKeyStore",
    "AES/GCM/NoPadding",
    "setUserAuthenticationRequired(false)",
    "setRandomizedEncryptionRequired(true)",
    "MAX_VALUE_BYTES",
    "GCMParameterSpec",
):
    if needle not in vault:
        errors.append(f"SecureVault.java is missing {needle}")

if "putString(key, seal(" not in vault:
    errors.append("the vault does not encrypt before persisting")
if re.search(r"putString\(key,\s*value\)", vault):
    errors.append("the vault writes plaintext values")
if "setUserAuthenticationRequired(true)" in vault:
    errors.append("the vault requires authentication; apps must stay usable")
if "Log." in vault and re.search(r"Log\.\w+\([^;]*value", vault):
    errors.append("the vault must never log values")
if "keys()" not in vault or "JSONArray" not in vault:
    errors.append("the vault does not expose names-only key listing")

if "new SecureVault(this)" not in activity or '"iappyxVault"' not in activity:
    errors.append("ShellActivity does not expose the vault to pages")
if "secure:iappyxVault" not in activity:
    errors.append("ShellActivity does not alias iappyx.secure")
if "new SecureVault(ctx)" not in task or "secure:iappyxVault" not in task:
    errors.append("TaskService does not expose the vault to background tasks")

for source, label in ((activity, "ShellActivity"), (task, "TaskService")):
    if "setDomStorageEnabled(true)" not in source:
        errors.append(f"{label} does not enable DOM storage")
    if "setDatabaseEnabled(true)" not in source:
        errors.append(f"{label} does not enable database storage")

modules = index.get("modules", {}) if isinstance(index, dict) else {}
secure = set(modules.get("secure", []))
missing = VAULT_METHODS - secure
if missing:
    errors.append(f"bridge_index.json is missing vault methods: {sorted(missing)}")

for method in VAULT_METHODS - {"clear"}:
    if f"iappyx.secure.{method}" not in prompt:
        errors.append(f"system_prompt.md does not document iappyx.secure.{method}")
if "Android Keystore" not in prompt or "AES-256-GCM" not in prompt:
    errors.append("system_prompt.md does not explain the Keystore backing")
if "Never put them in `iappyx.save`" not in prompt:
    errors.append("system_prompt.md does not forbid secrets in plain storage")
if "IndexedDB" not in prompt:
    errors.append("system_prompt.md does not cover IndexedDB persistence")

if errors:
    print("Phase 4 check failed:", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    sys.exit(1)

print(f"Phase 4 OK: vault ({len(VAULT_METHODS)} methods), storage enabled, docs in sync")
