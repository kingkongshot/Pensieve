#!/usr/bin/env bash
# Claude plugin wrapper around the shared Pensieve skill scripts.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: run-hook.sh <script-name> [args...]" >&2
  exit 1
fi

SCRIPT_NAME="$1"
shift

to_posix_path() {
  local raw_path="$1"
  [[ -n "$raw_path" ]] || {
    echo ""
    return 0
  }

  if [[ "$raw_path" =~ ^[A-Za-z]:[\\/].* ]]; then
    if command -v cygpath >/dev/null 2>&1; then
      cygpath -u "$raw_path"
      return 0
    fi

    local drive rest drive_lower
    drive="${raw_path:0:1}"
    rest="${raw_path:2}"
    rest="${rest//\\//}"
    drive_lower="$(printf '%s' "$drive" | tr 'A-Z' 'a-z')"
    echo "/$drive_lower$rest"
    return 0
  fi

  echo "$raw_path"
}

PROJECT_ROOT="$(to_posix_path "${PENSIEVE_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}")"
SKILL_ROOT="$(to_posix_path "${PENSIEVE_SKILL_ROOT:-$PROJECT_ROOT/.claude/skills/pensieve}")"
TARGET="$SKILL_ROOT/.src/scripts/$SCRIPT_NAME"

export PENSIEVE_PROJECT_ROOT="$PROJECT_ROOT"
export PENSIEVE_SKILL_ROOT="$SKILL_ROOT"

[[ -f "$TARGET" ]] || {
  echo "Hook target not found: $TARGET" >&2
  echo "Hint: install the skill first with npx skills add" >&2
  exit 1
}

exec bash "$TARGET" "$@"
