#!/bin/bash
# End-to-end doctor runner: execute scanners, merge findings, and emit fixed-format report.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../loop/scripts/_lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  run-doctor.sh [options]

Options:
  --root <path>             Scan root. Default: <project>/.claude/skills/pensieve
  --state-dir <path>        Runtime state dir. Default: <project>/.state
  --report <path>           Markdown report path. Default: <state-dir>/pensieve-doctor-report.md
  --summary-json <path>     Summary json path. Default: <state-dir>/pensieve-doctor-summary.json
  --scan-output <path>      Structure scan json path. Default: <state-dir>/pensieve-structure-scan.json
  --frontmatter-output <path> Frontmatter scan json path. Default: <state-dir>/pensieve-frontmatter-scan.json
  --graph-output <path>     Graph markdown path. Default: <state-dir>/pensieve-user-data-graph.md
  --skip-maintain-skill     Skip maintain-project-skill after report generation
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
SKIP_MAINTAIN_SKILL=0
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
    --skip-maintain-skill)
      SKIP_MAINTAIN_SKILL=1
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

REPORT="$(resolve_path "$REPORT" "$STATE_DIR/pensieve-doctor-report.md")"
SUMMARY_JSON="$(resolve_path "$SUMMARY_JSON" "$STATE_DIR/pensieve-doctor-summary.json")"
SCAN_OUTPUT="$(resolve_path "$SCAN_OUTPUT" "$STATE_DIR/pensieve-structure-scan.json")"
FRONTMATTER_OUTPUT="$(resolve_path "$FRONTMATTER_OUTPUT" "$STATE_DIR/pensieve-frontmatter-scan.json")"
GRAPH_OUTPUT="$(resolve_path "$GRAPH_OUTPUT" "$STATE_DIR/pensieve-user-data-graph.md")"

mkdir -p "$STATE_DIR"
mkdir -p "$(dirname "$REPORT")" "$(dirname "$SUMMARY_JSON")" "$(dirname "$SCAN_OUTPUT")" "$(dirname "$FRONTMATTER_OUTPUT")" "$(dirname "$GRAPH_OUTPUT")"

SCAN_SCRIPT="$SCRIPT_DIR/scan-structure.sh"
FRONTMATTER_SCRIPT="$SCRIPT_DIR/check-frontmatter.sh"
GRAPH_SCRIPT="$SCRIPT_DIR/../../upgrade/scripts/generate-user-data-graph.sh"
MAINTAIN_SCRIPT="$SCRIPT_DIR/../../project-skill/scripts/maintain-project-skill.sh"

[[ -x "$SCAN_SCRIPT" ]] || { echo "Missing executable: $SCAN_SCRIPT" >&2; exit 1; }
[[ -x "$FRONTMATTER_SCRIPT" ]] || { echo "Missing executable: $FRONTMATTER_SCRIPT" >&2; exit 1; }
[[ -x "$GRAPH_SCRIPT" ]] || { echo "Missing executable: $GRAPH_SCRIPT" >&2; exit 1; }

bash "$SCAN_SCRIPT" --root "$ROOT" --format json --output "$SCAN_OUTPUT"
bash "$FRONTMATTER_SCRIPT" --root "$ROOT" --format json > "$FRONTMATTER_OUTPUT"
bash "$GRAPH_SCRIPT" --root "$ROOT" --output "$GRAPH_OUTPUT" >/dev/null

PYTHON_BIN="$(python_bin || true)"
[[ -n "$PYTHON_BIN" ]] || { echo "Python not found" >&2; exit 1; }

CHECK_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

"$PYTHON_BIN" - "$SCAN_OUTPUT" "$FRONTMATTER_OUTPUT" "$GRAPH_OUTPUT" "$REPORT" "$SUMMARY_JSON" "$PROJECT_ROOT" "$ROOT" "$CHECK_TIME" <<'PY'
from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

scan_file = Path(sys.argv[1])
frontmatter_file = Path(sys.argv[2])
graph_file = Path(sys.argv[3])
report_file = Path(sys.argv[4])
summary_file = Path(sys.argv[5])
project_root = sys.argv[6]
user_root = sys.argv[7]
check_time = sys.argv[8]


@dataclass
class Finding:
    finding_id: str
    severity: str
    category: str
    path: str
    rule_source: str
    message: str
    recommendation: str


def load_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(f"Failed to parse json: {path} ({exc})")
    if not isinstance(data, dict):
        raise SystemExit(f"Invalid json root type: {path}")
    return data


def parse_graph(path: Path) -> tuple[dict[str, int], list[tuple[str, str]]]:
    text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    stats = {
        "notes": 0,
        "links": 0,
        "resolved": 0,
        "unresolved": 0,
    }

    patterns = {
        "notes": re.compile(r"^- 扫描笔记数:\s*(\d+)\s*$", flags=re.MULTILINE),
        "links": re.compile(r"^- 发现链接数:\s*(\d+)\s*$", flags=re.MULTILINE),
        "resolved": re.compile(r"^- 已解析链接:\s*(\d+)\s*$", flags=re.MULTILINE),
        "unresolved": re.compile(r"^- 未解析链接:\s*(\d+)\s*$", flags=re.MULTILINE),
    }
    for key, pat in patterns.items():
        m = pat.search(text)
        if m:
            stats[key] = int(m.group(1))

    unresolved: list[tuple[str, str]] = []
    for m in re.finditer(r"^- `([^`]+)` -> `\[\[([^\]]+)\]\]`\s*$", text, flags=re.MULTILINE):
        unresolved.append((m.group(1), m.group(2)))

    return stats, unresolved


scan = load_json(scan_file)
frontmatter = load_json(frontmatter_file)
graph_stats, unresolved_links = parse_graph(graph_file)

findings: list[Finding] = []

for item in scan.get("findings", []):
    if not isinstance(item, dict):
        continue
    findings.append(
        Finding(
            finding_id=str(item.get("id", "UNKNOWN")),
            severity=str(item.get("severity", "INFO")),
            category=str(item.get("category", "structure")),
            path=str(item.get("path", "")),
            rule_source="tools/doctor/migrations/README.md",
            message=str(item.get("message", "")),
            recommendation=str(item.get("recommended_action", "执行 upgrade 或修复结构后重试")),
        )
    )

for issue in frontmatter.get("issues", []):
    if not isinstance(issue, dict):
        continue
    level = str(issue.get("level", "SHOULD_FIX"))
    sev = "MUST_FIX" if level == "MUST_FIX" else "SHOULD_FIX"
    findings.append(
        Finding(
            finding_id=str(issue.get("code", "FM-UNK")),
            severity=sev,
            category="frontmatter",
            path=str(issue.get("path", "")),
            rule_source="tools/doctor/scripts/check-frontmatter.sh",
            message=str(issue.get("message", "")),
            recommendation="修复 frontmatter 字段与命名规则后重跑 doctor",
        )
    )

for idx, (src, target) in enumerate(unresolved_links, start=1):
    is_hard_break = src.startswith("decisions/") or src.startswith("pipelines/")
    findings.append(
        Finding(
            finding_id=f"GRAPH-{idx:03d}",
            severity="MUST_FIX" if is_hard_break else "INFO",
            category="graph_unresolved_link",
            path=src,
            rule_source="tools/doctor/_doctor.md#phase-2-5",
            message=f"未解析链接 [[{target}]]",
            recommendation="补齐目标文件或修正链接目标名称",
        )
    )

must_fix = [f for f in findings if f.severity == "MUST_FIX"]
should_fix = [f for f in findings if f.severity == "SHOULD_FIX"]
info = [f for f in findings if f.severity == "INFO"]

if must_fix:
    status = "FAIL"
    next_step = "upgrade"
elif should_fix or info:
    status = "PASS_WITH_WARNINGS"
    next_step = "self-improve"
else:
    status = "PASS"
    next_step = "none"

flags = scan.get("flags", {}) if isinstance(scan.get("flags"), dict) else {}


def yes_no(v: object) -> str:
    return "yes" if bool(v) else "no"


if graph_stats["unresolved"] == 0:
    graph_observation = "图谱链接全部可解析。"
else:
    hard = sum(1 for src, _ in unresolved_links if src.startswith("decisions/") or src.startswith("pipelines/"))
    graph_observation = f"发现 {graph_stats['unresolved']} 条未解析链接（decision/pipeline 断链 {hard} 条）。"

lines: list[str] = []
lines.append("# Pensieve Doctor 报告")
lines.append("")
lines.append("## 0) 头信息")
lines.append(f"- 检查时间: {check_time}")
lines.append(f"- 项目根目录: `{project_root}`")
lines.append(f"- 数据目录: `{user_root}`")
lines.append("")
lines.append("## 1) 执行摘要（先看这里）")
lines.append(f"- 总体状态: {status}")
lines.append(f"- MUST_FIX: {len(must_fix)}")
lines.append(f"- SHOULD_FIX: {len(should_fix)}")
lines.append(f"- INFO: {len(info)}")
lines.append(f"- 建议下一步: `{next_step}`")
lines.append("")
lines.append("## 1.5) 图谱摘要（结论前置依据）")
lines.append(f"- 图谱文件: `{graph_file}`")
lines.append(f"- 扫描笔记数: {graph_stats['notes']}")
lines.append(f"- 发现链接数: {graph_stats['links']}")
lines.append(f"- 已解析链接: {graph_stats['resolved']}")
lines.append(f"- 未解析链接: {graph_stats['unresolved']}")
lines.append(f"- 图谱观察: {graph_observation}")
lines.append("")
lines.append("## 2) 需优先处理（MUST_FIX，按优先级）")
if not must_fix:
    lines.append("- (none)")
else:
    for i, f in enumerate(must_fix, start=1):
        lines.append(f"{i}. [{f.finding_id}] {f.message}")
        lines.append(f"文件: `{f.path}`")
        lines.append(f"依据: `{f.rule_source}`")
        lines.append(f"修复: {f.recommendation}")
        lines.append("")
if lines and lines[-1] == "":
    lines.pop()
lines.append("")
lines.append("## 3) 建议处理（SHOULD_FIX）")
if not should_fix:
    lines.append("- (none)")
else:
    for i, f in enumerate(should_fix, start=1):
        lines.append(f"{i}. [{f.finding_id}] {f.message}（`{f.path}`）")
lines.append("")
lines.append("## 4) 迁移与结构检查")
lines.append(f"- 发现旧路径: {yes_no(flags.get('has_deprecated_paths'))}")
lines.append(f"- 发现新旧并行: {yes_no(flags.get('has_deprecated_paths'))}")
lines.append(f"- 发现非项目级 skill 根: {yes_no(flags.get('has_deprecated_paths'))}")
lines.append(f"- 发现独立 graph 文件: {yes_no(flags.get('has_legacy_graph_files'))}")
lines.append(f"- 缺失关键目录: {yes_no(flags.get('has_missing_directories'))}")
lines.append(
    f"- MEMORY.md 缺失/漂移: {yes_no(flags.get('has_missing_memory_file') or flags.get('has_memory_content_drift'))}"
)
lines.append(f"- 建议动作: `{next_step if next_step == 'upgrade' else 'none'}`")
lines.append("")
lines.append("## 5) 三步行动计划")
if must_fix:
    lines.append("1. 先运行 `upgrade` 脚本完成迁移、配置清理和关键文件对齐。")
    lines.append("2. 再运行一次 `doctor`，确认 MUST_FIX 清零。")
    lines.append("3. 若仍有 SHOULD_FIX/INFO，再按优先级逐项修复。")
elif should_fix or info:
    lines.append("1. 先处理 SHOULD_FIX 项，保证规范可长期维护。")
    lines.append("2. 修复后重跑 `doctor`，确认状态变为 PASS。")
    lines.append("3. 将有效修复经验沉淀到 `self-improve`。")
else:
    lines.append("1. 当前无需结构修复。")
    lines.append("2. 继续按现有流程使用 loop/self-improve。")
    lines.append("3. 下次升级后重复执行 doctor。")
lines.append("")
lines.append("## 6) 规则命中明细（附录）")
lines.append("| ID | 严重级别 | 分类 | 文件/路径 | 规则来源 | 问题 | 修复建议 |")
lines.append("|---|---|---|---|---|---|---|")
if findings:
    for f in findings:
        issue = f.message.replace("|", "\\|")
        rec = f.recommendation.replace("|", "\\|")
        lines.append(
            f"| {f.finding_id} | {f.severity} | {f.category} | {f.path} | {f.rule_source} | {issue} | {rec} |"
        )
else:
    lines.append("| - | - | - | - | - | - | - |")
lines.append("")
lines.append("## 7) 图谱断链明细（附录）")
lines.append("| 源文件 | 未解析链接 | 备注 |")
lines.append("|---|---|---|")
if unresolved_links:
    for src, target in unresolved_links:
        memo = "decision/pipeline 断链（MUST_FIX）" if (src.startswith("decisions/") or src.startswith("pipelines/")) else "一般断链"
        lines.append(f"| {src} | [[{target}]] | {memo} |")
else:
    lines.append("| - | - | 无断链 |")
lines.append("")
lines.append("## 8) Frontmatter 快检结果（附录）")
lines.append("| 文件 | 级别 | 检查码 | 问题 |")
lines.append("|---|---|---|---|")
fm_issues = [f for f in findings if f.category == "frontmatter"]
if fm_issues:
    for f in fm_issues:
        msg = f.message.replace("|", "\\|")
        lines.append(f"| {f.path} | {f.severity} | {f.finding_id} | {msg} |")
else:
    lines.append("| - | - | - | 无 frontmatter 问题 |")

report_text = "\n".join(lines).rstrip() + "\n"
report_file.write_text(report_text, encoding="utf-8")

summary = {
    "status": status,
    "must_fix": len(must_fix),
    "should_fix": len(should_fix),
    "info": len(info),
    "next_step": next_step,
    "project_root": project_root,
    "data_root": user_root,
    "report_file": str(report_file),
    "scan_file": str(scan_file),
    "frontmatter_file": str(frontmatter_file),
    "graph_file": str(graph_file),
}
summary_file.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(json.dumps(summary, ensure_ascii=False))
PY

SUMMARY_STATUS="$(json_get_value "$SUMMARY_JSON" "status" "UNKNOWN")"
SUMMARY_MUST_FIX="$(json_get_value "$SUMMARY_JSON" "must_fix" "0")"
SUMMARY_SHOULD_FIX="$(json_get_value "$SUMMARY_JSON" "should_fix" "0")"
SUMMARY_INFO="$(json_get_value "$SUMMARY_JSON" "info" "0")"
SUMMARY_NEXT="$(json_get_value "$SUMMARY_JSON" "next_step" "none")"

if [[ "$SKIP_MAINTAIN_SKILL" -eq 0 && -x "$MAINTAIN_SCRIPT" ]]; then
  bash "$MAINTAIN_SCRIPT" --event doctor --note "doctor summary: status=$SUMMARY_STATUS, must_fix=$SUMMARY_MUST_FIX, should_fix=$SUMMARY_SHOULD_FIX, info=$SUMMARY_INFO, next=$SUMMARY_NEXT" >/dev/null || true
fi

echo "✅ Doctor completed"
echo "  - status: $SUMMARY_STATUS"
echo "  - must_fix: $SUMMARY_MUST_FIX"
echo "  - should_fix: $SUMMARY_SHOULD_FIX"
echo "  - info: $SUMMARY_INFO"
echo "  - report: $REPORT"

echo "  - summary: $SUMMARY_JSON"

if [[ "$STRICT_MODE" -eq 1 && "$SUMMARY_STATUS" == "FAIL" ]]; then
  exit 3
fi

exit 0
