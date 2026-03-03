#!/bin/bash
# PreToolUse hook for Agent tool.
# When spawning an Explore agent, injects the project-level Pensieve SKILL.md
# directly into the agent's prompt via updatedInput so it arrives before execution.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../skills/pensieve/tools/loop/scripts/_lib.sh"

PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || command -v python || true)}"
[[ -n "$PYTHON_BIN" ]] || exit 0

# Read hook payload from stdin
STDIN_DATA="$(cat)"
[[ -n "$STDIN_DATA" ]] || exit 0

PROJECT_ROOT="$(to_posix_path "$(project_root)")"
SKILL_FILE="$PROJECT_ROOT/.claude/skills/pensieve/SKILL.md"

[[ -f "$SKILL_FILE" ]] || exit 0

"$PYTHON_BIN" - "$SKILL_FILE" "$STDIN_DATA" <<'PY'
import json
import sys

skill_file = sys.argv[1]
stdin_raw = sys.argv[2]

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

updated_prompt = guidance + skill_content + "\n\n---\n\n" + original_prompt

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
