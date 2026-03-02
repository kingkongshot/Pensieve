#!/bin/bash
# Upgrade runner (version-only):
# 1) Compare plugin version before/after update
# 2) Pull latest plugin
# 3) Align enabledPlugins keys
# 4) Cleanup legacy plugin ids
# 5) Tell user to run doctor manually

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../loop/scripts/_lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  run-upgrade.sh [options]

Options:
  --state-dir <path>        Runtime state dir. Default: <project>/.state
  --report <path>           Upgrade markdown report. Default: <state-dir>/pensieve-upgrade-report.md
  --summary-json <path>     Upgrade summary json. Default: <state-dir>/pensieve-upgrade-summary.json
  --plugin-scope <scope>    Scope for plugin update command: user | project. Default: user
  --skip-version-check      Skip marketplace/plugin update commands
  --dry-run                 Print and record actions without changing files

Compatibility options (accepted but ignored):
  --root <path>             Deprecated. Upgrade no longer mutates user data.
  --backup-dir <path>       Deprecated. Upgrade no longer mutates user data.
  --skip-doctor             Deprecated. Upgrade no longer runs doctor automatically.
  --doctor-strict           Deprecated. Upgrade no longer runs doctor automatically.

  -h, --help                Show help
USAGE
}

STATE_DIR=""
REPORT=""
SUMMARY_JSON=""
PLUGIN_SCOPE="user"
SKIP_VERSION_CHECK=0
DRY_RUN=0

# Deprecated compatibility flags.
ROOT=""
BACKUP_DIR=""
SKIP_DOCTOR=0
DOCTOR_STRICT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for --state-dir" >&2; exit 1; }
      STATE_DIR="$2"
      shift 2
      ;;
    --report)
      [[ $# -ge 2 ]] || { echo "Missing value for --report" >&2; exit 1; }
      REPORT="$2"
      shift 2
      ;;
    --summary-json)
      [[ $# -ge 2 ]] || { echo "Missing value for --summary-json" >&2; exit 1; }
      SUMMARY_JSON="$2"
      shift 2
      ;;
    --plugin-scope)
      [[ $# -ge 2 ]] || { echo "Missing value for --plugin-scope" >&2; exit 1; }
      PLUGIN_SCOPE="$2"
      shift 2
      ;;
    --skip-version-check)
      SKIP_VERSION_CHECK=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --root)
      [[ $# -ge 2 ]] || { echo "Missing value for --root" >&2; exit 1; }
      ROOT="$2"
      shift 2
      ;;
    --backup-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for --backup-dir" >&2; exit 1; }
      BACKUP_DIR="$2"
      shift 2
      ;;
    --skip-doctor)
      SKIP_DOCTOR=1
      shift
      ;;
    --doctor-strict)
      DOCTOR_STRICT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

case "$PLUGIN_SCOPE" in
  user|project)
    ;;
  *)
    echo "Unsupported --plugin-scope: $PLUGIN_SCOPE (expected: user|project)" >&2
    exit 1
    ;;
esac

if [[ -n "$ROOT" || -n "$BACKUP_DIR" || "$SKIP_DOCTOR" -eq 1 || "$DOCTOR_STRICT" -eq 1 ]]; then
  echo "[upgrade] notice: --root/--backup-dir/--skip-doctor/--doctor-strict are deprecated and ignored." >&2
fi

PROJECT_ROOT="$(to_posix_path "$(project_root)")"
if [[ -z "$STATE_DIR" ]]; then
  STATE_DIR="$PROJECT_ROOT/.state"
fi
STATE_DIR="$(to_posix_path "$STATE_DIR")"
if [[ "$STATE_DIR" != /* ]]; then
  STATE_DIR="$PROJECT_ROOT/$STATE_DIR"
fi

resolve_path() {
  local maybe_path="$1"
  local default_path="$2"
  local out
  out="$maybe_path"
  if [[ -z "$out" ]]; then
    out="$default_path"
  fi
  out="$(to_posix_path "$out")"
  if [[ "$out" != /* ]]; then
    out="$PROJECT_ROOT/$out"
  fi
  printf '%s\n' "$out"
}

REPORT="$(resolve_path "$REPORT" "$STATE_DIR/pensieve-upgrade-report.md")"
SUMMARY_JSON="$(resolve_path "$SUMMARY_JSON" "$STATE_DIR/pensieve-upgrade-summary.json")"
VERSION_LOG="$STATE_DIR/pensieve-upgrade-version-check.log"
SETTINGS_SUMMARY="$STATE_DIR/pensieve-upgrade-settings-summary.json"
MAINTAIN_SCRIPT="$SCRIPT_DIR/../../project-skill/scripts/maintain-project-skill.sh"

mkdir -p "$STATE_DIR" "$(dirname "$REPORT")" "$(dirname "$SUMMARY_JSON")"

PLUGIN_ROOT="$(plugin_root_from_script "$SCRIPT_DIR")"
SCHEMA_FILE="$PLUGIN_ROOT/skills/pensieve/tools/core/schema.json"
PYTHON_BIN="$(python_bin || true)"
[[ -n "$PYTHON_BIN" ]] || { echo "Python not found" >&2; exit 1; }

SCHEMA_KEYS="$($PYTHON_BIN - "$SCHEMA_FILE" <<'PY'
import json
import sys
from pathlib import Path

schema_file = Path(sys.argv[1])
try:
    data = json.loads(schema_file.read_text(encoding="utf-8", errors="replace"))
except Exception:
    print("pensieve@kingkongshot-marketplace")
    print("pensieve@Pensieve")
    print("pensieve@pensieve-claude-plugin")
    raise SystemExit(0)

plugin_keys = data.get("plugin_keys") if isinstance(data, dict) else {}
if not isinstance(plugin_keys, dict):
    plugin_keys = {}

current = plugin_keys.get("current")
legacy = plugin_keys.get("legacy")
if not isinstance(current, str) or not current.strip():
    current = "pensieve@kingkongshot-marketplace"
if not isinstance(legacy, list):
    legacy = ["pensieve@Pensieve", "pensieve@pensieve-claude-plugin"]

print(current)
for item in legacy:
    if isinstance(item, str) and item.strip():
        print(item.strip())
PY
)"

CURRENT_PLUGIN_KEY="$(printf '%s\n' "$SCHEMA_KEYS" | sed -n '1p')"
LEGACY_PLUGIN_KEYS=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  LEGACY_PLUGIN_KEYS+=("$line")
done < <(printf '%s\n' "$SCHEMA_KEYS" | sed -n '2,$p')

plugin_version() {
  local scope="$1"
  local plugin_id="$CURRENT_PLUGIN_KEY"
  local list_json
  list_json="$(claude plugin list --json 2>/dev/null || echo '[]')"

  printf '%s' "$list_json" | "$PYTHON_BIN" -c '
import json
import sys

plugin_id, scope = sys.argv[1], sys.argv[2]
try:
    data = json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit(0)

if not isinstance(data, list):
    print("")
    raise SystemExit(0)

for item in data:
    if not isinstance(item, dict):
        continue
    if item.get("id") == plugin_id and item.get("scope") == scope:
        v = item.get("version")
        print(v if isinstance(v, str) else "")
        raise SystemExit(0)

print("")
' "$plugin_id" "$scope"
}

run_version_check() {
  : > "$VERSION_LOG"

  if ! command -v claude >/dev/null 2>&1; then
    echo "claude command not found; cannot perform version check/update" >&2
    return 2
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    {
      echo "[dry-run] CLAUDECODE= claude plugin marketplace update kingkongshot/Pensieve"
      echo "[dry-run] CLAUDECODE= claude plugin update $CURRENT_PLUGIN_KEY --scope $PLUGIN_SCOPE"
    } >>"$VERSION_LOG"
    return 0
  fi

  local rc=0
  {
    echo "[upgrade] running marketplace update..."
    env CLAUDECODE= claude plugin marketplace update kingkongshot/Pensieve
    echo "[upgrade] running plugin update (scope=$PLUGIN_SCOPE)..."
    env CLAUDECODE= claude plugin update "$CURRENT_PLUGIN_KEY" --scope "$PLUGIN_SCOPE"
  } >>"$VERSION_LOG" 2>&1 || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "version update failed, see: $VERSION_LOG" >&2
    return "$rc"
  fi
  return 0
}

update_settings_keys() {
  local user_settings project_settings
  user_settings="$(to_posix_path "${HOME}/.claude/settings.json")"
  project_settings="$PROJECT_ROOT/.claude/settings.json"

  "$PYTHON_BIN" - "$user_settings" "$project_settings" "$SETTINGS_SUMMARY" "$DRY_RUN" "$CURRENT_PLUGIN_KEY" "${LEGACY_PLUGIN_KEYS[@]}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

user_settings = Path(sys.argv[1])
project_settings = Path(sys.argv[2])
summary_path = Path(sys.argv[3])
dry_run = sys.argv[4] == "1"
new_key = sys.argv[5]
old_keys = [x for x in sys.argv[6:] if x]

summary = {"updated": [], "created": [], "warnings": []}


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def process(path: Path) -> None:
    if not path.exists():
        summary["created"].append(str(path))
        if dry_run:
            return
        ensure_parent(path)
        path.write_text(
            json.dumps({"enabledPlugins": {new_key: True}}, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        return

    try:
        data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except Exception as exc:  # noqa: BLE001
        summary["warnings"].append(f"{path}: parse error ({exc})")
        return

    if not isinstance(data, dict):
        summary["warnings"].append(f"{path}: root is not JSON object")
        return

    enabled = data.get("enabledPlugins")
    if enabled is None:
        enabled = {}
        data["enabledPlugins"] = enabled
    if not isinstance(enabled, dict):
        summary["warnings"].append(f"{path}: enabledPlugins is not object")
        return

    changed = False
    for key in old_keys:
        if key in enabled:
            enabled.pop(key, None)
            changed = True
    if enabled.get(new_key) is not True:
        enabled[new_key] = True
        changed = True

    if changed:
        summary["updated"].append(str(path))
        if not dry_run:
            path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


for target in [user_settings, project_settings]:
    process(target)

summary_path.parent.mkdir(parents=True, exist_ok=True)
summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

cleanup_legacy_plugins() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  if ! command -v claude >/dev/null 2>&1; then
    return 0
  fi

  local legacy
  for legacy in "${LEGACY_PLUGIN_KEYS[@]}"; do
    env CLAUDECODE= claude plugin uninstall "$legacy" --scope user >/dev/null 2>&1 || true
    env CLAUDECODE= claude plugin uninstall "$legacy" --scope project >/dev/null 2>&1 || true
  done
}

PRE_VERSION=""
POST_VERSION=""
VERSION_CHANGED="unknown"

if command -v claude >/dev/null 2>&1; then
  PRE_VERSION="$(plugin_version "$PLUGIN_SCOPE")"
fi

if [[ "$SKIP_VERSION_CHECK" -eq 0 ]]; then
  run_version_check
fi

if command -v claude >/dev/null 2>&1; then
  POST_VERSION="$(plugin_version "$PLUGIN_SCOPE")"
fi

if [[ -n "$PRE_VERSION" && -n "$POST_VERSION" ]]; then
  if [[ "$PRE_VERSION" == "$POST_VERSION" ]]; then
    VERSION_CHANGED="no"
  else
    VERSION_CHANGED="yes"
  fi
elif [[ -z "$PRE_VERSION" && -n "$POST_VERSION" ]]; then
  VERSION_CHANGED="installed"
elif [[ -n "$PRE_VERSION" && -z "$POST_VERSION" ]]; then
  VERSION_CHANGED="missing_after_update"
else
  VERSION_CHANGED="unknown"
fi

update_settings_keys
cleanup_legacy_plugins
if [[ "$DRY_RUN" -eq 0 && -x "$MAINTAIN_SCRIPT" ]]; then
  bash "$MAINTAIN_SCRIPT" --event upgrade --note "upgrade completed: scope=$PLUGIN_SCOPE, pre_version=${PRE_VERSION:-unknown}, post_version=${POST_VERSION:-unknown}, changed=$VERSION_CHANGED" >/dev/null || true
fi

"$PYTHON_BIN" - "$REPORT" "$SUMMARY_JSON" "$SETTINGS_SUMMARY" "$VERSION_LOG" "$PLUGIN_SCOPE" "$PRE_VERSION" "$POST_VERSION" "$VERSION_CHANGED" "$SKIP_VERSION_CHECK" "$DRY_RUN" "$CURRENT_PLUGIN_KEY" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

report_file = Path(sys.argv[1])
summary_file = Path(sys.argv[2])
settings_file = Path(sys.argv[3])
version_log = sys.argv[4]
plugin_scope = sys.argv[5]
pre_version = sys.argv[6]
post_version = sys.argv[7]
version_changed = sys.argv[8]
skip_version_check = sys.argv[9] == "1"
dry_run = sys.argv[10] == "1"
plugin_key = sys.argv[11]


def load(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


settings = load(settings_file)
settings_updated = settings.get("updated") or []
settings_created = settings.get("created") or []
settings_warnings = settings.get("warnings") or []

status = "DONE"
if version_changed == "missing_after_update":
    status = "WARN"

summary = {
    "status": status,
    "plugin_scope": plugin_scope,
    "plugin_key": plugin_key,
    "pre_version": pre_version,
    "post_version": post_version,
    "version_changed": version_changed,
    "skip_version_check": skip_version_check,
    "dry_run": dry_run,
    "report_file": str(report_file),
    "summary_file": str(summary_file),
    "settings_summary_file": str(settings_file),
    "version_log": version_log,
    "next_action": "run doctor",
}
summary_file.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

lines = [
    "# Pensieve Upgrade 报告",
    "",
    "## 1) 结果",
    f"- 状态: {status}",
    f"- Scope: {plugin_scope}",
    f"- 插件键: {plugin_key}",
    f"- 升级前版本: {pre_version or '(unknown)'}",
    f"- 升级后版本: {post_version or '(unknown)'}",
    f"- 版本是否变化: {version_changed}",
    f"- 跳过版本检查: {'yes' if skip_version_check else 'no'}",
    f"- Dry-run: {'yes' if dry_run else 'no'}",
    "",
    "## 2) 配置对齐统计",
    f"- settings 已更新: {len(settings_updated)}",
    f"- settings 已创建: {len(settings_created)}",
    f"- settings 警告: {len(settings_warnings)}",
    "",
    "## 3) 边界说明",
    "- Upgrade 仅处理版本与插件配置，不执行用户数据迁移或关键文件替换。",
    "- 结构迁移与旧路径清理请运行 migrate。",
    "",
    "## 4) 下一步（手动）",
    "- 升级后建议先运行 doctor：",
    "```bash",
    "bash <SYSTEM_SKILL_ROOT>/tools/doctor/scripts/run-doctor.sh --strict",
    "```",
    "",
    "## 5) 文件",
    f"- 升级日志: `{version_log}`",
    f"- 升级报告: `{report_file}`",
    f"- 升级摘要: `{summary_file}`",
]

if settings_warnings:
    lines.append("")
    lines.append("## 6) 警告")
    for w in settings_warnings[:60]:
        lines.append(f"- {w}")

report_file.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
PY

echo "✅ Upgrade completed"
echo "  - pre_version: ${PRE_VERSION:-unknown}"
echo "  - post_version: ${POST_VERSION:-unknown}"
echo "  - version_changed: $VERSION_CHANGED"
echo "  - report: $REPORT"
echo "  - summary: $SUMMARY_JSON"
echo "  - next: run doctor manually"

exit 0
