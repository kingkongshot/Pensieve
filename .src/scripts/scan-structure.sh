#!/bin/bash
# Shared structural scanner for Pensieve user data root.
# Single source for Doctor/Migrate structural checks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  scan-structure.sh [--root <path>] [--output <path>] [--format <json|text>] [--fail-on-drift]

Options:
  --root <path>       Scan root. Default: current user data root
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

PROJECT_ROOT="$(to_posix_path "$(project_root "$SCRIPT_DIR")")"
if [[ -z "$ROOT" ]]; then
  ROOT="$(user_data_root "$SCRIPT_DIR")"
fi
ROOT="$(to_posix_path "$ROOT")"
AUTO_MEMORY_FILE="$(to_posix_path "$(auto_memory_file "$SCRIPT_DIR")")"

if [[ "$OUTPUT" != "-" ]]; then
  OUTPUT="$(to_posix_path "$OUTPUT")"
  if [[ "$OUTPUT" != /* ]]; then
    OUTPUT="$PROJECT_ROOT/$OUTPUT"
  fi
  mkdir -p "$(dirname "$OUTPUT")"
fi

SKILL_ROOT="$(skill_root_from_script "$SCRIPT_DIR")"
SCHEMA_FILE="$SKILL_ROOT/.src/core/schema.json"
HOME_DIR="${HOME:-}"
TIMESTAMP="$(runtime_now_utc)"

PYTHON_BIN="$(python_bin || true)"
[[ -n "$PYTHON_BIN" ]] || { echo "Python not found" >&2; exit 1; }

"$PYTHON_BIN" - "$ROOT" "$PROJECT_ROOT" "$SKILL_ROOT" "$SCHEMA_FILE" "$HOME_DIR" "$AUTO_MEMORY_FILE" "$FORMAT" "$OUTPUT" "$TIMESTAMP" "$FAIL_ON_DRIFT" <<'PY'
from __future__ import annotations

import importlib.util
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
skill_root = Path(sys.argv[3])
schema_file = Path(sys.argv[4])
home_dir = Path(sys.argv[5]) if sys.argv[5] else Path.home()
memory_file = Path(sys.argv[6])
fmt = sys.argv[7]
output = sys.argv[8]
generated_at = sys.argv[9]
fail_on_drift = sys.argv[10] == "1"

findings: list[Finding] = []
dedupe_keys: set[tuple[str, str, str]] = set()

core_file = skill_root / ".src" / "core" / "pensieve_core.py"
spec = importlib.util.spec_from_file_location("pensieve_core", core_file)
if spec is None or spec.loader is None:
    raise SystemExit(f"failed to load core module: {core_file}")
core_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core_module)
try:
    schema = core_module.load_schema(schema_file)
except Exception as exc:  # noqa: BLE001
    raise SystemExit(f"failed to load schema: {exc}") from exc

required_dirs = [str(x) for x in schema.get("required_dirs", [])]
critical_files = []
for item in schema.get("critical_files", []):
    if not isinstance(item, dict):
        continue
    target = item.get("target")
    template = item.get("template")
    if not isinstance(target, str) or not isinstance(template, str):
        continue
    critical_files.append((root / target, skill_root / template))

legacy_project_paths = [project_root / p for p in schema.get("legacy_paths", {}).get("project", [])]
legacy_user_paths = [home_dir / p for p in schema.get("legacy_paths", {}).get("user", [])]
legacy_graph_patterns = [str(x) for x in schema.get("legacy_graph_patterns", [])]
legacy_readme_re = re.compile(str(schema.get("legacy_readme_regex", r"(?i)^readme(?:.*\.md)?$")))
finding_templates = schema.get("findings", {}) if isinstance(schema.get("findings"), dict) else {}
# Detect stale references to old skill paths or hidden template paths.
legacy_knowledge_path_re = re.compile(
    r"(?:(?<!\\.claude/)skills/pensieve/knowledge/|\\.claude/skills/pensieve/knowledge/|\\.src/templates/knowledge/)"
)
system_skill_file = skill_root / "SKILL.md"
memory_start_marker = str(schema.get("memory", {}).get("start_marker", "<!-- pensieve:auto-memory:start -->"))
memory_end_marker = str(schema.get("memory", {}).get("end_marker", "<!-- pensieve:auto-memory:end -->"))
memory_guidance_line = str(
    schema.get("memory", {}).get(
        "guidance_line",
        "- 引导：当需求涉及项目知识沉淀、结构体检、版本迁移或复杂任务拆解时，优先调用 `pensieve` skill。",
    )
)


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


def finding_text(
    finding_id: str,
    field: str,
    fallback: str = "",
    **kwargs: str,
) -> str:
    text = fallback
    entry = finding_templates.get(finding_id)
    if isinstance(entry, dict):
        value = entry.get(field)
        if isinstance(value, str) and value:
            text = value
    if kwargs:
        try:
            return text.format(**kwargs)
        except Exception:  # noqa: BLE001
            return text
    return text


def add_finding_by_id(
    finding_id: str,
    severity: str,
    category: str,
    path: Path | str,
    **kwargs: str,
) -> None:
    add_finding(
        finding_id,
        severity,
        category,
        path,
        finding_text(finding_id, "message", "", **kwargs),
        finding_text(finding_id, "recommendation", "按建议修复后重跑 doctor", **kwargs),
    )


def same_path(a: Path, b: Path) -> bool:
    try:
        return a.resolve() == b.resolve()
    except Exception:  # noqa: BLE001
        return False


def read_text_normalized(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")


def has_legacy_knowledge_path_reference(text: str) -> bool:
    if "<SYSTEM_SKILL_ROOT>/knowledge/" in text:
        return True
    return bool(legacy_knowledge_path_re.search(text))


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
    add_finding_by_id(
        "STR-001",
        "MUST_FIX",
        "missing_root",
        root,
    )

skill_file = root / "SKILL.md"
if not skill_file.is_file():
    add_finding_by_id(
        "STR-003",
        "MUST_FIX",
        "missing_skill_file",
        skill_file,
    )

for d in required_dirs:
    p = root / d
    if not p.is_dir():
        add_finding_by_id(
            "STR-002",
            "MUST_FIX",
            "missing_directory",
            p,
            dir=d,
        )

for p in legacy_project_paths + legacy_user_paths:
    if same_path(p, skill_root):
        continue
    if p.exists():
        add_finding_by_id(
            "STR-101",
            "MUST_FIX",
            "deprecated_path",
            p,
        )

if root.is_dir():
    for pattern in legacy_graph_patterns:
        for matched in sorted(root.glob(pattern)):
            if not matched.is_file():
                continue
            add_finding_by_id(
                "STR-111",
                "MUST_FIX",
                "legacy_graph_file",
                matched,
            )

for d in required_dirs:
    cat_dir = root / d
    if not cat_dir.is_dir():
        continue
    for item in sorted(cat_dir.iterdir()):
        if not item.is_file():
            continue
        if legacy_readme_re.match(item.name):
            add_finding_by_id(
                "STR-121",
                "MUST_FIX",
                "legacy_spec_readme_copy",
                item,
            )

for target, template in critical_files:
    if not target.is_file():
        add_finding_by_id(
            "STR-201",
            "MUST_FIX",
            "missing_critical_file",
            target,
        )
        continue
    if not template.is_file():
        add_finding_by_id(
            "STR-901",
            "MUST_FIX",
            "scanner_template_missing",
            template,
            detail="关键文件模板不存在，无法判定关键文件是否漂移",
        )
        continue
    target_text = normalize_critical_file_content(target, read_text_normalized(target))
    template_text = normalize_critical_file_content(template, read_text_normalized(template))
    if target_text != template_text:
        add_finding_by_id(
            "STR-202",
            "MUST_FIX",
            "critical_file_drift",
            target,
        )

review_pipeline = root / "pipelines" / "run-when-reviewing-code.md"
if review_pipeline.is_file():
    txt = read_text_normalized(review_pipeline)
    if has_legacy_knowledge_path_reference(txt):
        add_finding_by_id(
            "STR-301",
            "MUST_FIX",
            "review_pipeline_path_drift",
            review_pipeline,
        )

system_skill_description = load_system_skill_description(system_skill_file)
if system_skill_description is None:
    add_finding_by_id(
        "STR-901",
        "MUST_FIX",
        "scanner_template_missing",
        system_skill_file,
        detail="系统 skill 描述缺失，无法校验 MEMORY.md 的 Pensieve 引导块",
    )
else:
    if not memory_file.is_file():
        add_finding_by_id(
            "STR-501",
            "MUST_FIX",
            "missing_memory_file",
            memory_file,
        )
    else:
        memory_text = read_text_normalized(memory_file)
        memory_block = extract_pensieve_memory_block(memory_text)
        if system_skill_description not in memory_block or not has_memory_guidance(memory_block):
            add_finding_by_id(
                "STR-502",
                "MUST_FIX",
                "memory_content_drift",
                memory_file,
            )

must_fix = sum(1 for f in findings if f.severity == "MUST_FIX")
should_fix = sum(1 for f in findings if f.severity == "SHOULD_FIX")
status = "aligned" if must_fix == 0 else "drift"
state = core_module.classify_state(
    has_missing_root=any(f.finding_id == "STR-001" for f in findings),
    has_missing_directories=any(f.finding_id == "STR-002" for f in findings),
    has_missing_critical_files=any(f.finding_id == "STR-201" for f in findings),
    must_fix_count=must_fix,
)

flags = {
    "has_missing_root": any(f.finding_id == "STR-001" for f in findings),
    "has_missing_directories": any(f.finding_id == "STR-002" for f in findings),
    "has_deprecated_paths": any(f.finding_id == "STR-101" for f in findings),
    "has_legacy_graph_files": any(f.finding_id == "STR-111" for f in findings),
    "has_legacy_spec_readme_copies": any(f.finding_id == "STR-121" for f in findings),
    "has_missing_critical_files": any(f.finding_id == "STR-201" for f in findings),
    "has_critical_file_drift": any(f.finding_id == "STR-202" for f in findings),
    "has_review_pipeline_path_drift": any(f.finding_id == "STR-301" for f in findings),
    "has_missing_memory_file": any(f.finding_id == "STR-501" for f in findings),
    "has_memory_content_drift": any(f.finding_id == "STR-502" for f in findings),
}

report = {
    "generated_at_utc": generated_at,
    "status": status,
    "state": state,
    "root": str(root),
    "project_root": str(project_root),
    "skill_root": str(skill_root),
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
