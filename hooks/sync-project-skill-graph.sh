#!/bin/bash
# PostToolUse hook:
# When project user-data files are edited, auto-refresh `.claude/skills/pensieve/SKILL.md`
# and keep Claude auto memory `MEMORY.md` Pensieve guidance block in sync.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../skills/pensieve/tools/loop/scripts/_lib.sh"

PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || command -v python || true)}"
[[ -n "$PYTHON_BIN" ]] || exit 0

HOOK_INPUT="$(cat || true)"
[[ -n "$HOOK_INPUT" ]] || exit 0

extract_field() {
    local input="$1"
    local field="$2"
    printf '%s' "$input" | "$PYTHON_BIN" -c '
import json
import sys

field = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit(0)

tool_input = data.get("tool_input") or {}
tool_response = data.get("tool_response") or {}

if field == "tool_name":
    print(data.get("tool_name", ""))
elif field == "file_path":
    print(tool_input.get("file_path", ""))
elif field == "cwd":
    print(data.get("cwd", ""))
elif field == "success":
    ok = tool_response.get("success", True)
    print("true" if bool(ok) else "false")
else:
    print("")
' "$field"
}

TOOL_NAME="$(extract_field "$HOOK_INPUT" "tool_name")"
FILE_PATH_RAW="$(extract_field "$HOOK_INPUT" "file_path")"
CWD_RAW="$(extract_field "$HOOK_INPUT" "cwd")"
SUCCESS="$(extract_field "$HOOK_INPUT" "success")"

[[ "$SUCCESS" == "true" ]] || exit 0
[[ -n "$FILE_PATH_RAW" ]] || exit 0

FILE_PATH="$(to_posix_path "$FILE_PATH_RAW")"
CWD="$(to_posix_path "$CWD_RAW")"

if [[ "$FILE_PATH" != /* && -n "$CWD" ]]; then
    FILE_PATH="$CWD/$FILE_PATH"
fi

PROJECT_ROOT="$(to_posix_path "$(project_root)")"
USER_DATA_ROOT="$PROJECT_ROOT/.claude/skills/pensieve"

if [[ "$FILE_PATH" != "$USER_DATA_ROOT" && "$FILE_PATH" != "$USER_DATA_ROOT/"* ]]; then
    exit 0
fi

REL_PATH="${FILE_PATH#$PROJECT_ROOT/}"
case "$REL_PATH" in
    .claude/skills/pensieve/maxims/*|.claude/skills/pensieve/decisions/*|.claude/skills/pensieve/knowledge/*|.claude/skills/pensieve/pipelines/*)
        ;;
    *)
        exit 0
        ;;
esac

PLUGIN_ROOT="$(plugin_root_from_script "$SCRIPT_DIR")"
MAINTAIN_SCRIPT="$PLUGIN_ROOT/skills/pensieve/tools/project-skill/scripts/maintain-project-skill.sh"

[[ -x "$MAINTAIN_SCRIPT" ]] || exit 0

NOTE="posttooluse ${TOOL_NAME:-unknown}: ${REL_PATH}"
bash "$MAINTAIN_SCRIPT" --event sync --note "$NOTE" >/dev/null 2>&1 || true

exit 0
