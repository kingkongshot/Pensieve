#!/bin/bash
# Upgrade runner for a git-cloned Pensieve checkout.
# 1) Detect current skill version
# 2) Refresh via git pull --ff-only
# 3) Record the result
# 4) Tell the user to run doctor manually

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  run-upgrade.sh [options]

Options:
  --state-dir <path>        Runtime state dir. Default: <project>/.pensieve/.state
  --report <path>           Upgrade markdown report. Default: <state-dir>/pensieve-upgrade-report.md
  --summary-json <path>     Upgrade summary json. Default: <state-dir>/pensieve-upgrade-summary.json
  --skip-version-check      Skip git pull and only refresh local reports
  --dry-run                 Print and record actions without changing files
  -h, --help                Show help
USAGE
}

STATE_DIR=""
REPORT=""
SUMMARY_JSON=""
SKIP_VERSION_CHECK=0
DRY_RUN=0

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
    --skip-version-check)
      SKIP_VERSION_CHECK=1
      shift
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

PROJECT_ROOT="$(project_root)" || exit 1
PROJECT_ROOT="$(to_posix_path "$PROJECT_ROOT")"
validate_project_root "$PROJECT_ROOT"
SKILL_ROOT="$(skill_root_from_script "$SCRIPT_DIR")"

if [[ -z "$STATE_DIR" ]]; then
  STATE_DIR="$(state_root)"
fi
STATE_DIR="$(to_posix_path "$STATE_DIR")"
if [[ "$STATE_DIR" != /* ]]; then
  STATE_DIR="$PROJECT_ROOT/$STATE_DIR"
fi

resolve_path() {
  resolve_output_path "$1" "$2" "$PROJECT_ROOT"
}

REPORT="$(resolve_path "$REPORT" "$STATE_DIR/pensieve-upgrade-report.md")"
SUMMARY_JSON="$(resolve_path "$SUMMARY_JSON" "$STATE_DIR/pensieve-upgrade-summary.json")"
VERSION_LOG="$STATE_DIR/pensieve-upgrade-version-check.log"
MAINTAIN_SCRIPT="$SCRIPT_DIR/maintain-project-state.sh"

ensure_state_dir "$STATE_DIR" >/dev/null
mkdir -p "$(dirname "$REPORT")" "$(dirname "$SUMMARY_JSON")"

ensure_python_env
[[ -n "${PYTHON_BIN:-}" ]] || { echo "Python not found" >&2; exit 1; }

if ! git -C "$SKILL_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Pensieve upgrade requires a git checkout at: $SKILL_ROOT" >&2
  exit 1
fi

PRE_VERSION="$(skill_version "$SCRIPT_DIR")"
POST_VERSION="$PRE_VERSION"
UPDATE_STRATEGY="skipped"

handle_upgrade() {
  : >"$VERSION_LOG"

  if [[ "$SKIP_VERSION_CHECK" -eq 1 ]]; then
    echo "[skip] external update command disabled" >>"$VERSION_LOG"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] git -C $SKILL_ROOT pull --ff-only (fallback: fetch+reset)" >>"$VERSION_LOG"
    UPDATE_STRATEGY="git-pull"
    return 0
  fi

  # Try fast-forward first; if remote was force-pushed, fall back to fetch+reset.
  # This is safe because the skill root contains only tracked system files —
  # user data lives at <project>/.pensieve/, not here.
  if git -C "$SKILL_ROOT" pull --ff-only >>"$VERSION_LOG" 2>&1; then
    UPDATE_STRATEGY="git-pull-ff"
  else
    echo "[info] fast-forward failed, falling back to fetch+reset" >>"$VERSION_LOG"
    local branch
    branch="$(git -C "$SKILL_ROOT" rev-parse --abbrev-ref HEAD)"
    git -C "$SKILL_ROOT" fetch origin >>"$VERSION_LOG" 2>&1
    git -C "$SKILL_ROOT" reset --hard "origin/$branch" >>"$VERSION_LOG" 2>&1
    UPDATE_STRATEGY="git-fetch-reset"
  fi
}

if ! handle_upgrade; then
  cat "$VERSION_LOG" >&2
  exit 1
fi

POST_VERSION="$(skill_version "$SCRIPT_DIR")"

"$PYTHON_BIN" - "$REPORT" "$SUMMARY_JSON" "$VERSION_LOG" "$PRE_VERSION" "$POST_VERSION" "$SKIP_VERSION_CHECK" "$DRY_RUN" "$UPDATE_STRATEGY" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

report_file = Path(sys.argv[1])
summary_file = Path(sys.argv[2])
version_log = Path(sys.argv[3])
pre_version = sys.argv[4]
post_version = sys.argv[5]
skip_version_check = sys.argv[6] == "1"
dry_run = sys.argv[7] == "1"
update_strategy = sys.argv[8]

version_changed = pre_version != post_version
status = "DONE"

summary = {
    "status": status,
    "pre_version": pre_version,
    "post_version": post_version,
    "version_changed": version_changed,
    "skip_version_check": skip_version_check,
    "dry_run": dry_run,
    "update_strategy": update_strategy,
    "version_log": str(version_log),
    "next_action": "run doctor",
}
summary_file.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

lines = [
    "# Pensieve Upgrade Report",
    "",
    "## 1) Result",
    f"- Status: {status}",
    f"- Dry-run: {'yes' if dry_run else 'no'}",
    f"- Pre-upgrade version: {pre_version}",
    f"- Post-upgrade version: {post_version}",
    f"- Version changed: {'yes' if version_changed else 'no'}",
    f"- Update strategy: {update_strategy}",
    f"- Skip external update: {'yes' if skip_version_check else 'no'}",
    "",
    "## 2) Next Steps (manual)",
    "- Run doctor manually after upgrade:",
    "```bash",
    'bash "$PENSIEVE_SKILL_ROOT/.src/scripts/run-doctor.sh" --strict',
    "```",
    "",
    "## 3) Files",
    f"- Upgrade log: `{version_log}`",
    f"- Upgrade report: `{report_file}`",
    f"- Upgrade summary: `{summary_file}`",
]

report_file.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
PY

if [[ -x "$MAINTAIN_SCRIPT" ]]; then
  bash "$MAINTAIN_SCRIPT" --event upgrade --note "upgrade completed: pre_version=$PRE_VERSION, post_version=$POST_VERSION, strategy=$UPDATE_STRATEGY" >/dev/null || true
fi

echo "✅ Upgrade completed"
echo "  - pre_version: $PRE_VERSION"
echo "  - post_version: $POST_VERSION"
echo "  - strategy: $UPDATE_STRATEGY"
echo "  - report: $REPORT"
echo "  - summary: $SUMMARY_JSON"

exit 0
