#!/bin/bash
# Register/update Pensieve hooks in ~/.claude/settings.json.
# Idempotent: safe to run repeatedly. Only touches Pensieve hooks (identified by run-hook.sh pattern).
# Called by init-project-data.sh and can be run manually.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

ensure_python_env
[[ -n "${PYTHON_BIN:-}" ]] || { echo "⚠️  Python not available, hook registration skipped" >&2; exit 0; }

SKILL_ROOT="$(skill_root_from_script "$SCRIPT_DIR")"
HOOKS_JSON="$SKILL_ROOT/.src/core/hooks.json"
SETTINGS_JSON="$HOME/.claude/settings.json"

[[ -f "$HOOKS_JSON" ]] || { echo "⚠️  hooks.json not found at $HOOKS_JSON" >&2; exit 1; }

# Ensure settings.json parent directory exists
mkdir -p "$(dirname "$SETTINGS_JSON")"

"$PYTHON_BIN" - "$HOOKS_JSON" "$SETTINGS_JSON" <<'PY'
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any

hooks_json_path = Path(sys.argv[1])
settings_path = Path(sys.argv[2])

# Load hook declarations
hooks_decl = json.loads(hooks_json_path.read_text(encoding="utf-8"))
identifier = hooks_decl.get("identifier_pattern", "run-hook.sh")
desired_hooks: dict[str, list] = hooks_decl.get("hooks", {})

# Load existing settings
if settings_path.exists():
    try:
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        settings = {}
else:
    settings = {}

if not isinstance(settings, dict):
    settings = {}

existing_hooks: dict[str, list] = settings.get("hooks", {})
if not isinstance(existing_hooks, dict):
    existing_hooks = {}


def is_pensieve_hook(entry: dict) -> bool:
    """Check if a hook entry belongs to Pensieve."""
    for hook in entry.get("hooks", []):
        cmd = hook.get("command", "")
        if identifier in cmd:
            return True
    return False


changes: list[str] = []

for event_name, desired_entries in desired_hooks.items():
    current_entries = existing_hooks.get(event_name, [])
    if not isinstance(current_entries, list):
        current_entries = []

    # Separate non-Pensieve hooks (preserve) from Pensieve hooks (replace)
    non_pensieve = [e for e in current_entries if isinstance(e, dict) and not is_pensieve_hook(e)]
    old_pensieve = [e for e in current_entries if isinstance(e, dict) and is_pensieve_hook(e)]

    # Build new list: non-Pensieve first, then desired Pensieve hooks
    new_entries = non_pensieve + desired_entries

    # Detect changes
    if len(old_pensieve) != len(desired_entries):
        changes.append(f"  {event_name}: {len(old_pensieve)} → {len(desired_entries)} Pensieve hook(s)")
    elif json.dumps(old_pensieve, sort_keys=True) != json.dumps(desired_entries, sort_keys=True):
        changes.append(f"  {event_name}: updated {len(desired_entries)} Pensieve hook(s)")

    existing_hooks[event_name] = new_entries

settings["hooks"] = existing_hooks

# Atomic write
settings_path.parent.mkdir(parents=True, exist_ok=True)
payload = json.dumps(settings, ensure_ascii=False, indent=2) + "\n"
with tempfile.NamedTemporaryFile(
    mode="w",
    encoding="utf-8",
    dir=str(settings_path.parent),
    prefix=settings_path.name + ".",
    suffix=".tmp",
    delete=False,
) as tmp:
    tmp.write(payload)
    tmp_path = Path(tmp.name)
os.replace(tmp_path, settings_path)

if changes:
    print("✅ Pensieve hooks registered in settings.json:")
    for line in changes:
        print(line)
else:
    print("✅ Pensieve hooks already up to date in settings.json")
PY
