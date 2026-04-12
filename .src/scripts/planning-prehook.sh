#!/bin/bash
# PreToolUse hook for planning-related tools.
# Triggers on:
#   1. EnterPlanMode — any project, no gstack needed
#   2. Skill tool with planning skills (plan-*, autoplan, office-hours) — gstack projects
# Injects Pensieve knowledge context before planning begins.
# Gracefully exits for non-planning tools and non-Pensieve projects.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Read hook payload from stdin.
HOOK_INPUT=""
if [[ ! -t 0 ]]; then
  HOOK_INPUT=$(timeout 2 cat 2>/dev/null || true)
fi

# Determine if this is a planning-related invocation.
TOOL_NAME=""
SKILL_NAME=""
if [[ -n "$HOOK_INPUT" ]] && command -v jq &>/dev/null; then
  TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // ""' 2>/dev/null || true)
  SKILL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_input.skill // ""' 2>/dev/null || true)
fi

IS_PLANNING=false
case "$TOOL_NAME" in
  EnterPlanMode) IS_PLANNING=true ;;
esac
case "$SKILL_NAME" in
  plan-*|autoplan|office-hours) IS_PLANNING=true ;;
esac

[[ "$IS_PLANNING" == "true" ]] || exit 0

# Detect project root and .pensieve/ directory.
PROJECT_ROOT="$(project_root 2>/dev/null)" || exit 0
PENSIEVE_DIR="$PROJECT_ROOT/.pensieve"
[[ -d "$PENSIEVE_DIR" ]] || exit 0

# Read planning pipeline if it exists.
PLANNING_PIPELINE="$PENSIEVE_DIR/pipelines/run-when-planning.md"
PIPELINE_CONTENT=""
if [[ -f "$PLANNING_PIPELINE" ]]; then
  PIPELINE_CONTENT=$(cat "$PLANNING_PIPELINE" 2>/dev/null || true)
fi

# Quick grep for decisions with "探索减负" (exploration reduction).
PRIOR_ART=""
for dir in "$PENSIEVE_DIR/decisions" "$PENSIEVE_DIR/knowledge" "$PENSIEVE_DIR/maxims"; do
  [[ -d "$dir" ]] || continue
  # Find files with active status
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    # Extract first heading and one-line conclusion/summary
    title=$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^# //' || true)
    status=$(grep -m1 '^status:' "$f" 2>/dev/null | sed 's/^status:[[:space:]]*//' || true)
    [[ "$status" == "active" ]] || continue
    rel_path="${f#$PENSIEVE_DIR/}"
    PRIOR_ART="${PRIOR_ART}\n- ${rel_path}: ${title}"
  done < <(find "$dir" -name '*.md' -type f 2>/dev/null | LC_ALL=C sort)
done

# Build additional context.
CTX=""
if [[ -n "$PIPELINE_CONTENT" ]]; then
  CTX="## Planning Pipeline (run-when-planning)\n\n${PIPELINE_CONTENT}"
fi
if [[ -n "$PRIOR_ART" ]]; then
  CTX="${CTX}\n\n## Available Pensieve Knowledge\n${PRIOR_ART}"
fi

if [[ -z "$CTX" ]]; then
  exit 0
fi

ensure_python_env
[[ -n "${PYTHON_BIN:-}" ]] || exit 0

"$PYTHON_BIN" -c "
import json, sys
ctx = sys.stdin.read()
payload = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'allow',
        'additionalContext': ctx,
    },
}
print(json.dumps(payload, ensure_ascii=False))
" <<< "$(echo -e "$CTX")"
