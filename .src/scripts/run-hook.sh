#!/bin/bash
# Unified hook launcher for optional Claude hook wiring.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: run-hook.sh <script-name> [args...]" >&2
  exit 1
fi

SCRIPT_NAME="$1"
shift

# NOTE: This to_posix_path is a standalone copy required before lib.sh can be
# sourced (we need it to resolve the skill root first). Keep in sync with
# the canonical implementation in lib.sh:to_posix_path.
# Sync marker: v2026-03-10
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

ROOT_RAW="${PENSIEVE_SKILL_ROOT:-}"
if [[ -z "$ROOT_RAW" ]]; then
  # Resolve HOME reliably (may be unset on some Windows shell configurations).
  if [[ -z "${HOME:-}" ]]; then
    if [[ -n "${USERPROFILE:-}" ]]; then
      HOME="$(to_posix_path "$USERPROFILE")"
      export HOME
    elif _h="$(cd ~ 2>/dev/null && pwd)"; then
      HOME="$_h"
      export HOME
    fi
  fi
  # v2: default to user-level skill root
  ROOT_RAW="${HOME:+$HOME/.claude/skills/pensieve}"
  # Fallback: derive from script location
  if [[ -z "$ROOT_RAW" || ! -d "$ROOT_RAW" ]]; then
    SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ROOT_RAW="$(cd "$SELF_DIR/../.." && pwd)"
  fi
fi
ROOT="$(to_posix_path "$ROOT_RAW")"
TARGET="$ROOT/.src/scripts/$SCRIPT_NAME"

# v2: Ensure PENSIEVE_PROJECT_ROOT is set for downstream scripts.
# In hook context, CLAUDE_PROJECT_DIR is provided by Claude Code.
# Without it, scripts inside the user-level skill root cannot resolve
# the actual project directory.
if [[ -z "${PENSIEVE_PROJECT_ROOT:-}" && -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  _resolved_pr="$(to_posix_path "$CLAUDE_PROJECT_DIR")"
  if [[ -d "$_resolved_pr" ]]; then
    export PENSIEVE_PROJECT_ROOT="$_resolved_pr"
  fi
  unset _resolved_pr
fi
export PENSIEVE_SKILL_ROOT="$ROOT"

[[ -f "$TARGET" ]] || {
  echo "Hook target not found: $TARGET" >&2
  exit 1
}

exec bash "$TARGET" "$@"
