#!/bin/bash
# Pensieve shared library
#
# Conventions:
# - System capability lives inside the plugin: <plugin>/skills/pensieve
# - User data lives at project level: <project>/.claude/pensieve

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
    echo "$pr/.claude/pensieve"
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

# ============================================
# Claude Code process detection (for Loop marker binding)
# ============================================

# Print nearest `claude` PID in current process tree (stdout), non‑zero if not found
find_claude_pid() {
    local pid="$$"
    while [[ "$pid" -gt 1 ]]; do
        local comm
        comm=$(ps -o comm= -p "$pid" 2>/dev/null | sed 's/^[[:space:]]*//')
        comm=$(basename "$comm")
        if [[ "$comm" == "claude" ]]; then
            echo "$pid"
            return 0
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        [[ -z "$pid" ]] && break
    done
    return 1
}

# Print the shell PID that launched this `claude` (stdout), non‑zero if not found
find_claude_session_pid() {
    local claude_pid
    claude_pid="$(find_claude_pid)" || return 1
    ps -o ppid= -p "$claude_pid" 2>/dev/null | tr -d ' '
}

# ============================================
# _meta.md reading
# ============================================

# Read task_list_id from _meta.md
# arg: $1 = _meta.md path
# returns: task_list_id or empty string
read_task_list_id_from_meta() {
    local meta_file="$1"
    [[ ! -f "$meta_file" ]] && echo "" && return 0

    sed -n '/^---$/,/^---$/p' "$meta_file" | grep "^task_list_id:" | sed 's/^task_list_id: *//'
}

# ============================================
# Loop directory scan
# ============================================

# Find loop dir with pending tasks
# arg: $1 = loop base dir
# returns: loop dir path (stdout) or non‑zero
find_active_loop() {
    local loop_base_dir="$1"

    for loop_dir in "$loop_base_dir"/????-??-??-*/; do
        [[ ! -d "$loop_dir" ]] && continue

        local meta_file="$loop_dir/_meta.md"
        [[ ! -f "$meta_file" ]] && continue

        local task_list_id
        task_list_id=$(read_task_list_id_from_meta "$meta_file")
        [[ -z "$task_list_id" ]] && continue

        local tasks_dir="$HOME/.claude/tasks/$task_list_id"
        [[ ! -d "$tasks_dir" ]] && continue

        # Check for pending or in_progress tasks
        for task_file in "$tasks_dir"/*.json; do
            [[ -f "$task_file" ]] || continue
            local status
            status=$(json_get_value "$task_file" "status" "")
            if [[ "$status" == "pending" || "$status" == "in_progress" ]]; then
                echo "${loop_dir%/}"
                return 0
            fi
        done
    done

    return 1
}

# Find loop directory by name
# arg: $1 = loop base dir, $2 = loop name (e.g., 2026-01-24-feature)
# returns: loop dir path or empty
find_loop_by_name() {
    local loop_base_dir="$1"
    local loop_name="$2"
    local loop_dir="$loop_base_dir/$loop_name"

    if [[ -d "$loop_dir" ]]; then
        echo "$loop_dir"
        return 0
    fi

    return 1
}
