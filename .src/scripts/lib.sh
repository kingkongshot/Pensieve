#!/bin/bash
# Pensieve shared library
#
# Conventions (v2):
# - The skill root is the global git checkout at ~/.claude/skills/pensieve/.
# - Tracked system files live under .src/, agents/, and SKILL.md (static, tracked).
# - User data lives at <project>/.pensieve/ (maxims/decisions/knowledge/pipelines).
# - Dynamic project state lives at <project>/.pensieve/state.md.
# - Hidden runtime state lives under <project>/.pensieve/.state/.

# Resolve home directory reliably across platforms.
# Priority: $HOME > $USERPROFILE (Windows) > cd ~ (tilde expansion).
resolve_home() {
    if [[ -n "${HOME:-}" ]]; then
        to_posix_path "$HOME"
        return 0
    fi
    # Windows: USERPROFILE is always set by the OS.
    if [[ -n "${USERPROFILE:-}" ]]; then
        to_posix_path "$USERPROFILE"
        return 0
    fi
    # Last resort: tilde expansion (works in bash even without HOME).
    local h
    if h="$(cd ~ 2>/dev/null && pwd)"; then
        echo "$h"
        return 0
    fi
    echo "resolve_home: cannot determine home directory" >&2
    return 1
}

# Ensure HOME is set and POSIX-normalized. Call early in scripts that depend on $HOME.
# Exports HOME so child processes (Python, sub-scripts) also see it.
ensure_home() {
    if [[ -z "${HOME:-}" ]]; then
        HOME="$(resolve_home)" || return 1
    else
        HOME="$(to_posix_path "$HOME")"
    fi
    export HOME
}

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
    local dir prev_dir
    dir="$(cd "$script_dir" && pwd)"

    local depth=0
    while [[ $depth -lt 50 ]]; do
        if [[ -f "$dir/.src/manifest.json" ]]; then
            echo "$dir"
            return 0
        fi
        prev_dir="$dir"
        dir="$(cd "$dir/.." && pwd)"
        # Reached filesystem root (Unix "/" or Windows drive root "/c").
        [[ "$dir" != "$prev_dir" ]] || break
        depth=$((depth + 1))
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
        local pr_env
        pr_env="$(to_posix_path "$PENSIEVE_PROJECT_ROOT")"
        if [[ -d "$pr_env" ]]; then
            echo "$pr_env"
            return 0
        fi
        echo "project_root: PENSIEVE_PROJECT_ROOT='$PENSIEVE_PROJECT_ROOT' does not exist, falling back to detection" >&2
    fi

    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        local cd_env
        cd_env="$(to_posix_path "$CLAUDE_PROJECT_DIR")"
        if [[ -d "$cd_env" ]]; then
            echo "$cd_env"
            return 0
        fi
        echo "project_root: CLAUDE_PROJECT_DIR='$CLAUDE_PROJECT_DIR' does not exist, falling back to detection" >&2
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
    local dir prev_dir
    dir="$(cd "$start_dir" && pwd)"
    local depth=0
    while [[ $depth -lt 50 ]]; do
        if [[ -d "$dir/.pensieve" ]]; then
            echo "$dir"
            return 0
        fi
        prev_dir="$dir"
        dir="$(cd "$dir/.." && pwd)"
        [[ "$dir" != "$prev_dir" ]] || break
        depth=$((depth + 1))
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
        # Normalize to POSIX before encoding — ensures the same key regardless
        # of whether the caller or env var uses Windows vs POSIX paths.
        pr="$(to_posix_path "$CLAUDE_PROJECT_DIR")"
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
    home_dir="$(resolve_home)" || { echo "auto_memory_dir: cannot resolve home" >&2; return 1; }
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
    mkdir -p "$dr"/short-term/{maxims,decisions,knowledge,pipelines}
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
    local p3
    p3="$(command -v python3 2>/dev/null)" || true
    # Validate python3 is real (Windows Store stub exits non-zero on --version).
    if [[ -n "$p3" ]] && "$p3" --version >/dev/null 2>&1; then
        echo "$p3"
        return 0
    fi
    command -v python
}

# Set up runtime environment for Windows compatibility.
# - Ensures HOME is set (falls back to USERPROFILE on Windows).
# - PYTHONIOENCODING=utf-8: prevents UnicodeEncodeError on GBK terminals
#   when printing emoji/CJK characters.
# - Resolves and exports PYTHON_BIN so callers don't repeat detection.
ensure_python_env() {
    ensure_home || true
    export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"
    if [[ -z "${PYTHON_BIN:-}" ]]; then
        PYTHON_BIN="$(python_bin || true)"
        export PYTHON_BIN
    fi
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
    home_dir="$(resolve_home 2>/dev/null)" || home_dir=""

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
