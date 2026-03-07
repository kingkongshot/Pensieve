#!/bin/bash
# Maintain generated Pensieve SKILL.md and Claude auto memory guidance.
#
# Usage:
#   maintain-project-skill.sh --event <install|upgrade|migrate|doctor|self-improve|sync> [--note "..."]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

EVENT=""
NOTE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event)
      [[ $# -ge 2 ]] || { echo "Missing value for --event" >&2; exit 1; }
      EVENT="$2"
      shift 2
      ;;
    --note)
      [[ $# -ge 2 ]] || { echo "Missing value for --note" >&2; exit 1; }
      NOTE="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  maintain-project-skill.sh --event <install|upgrade|migrate|doctor|self-improve|sync> [--note "..."]

Options:
  --event <name>   Lifecycle event to record
  --note <text>    Optional one-line note
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

if [[ -z "$EVENT" ]]; then
  echo "--event is required" >&2
  exit 1
fi

case "$EVENT" in
  install|init|upgrade|migrate|doctor|self-improve|selfimprove|sync|auto-sync)
    ;;
  *)
    echo "Unsupported --event: $EVENT" >&2
    exit 1
    ;;
esac

PROJECT_ROOT="$(to_posix_path "$(project_root "$SCRIPT_DIR")")"
USER_DATA_ROOT="$(user_data_root "$SCRIPT_DIR")"
STATE_ROOT="$(ensure_state_dir "$(state_root "$SCRIPT_DIR")")"
SKILL_FILE="$(project_skill_file "$SCRIPT_DIR")"
GRAPH_FILE="$(project_graph_file "$SCRIPT_DIR")"
SKILL_ROOT="$(skill_root_from_script "$SCRIPT_DIR")"
GRAPH_SCRIPT="$SKILL_ROOT/.src/scripts/generate-user-data-graph.sh"
AUTO_MEMORY_SCRIPT="$SKILL_ROOT/.src/scripts/maintain-auto-memory.sh"

mkdir -p "$USER_DATA_ROOT"/{maxims,decisions,knowledge,pipelines}

if [[ -x "$GRAPH_SCRIPT" ]]; then
  bash "$GRAPH_SCRIPT" --root "$USER_DATA_ROOT" --output "$GRAPH_FILE" >/dev/null
else
  printf '%s\n' "_(graph not generated yet)_" > "$GRAPH_FILE"
fi

# Remove legacy standalone graph files from the user data root.
for legacy_graph in \
  "$USER_DATA_ROOT"/_pensieve-graph.md \
  "$USER_DATA_ROOT"/_pensieve-graph.*.md \
  "$USER_DATA_ROOT"/pensieve-graph.md \
  "$USER_DATA_ROOT"/pensieve-graph.*.md \
  "$USER_DATA_ROOT"/graph.md \
  "$USER_DATA_ROOT"/graph.*.md; do
  [[ -e "$legacy_graph" ]] || continue
  rm -f "$legacy_graph"
done

PYTHON_BIN="$(python_bin || true)"
[[ -n "$PYTHON_BIN" ]] || { echo "Python not found" >&2; exit 1; }
TODAY_UTC="$(date -u +"%Y-%m-%d")"

"$PYTHON_BIN" - "$SKILL_FILE" "$GRAPH_FILE" "$EVENT" "$TODAY_UTC" "$PROJECT_ROOT" "$USER_DATA_ROOT" "$STATE_ROOT" "$NOTE" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

skill_file = Path(sys.argv[1])
graph_file = Path(sys.argv[2])
event = sys.argv[3].strip()
today = sys.argv[4].strip()
project_root = sys.argv[5].strip()
user_data_root = sys.argv[6].strip()
state_root = sys.argv[7].strip()
note = (sys.argv[8] or "").strip().replace("\n", " ")


def event_display_name(raw: str) -> str:
    r = raw.lower()
    if r in {"install", "init"}:
        return "install/init"
    if r == "upgrade":
        return "upgrade"
    if r == "migrate":
        return "migrate"
    if r == "doctor":
        return "doctor"
    if r in {"sync", "auto-sync"}:
        return "auto-sync"
    return "self-improve"


TOOLS = [
    ("init", "Init"),
    ("upgrade", "Upgrade"),
    ("migrate", "Migrate"),
    ("doctor", "Doctor"),
    ("self-improve", "Self-Improve"),
]


def read_tool_description(tool_dir: str) -> str:
    tool_file = Path(user_data_root) / ".src" / "tools" / f"{tool_dir}.md"
    if not tool_file.exists():
        return "(description not available)"
    text = tool_file.read_text(encoding="utf-8", errors="replace")
    m = re.match(r"^---\s*\n(.*?)\n---", text, flags=re.DOTALL)
    if not m:
        return "(no frontmatter)"
    for line in m.group(1).split("\n"):
        if line.startswith("description:"):
            return line[len("description:") :].strip()
    return "(no description field)"


def build_routing_section() -> str:
    lines = []
    for tool_dir, display_name in TOOLS:
        desc = read_tool_description(tool_dir)
        lines.append(f"- {display_name}：{desc} 工具规范：`.src/tools/{tool_dir}.md`。")
    lines.append("- Graph View：读取本文件 `## Graph` 段。")
    return "\n".join(lines)


def load_graph() -> str:
    if not graph_file.exists():
        return "_(graph not generated yet)_"
    txt = graph_file.read_text(encoding="utf-8", errors="replace").strip()
    if txt == "":
        return "_(graph is empty)_"
    return txt


def replace_section(lines: list[str], header: str, new_body: list[str]) -> list[str]:
    start = None
    end = len(lines)
    for i, line in enumerate(lines):
        if start is None and line.rstrip() == header:
            start = i
        elif start is not None and i > start and line.startswith("## "):
            end = i
            break
    if start is None:
        return lines + ["", header] + new_body
    return lines[: start + 1] + new_body + lines[end:]


event_name = event_display_name(event)
graph_markdown = load_graph()
last_note = note if note else "(none)"

if skill_file.exists():
    text = skill_file.read_text(encoding="utf-8", errors="replace")
    lines = text.split("\n")

    lines = replace_section(
        lines,
        "## Lifecycle State",
        [
            f"- Last Event: {event_name}",
            f"- Last Note: {last_note}",
            "",
        ],
    )

    lines = replace_section(
        lines,
        "## Graph",
        [
            "",
            graph_markdown,
            "",
        ],
    )

    skill_file.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
else:
    content = f"""---
name: pensieve
description: 项目知识库与工作流路由。knowledge 里有之前探索过的文件位置、模块边界、调用链路，可直接复用不必重新定位；decisions/maxims 是已定论的架构决定和编码准则，应遵守而非重新讨论；pipelines 是可复用的工作流程。完成任务后用 self-improve 沉淀新发现。提供 init、upgrade、migrate、doctor、self-improve 五个工具。
---

# Pensieve

将用户请求路由到正确的工具。不确定时先确认。

## Lifecycle State
- Last Event: {event_name}
- Last Note: {last_note}

## Routing
{build_routing_section()}

## Project Paths
- Project Root: `{project_root}`
- Skill Root: `{user_data_root}`
- System Files: `.src/`, `agents/`
- Generated Route File: `SKILL.md`
- Runtime State: `{state_root}/`
- Maxims: `maxims/`
- Decisions: `decisions/`
- Knowledge: `knowledge/`
- Pipelines: `pipelines/`

## Graph

{graph_markdown}
"""
    skill_file.write_text(content.rstrip() + "\n", encoding="utf-8")
PY

echo "✅ Pensieve project SKILL updated"
echo "  - skill: $SKILL_FILE"
echo "  - graph: $GRAPH_FILE"

if [[ -x "$AUTO_MEMORY_SCRIPT" ]]; then
  if ! bash "$AUTO_MEMORY_SCRIPT" --event "$EVENT"; then
    echo "⚠️  Auto memory update skipped: failed to run maintain-auto-memory.sh" >&2
  fi
fi
