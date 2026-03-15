#!/bin/bash
# Pensieve shared library
#
# Conventions (v2):
# - The skill root is the global git checkout at ~/.claude/skills/pensieve/.
# - Tracked system files live under .src/, agents/, and SKILL.md (static, tracked).
# - User data lives at <project>/.pensieve/ (maxims/decisions/knowledge/pipelines).
# - Dynamic project state lives at <project>/.pensieve/state.md.
# - Hidden runtime state lives under <project>/.pensieve/.state/.

# Sync marker: v2026-03-10 — run-hook.sh has a standalone copy; keep in sync.
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
        if [[ -f "$dir/.src/manifest.json" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(cd "$dir/.." && pwd)"
    done

    echo "Failed to locate skill root from: $script_dir" >&2
    return 1
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
            local pr
            pr="$(project_root "$caller")" || { echo "state_root: project_root failed" >&2; return 1; }
            echo "$pr/$state_dir"
        fi
        return 0
    fi

    local pr
    pr="$(project_root "$caller")" || { echo "state_root: project_root failed" >&2; return 1; }
    echo "$pr/.pensieve/.state"
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

    # v2: skill root lives at user-level (~/.claude/skills/pensieve/), so we
    # cannot derive project root from it. Use the caller's directory context.
    local start_dir
    if [[ -d "$caller" ]]; then
        start_dir="$caller"
    else
        start_dir="$(dirname "$caller")"
    fi

    # Try git first from the caller's directory.
    # But skip if the result is the skill root itself (v2: skill root is a
    # separate git repo at user-level, not the project).
    local git_root
    if git_root="$(git -C "$start_dir" rev-parse --show-toplevel 2>/dev/null)"; then
        git_root="$(to_posix_path "$git_root")"
        local sr_check
        if sr_check="$(skill_root "$caller" 2>/dev/null)" && [[ "$git_root" == "$sr_check" ]]; then
            : # git root is the skill root, not the project — skip
        else
            echo "$git_root"
            return 0
        fi
    fi

    # Walk up looking for .pensieve/ directory (v2 project marker).
    local dir
    dir="$(cd "$start_dir" && pwd)"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.pensieve" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(cd "$dir/.." && pwd)"
    done

    echo "project_root: unable to determine project root from '$start_dir'. Set PENSIEVE_PROJECT_ROOT or cd into your project." >&2
    return 1
}

user_data_root() {
    if [[ -n "${PENSIEVE_DATA_ROOT:-}" ]]; then
        to_posix_path "$PENSIEVE_DATA_ROOT"
        return 0
    fi
    local pr
    pr="$(project_root "${1:-$(pwd)}")" || { echo "user_data_root: project_root failed" >&2; return 1; }
    echo "$pr/.pensieve"
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

project_state_file() {
    local dr
    dr="$(user_data_root "${1:-$(pwd)}")"
    echo "$dr/state.md"
}

skill_md_file() {
    local sr
    sr="$(skill_root "${1:-$(pwd)}")"
    echo "$sr/SKILL.md"
}

project_graph_file() {
    local sr
    sr="$(state_root "${1:-$(pwd)}")"
    echo "$sr/pensieve-user-data-graph.md"
}

ensure_user_data_root() {
    local dr
    dr="$(user_data_root "${1:-$(pwd)}")"
    mkdir -p "$dr"/{maxims,decisions,knowledge,pipelines}
    echo "$dr"
}

ensure_ignore_all() {
    local dir="$1"
    local ignore_file="$dir/.gitignore"

    if grep -Fxq '*' "$ignore_file" 2>/dev/null; then
        return 0
    fi

    local payload=""
    if [[ -f "$ignore_file" ]]; then
        payload="$(cat "$ignore_file")"
    fi
    payload="${payload}"$'\n''*'

    printf '%s\n' "${payload#$'\n'}" > "$ignore_file"
}

ensure_state_dir() {
    local dir
    dir="${1:-$(state_root "${2:-$(pwd)}")}" || return 1
    dir="$(to_posix_path "$dir")"
    if ! mkdir -p "$dir"; then
        echo "ensure_state_dir: failed to create $dir" >&2
        return 1
    fi
    ensure_ignore_all "$dir"
    echo "$dir"
}

python_bin() {
    command -v python3 || command -v python
}

runtime_now_utc() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
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

resolve_output_path() {
    local maybe_path="$1"
    local default_path="$2"
    local project_dir="${3:-$(project_root "$(pwd)")}"
    local out
    out="$maybe_path"
    if [[ -z "$out" ]]; then
        out="$default_path"
    fi
    out="$(to_posix_path "$out")"
    if [[ "$out" != /* ]]; then
        out="$project_dir/$out"
    fi
    printf '%s\n' "$out"
}

# Validate that a resolved project root is reasonable.
# Rejects $HOME itself, filesystem root, and /tmp to prevent accidental
# data writes when scripts are invoked from outside a project directory.
validate_project_root() {
    local root="$1"

    if [[ -z "$root" ]]; then
        echo "Refusing to use empty string as project root. Set PENSIEVE_PROJECT_ROOT or cd into your project directory first." >&2
        return 1
    fi

    local home_dir
    home_dir="$(to_posix_path "$HOME")"

    case "$root" in
        /|/tmp|/tmp/*)
            echo "Refusing to use '$root' as project root. cd into your project directory first." >&2
            return 1
            ;;
    esac

    if [[ "$root" == "$home_dir" ]]; then
        echo "Refusing to use home directory '$root' as project root. cd into your project directory first." >&2
        return 1
    fi

    # Reject skill root itself — it contains .src/manifest.json but is not a project.
    if [[ -f "$root/.src/manifest.json" ]]; then
        echo "Refusing to use skill root '$root' as project root. cd into your project directory first." >&2
        return 1
    fi

    return 0
}
