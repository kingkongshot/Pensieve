#!/bin/bash
# Install Pensieve hooks into ~/.claude/settings.json.
# Idempotent — safe to run repeatedly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

SKILL_ROOT="$(skill_root_from_script "$SCRIPT_DIR")"
ensure_home || { echo "Cannot determine home directory" >&2; exit 1; }
SETTINGS_FILE="$HOME/.claude/settings.json"

ensure_python_env
[[ -n "${PYTHON_BIN:-}" ]] || { echo "Python not found" >&2; exit 1; }

mkdir -p "$(dirname "$SETTINGS_FILE")"

"$PYTHON_BIN" - "$SETTINGS_FILE" "$SKILL_ROOT" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

settings_file = Path(sys.argv[1])
skill_root = sys.argv[2]

run_hook = f"{skill_root}/.src/scripts/run-hook.sh"

# Hook definitions for Pensieve
pensieve_hooks = {
    "SessionStart": [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": f'bash "{run_hook}" pensieve-session-marker.sh --mode session-start',
                }
            ]
        }
    ],
    "PreToolUse": [
        {
            "matcher": "Agent",
            "hooks": [
                {
                    "type": "command",
                    "command": f'bash "{run_hook}" explore-prehook.sh',
                }
            ],
        }
    ],
    "PostToolUse": [
        {
            "matcher": "Write|Edit|MultiEdit",
            "hooks": [
                {
                    "type": "command",
                    "command": f'bash "{run_hook}" sync-project-skill-graph.sh',
                }
            ],
        }
    ],
}

# Load existing settings
settings: dict = {}
if settings_file.exists():
    try:
        settings = json.loads(settings_file.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"Error: {settings_file} contains invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)
    except OSError as e:
        print(f"Error reading {settings_file}: {e}", file=sys.stderr)
        sys.exit(1)

if not isinstance(settings, dict):
    settings = {}

hooks = settings.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}
    settings["hooks"] = hooks


def is_pensieve_hook(entry: dict) -> bool:
    """Check if a hook entry belongs to Pensieve."""
    for h in entry.get("hooks", []):
        cmd = h.get("command", "")
        if "run-hook.sh" in cmd and ("pensieve" in cmd or "explore-prehook" in cmd or "sync-project-skill-graph" in cmd):
            return True
    return False


# Clean up legacy v1 marketplace entry (claude-plugin branch, now obsolete)
marketplaces = settings.get("extraKnownMarketplaces")
if isinstance(marketplaces, dict):
    legacy_keys = [
        k for k, v in marketplaces.items()
        if isinstance(v, dict)
        and "kingkongshot/Pensieve" in json.dumps(v)
    ]
    for k in legacy_keys:
        del marketplaces[k]
    if legacy_keys:
        if not marketplaces:
            del settings["extraKnownMarketplaces"]
        changed_marketplace = True
    else:
        changed_marketplace = False
else:
    changed_marketplace = False

changed = changed_marketplace
for event_name, new_entries in pensieve_hooks.items():
    existing = hooks.get(event_name, [])
    if not isinstance(existing, list):
        existing = []

    # Remove any existing Pensieve hooks
    filtered = [e for e in existing if not is_pensieve_hook(e)]

    # Append new Pensieve hooks
    updated = filtered + new_entries

    if updated != existing:
        changed = True
    hooks[event_name] = updated

if changed:
    settings_file.write_text(
        json.dumps(settings, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"✅ Hooks installed to {settings_file}")
    if changed_marketplace:
        print(f"  - Cleaned up legacy v1 marketplace entries")
else:
    print(f"✅ Hooks already up to date in {settings_file}")
PY
