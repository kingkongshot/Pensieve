#!/bin/bash
# Pensieve marker state manager.
# - session-start: read-only check and optional context injection.
# - record: update marker after init/doctor/migrate/upgrade actually finishes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

MODE="session-start"
EVENT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || { echo "Missing value for --mode" >&2; exit 1; }
      MODE="$2"
      shift 2
      ;;
    --event)
      [[ $# -ge 2 ]] || { echo "Missing value for --event" >&2; exit 1; }
      EVENT="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  pensieve-session-marker.sh --mode session-start
  pensieve-session-marker.sh --mode record --event <install|init|upgrade|migrate|doctor|self-improve|sync>
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

case "$MODE" in
  session-start|record)
    ;;
  *)
    echo "Unsupported --mode: $MODE" >&2
    exit 1
    ;;
esac

if [[ "$MODE" == "record" && -z "$EVENT" ]]; then
  echo "--event is required for --mode record" >&2
  exit 1
fi

PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || command -v python || true)}"
[[ -n "$PYTHON_BIN" ]] || exit 0

SKILL_ROOT="$(skill_root_from_script "$SCRIPT_DIR")"
PROJECT_ROOT="$(project_root)" || exit 0
PROJECT_ROOT="$(to_posix_path "$PROJECT_ROOT")"

# Graceful degradation: silently exit for projects without .pensieve/.
# This ensures zero impact on projects that do not use Pensieve (architecture-v2 §5.3).
# The record mode is exempt because init calls it to create the initial marker.
if [[ "$MODE" == "session-start" && ! -d "$PROJECT_ROOT/.pensieve" ]]; then
  exit 0
fi
STATE_ROOT="$(state_root)" || exit 0
STATE_ROOT="$(to_posix_path "$STATE_ROOT")"
SKILL_VERSION="$(skill_version "$SCRIPT_DIR")"
MARKER_FILE="$STATE_ROOT/pensieve-session-marker.json"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

"$PYTHON_BIN" - "$MODE" "$EVENT" "$MARKER_FILE" "$SKILL_VERSION" "$PROJECT_ROOT" "$NOW_UTC" "$SKILL_ROOT" <<'PY'
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any

mode = sys.argv[1].strip().lower()
event_raw = sys.argv[2].strip().lower()
marker_file = Path(sys.argv[3])
skill_version = sys.argv[4].strip()
project_root = sys.argv[5].strip()
now_utc = sys.argv[6].strip()
skill_root = sys.argv[7].strip()


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def normalize_event(value: str) -> str:
    if value in {"init", "install"}:
        return "init"
    if value == "doctor":
        return "doctor"
    if value == "upgrade":
        return "upgrade"
    if value == "migrate":
        return "migrate"
    if value in {"self-improve", "selfimprove"}:
        return "self-improve"
    if value in {"sync", "auto-sync"}:
        return "sync"
    return value


def default_state() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "project_root": project_root,
        "skill_root": skill_root,
        "skill_version": skill_version,
        "initialized": False,
        "self_check_version": "",
        "self_check_at": "",
        "last_event": "",
        "updated_at": now_utc,
    }


def write_json_atomic(path: Path, payload_obj: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(payload_obj, ensure_ascii=False, indent=2) + "\n"
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=str(path.parent),
        prefix=path.name + ".",
        suffix=".tmp",
        delete=False,
    ) as tmp:
        tmp.write(payload)
        tmp_path = Path(tmp.name)
    os.replace(tmp_path, path)


def ensure_state_gitignore(state_dir: Path) -> None:
    state_dir.mkdir(parents=True, exist_ok=True)
    ignore_file = state_dir / ".gitignore"
    existing = ignore_file.read_text(encoding="utf-8") if ignore_file.exists() else ""
    lines = existing.splitlines()
    if "*" in lines:
        return
    lines.append("*")
    payload = "\n".join(lines).rstrip() + "\n"
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=str(state_dir),
        prefix=ignore_file.name + ".",
        suffix=".tmp",
        delete=False,
    ) as tmp:
        tmp.write(payload)
        tmp_path = Path(tmp.name)
    os.replace(tmp_path, ignore_file)


raw_state = load_json(marker_file)
if raw_state.get("schema_version") != 1:
    state = default_state()
else:
    state = default_state()
    for key, value in raw_state.items():
        state[key] = value

state["project_root"] = project_root
state["skill_root"] = skill_root

stored_skill_version = str(state.get("skill_version") or "")
if stored_skill_version != skill_version:
    state["skill_version"] = skill_version
    state["self_check_version"] = ""
    state["self_check_at"] = ""

if mode == "record":
    event = normalize_event(event_raw)
    if event == "init":
        state["initialized"] = True
    elif event == "doctor" and bool(state.get("initialized")):
        state["self_check_version"] = skill_version
        state["self_check_at"] = now_utc
    elif event == "upgrade":
        state["self_check_version"] = ""
        state["self_check_at"] = ""

    state["skill_version"] = skill_version
    state["last_event"] = event or str(state.get("last_event") or "")
    state["updated_at"] = now_utc

    ensure_state_gitignore(marker_file.parent)
    write_json_atomic(marker_file, state)
    sys.exit(0)

initialized = bool(state.get("initialized"))
self_check_version = str(state.get("self_check_version") or "")
self_check_ok = self_check_version == skill_version

if initialized and self_check_ok:
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": f"PENSIEVE_SKILL_ROOT={skill_root}\nPENSIEVE_PROJECT_ROOT={project_root}",
        },
    }
    print(json.dumps(payload, ensure_ascii=False))
    sys.exit(0)

record_init_cmd = f"bash '{skill_root}/.src/scripts/pensieve-session-marker.sh' --mode record --event init"
record_doctor_cmd = f"bash '{skill_root}/.src/scripts/pensieve-session-marker.sh' --mode record --event doctor"

messages: list[str] = []
messages.append(f"PENSIEVE_SKILL_ROOT={skill_root}")
messages.append(f"PENSIEVE_PROJECT_ROOT={project_root}")
messages.append("")
messages.append("## Pensieve Session Pre-check")
messages.append("")
messages.append("- Severity: `P0` (affects downstream routing and diagnostic accuracy)")
messages.append("- Main window strategy: complete pre-check fixes and update marker before handling the user's current request.")
messages.append("- Action: report the status above to the user and ask whether to complete `init/doctor` pre-check fixes now.")
messages.append(f"- Current skill version: `{skill_version}`")
messages.append(f"- Current project marker: `{marker_file}`")
messages.append("- Rule: only update this marker file after the main window confirms migration/fix is complete.")

if not initialized:
    messages.append("- Project not initialized: run `init` first.")
    messages.append(f"- After `init` succeeds, run in main window: `{record_init_cmd}`")

if not self_check_ok:
    recorded = self_check_version if self_check_version else "not recorded"
    messages.append(f"- Self-check version mismatch: recorded `{recorded}`, required `{skill_version}`. Run `doctor` first.")
    messages.append(f"- After `doctor` passes, run in main window: `{record_doctor_cmd}`")

messages.append("- Suggested order: `init` -> `doctor`." if not initialized else "- Suggested action: run `doctor` and update marker.")

user_parts: list[str] = []
if not initialized:
    user_parts.append("not initialized")
if not self_check_ok:
    user_parts.append("doctor version mismatch")
user_summary = f"Pensieve ({skill_version}): {', '.join(user_parts)}. Run /pensieve doctor to fix."

payload = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "\n".join(messages),
    },
    "systemMessage": user_summary,
}
print(json.dumps(payload, ensure_ascii=False))
PY
