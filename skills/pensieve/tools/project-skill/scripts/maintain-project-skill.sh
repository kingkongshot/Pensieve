#!/bin/bash
# Maintain project-level Pensieve SKILL.md and Claude auto memory guidance block.
#
# Usage:
#   maintain-project-skill.sh --event <install|upgrade|migrate|doctor|self-improve|sync> [--note "..."]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../loop/scripts/_lib.sh"

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

PROJECT_ROOT="$(to_posix_path "$(project_root)")"
USER_DATA_ROOT="$(user_data_root)"
SKILL_FILE="$(project_skill_file)"
PLUGIN_ROOT="$(plugin_root_from_script "$SCRIPT_DIR")"
GRAPH_SCRIPT="$PLUGIN_ROOT/skills/pensieve/tools/upgrade/scripts/generate-user-data-graph.sh"
AUTO_MEMORY_SCRIPT="$PLUGIN_ROOT/skills/pensieve/tools/project-skill/scripts/maintain-auto-memory.sh"
TMP_GRAPH_FILE="$(mktemp "${TMPDIR:-/tmp}/pensieve-graph.XXXXXX")"

cleanup_tmp_graph() {
  rm -f "$TMP_GRAPH_FILE"
}
trap cleanup_tmp_graph EXIT

mkdir -p "$USER_DATA_ROOT"/{maxims,decisions,knowledge,pipelines,loop}

if [[ -x "$GRAPH_SCRIPT" ]]; then
  bash "$GRAPH_SCRIPT" --root "$USER_DATA_ROOT" --output "$TMP_GRAPH_FILE" >/dev/null
else
  printf '%s\n' "_(graph not generated yet)_" > "$TMP_GRAPH_FILE"
fi

# Graph is embedded in SKILL.md only. Remove legacy standalone graph files.
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

SYSTEM_SKILL_ROOT="$PLUGIN_ROOT/skills/pensieve"

"$PYTHON_BIN" - "$SKILL_FILE" "$TMP_GRAPH_FILE" "$EVENT" "$TODAY_UTC" "$PROJECT_ROOT" "$USER_DATA_ROOT" "$NOTE" "$SYSTEM_SKILL_ROOT" <<'PY'
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
note = (sys.argv[7] or "").strip().replace("\n", " ")
system_skill_root = Path(sys.argv[8]) if len(sys.argv) > 8 else None


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
    ("loop", "Loop"),
]


def read_tool_description(tool_dir: str) -> str:
    """Read description from a tool file's YAML frontmatter."""
    if system_skill_root is None:
        return "(description not available)"
    tool_file = system_skill_root / "tools" / tool_dir / f"_{tool_dir}.md"
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
        lines.append(
            f"- {display_name}：{desc}"
            f"工具规范：`<SYSTEM_SKILL_ROOT>/tools/{tool_dir}/_{tool_dir}.md`。"
        )
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
    """Replace the body of a ## section, keeping the header line intact."""
    start = None
    end = len(lines)
    for i, line in enumerate(lines):
        if start is None and line.rstrip() == header:
            start = i
        elif start is not None and i > start and line.startswith("## "):
            end = i
            break
    if start is None:
        # Section not found — append it
        return lines + ["", header] + new_body
    return lines[: start + 1] + new_body + lines[end:]


event_name = event_display_name(event)
graph_markdown = load_graph()
last_note = note if note else "(none)"

if skill_file.exists():
    # ── Surgical update: only touch Lifecycle State + Graph ──
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
    # ── Initial creation: full template ──
    content = f"""---
id: pensieve-project-skill
type: skill
title: Pensieve Project Skill (Auto Generated)
status: active
created: {today}
tags: [pensieve, skill, project, auto-generated]
name: pensieve-project-skill
description: 项目知识库（自动维护）。knowledge 有已探索过的文件位置与模块边界可直接复用；decisions/maxims 是已定论的决定与准则应遵守；pipelines 是可复用流程。另含路由表、知识图谱、项目路径。
---

# Pensieve Project Skill（自动维护）

> Graph and Lifecycle State are auto-updated by `maintain-project-skill.sh`.
> Other sections may be manually edited.

## Lifecycle State
- Last Event: {event_name}
- Last Note: {last_note}

## Routing
{build_routing_section()}

## Project Paths
- Project Root: `{project_root}`
- Skill Root: `{user_data_root}`
- Maxims: `{user_data_root}/maxims/`
- Decisions: `{user_data_root}/decisions/`
- Knowledge: `{user_data_root}/knowledge/`
- Pipelines: `{user_data_root}/pipelines/`
- Loop: `{user_data_root}/loop/`

## Graph

{graph_markdown}
"""
    skill_file.write_text(content.rstrip() + "\n", encoding="utf-8")
PY

echo "✅ Pensieve project SKILL updated"
echo "  - skill: $SKILL_FILE"

if [[ -x "$AUTO_MEMORY_SCRIPT" ]]; then
  if ! bash "$AUTO_MEMORY_SCRIPT" --event "$EVENT"; then
    echo "⚠️  Auto memory update skipped: failed to run maintain-auto-memory.sh" >&2
  fi
fi
