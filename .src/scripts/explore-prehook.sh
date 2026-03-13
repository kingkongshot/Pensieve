#!/bin/bash
# PreToolUse hook helper.
# When spawning an Explore or Plan agent, inject the system SKILL.md and
# project state.md directly into the agent prompt via updatedInput.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Read hook payload from stdin first — fast-path exit for non-Explore/Plan agents
# to avoid unnecessary file I/O and Python startup under parallel agent creation.
STDIN_DATA="$(cat)"
[[ -n "$STDIN_DATA" ]] || exit 0

# Lightweight bash-level check: skip Python entirely for non-matching agent types.
# This prevents hook timeout errors when 4+ agents are created in parallel.
if [[ "$STDIN_DATA" != *'"subagent_type"'*'"Explore"'* ]] && \
   [[ "$STDIN_DATA" != *'"subagent_type"'*'"Plan"'* ]]; then
  exit 0
fi

PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || command -v python || true)}"
[[ -n "$PYTHON_BIN" ]] || exit 0

SKILL_FILE="$(skill_md_file "$SCRIPT_DIR")"
STATE_FILE="$(project_state_file)"

# Graceful degradation: silently exit for projects without .pensieve/ (architecture-v2 §5.3).
# SKILL.md is a static tracked file at the skill root — always present when hooks are installed.
# state.md exists only after `init`; its absence means this project hasn't opted in.
[[ -f "$STATE_FILE" ]] || exit 0

"$PYTHON_BIN" - "$SKILL_FILE" "$STATE_FILE" "$STDIN_DATA" <<'PY'
import json
import sys

skill_file = sys.argv[1]
state_file = sys.argv[2]
stdin_raw = sys.argv[3]

try:
    payload = json.loads(stdin_raw)
except Exception:
    sys.exit(0)

tool_input = payload.get("tool_input", {})
subagent_type = tool_input.get("subagent_type", "")
if subagent_type not in ("Explore", "Plan"):
    sys.exit(0)

original_prompt = tool_input.get("prompt", "")

guidance = """\
[Pensieve] Project knowledge index — check before exploring, what you need may already be documented:
- Knowledge: previously explored file locations, module boundaries, call chains — reuse directly.
- Decisions / Maxims: settled architectural decisions and coding principles — follow, don't re-debate.
- Pipelines: reusable workflows — if one matches the current task, follow it.

---
"""

try:
    with open(skill_file, "r", encoding="utf-8") as f:
        skill_content = f.read()
except Exception:
    sys.exit(0)

# Also inject project state if available
state_content = ""
try:
    with open(state_file, "r", encoding="utf-8") as f:
        state_content = f.read()
except Exception:
    pass

updated_prompt = guidance + skill_content
if state_content:
    updated_prompt += "\n\n---\n\n## Project State\n\n" + state_content
updated_prompt += "\n\n---\n\n" + original_prompt

updated_input = dict(tool_input)
updated_input["prompt"] = updated_prompt

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "updatedInput": updated_input,
    }
}))
PY
