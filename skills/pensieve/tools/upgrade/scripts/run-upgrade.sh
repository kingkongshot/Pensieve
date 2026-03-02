#!/bin/bash
# Simplified upgrade runner:
# 1) Compare plugin version before/after update
# 2) Pull latest plugin
# 3) Cleanup legacy plugin residues and deprecated paths
# 4) Tell user to run doctor manually

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../loop/scripts/_lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  run-upgrade.sh [options]

Options:
  --root <path>             Target user data root. Default: <project>/.claude/skills/pensieve
  --state-dir <path>        Runtime state dir. Default: <project>/.state
  --report <path>           Upgrade markdown report. Default: <state-dir>/pensieve-upgrade-report.md
  --summary-json <path>     Upgrade summary json. Default: <state-dir>/pensieve-upgrade-summary.json
  --backup-dir <path>       Backup dir for replaced files. Default: <state-dir>/upgrade-backups/<timestamp>
  --plugin-scope <scope>    Scope for plugin update command: user | project. Default: user
  --skip-version-check      Skip marketplace/plugin update commands
  --dry-run                 Print and record actions without changing files

Compatibility options (accepted but ignored):
  --skip-doctor             Deprecated. Upgrade no longer runs doctor automatically.
  --doctor-strict           Deprecated. Upgrade no longer runs doctor automatically.

  -h, --help                Show help
USAGE
}

ROOT=""
STATE_DIR=""
REPORT=""
SUMMARY_JSON=""
BACKUP_DIR=""
PLUGIN_SCOPE="user"
SKIP_VERSION_CHECK=0
DRY_RUN=0

# Deprecated compatibility flags.
SKIP_DOCTOR=0
DOCTOR_STRICT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || { echo "Missing value for --root" >&2; exit 1; }
      ROOT="$2"
      shift 2
      ;;
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
    --backup-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for --backup-dir" >&2; exit 1; }
      BACKUP_DIR="$2"
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

if [[ "$SKIP_DOCTOR" -eq 1 || "$DOCTOR_STRICT" -eq 1 ]]; then
  echo "[upgrade] notice: --skip-doctor/--doctor-strict are deprecated and ignored." >&2
fi

PROJECT_ROOT="$(to_posix_path "$(project_root)")"
if [[ -z "$ROOT" ]]; then
  ROOT="$(user_data_root)"
fi
ROOT="$(to_posix_path "$ROOT")"

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

TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
if [[ -z "$BACKUP_DIR" ]]; then
  BACKUP_DIR="$STATE_DIR/upgrade-backups/$TIMESTAMP"
fi
BACKUP_DIR="$(resolve_path "$BACKUP_DIR" "$BACKUP_DIR")"

VERSION_LOG="$STATE_DIR/pensieve-upgrade-version-check.log"
MIGRATION_SUMMARY="$STATE_DIR/pensieve-upgrade-migration-summary.json"
SETTINGS_SUMMARY="$STATE_DIR/pensieve-upgrade-settings-summary.json"

mkdir -p "$STATE_DIR" "$(dirname "$REPORT")" "$(dirname "$SUMMARY_JSON")"

MAINTAIN_SCRIPT="$SCRIPT_DIR/../../project-skill/scripts/maintain-project-skill.sh"
PYTHON_BIN="$(python_bin || true)"
[[ -n "$PYTHON_BIN" ]] || { echo "Python not found" >&2; exit 1; }

plugin_version() {
  local scope="$1"
  local plugin_id="pensieve@kingkongshot-marketplace"
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
      echo "[dry-run] CLAUDECODE= claude plugin update pensieve@kingkongshot-marketplace --scope $PLUGIN_SCOPE"
    } >>"$VERSION_LOG"
    return 0
  fi

  local rc=0
  {
    echo "[upgrade] running marketplace update..."
    env CLAUDECODE= claude plugin marketplace update kingkongshot/Pensieve
    echo "[upgrade] running plugin update (scope=$PLUGIN_SCOPE)..."
    env CLAUDECODE= claude plugin update pensieve@kingkongshot-marketplace --scope "$PLUGIN_SCOPE"
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

  "$PYTHON_BIN" - "$user_settings" "$project_settings" "$SETTINGS_SUMMARY" "$DRY_RUN" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

user_settings = Path(sys.argv[1])
project_settings = Path(sys.argv[2])
summary_path = Path(sys.argv[3])
dry_run = sys.argv[4] == "1"

old_keys = ["pensieve@Pensieve", "pensieve@pensieve-claude-plugin"]
new_key = "pensieve@kingkongshot-marketplace"

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

  env CLAUDECODE= claude plugin uninstall pensieve@Pensieve --scope user >/dev/null 2>&1 || true
  env CLAUDECODE= claude plugin uninstall pensieve@pensieve-claude-plugin --scope user >/dev/null 2>&1 || true
  env CLAUDECODE= claude plugin uninstall pensieve@Pensieve --scope project >/dev/null 2>&1 || true
  env CLAUDECODE= claude plugin uninstall pensieve@pensieve-claude-plugin --scope project >/dev/null 2>&1 || true
}

run_cleanup_and_migrate() {
  local plugin_root home_dir
  plugin_root="$(plugin_root_from_script "$SCRIPT_DIR")"
  home_dir="$(to_posix_path "${HOME:-}")"
  mkdir -p "$BACKUP_DIR"

  "$PYTHON_BIN" - "$ROOT" "$PROJECT_ROOT" "$plugin_root" "$home_dir" "$BACKUP_DIR" "$MIGRATION_SUMMARY" "$DRY_RUN" "$TIMESTAMP" <<'PY'
from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

root = Path(sys.argv[1])
project_root = Path(sys.argv[2])
plugin_root = Path(sys.argv[3])
home_dir = Path(sys.argv[4]) if sys.argv[4] else Path.home()
backup_dir = Path(sys.argv[5])
summary_file = Path(sys.argv[6])
dry_run = sys.argv[7] == "1"
timestamp = sys.argv[8]

required_dirs = ["maxims", "decisions", "knowledge", "pipelines", "loop"]
legacy_paths = [
    project_root / "skills" / "pensieve",
    project_root / ".claude" / "pensieve",
    home_dir / ".claude" / "skills" / "pensieve",
    home_dir / ".claude" / "pensieve",
]
plugin_skill_root = plugin_root / "skills" / "pensieve"
legacy_graph_patterns = ["_pensieve-graph*.md", "pensieve-graph*.md", "graph*.md"]
legacy_readme_re = re.compile(r"(?i)^readme(?:.*\.md)?$")

critical_pairs = [
    (
        root / "pipelines" / "run-when-reviewing-code.md",
        plugin_skill_root / "tools" / "upgrade" / "templates" / "pipeline.run-when-reviewing-code.md",
    ),
    (
        root / "pipelines" / "run-when-committing.md",
        plugin_skill_root / "tools" / "upgrade" / "templates" / "pipeline.run-when-committing.md",
    ),
    (
        root / "knowledge" / "taste-review" / "content.md",
        plugin_skill_root / "knowledge" / "taste-review" / "content.md",
    ),
]

summary = {
    "dry_run": dry_run,
    "created_dirs": [],
    "migrated_files": [],
    "conflict_files": [],
    "replaced_critical_files": [],
    "created_critical_files": [],
    "removed_legacy_paths": [],
    "removed_legacy_graph_files": [],
    "removed_legacy_readmes": [],
    "warnings": [],
}


def same_path(a: Path, b: Path) -> bool:
    try:
        return a.resolve() == b.resolve()
    except Exception:  # noqa: BLE001
        return False


def ensure_dir(path: Path) -> None:
    if path.is_dir():
        return
    summary["created_dirs"].append(str(path))
    if not dry_run:
        path.mkdir(parents=True, exist_ok=True)


def is_readme(name: str) -> bool:
    return bool(legacy_readme_re.match(name))


def backup_copy(path: Path) -> Path:
    rel = path.relative_to(root)
    dst = backup_dir / rel
    dst = dst.with_suffix(dst.suffix + f".bak.{timestamp}")
    if not dry_run:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dst)
    return dst


def copy_with_conflict(src: Path, dst: Path) -> None:
    if not dst.exists():
        summary["migrated_files"].append({"from": str(src), "to": str(dst), "mode": "copied"})
        if not dry_run:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
        return

    try:
        same = src.read_bytes() == dst.read_bytes()
    except Exception:  # noqa: BLE001
        same = False
    if same:
        summary["migrated_files"].append({"from": str(src), "to": str(dst), "mode": "identical-skip"})
        return

    conflict = dst.with_name(f"{dst.stem}.migrated.{timestamp}{dst.suffix}")
    summary["conflict_files"].append({"from": str(src), "target": str(dst), "written": str(conflict)})
    if not dry_run:
        conflict.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, conflict)


def iter_category_files(base: Path, category: str):
    cat_dir = base / category
    if not cat_dir.is_dir():
        return
    if category in {"knowledge", "loop"}:
        for p in sorted(cat_dir.rglob("*")):
            if p.is_file() and not is_readme(p.name):
                yield p, p.relative_to(cat_dir)
        return

    for p in sorted(cat_dir.rglob("*.md")):
        if not p.is_file():
            continue
        name = p.name
        if is_readme(name):
            continue
        if category == "maxims" and name.startswith("_"):
            continue

        rel = p.relative_to(cat_dir)
        if category == "pipelines":
            if rel.name == "review.md":
                rel = rel.with_name("run-when-reviewing-code.md")
            elif rel.name.startswith("pipeline.run-when-"):
                rel = rel.with_name(rel.name[len("pipeline.") :])
        yield p, rel


ensure_dir(root)
for d in required_dirs:
    ensure_dir(root / d)

for legacy in legacy_paths:
    if same_path(legacy, root) or same_path(legacy, plugin_skill_root):
        continue
    if not legacy.is_dir():
        continue

    for category in ["maxims", "decisions", "knowledge", "pipelines", "loop"]:
        for src_file, rel in iter_category_files(legacy, category) or []:
            dst = root / category / rel
            copy_with_conflict(src_file, dst)

for pattern in legacy_graph_patterns:
    for path in sorted(root.glob(pattern)):
        if not path.is_file():
            continue
        summary["removed_legacy_graph_files"].append(str(path))
        if not dry_run:
            path.unlink(missing_ok=True)

for category in required_dirs:
    cat_dir = root / category
    if not cat_dir.is_dir():
        continue
    for item in sorted(cat_dir.iterdir()):
        if item.is_file() and is_readme(item.name):
            summary["removed_legacy_readmes"].append(str(item))
            if not dry_run:
                item.unlink(missing_ok=True)

for target, template in critical_pairs:
    if not template.is_file():
        summary["warnings"].append(f"missing template: {template}")
        continue
    template_text = template.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")

    if not target.exists():
        summary["created_critical_files"].append(str(target))
        if not dry_run:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(template_text, encoding="utf-8")
        continue

    current_text = target.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")
    if current_text == template_text:
        continue

    backup_path = backup_copy(target)
    summary["replaced_critical_files"].append({"file": str(target), "backup": str(backup_path)})
    if not dry_run:
        target.write_text(template_text, encoding="utf-8")

for legacy in legacy_paths:
    if same_path(legacy, root) or same_path(legacy, plugin_skill_root):
        continue
    if not legacy.exists():
        continue
    summary["removed_legacy_paths"].append(str(legacy))
    if not dry_run:
        if legacy.is_dir():
            shutil.rmtree(legacy, ignore_errors=True)
        else:
            legacy.unlink(missing_ok=True)

summary_file.parent.mkdir(parents=True, exist_ok=True)
summary_file.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
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
run_cleanup_and_migrate

if [[ "$DRY_RUN" -eq 0 && -x "$MAINTAIN_SCRIPT" ]]; then
  bash "$MAINTAIN_SCRIPT" --event upgrade --note "upgrade completed: pre_version=${PRE_VERSION:-unknown}, post_version=${POST_VERSION:-unknown}, changed=$VERSION_CHANGED" >/dev/null || true
fi

"$PYTHON_BIN" - "$REPORT" "$SUMMARY_JSON" "$MIGRATION_SUMMARY" "$SETTINGS_SUMMARY" "$PROJECT_ROOT" "$ROOT" "$BACKUP_DIR" "$VERSION_LOG" "$PLUGIN_SCOPE" "$PRE_VERSION" "$POST_VERSION" "$VERSION_CHANGED" "$SKIP_VERSION_CHECK" "$DRY_RUN" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

report_file = Path(sys.argv[1])
summary_file = Path(sys.argv[2])
migration_file = Path(sys.argv[3])
settings_file = Path(sys.argv[4])
project_root = sys.argv[5]
user_root = sys.argv[6]
backup_dir = sys.argv[7]
version_log = sys.argv[8]
plugin_scope = sys.argv[9]
pre_version = sys.argv[10]
post_version = sys.argv[11]
version_changed = sys.argv[12]
skip_version_check = sys.argv[13] == "1"
dry_run = sys.argv[14] == "1"


def load(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


migration = load(migration_file)
settings = load(settings_file)

created_dirs = migration.get("created_dirs") or []
migrated_files = migration.get("migrated_files") or []
conflicts = migration.get("conflict_files") or []
replaced = migration.get("replaced_critical_files") or []
created_critical = migration.get("created_critical_files") or []
removed_paths = migration.get("removed_legacy_paths") or []
removed_graphs = migration.get("removed_legacy_graph_files") or []
removed_readmes = migration.get("removed_legacy_readmes") or []
warnings = migration.get("warnings") or []

settings_updated = settings.get("updated") or []
settings_created = settings.get("created") or []
settings_warnings = settings.get("warnings") or []

status = "DONE"
if version_changed == "missing_after_update":
    status = "WARN"

summary = {
    "status": status,
    "plugin_scope": plugin_scope,
    "pre_version": pre_version,
    "post_version": post_version,
    "version_changed": version_changed,
    "skip_version_check": skip_version_check,
    "dry_run": dry_run,
    "report_file": str(report_file),
    "summary_file": str(summary_file),
    "migration_summary_file": str(migration_file),
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
    f"- 升级前版本: {pre_version or '(unknown)'}",
    f"- 升级后版本: {post_version or '(unknown)'}",
    f"- 版本是否变化: {version_changed}",
    f"- 跳过版本检查: {'yes' if skip_version_check else 'no'}",
    f"- Dry-run: {'yes' if dry_run else 'no'}",
    "",
    "## 2) 清理与迁移统计",
    f"- 创建目录: {len(created_dirs)}",
    f"- 迁移文件: {len(migrated_files)}",
    f"- 冲突落盘(*.migrated.*): {len(conflicts)}",
    f"- 关键文件替换: {len(replaced)}",
    f"- 关键文件补齐: {len(created_critical)}",
    f"- 删除旧路径: {len(removed_paths)}",
    f"- 删除旧 graph 文件: {len(removed_graphs)}",
    f"- 删除历史 README 副本: {len(removed_readmes)}",
    f"- 备份目录: `{backup_dir}`",
    "",
    "## 3) settings.json 对齐",
    f"- 已更新: {len(settings_updated)}",
    f"- 已创建: {len(settings_created)}",
    f"- 警告: {len(settings_warnings)}",
    "",
    "## 4) 下一步（手动）",
    "- 升级完成后请手动运行 doctor：",
    "```bash",
    "bash <SYSTEM_SKILL_ROOT>/tools/doctor/scripts/run-doctor.sh --strict",
    "```",
    "",
    "## 5) 文件",
    f"- 升级日志: `{version_log}`",
    f"- 升级报告: `{report_file}`",
    f"- 升级摘要: `{summary_file}`",
]

if conflicts:
    lines.append("")
    lines.append("## 6) 冲突文件（需人工合并）")
    for item in conflicts[:30]:
        lines.append(f"- target: `{item.get('target','')}` | migrated: `{item.get('written','')}`")

if settings_warnings or warnings:
    lines.append("")
    lines.append("## 7) 警告")
    for w in (settings_warnings + warnings)[:60]:
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
