#!/bin/bash
# End-to-end doctor runner: execute scanners, merge findings, and emit fixed-format report.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  run-doctor.sh [options]

Options:
  --root <path>             Scan root. Default: current user data root
  --state-dir <path>        Runtime state dir. Default: <project>/.pensieve/.state
  --report <path>           Markdown report path. Default: <state-dir>/pensieve-doctor-report.md
  --summary-json <path>     Summary json path. Default: <state-dir>/pensieve-doctor-summary.json
  --scan-output <path>      Structure scan json path. Default: <state-dir>/pensieve-structure-scan.json
  --frontmatter-output <path> Frontmatter scan json path. Default: <state-dir>/pensieve-frontmatter-scan.json
  --graph-output <path>     Graph markdown path. Default: <state-dir>/pensieve-user-data-graph.md
  --skip-maintain-state     Skip maintain-project-state after report generation
  --strict                  Exit 3 when final status is FAIL
  -h, --help                Show help
USAGE
}

ROOT=""
STATE_DIR=""
REPORT=""
SUMMARY_JSON=""
SCAN_OUTPUT=""
FRONTMATTER_OUTPUT=""
GRAPH_OUTPUT=""
SKIP_MAINTAIN_STATE=0
STRICT_MODE=0

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
    --scan-output)
      [[ $# -ge 2 ]] || { echo "Missing value for --scan-output" >&2; exit 1; }
      SCAN_OUTPUT="$2"
      shift 2
      ;;
    --frontmatter-output)
      [[ $# -ge 2 ]] || { echo "Missing value for --frontmatter-output" >&2; exit 1; }
      FRONTMATTER_OUTPUT="$2"
      shift 2
      ;;
    --graph-output)
      [[ $# -ge 2 ]] || { echo "Missing value for --graph-output" >&2; exit 1; }
      GRAPH_OUTPUT="$2"
      shift 2
      ;;
    --skip-maintain-state)
      SKIP_MAINTAIN_STATE=1
      shift
      ;;
    --strict)
      STRICT_MODE=1
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
if [[ -z "$ROOT" ]]; then
  ROOT="$(user_data_root)"
fi
ROOT="$(to_posix_path "$ROOT")"

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

REPORT="$(resolve_path "$REPORT" "$STATE_DIR/pensieve-doctor-report.md")"
SUMMARY_JSON="$(resolve_path "$SUMMARY_JSON" "$STATE_DIR/pensieve-doctor-summary.json")"
SCAN_OUTPUT="$(resolve_path "$SCAN_OUTPUT" "$STATE_DIR/pensieve-structure-scan.json")"
FRONTMATTER_OUTPUT="$(resolve_path "$FRONTMATTER_OUTPUT" "$STATE_DIR/pensieve-frontmatter-scan.json")"
GRAPH_OUTPUT="$(resolve_path "$GRAPH_OUTPUT" "$STATE_DIR/pensieve-user-data-graph.md")"

ensure_state_dir "$STATE_DIR" >/dev/null
mkdir -p "$(dirname "$REPORT")" "$(dirname "$SUMMARY_JSON")" "$(dirname "$SCAN_OUTPUT")" "$(dirname "$FRONTMATTER_OUTPUT")" "$(dirname "$GRAPH_OUTPUT")"

SCAN_SCRIPT="$SCRIPT_DIR/scan-structure.sh"
FRONTMATTER_SCRIPT="$SCRIPT_DIR/check-frontmatter.sh"
GRAPH_SCRIPT="$SCRIPT_DIR/generate-user-data-graph.sh"
MAINTAIN_SCRIPT="$SCRIPT_DIR/maintain-project-state.sh"
SKILL_ROOT="$(skill_root_from_script "$SCRIPT_DIR")"
SCHEMA_FILE="$SKILL_ROOT/.src/core/schema.json"
DOCTOR_ENGINE="$SKILL_ROOT/.src/core/doctor_engine.py"

[[ -x "$SCAN_SCRIPT" ]] || { echo "Missing executable: $SCAN_SCRIPT" >&2; exit 1; }
[[ -x "$FRONTMATTER_SCRIPT" ]] || { echo "Missing executable: $FRONTMATTER_SCRIPT" >&2; exit 1; }
[[ -x "$GRAPH_SCRIPT" ]] || { echo "Missing executable: $GRAPH_SCRIPT" >&2; exit 1; }
[[ -f "$DOCTOR_ENGINE" ]] || { echo "Missing core engine: $DOCTOR_ENGINE" >&2; exit 1; }

bash "$SCAN_SCRIPT" --root "$ROOT" --format json --output "$SCAN_OUTPUT"
bash "$FRONTMATTER_SCRIPT" --root "$ROOT" --format json > "$FRONTMATTER_OUTPUT"
bash "$GRAPH_SCRIPT" --root "$ROOT" --output "$GRAPH_OUTPUT" >/dev/null

ensure_python_env
[[ -n "${PYTHON_BIN:-}" ]] || { echo "Python not found" >&2; exit 1; }

CHECK_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
"$PYTHON_BIN" "$DOCTOR_ENGINE" "$SCAN_OUTPUT" "$FRONTMATTER_OUTPUT" "$GRAPH_OUTPUT" "$REPORT" "$SUMMARY_JSON" "$PROJECT_ROOT" "$ROOT" "$CHECK_TIME" "$SCHEMA_FILE"

SUMMARY_STATUS="$(json_get_value "$SUMMARY_JSON" "status" "UNKNOWN")"
SUMMARY_MUST_FIX="$(json_get_value "$SUMMARY_JSON" "must_fix" "0")"
SUMMARY_SHOULD_FIX="$(json_get_value "$SUMMARY_JSON" "should_fix" "0")"
SUMMARY_INFO="$(json_get_value "$SUMMARY_JSON" "info" "0")"
SUMMARY_NEXT="$(json_get_value "$SUMMARY_JSON" "next_step" "none")"

if [[ "$SKIP_MAINTAIN_STATE" -eq 0 && -x "$MAINTAIN_SCRIPT" ]]; then
  bash "$MAINTAIN_SCRIPT" --event doctor --note "doctor summary: status=$SUMMARY_STATUS, must_fix=$SUMMARY_MUST_FIX, should_fix=$SUMMARY_SHOULD_FIX, info=$SUMMARY_INFO, next=$SUMMARY_NEXT" >/dev/null || true
fi

echo "✅ Doctor completed"
echo "  - status: $SUMMARY_STATUS"
echo "  - must_fix: $SUMMARY_MUST_FIX"
echo "  - should_fix: $SUMMARY_SHOULD_FIX"
echo "  - info: $SUMMARY_INFO"
echo "  - report: $REPORT"
echo "  - summary: $SUMMARY_JSON"

MARKER_SCRIPT="$SCRIPT_DIR/pensieve-session-marker.sh"
if [[ "$SUMMARY_STATUS" != "FAIL" && -f "$MARKER_SCRIPT" ]]; then
  bash "$MARKER_SCRIPT" --mode record --event doctor || true
fi

if [[ "$STRICT_MODE" -eq 1 && "$SUMMARY_STATUS" == "FAIL" ]]; then
  exit 3
fi

exit 0
