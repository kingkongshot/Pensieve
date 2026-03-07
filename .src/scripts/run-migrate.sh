#!/bin/bash
# Migrate runner (structure-only):
# 1) Migrate legacy user-data paths into the current user data root
# 2) Align critical seed files
# 3) Cleanup legacy graph/readme residues
# 4) Tell user to run doctor manually

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  run-migrate.sh [options]

Options:
  --root <path>             Target user data root. Default: current user data root
  --state-dir <path>        Runtime state dir. Default: <project>/.state
  --report <path>           Migrate markdown report. Default: <state-dir>/pensieve-migrate-report.md
  --summary-json <path>     Migrate summary json. Default: <state-dir>/pensieve-migrate-summary.json
  --backup-dir <path>       Backup dir for replaced files. Default: <state-dir>/migrate-backups/<timestamp>
  --dry-run                 Print and record actions without changing files
  -h, --help                Show help
USAGE
}

ROOT=""
STATE_DIR=""
REPORT=""
SUMMARY_JSON=""
BACKUP_DIR=""
DRY_RUN=0

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
    --dry-run)
      DRY_RUN=1
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

PROJECT_ROOT="$(to_posix_path "$(project_root "$SCRIPT_DIR")")"
if [[ -z "$ROOT" ]]; then
  ROOT="$(user_data_root "$SCRIPT_DIR")"
fi
ROOT="$(to_posix_path "$ROOT")"

if [[ -z "$STATE_DIR" ]]; then
  STATE_DIR="$(state_root "$SCRIPT_DIR")"
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

REPORT="$(resolve_path "$REPORT" "$STATE_DIR/pensieve-migrate-report.md")"
SUMMARY_JSON="$(resolve_path "$SUMMARY_JSON" "$STATE_DIR/pensieve-migrate-summary.json")"

TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
if [[ -z "$BACKUP_DIR" ]]; then
  BACKUP_DIR="$STATE_DIR/migrate-backups/$TIMESTAMP"
fi
BACKUP_DIR="$(resolve_path "$BACKUP_DIR" "$BACKUP_DIR")"

MIGRATION_SUMMARY="$STATE_DIR/pensieve-migration-actions.json"

ensure_state_dir "$STATE_DIR" >/dev/null
mkdir -p "$(dirname "$REPORT")" "$(dirname "$SUMMARY_JSON")"

SKILL_ROOT="$(skill_root_from_script "$SCRIPT_DIR")"
SCHEMA_FILE="$SKILL_ROOT/.src/core/schema.json"
MAINTAIN_SCRIPT="$SCRIPT_DIR/maintain-project-skill.sh"
PYTHON_BIN="$(python_bin || true)"
[[ -n "$PYTHON_BIN" ]] || { echo "Python not found" >&2; exit 1; }

mkdir -p "$BACKUP_DIR"

"$PYTHON_BIN" - "$ROOT" "$PROJECT_ROOT" "$SKILL_ROOT" "${HOME:-}" "$BACKUP_DIR" "$MIGRATION_SUMMARY" "$DRY_RUN" "$TIMESTAMP" "$SCHEMA_FILE" <<'PY'
from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

root = Path(sys.argv[1])
project_root = Path(sys.argv[2])
skill_root = Path(sys.argv[3])
home_dir = Path(sys.argv[4]) if sys.argv[4] else Path.home()
backup_dir = Path(sys.argv[5])
summary_file = Path(sys.argv[6])
dry_run = sys.argv[7] == "1"
timestamp = sys.argv[8]
schema_file = Path(sys.argv[9])


def read_schema(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(f"failed to parse schema: {path} ({exc})")
    if not isinstance(data, dict):
        raise SystemExit(f"invalid schema root: {path}")
    return data


schema = read_schema(schema_file)
required_dirs = [str(x) for x in schema.get("required_dirs", [])]
legacy_paths_schema = schema.get("legacy_paths") if isinstance(schema.get("legacy_paths"), dict) else {}
legacy_project_paths = [project_root / p for p in legacy_paths_schema.get("project", []) if isinstance(p, str)]
legacy_user_paths = [home_dir / p for p in legacy_paths_schema.get("user", []) if isinstance(p, str)]
legacy_paths = legacy_project_paths + legacy_user_paths
legacy_graph_patterns = [str(x) for x in schema.get("legacy_graph_patterns", [])]
legacy_readme_re = re.compile(str(schema.get("legacy_readme_regex", r"(?i)^readme(?:.*\\.md)?$")))

critical_pairs = []
for item in schema.get("critical_files", []):
    if not isinstance(item, dict):
        continue
    target = item.get("target")
    template = item.get("template")
    if not isinstance(target, str) or not isinstance(template, str):
        continue
    critical_pairs.append((root / target, skill_root / template))

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
    if category in {"knowledge"}:
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
    if same_path(legacy, root) or same_path(legacy, skill_root):
        continue
    if not legacy.is_dir():
        continue

    for category in required_dirs:
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
    if same_path(legacy, root) or same_path(legacy, skill_root):
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

"$PYTHON_BIN" - "$REPORT" "$SUMMARY_JSON" "$MIGRATION_SUMMARY" "$ROOT" "$BACKUP_DIR" "$DRY_RUN" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

report_file = Path(sys.argv[1])
summary_file = Path(sys.argv[2])
actions_file = Path(sys.argv[3])
user_root = sys.argv[4]
backup_dir = sys.argv[5]
dry_run = sys.argv[6] == "1"


def load(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


actions = load(actions_file)

created_dirs = actions.get("created_dirs") or []
migrated_files = actions.get("migrated_files") or []
conflicts = actions.get("conflict_files") or []
replaced = actions.get("replaced_critical_files") or []
created_critical = actions.get("created_critical_files") or []
removed_paths = actions.get("removed_legacy_paths") or []
removed_graphs = actions.get("removed_legacy_graph_files") or []
removed_readmes = actions.get("removed_legacy_readmes") or []
warnings = actions.get("warnings") or []

status = "DONE" if not conflicts else "DONE_WITH_CONFLICTS"

summary = {
    "status": status,
    "dry_run": dry_run,
    "user_data_root": user_root,
    "report_file": str(report_file),
    "summary_file": str(summary_file),
    "actions_file": str(actions_file),
    "next_action": "run doctor",
    "counts": {
        "created_dirs": len(created_dirs),
        "migrated_files": len(migrated_files),
        "conflict_files": len(conflicts),
        "replaced_critical_files": len(replaced),
        "created_critical_files": len(created_critical),
        "removed_legacy_paths": len(removed_paths),
        "removed_legacy_graph_files": len(removed_graphs),
        "removed_legacy_readmes": len(removed_readmes),
        "warnings": len(warnings),
    },
}
summary_file.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

lines = [
    "# Pensieve Migrate 报告",
    "",
    "## 1) 结果",
    f"- 状态: {status}",
    f"- Dry-run: {'yes' if dry_run else 'no'}",
    f"- 数据根目录: `{user_root}`",
    "",
    "## 2) 迁移与清理统计",
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
    "## 3) 下一步（手动）",
    "- 迁移完成后请手动运行 doctor：",
    "```bash",
    "bash .src/scripts/run-doctor.sh --strict",
    "```",
    "",
    "## 4) 文件",
    f"- 迁移动作清单: `{actions_file}`",
    f"- 迁移报告: `{report_file}`",
    f"- 迁移摘要: `{summary_file}`",
]

if conflicts:
    lines.append("")
    lines.append("## 5) 冲突文件（需人工合并）")
    for item in conflicts[:30]:
        lines.append(f"- target: `{item.get('target','')}` | migrated: `{item.get('written','')}`")

if warnings:
    lines.append("")
    lines.append("## 6) 警告")
    for w in warnings[:60]:
        lines.append(f"- {w}")

report_file.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
PY

if [[ "$DRY_RUN" -eq 0 && -x "$MAINTAIN_SCRIPT" ]]; then
  bash "$MAINTAIN_SCRIPT" --event migrate --note "migrate completed: user_root=$ROOT, actions=$MIGRATION_SUMMARY" >/dev/null || true
fi

echo "✅ Migrate completed"
echo "  - report: $REPORT"
echo "  - summary: $SUMMARY_JSON"
echo "  - next: run doctor manually"

exit 0
