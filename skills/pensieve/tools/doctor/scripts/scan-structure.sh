#!/bin/bash
# Shared structural scanner for project-level Pensieve user data.
# Single source for Doctor/Upgrade structural checks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../loop/scripts/_lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  scan-structure.sh [--root <path>] [--output <path>] [--format <json|text>] [--fail-on-drift]

Options:
  --root <path>       Scan root. Default: <project>/.claude/skills/pensieve
  --output <path>     Output file path. Default: stdout
  --format <fmt>      Output format: json | text. Default: json
  --fail-on-drift     Exit with code 3 when MUST_FIX findings exist
  -h, --help          Show help
USAGE
}

ROOT=""
OUTPUT="-"
FORMAT="json"
FAIL_ON_DRIFT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || { echo "Missing value for --root" >&2; exit 1; }
      ROOT="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "Missing value for --output" >&2; exit 1; }
      OUTPUT="$2"
      shift 2
      ;;
    --format)
      [[ $# -ge 2 ]] || { echo "Missing value for --format" >&2; exit 1; }
      FORMAT="$2"
      shift 2
      ;;
    --fail-on-drift)
      FAIL_ON_DRIFT=1
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

case "$FORMAT" in
  json|text)
    ;;
  *)
    echo "Unsupported --format: $FORMAT (expected: json|text)" >&2
    exit 1
    ;;
esac

PROJECT_ROOT="$(to_posix_path "$(project_root)")"
if [[ -z "$ROOT" ]]; then
  ROOT="$(user_data_root)"
fi
ROOT="$(to_posix_path "$ROOT")"
AUTO_MEMORY_FILE="$(to_posix_path "$(auto_memory_file)")"

if [[ "$OUTPUT" != "-" ]]; then
  OUTPUT="$(to_posix_path "$OUTPUT")"
  if [[ "$OUTPUT" != /* ]]; then
    OUTPUT="$PROJECT_ROOT/$OUTPUT"
  fi
  mkdir -p "$(dirname "$OUTPUT")"
fi

PLUGIN_ROOT="$(plugin_root_from_script "$SCRIPT_DIR")"
HOME_DIR="${HOME:-}"
TIMESTAMP="$(runtime_now_utc)"

PYTHON_BIN="$(python_bin || true)"
[[ -n "$PYTHON_BIN" ]] || { echo "Python not found" >&2; exit 1; }

"$PYTHON_BIN" - "$ROOT" "$PROJECT_ROOT" "$PLUGIN_ROOT" "$HOME_DIR" "$AUTO_MEMORY_FILE" "$FORMAT" "$OUTPUT" "$TIMESTAMP" "$FAIL_ON_DRIFT" <<'PY'
from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Finding:
    finding_id: str
    severity: str
    category: str
    path: str
    message: str
    recommended_action: str

    def as_dict(self) -> dict[str, str]:
        return {
            "id": self.finding_id,
            "severity": self.severity,
            "category": self.category,
            "path": self.path,
            "message": self.message,
            "recommended_action": self.recommended_action,
        }


root = Path(sys.argv[1])
project_root = Path(sys.argv[2])
plugin_root = Path(sys.argv[3])
home_dir = Path(sys.argv[4]) if sys.argv[4] else Path.home()
memory_file = Path(sys.argv[5])
fmt = sys.argv[6]
output = sys.argv[7]
generated_at = sys.argv[8]
fail_on_drift = sys.argv[9] == "1"

findings: list[Finding] = []
dedupe_keys: set[tuple[str, str, str]] = set()

required_dirs = ["maxims", "decisions", "knowledge", "pipelines", "loop"]
critical_files = [
    (
        root / "pipelines" / "run-when-reviewing-code.md",
        plugin_root / "skills" / "pensieve" / "tools" / "upgrade" / "templates" / "pipeline.run-when-reviewing-code.md",
    ),
    (
        root / "pipelines" / "run-when-committing.md",
        plugin_root / "skills" / "pensieve" / "tools" / "upgrade" / "templates" / "pipeline.run-when-committing.md",
    ),
    (
        root / "knowledge" / "taste-review" / "content.md",
        plugin_root / "skills" / "pensieve" / "knowledge" / "taste-review" / "content.md",
    ),
]

legacy_project_paths = [
    project_root / "skills" / "pensieve",
    project_root / ".claude" / "pensieve",
]
legacy_user_paths = [
    home_dir / ".claude" / "skills" / "pensieve",
    home_dir / ".claude" / "pensieve",
]
legacy_graph_patterns = ["_pensieve-graph*.md", "pensieve-graph*.md", "graph*.md"]
legacy_readme_re = re.compile(r"(?i)^readme(?:.*\.md)?$")
# Match plugin-internal knowledge path, but ignore project-scoped ".claude/skills/..." references.
plugin_path_re = re.compile(r"(?<!\.claude/)skills/pensieve/knowledge/")
plugin_skill_root = plugin_root / "skills" / "pensieve"
system_skill_file = plugin_skill_root / "SKILL.md"
memory_start_marker = "<!-- pensieve:auto-memory:start -->"
memory_end_marker = "<!-- pensieve:auto-memory:end -->"
memory_guidance_line = "- 引导：当需求涉及项目知识沉淀、结构体检、版本迁移或复杂任务拆解时，优先调用 `pensieve` skill。"


def add_finding(
    finding_id: str,
    severity: str,
    category: str,
    path: Path | str,
    message: str,
    recommended_action: str,
) -> None:
    path_str = str(path)
    key = (finding_id, severity, path_str)
    if key in dedupe_keys:
        return
    dedupe_keys.add(key)
    findings.append(
        Finding(
            finding_id=finding_id,
            severity=severity,
            category=category,
            path=path_str,
            message=message,
            recommended_action=recommended_action,
        )
    )


def same_path(a: Path, b: Path) -> bool:
    try:
        return a.resolve() == b.resolve()
    except Exception:  # noqa: BLE001
        return False


def read_text_normalized(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")


def has_plugin_knowledge_path_reference(text: str) -> bool:
    if "<SYSTEM_SKILL_ROOT>/knowledge/" in text:
        return True
    return bool(plugin_path_re.search(text))


def normalize_context_link_line(line: str) -> str:
    m = re.match(r"^(\s*-\s*(?:基于|导致|相关)：)\s*.*$", line)
    if not m:
        return line.rstrip()
    return f"{m.group(1)} <context-value>"


def normalize_critical_file_content(path: Path, text: str) -> str:
    rel = path.as_posix()
    basename = Path(rel).name
    if basename in ("run-when-reviewing-code.md", "pipeline.run-when-reviewing-code.md",
                     "run-when-committing.md", "pipeline.run-when-committing.md"):
        lines = [normalize_context_link_line(line) for line in text.split("\n")]
        return "\n".join(lines).rstrip() + "\n"
    return text


def has_memory_guidance(block: str) -> bool:
    for raw_line in block.splitlines():
        line = raw_line.strip()
        if line == memory_guidance_line:
            return True
        lower = line.lower()
        if lower.startswith("- guidance:") and "pensieve" in lower and "skill" in lower:
            if "when a request involves" in lower or "when needs involve" in lower:
                return True
    return False


def load_json(path: Path) -> tuple[dict | None, str | None]:
    if not path.exists():
        return None, None
    try:
        data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except Exception as exc:  # noqa: BLE001
        return None, str(exc)
    if not isinstance(data, dict):
        return None, "root must be a JSON object"
    return data, None


def load_system_skill_description(path: Path) -> str | None:
    if not path.is_file():
        return None
    text = read_text_normalized(path)
    m = re.search(r"^---\n(.*?)\n---\n?", text, flags=re.MULTILINE | re.DOTALL)
    if not m:
        return None
    for line in m.group(1).splitlines():
        if line.startswith("description:"):
            value = line.split(":", 1)[1].strip()
            return value if value else None
    return None


def extract_pensieve_memory_block(text: str) -> str:
    pattern = re.compile(
        re.escape(memory_start_marker) + r"(.*?)" + re.escape(memory_end_marker),
        flags=re.DOTALL,
    )
    m = pattern.search(text)
    if not m:
        return text
    return m.group(0)


if not root.exists():
    add_finding(
        "STR-001",
        "MUST_FIX",
        "missing_root",
        root,
        "项目级用户数据根目录不存在。",
        "先执行 init 或 upgrade 补齐 .claude/skills/pensieve 基础结构。",
    )

for d in required_dirs:
    p = root / d
    if not p.is_dir():
        add_finding(
            "STR-002",
            "MUST_FIX",
            "missing_directory",
            p,
            f"缺少关键目录: {d}/",
            "执行 upgrade 补齐目录结构，并复跑 doctor。",
        )

for p in legacy_project_paths + legacy_user_paths:
    # In plugin source repos, <project>/skills/pensieve can be the active system skill root.
    # Do not treat that specific path as deprecated user-data residue.
    if same_path(p, plugin_skill_root):
        continue
    if p.exists():
        add_finding(
            "STR-101",
            "MUST_FIX",
            "deprecated_path",
            p,
            "发现 deprecated 旧路径与 active 根目录并存。",
            "执行 upgrade 迁移并删除旧路径，收敛到 .claude/skills/pensieve 单根目录。",
        )

if root.is_dir():
    for pattern in legacy_graph_patterns:
        for matched in sorted(root.glob(pattern)):
            if not matched.is_file():
                continue
            add_finding(
                "STR-111",
                "MUST_FIX",
                "legacy_graph_file",
                matched,
                "发现独立 graph 遗留文件。",
                "执行 upgrade 删除独立 graph 文件，图谱仅保留在 SKILL.md#Graph。",
            )

for d in required_dirs:
    cat_dir = root / d
    if not cat_dir.is_dir():
        continue
    for item in sorted(cat_dir.iterdir()):
        if not item.is_file():
            continue
        if legacy_readme_re.match(item.name):
            add_finding(
                "STR-121",
                "MUST_FIX",
                "legacy_spec_readme_copy",
                item,
                "发现项目级子目录中的历史规范 README 副本。",
                "执行 upgrade 删除该副本；规范以插件侧 <SYSTEM_SKILL_ROOT>/*/README.md 为准。",
            )

for target, template in critical_files:
    if not target.is_file():
        add_finding(
            "STR-201",
            "MUST_FIX",
            "missing_critical_file",
            target,
            "缺少关键种子文件。",
            "执行 upgrade 进行关键文件强对齐。",
        )
        continue
    if not template.is_file():
        add_finding(
            "STR-901",
            "MUST_FIX",
            "scanner_template_missing",
            template,
            "扫描所需模板文件不存在，无法判定关键文件是否漂移。",
            "修复插件安装或更新到完整版本后重试。",
        )
        continue
    target_text = normalize_critical_file_content(target, read_text_normalized(target))
    template_text = normalize_critical_file_content(template, read_text_normalized(template))
    if target_text != template_text:
        add_finding(
            "STR-202",
            "MUST_FIX",
            "critical_file_drift",
            target,
            "关键文件主体内容与模板不一致（上下文链接值差异已忽略）。",
            "执行 upgrade 先备份再替换，恢复关键流程文件主体与模板一致。",
        )

review_pipeline = root / "pipelines" / "run-when-reviewing-code.md"
if review_pipeline.is_file():
    txt = read_text_normalized(review_pipeline)
    if has_plugin_knowledge_path_reference(txt):
        add_finding(
            "STR-301",
            "MUST_FIX",
            "review_pipeline_path_drift",
            review_pipeline,
            "review pipeline 仍引用插件内 Knowledge 路径。",
            "执行 upgrade 将引用切换为项目级 .claude/skills/pensieve/knowledge/... 路径。",
        )

settings_paths = [home_dir / ".claude" / "settings.json", project_root / ".claude" / "settings.json"]
old_keys = ["pensieve@Pensieve", "pensieve@pensieve-claude-plugin"]
new_key = "pensieve@kingkongshot-marketplace"
new_key_enabled = False
old_key_hits: list[str] = []

for s in settings_paths:
    parsed, err = load_json(s)
    if err is not None:
        add_finding(
            "STR-401",
            "SHOULD_FIX",
            "settings_parse_error",
            s,
            f"settings.json 解析失败，无法完整验证 enabledPlugins: {err}",
            "修复 settings.json 语法后重试。",
        )
        continue
    if parsed is None:
        continue
    enabled = parsed.get("enabledPlugins")
    if not isinstance(enabled, dict):
        continue
    if bool(enabled.get(new_key)):
        new_key_enabled = True
    for k in old_keys:
        if bool(enabled.get(k)):
            old_key_hits.append(f"{s}::{k}")

if old_key_hits:
    add_finding(
        "STR-402",
        "MUST_FIX",
        "legacy_enabled_plugins_key",
        "; ".join(old_key_hits),
        "enabledPlugins 中仍启用旧插件键。",
        "执行 upgrade 清理旧键，仅保留 pensieve@kingkongshot-marketplace。",
    )

if not new_key_enabled:
    add_finding(
        "STR-403",
        "MUST_FIX",
        "missing_enabled_plugins_key",
        "<user|project>/.claude/settings.json",
        "enabledPlugins 缺少新插件键或未启用。",
        "执行 upgrade 写入 pensieve@kingkongshot-marketplace: true。",
    )

system_skill_description = load_system_skill_description(system_skill_file)
if system_skill_description is None:
    add_finding(
        "STR-901",
        "MUST_FIX",
        "scanner_template_missing",
        system_skill_file,
        "扫描所需系统 skill 描述缺失，无法校验 MEMORY.md 的 Pensieve 引导块。",
        "修复插件安装或更新到完整版本后重试。",
    )
else:
    if not memory_file.is_file():
        add_finding(
            "STR-501",
            "MUST_FIX",
            "missing_memory_file",
            memory_file,
            "缺少 Claude Code auto memory 入口 MEMORY.md。",
            "执行 init/upgrade/doctor 触发 auto memory 补齐，或在 ~/.claude/projects/<project>/memory/MEMORY.md 写入 Pensieve 引导块。",
        )
    else:
        memory_text = read_text_normalized(memory_file)
        memory_block = extract_pensieve_memory_block(memory_text)
        if system_skill_description not in memory_block or not has_memory_guidance(memory_block):
            add_finding(
                "STR-502",
                "MUST_FIX",
                "memory_content_drift",
                memory_file,
                "MEMORY.md 缺少 Pensieve 说明，或内容未与系统 skill 的 description 对齐。",
                "执行 init/upgrade/doctor 触发 auto memory 对齐，确保 ~/.claude/projects/<project>/memory/MEMORY.md 与 skill description 一致并包含 pensieve skill 引导。",
            )

must_fix = sum(1 for f in findings if f.severity == "MUST_FIX")
should_fix = sum(1 for f in findings if f.severity == "SHOULD_FIX")
status = "aligned" if must_fix == 0 else "drift"

flags = {
    "has_missing_root": any(f.finding_id == "STR-001" for f in findings),
    "has_missing_directories": any(f.finding_id == "STR-002" for f in findings),
    "has_deprecated_paths": any(f.finding_id == "STR-101" for f in findings),
    "has_legacy_graph_files": any(f.finding_id == "STR-111" for f in findings),
    "has_legacy_spec_readme_copies": any(f.finding_id == "STR-121" for f in findings),
    "has_missing_critical_files": any(f.finding_id == "STR-201" for f in findings),
    "has_critical_file_drift": any(f.finding_id == "STR-202" for f in findings),
    "has_review_pipeline_path_drift": any(f.finding_id == "STR-301" for f in findings),
    "has_settings_parse_errors": any(f.finding_id == "STR-401" for f in findings),
    "has_legacy_enabled_plugins_key": any(f.finding_id == "STR-402" for f in findings),
    "has_missing_new_enabled_plugins_key": any(f.finding_id == "STR-403" for f in findings),
    "has_missing_memory_file": any(f.finding_id == "STR-501" for f in findings),
    "has_memory_content_drift": any(f.finding_id == "STR-502" for f in findings),
}

report = {
    "generated_at_utc": generated_at,
    "status": status,
    "root": str(root),
    "project_root": str(project_root),
    "plugin_root": str(plugin_root),
    "auto_memory_file": str(memory_file),
    "summary": {
        "must_fix_count": must_fix,
        "should_fix_count": should_fix,
        "total_findings": len(findings),
    },
    "flags": flags,
    "findings": [f.as_dict() for f in findings],
}


def render_text(data: dict) -> str:
    lines: list[str] = []
    lines.append("# Pensieve Structure Scan")
    lines.append("")
    lines.append(f"- status: `{data['status']}`")
    lines.append(f"- generated_at_utc: `{data['generated_at_utc']}`")
    lines.append(f"- root: `{data['root']}`")
    lines.append(f"- must_fix: `{data['summary']['must_fix_count']}`")
    lines.append(f"- should_fix: `{data['summary']['should_fix_count']}`")
    lines.append("")
    lines.append("## Findings")
    if not data["findings"]:
        lines.append("- none")
        return "\n".join(lines) + "\n"
    for item in data["findings"]:
        lines.append(
            f"- [{item['severity']}] {item['id']} | {item['category']} | `{item['path']}` | {item['message']}"
        )
    return "\n".join(lines) + "\n"


if fmt == "json":
    out = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
else:
    out = render_text(report)

if output == "-":
    sys.stdout.write(out)
else:
    Path(output).write_text(out, encoding="utf-8")

if fail_on_drift and must_fix > 0:
    sys.exit(3)
PY
