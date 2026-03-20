#!/bin/bash
# Maintain Claude Code auto memory guidance block for using the Pensieve skill.
#
# Usage:
#   maintain-auto-memory.sh [--event <name>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

EVENT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event)
      [[ $# -ge 2 ]] || { echo "Missing value for --event" >&2; exit 1; }
      EVENT="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  maintain-auto-memory.sh [--event <name>]

Options:
  --event <name>   Optional lifecycle event label for logging
  -h, --help       Show help
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

SKILL_ROOT="$(skill_root_from_script "$SCRIPT_DIR")"
MEMORY_FILE="$(auto_memory_file)"
SYSTEM_SKILL_FILE="$SKILL_ROOT/SKILL.md"
SCHEMA_FILE="$SKILL_ROOT/.src/core/schema.json"

ensure_python_env
[[ -n "${PYTHON_BIN:-}" ]] || { echo "Python not found" >&2; exit 1; }

"$PYTHON_BIN" - "$MEMORY_FILE" "$SYSTEM_SKILL_FILE" "$EVENT" "$SCHEMA_FILE" "$SKILL_ROOT" <<'PY'
from __future__ import annotations

import importlib.util
import json
import re
import sys
from pathlib import Path

memory_file = Path(sys.argv[1])
system_skill_file = Path(sys.argv[2])
event = (sys.argv[3] or "").strip()
schema_file = Path(sys.argv[4])
skill_root = Path(sys.argv[5])

# Load shared core module.
core_file = skill_root / ".src" / "core" / "pensieve_core.py"
_spec = importlib.util.spec_from_file_location("pensieve_core", core_file)
if _spec is None or _spec.loader is None:
    raise SystemExit(f"failed to load core module: {core_file}")
core_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(core_module)

# Read marker/guidance config from schema.json (single source of truth).
_FALLBACK_START = "<!-- pensieve:auto-memory:start -->"
_FALLBACK_END = "<!-- pensieve:auto-memory:end -->"
_FALLBACK_GUIDANCE = "- Guidance: When a request involves knowledge retention, structural checks, version migration, or complex task decomposition, prefer invoking the `pensieve` skill."

try:
    schema = json.loads(schema_file.read_text(encoding="utf-8", errors="replace"))
    memory_cfg = schema.get("memory", {}) if isinstance(schema.get("memory"), dict) else {}
except Exception:
    memory_cfg = {}

start_marker = str(memory_cfg.get("start_marker", _FALLBACK_START))
end_marker = str(memory_cfg.get("end_marker", _FALLBACK_END))
guidance_line = str(memory_cfg.get("guidance_line", _FALLBACK_GUIDANCE))

description = core_module.load_skill_description(system_skill_file)
if description is None:
    raise SystemExit(f"Missing or invalid skill description in: {system_skill_file}")


def build_block(description: str) -> str:
    return (
        f"{start_marker}\n"
        "## Pensieve\n"
        f"{description}\n"
        f"{guidance_line}\n"
        f"{end_marker}"
    )


def upsert_block(existing: str, block: str) -> str:
    pattern = re.compile(re.escape(start_marker) + r".*?" + re.escape(end_marker), flags=re.DOTALL)
    if pattern.search(existing):
        updated = pattern.sub(block, existing, count=1)
    else:
        trimmed = existing.rstrip("\n")
        updated = (trimmed + "\n\n" if trimmed else "") + block + "\n"
    return updated


block = build_block(description)

if memory_file.exists():
    original = memory_file.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")
else:
    original = ""

updated = upsert_block(original, block)
if updated != original:
    memory_file.parent.mkdir(parents=True, exist_ok=True)
    memory_file.write_text(updated, encoding="utf-8")
    action = "updated" if original else "created"
else:
    action = "unchanged"

event_label = event if event else "unknown"
print(f"✅ Pensieve auto memory {action}: {memory_file} (event={event_label})")
PY
