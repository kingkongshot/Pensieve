#!/bin/bash
# Pensieve shared library
#
# Conventions:
# - The skill root contains SKILL.md and hidden system files.
# - User-editable data defaults to the skill root, but plugin shells may override it.
# - Hidden system files live under <skill-root>/.src.
# - Hidden runtime state lives under <project-root>/.state.

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

skill_root_from_script() {
    local script_dir="$1"
    local dir
    dir="$(cd "$script_dir" && pwd)"

    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/SKILL.md" && -d "$dir/.src" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(cd "$dir/.." && pwd)"
    done

    echo "Failed to locate skill root from: $script_dir" >&2
    return 1
}

# Backward-compatible alias used by older scripts.
plugin_root_from_script() {
    skill_root_from_script "$1"
}

skill_root() {
    local caller="${1:-$(pwd)}"
    if [[ -n "${PENSIEVE_SKILL_ROOT:-}" ]]; then
        to_posix_path "$PENSIEVE_SKILL_ROOT"
        return 0
    fi
    if [[ -d "$caller" ]]; then
        skill_root_from_script "$caller"
    else
        skill_root_from_script "$(dirname "$caller")"
    fi
}

system_root() {
    local sr
    sr="$(skill_root "${1:-$(pwd)}")"
    echo "$sr/.src"
}

state_root() {
    local caller="${1:-$(pwd)}"
    if [[ -n "${PENSIEVE_STATE_ROOT:-}" ]]; then
        local state_dir
        state_dir="$(to_posix_path "$PENSIEVE_STATE_ROOT")"
        if [[ "$state_dir" == /* ]]; then
            echo "$state_dir"
        else
            echo "$(project_root "$caller")/$state_dir"
        fi
        return 0
    fi

    local pr
    pr="$(project_root "$caller")"
    echo "$pr/.state"
}

project_root() {
    local caller
    caller="${1:-$(pwd)}"

    if [[ -n "${PENSIEVE_PROJECT_ROOT:-}" ]]; then
        to_posix_path "$PENSIEVE_PROJECT_ROOT"
        return 0
    fi

    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        to_posix_path "$CLAUDE_PROJECT_DIR"
        return 0
    fi

    local sr
    if ! sr="$(skill_root "$caller" 2>/dev/null)"; then
        if [[ -d "$caller" ]]; then
            to_posix_path "$caller"
        else
            to_posix_path "$(dirname "$caller")"
        fi
        return 0
    fi
    case "$sr" in
        */.agents/skills/*)
            echo "${sr%/.agents/skills/*}"
            return 0
            ;;
        */.claude/skills/*)
            echo "${sr%/.claude/skills/*}"
            return 0
            ;;
        */.codex/skills/*)
            echo "${sr%/.codex/skills/*}"
            return 0
            ;;
        */.cursor/skills/*)
            echo "${sr%/.cursor/skills/*}"
            return 0
            ;;
    esac

    git -C "$sr" rev-parse --show-toplevel 2>/dev/null || pwd
}

_is_plugin_install() {
    local sr="$1"
    [[ "${PENSIEVE_INSTALL_MODE:-}" == "claude-plugin" ]] && return 0
    local dir="$sr"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.claude-plugin" ]]; then
            return 0
        fi
        dir="$(cd "$dir/.." && pwd)"
    done
    return 1
}

user_data_root() {
    if [[ -n "${PENSIEVE_DATA_ROOT:-}" ]]; then
        to_posix_path "$PENSIEVE_DATA_ROOT"
        return 0
    fi
    local sr
    sr="$(skill_root "${1:-$(pwd)}")"
    if _is_plugin_install "$sr"; then
        local pr
        pr="$(project_root "${1:-$(pwd)}")"
        echo "$pr/.claude/skills/pensieve"
        return 0
    fi
    echo "$sr"
}

skill_manifest_file() {
    local sr
    sr="$(skill_root "${1:-$(pwd)}")"
    echo "$sr/.src/manifest.json"
}

skill_version() {
    local sr manifest version
    sr="$(skill_root "${1:-$(pwd)}")"
    manifest="$(skill_manifest_file "$sr")"

    if [[ -f "$manifest" ]]; then
        version="$(json_get_value "$manifest" "version" "")"
        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi
    fi

    if git -C "$sr" rev-parse --short HEAD >/dev/null 2>&1; then
        git -C "$sr" rev-parse --short HEAD
        return 0
    fi

    local schema_file schema_version
    schema_file="$sr/.src/core/schema.json"
    schema_version="$(json_get_value "$schema_file" "schema_version" "unknown")"
    echo "schema-$schema_version"
}

auto_memory_project_key() {
    local pr
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        pr="$CLAUDE_PROJECT_DIR"
    else
        pr="$(project_root "${1:-$(pwd)}")"
    fi
    [[ -n "$pr" ]] || {
        echo ""
        return 0
    }

    local encoded
    encoded="${pr//[:\/\\_]/-}"
    echo "$encoded"
}

auto_memory_dir() {
    local home_dir key
    home_dir="$(to_posix_path "${HOME:-$(cd ~ && pwd)}")"
    key="$(auto_memory_project_key "${1:-$(pwd)}")"
    echo "$home_dir/.claude/projects/$key/memory"
}

auto_memory_file() {
    local dr
    dr="$(auto_memory_dir "${1:-$(pwd)}")"
    echo "$dr/MEMORY.md"
}

project_skill_file() {
    local dr
    dr="$(user_data_root "${1:-$(pwd)}")"
    echo "$dr/SKILL.md"
}

ensure_user_data_root() {
    local dr
    dr="$(user_data_root "${1:-$(pwd)}")"
    mkdir -p "$dr"/{maxims,decisions,knowledge,pipelines,loop}
    echo "$dr"
}

ensure_state_dir() {
    local dir
    dir="${1:-$(state_root "${2:-$(pwd)}")}"
    dir="$(to_posix_path "$dir")"
    mkdir -p "$dir"

    local ignore_file="$dir/.gitignore"
    local payload=""

    if [[ -f "$ignore_file" ]]; then
        payload="$(cat "$ignore_file")"
    fi

    if ! grep -Fxq '*' "$ignore_file" 2>/dev/null; then
        payload="${payload}"$'\n''*'
    fi
    if ! grep -Fxq '!.gitignore' "$ignore_file" 2>/dev/null; then
        payload="${payload}"$'\n''!.gitignore'
    fi

    printf '%s\n' "${payload#$'\n'}" > "$ignore_file"
    echo "$dir"
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
