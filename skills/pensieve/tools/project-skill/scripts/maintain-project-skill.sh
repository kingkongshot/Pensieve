#!/bin/bash
# Maintain project-level Pensieve SKILL.md and Claude auto memory guidance block.
#
# Usage:
#   maintain-project-skill.sh --event <install|upgrade|doctor|self-improve|sync> [--note "..."]

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
  maintain-project-skill.sh --event <install|upgrade|doctor|self-improve|sync> [--note "..."]

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
  install|init|upgrade|doctor|self-improve|selfimprove|sync|auto-sync)
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

"$PYTHON_BIN" - "$SKILL_FILE" "$TMP_GRAPH_FILE" "$EVENT" "$TODAY_UTC" "$PROJECT_ROOT" "$USER_DATA_ROOT" "$NOTE" <<'PY'
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


def event_display_name(raw: str) -> str:
    r = raw.lower()
    if r in {"install", "init"}:
        return "install/init"
    if r == "upgrade":
        return "upgrade"
    if r == "doctor":
        return "doctor"
    if r in {"sync", "auto-sync"}:
        return "auto-sync"
    return "self-improve"


def read_existing_created_date() -> str:
    if not skill_file.exists():
        return today
    text = skill_file.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"^created:\s*(\d{4}-\d{2}-\d{2})\s*$", text, flags=re.MULTILINE)
    if m:
        return m.group(1)
    return today


def load_graph() -> str:
    if not graph_file.exists():
        return "_(graph not generated yet)_"
    txt = graph_file.read_text(encoding="utf-8", errors="replace").strip()
    if txt == "":
        return "_(graph is empty)_"
    return txt


created_date = read_existing_created_date()
event_name = event_display_name(event)
graph_markdown = load_graph()
last_note = note if note else "(none)"

content = f"""---
id: pensieve-project-skill
type: skill
title: Pensieve Project Skill (Auto Generated)
status: active
created: {created_date}
tags: [pensieve, skill, project, auto-generated]
name: pensieve-project-skill
description: Project knowledge base (auto-maintained). Knowledge contains previously explored file locations and module boundaries for direct reuse; decisions/maxims are settled decisions and principles to follow; pipelines are reusable workflows. Also includes routing table, knowledge graph, and project paths.
---

# Pensieve Project Skill (Auto-Maintained)

> AUTO-GENERATED FILE. DO NOT EDIT MANUALLY.
> Source of truth: `{user_data_root}/SKILL.md`

## Lifecycle State
- Last Event: {event_name}
- Last Note: {last_note}

## Routing
- Init: Initialize project-level skill data directory and seed initial content; then perform first-round commit/code exploration and review taste baseline analysis (read-only). Tool spec: `<SYSTEM_SKILL_ROOT>/tools/init/_init.md` (read `## Tool Contract` first).
- Upgrade: Version check first; if no new version, ask whether to run `doctor` self-check; only perform migration alignment when a new version exists. Tool spec: `<SYSTEM_SKILL_ROOT>/tools/upgrade/_upgrade.md` (read `## Tool Contract` first).
- Doctor: Structural/frontmatter/link health check with fix suggestions. Tool spec: `<SYSTEM_SKILL_ROOT>/tools/doctor/_doctor.md` (read `## Tool Contract` first).
- Self-Improve: Capture knowledge/decision/maxim/pipeline. Tool spec: `<SYSTEM_SKILL_ROOT>/tools/self-improve/_self-improve.md` (read `## Tool Contract` first).
- Loop: Enter task decomposition and execution loop. Tool spec: `<SYSTEM_SKILL_ROOT>/tools/loop/_loop.md` (read `## Tool Contract` first).
- Graph View: Read this file's `## Graph` section directly; standalone pipeline commands are no longer used.

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

echo "Pensieve project SKILL updated"
echo "  - skill: $SKILL_FILE"

if [[ -x "$AUTO_MEMORY_SCRIPT" ]]; then
  if ! bash "$AUTO_MEMORY_SCRIPT" --event "$EVENT"; then
    echo "Auto memory update skipped: failed to run maintain-auto-memory.sh" >&2
  fi
fi
