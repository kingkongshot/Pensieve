#!/bin/bash
# Pensieve marker state manager.
# - SessionStart mode: read-only check and optional context injection.
# - Record mode: main window updates marker only after init/migrate/doctor/upgrade actually finishes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../skills/pensieve/tools/loop/scripts/_lib.sh"

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

PLUGIN_ROOT="$(plugin_root_from_script "$SCRIPT_DIR")"
PROJECT_ROOT="$(to_posix_path "$(project_root)")"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
MARKER_FILE="$PROJECT_ROOT/.state/pensieve-session-marker.json"

PLUGIN_VERSION="$("$PYTHON_BIN" - "$PLUGIN_JSON" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    print("unknown")
    sys.exit(0)

value = data.get("version")
if isinstance(value, str) and value.strip():
    print(value.strip())
else:
    print("unknown")
PY
)"

NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

"$PYTHON_BIN" - "$MODE" "$EVENT" "$MARKER_FILE" "$PLUGIN_VERSION" "$PROJECT_ROOT" "$NOW_UTC" <<'PY'
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
plugin_version = sys.argv[4].strip()
project_root = sys.argv[5].strip()
now_utc = sys.argv[6].strip()


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
        "plugin_version": plugin_version,
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
    existing = ""
    if ignore_file.exists():
        try:
            existing = ignore_file.read_text(encoding="utf-8")
        except Exception:
            existing = ""

    lines = existing.splitlines()
    changed = False
    if "*" not in lines:
        lines.append("*")
        changed = True
    if "!.gitignore" not in lines:
        lines.append("!.gitignore")
        changed = True

    if ignore_file.exists() and not changed:
        return

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

stored_plugin_version = str(state.get("plugin_version") or "")
if stored_plugin_version != plugin_version:
    # Version changed => old self-check result is no longer valid.
    state["plugin_version"] = plugin_version
    state["self_check_version"] = ""
    state["self_check_at"] = ""

if mode == "record":
    event = normalize_event(event_raw)
    if event == "init":
        state["initialized"] = True
    elif event == "doctor":
        if bool(state.get("initialized")):
            state["self_check_version"] = plugin_version
            state["self_check_at"] = now_utc
    elif event == "upgrade":
        state["self_check_version"] = ""
        state["self_check_at"] = ""

    state["plugin_version"] = plugin_version
    state["last_event"] = event or str(state.get("last_event") or "")
    state["updated_at"] = now_utc

    try:
        ensure_state_gitignore(marker_file.parent)
        write_json_atomic(marker_file, state)
    except Exception:
        pass

    sys.exit(0)

initialized = bool(state.get("initialized"))
self_check_version = str(state.get("self_check_version") or "")
self_check_ok = self_check_version == plugin_version

if initialized and self_check_ok:
    sys.exit(0)

messages: list[str] = []
messages.append("## Pensieve 会话前置检查")
messages.append("")
messages.append("- 严重级别：`P0`（会影响后续路由与诊断准确性）")
messages.append("- 主窗口策略：先完成前置修复并更新 marker，再处理用户当前需求。")
messages.append("- 行动建议：先向用户汇报以上状态，并询问“是否现在先完成 `init/doctor` 前置修复？”")
messages.append(f"- 当前插件版本：`{plugin_version}`")
messages.append(f"- 当前项目 marker：`{marker_file}`")
messages.append("- 规则：仅在主窗口确认迁移/修复已完成后，才主动更新这个 marker 文件。")
messages.append("- 指引：在主窗口调用 `pensieve` skill，询问如何完成 `init/doctor`。")

if not initialized:
    messages.append("- 当前项目未初始化：先执行 `init`。")
    messages.append("- `init` 成功后，主窗口执行：`bash -lc 'root=\"${CLAUDE_PLUGIN_ROOT:-}\"; [[ -n \"$root\" ]] || exit 0; if [[ \"${root:1:1}\" == \":\" && \"${root:0:1}\" =~ [A-Za-z] ]]; then if command -v cygpath >/dev/null 2>&1; then root=\"$(cygpath -u \"$root\")\"; else drive=\"${root:0:1}\"; rest=\"${root:2}\"; rest=\"${rest//\\\\//}\"; drive=\"$(printf \"%s\" \"$drive\" | tr \"A-Z\" \"a-z\")\"; root=\"/$drive$rest\"; fi; fi; exec \"$root/hooks/run-hook.sh\" pensieve-session-marker.sh --mode record --event init'`")

if not self_check_ok:
    recorded = self_check_version if self_check_version else "未记录"
    messages.append(f"- 自检版本不匹配：记录为 `{recorded}`，需要 `{plugin_version}`。先执行 `doctor`。")
    messages.append("- `doctor` 通过后，主窗口执行：`bash -lc 'root=\"${CLAUDE_PLUGIN_ROOT:-}\"; [[ -n \"$root\" ]] || exit 0; if [[ \"${root:1:1}\" == \":\" && \"${root:0:1}\" =~ [A-Za-z] ]]; then if command -v cygpath >/dev/null 2>&1; then root=\"$(cygpath -u \"$root\")\"; else drive=\"${root:0:1}\"; rest=\"${root:2}\"; rest=\"${rest//\\\\//}\"; drive=\"$(printf \"%s\" \"$drive\" | tr \"A-Z\" \"a-z\")\"; root=\"/$drive$rest\"; fi; fi; exec \"$root/hooks/run-hook.sh\" pensieve-session-marker.sh --mode record --event doctor'`")

if not initialized:
    messages.append("- 建议顺序：`init` -> `doctor`。")
else:
    messages.append("- 建议动作：执行 `doctor` 并更新 marker。")

user_parts: list[str] = []
if not initialized:
    user_parts.append("项目未初始化")
if not self_check_ok:
    user_parts.append("体检版本不匹配")
user_summary = f"Pensieve（v{plugin_version}）：{'，'.join(user_parts)}。输入 /pensieve 执行修复。"

payload = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "\n".join(messages),
    },
    "systemMessage": user_summary,
}
print(json.dumps(payload, ensure_ascii=False))
PY
