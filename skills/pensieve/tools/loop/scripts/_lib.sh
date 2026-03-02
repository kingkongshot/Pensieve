#!/bin/bash
# Pensieve shared library
#
# Conventions:
# - System capability lives inside the plugin: <plugin>/skills/pensieve
# - User data lives at project level: <project>/.claude/skills/pensieve

plugin_root_from_script() {
    local script_dir="$1"
    local dir
    dir="$(cd "$script_dir" && pwd)"

    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.claude-plugin" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(cd "$dir/.." && pwd)"
    done

    # fallback: walk back from skills/pensieve
    local skill_root
    skill_root="$(cd "$script_dir/../../.." && pwd)"  # .../skills/pensieve
    cd "$skill_root/../.." && pwd                     # ... (plugin root)
}

to_posix_path() {
    local raw_path="$1"
    [[ -n "$raw_path" ]] || {
        echo ""
        return 0
    }

    # Convert Windows-style paths (e.g. C:\foo or C:/foo) for Git Bash/MSYS.
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

project_root() {
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        to_posix_path "$CLAUDE_PROJECT_DIR"
        return 0
    fi
    git rev-parse --show-toplevel 2>/dev/null || pwd
}

user_data_root() {
    local pr
    pr="$(project_root)"
    echo "$pr/.claude/skills/pensieve"
}

# Claude Code auto memory directory:
#   ~/.claude/projects/<encoded-project-root>/memory
auto_memory_project_key() {
    local pr
    # Use raw path — must NOT go through to_posix_path so that the
    # generated key matches Claude Code's own project-key algorithm.
    # Fixes: https://github.com/kingkongshot/Pensieve/issues/16
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        pr="$CLAUDE_PROJECT_DIR"
    else
        pr="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    fi
    [[ -n "$pr" ]] || {
        echo ""
        return 0
    }

    local encoded
    # Match Claude Code's project key encoding:
    # Replace : / \ _ with -
    encoded="${pr//[:\/\\_]/-}"
    echo "$encoded"
}

auto_memory_dir() {
    local home_dir key
    home_dir="$(to_posix_path "${HOME:-$(cd ~ && pwd)}")"
    key="$(auto_memory_project_key)"
    echo "$home_dir/.claude/projects/$key/memory"
}

auto_memory_file() {
    local dr
    dr="$(auto_memory_dir)"
    echo "$dr/MEMORY.md"
}

project_skill_file() {
    local dr
    dr="$(user_data_root)"
    echo "$dr/SKILL.md"
}

ensure_user_data_root() {
    local dr
    dr="$(user_data_root)"
    mkdir -p "$dr"/{maxims,decisions,knowledge,pipelines,loop}
    echo "$dr"
}

python_bin() {
    command -v python3 || command -v python
}

runtime_now_utc() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

runtime_log() {
    local level="$1"
    local code="$2"
    local message="$3"
    shift 3 || true

    local ts
    ts="$(runtime_now_utc)"
    printf '[pensieve-runtime] ts=%s level=%s code=%s message=%s' "$ts" "$level" "$code" "$message" >&2

    local kv
    for kv in "$@"; do
        printf ' %s' "$kv" >&2
    done
    printf '\n' >&2
}

# Run a command with a timeout and bounded retries.
# Usage:
#   run_with_retry_timeout "<label>" <timeout_sec> <retries> -- <cmd> [args...]
# Return codes:
#   0 success
#   124 timeout
#   other non-zero command exit code
#   2 invalid runtime usage
run_with_retry_timeout() {
    local label="$1"
    local timeout_sec="$2"
    local retries="$3"
    shift 3

    if ! [[ "$timeout_sec" =~ ^[0-9]+$ ]]; then
        runtime_log "error" "RUNTIME_USAGE" "timeout_sec must be a non-negative integer" "label=$label" "timeout_sec=$timeout_sec"
        return 2
    fi
    if ! [[ "$retries" =~ ^[0-9]+$ ]]; then
        runtime_log "error" "RUNTIME_USAGE" "retries must be a non-negative integer" "label=$label" "retries=$retries"
        return 2
    fi
    if [[ "${1:-}" != "--" ]]; then
        runtime_log "error" "RUNTIME_USAGE" "missing -- separator before command" "label=$label"
        return 2
    fi
    shift
    if [[ $# -eq 0 ]]; then
        runtime_log "error" "RUNTIME_USAGE" "missing command" "label=$label"
        return 2
    fi

    local py
    py="$(python_bin || true)"
    if [[ -z "$py" && "$timeout_sec" -gt 0 ]]; then
        runtime_log "warn" "RUNTIME_NO_TIMEOUT" "python not available; running without timeout" "label=$label"
    fi

    local attempt=1
    local rc
    while true; do
        if [[ -n "$py" && "$timeout_sec" -gt 0 ]]; then
            "$py" - "$timeout_sec" "$@" <<'PY'
import subprocess
import sys

timeout = float(sys.argv[1])
cmd = sys.argv[2:]
try:
    completed = subprocess.run(cmd, timeout=timeout)
    sys.exit(completed.returncode)
except subprocess.TimeoutExpired:
    sys.exit(124)
PY
            rc=$?
        else
            "$@"
            rc=$?
        fi

        if [[ "$rc" -eq 0 ]]; then
            return 0
        fi

        if [[ "$rc" -eq 124 ]]; then
            runtime_log "warn" "RUNTIME_TIMEOUT" "command timed out" "label=$label" "attempt=$attempt" "timeout_sec=$timeout_sec"
        else
            runtime_log "warn" "RUNTIME_RETRY" "command failed" "label=$label" "attempt=$attempt" "exit=$rc"
        fi

        if (( attempt > retries )); then
            runtime_log "error" "RUNTIME_FAILED" "command exhausted retries" "label=$label" "attempts=$attempt" "exit=$rc"
            return "$rc"
        fi

        attempt=$((attempt + 1))
        sleep 1
    done
}

json_get_value() {
    local file="$1"
    local key="$2"
    local default_value="${3:-}"
    local py
    py="$(python_bin)" || {
        echo "$default_value"
        return 0
    }

    "$py" - "$file" "$key" "$default_value" <<'PY'
import json
import sys

file_path, key, default_value = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    print(default_value)
    sys.exit(0)

if not isinstance(data, dict):
    print(default_value)
    sys.exit(0)

value = data.get(key)
if value is None:
    print(default_value)
elif isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (int, float)):
    print(value)
elif isinstance(value, str):
    print(value)
else:
    print(default_value)
PY
}

# Note: legacy loop helpers were removed after continuation moved to main-window control.
