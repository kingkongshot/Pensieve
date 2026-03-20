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

PROJECT_ROOT="$(project_root)" || exit 1
PROJECT_ROOT="$(to_posix_path "$PROJECT_ROOT")"
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

SKILL_ROOT="$(skill_root_from_script "$SCRIPT_DIR")"
SCHEMA_FILE="$SKILL_ROOT/.src/core/schema.json"
TIMESTAMP="$(runtime_now_utc)"

ensure_python_env
[[ -n "${PYTHON_BIN:-}" ]] || { echo "Python not found" >&2; exit 1; }
HOME_DIR="$(resolve_home 2>/dev/null || echo "")"

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
optional_dirs = [str(x) for x in schema.get("optional_dirs", [])]
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
system_skill_file = skill_root / "SKILL.md"
memory_start_marker = str(schema.get("memory", {}).get("start_marker", "<!-- pensieve:auto-memory:start -->"))
memory_end_marker = str(schema.get("memory", {}).get("end_marker", "<!-- pensieve:auto-memory:end -->"))
memory_guidance_line = str(
    schema.get("memory", {}).get(
        "guidance_line",
        "- Guidance: When a request involves knowledge retention, structural checks, version migration, or complex task decomposition, prefer invoking the `pensieve` skill.",
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


def same_path(a: Path, b: Path) -> bool:
    try:
        return a.resolve() == b.resolve()
    except Exception:  # noqa: BLE001
        return False


def read_text_normalized(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")


def normalize_context_link_line(line: str) -> str:
    return core_module.normalize_context_link_line(line)


def normalize_critical_file_content(path: Path, text: str) -> str:
    return core_module.normalize_critical_file_content(path.name, text)


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
        "STR-001", "MUST_FIX", "missing_root", root,
        "User data root directory does not exist.",
        "Run init to initialize the Pensieve project in this repository.",
    )

skill_file = system_skill_file
if not skill_file.is_file():
    add_finding(
        "STR-003", "MUST_FIX", "missing_skill_file", skill_file,
        "SKILL.md not found in skill root directory.",
        "Ensure the skill is properly installed at ~/.claude/skills/pensieve/ with a tracked SKILL.md.",
    )

state_file = root / "state.md"
if root.exists() and not state_file.is_file():
    add_finding(
        "STR-004", "MUST_FIX", "missing_state_file", state_file,
        "Project state.md does not exist.",
        "Run init to generate .pensieve/state.md.",
    )

for d in required_dirs:
    p = root / d
    if not p.is_dir():
        add_finding(
            "STR-002", "MUST_FIX", "missing_directory", p,
            f"Missing required directory: {d}/",
            "Run init or migrate to restore the directory structure, then re-run doctor.",
        )

for d in optional_dirs:
    p = root / d
    if not p.is_dir():
        add_finding(
            "STR-003", "INFO", "missing_optional_directory", p,
            f"Optional directory not found: {d}/",
            "Run init or migrate to create the directory, or ignore if not needed.",
        )

# Check for legacy v1 directories (existence only, not contents).
for p in legacy_project_paths + legacy_user_paths:
    if not p.is_dir():
        continue
    # When a legacy path candidate resolves to skill_root AND skill_root
    # is at the canonical user-level location (~/.claude/skills/pensieve),
    # this is the actual installation, not a legacy remnant — skip it.
    user_level_skill = home_dir / ".claude" / "skills" / "pensieve"
    if same_path(p, skill_root) and same_path(skill_root, user_level_skill):
        continue
    if same_path(p, skill_root):
        add_finding(
            "STR-101", "MUST_FIX", "deprecated_path", p,
            f"Legacy v1 data directory found: {p} (current skill_root — switch to user-level installation)",
            "Install Pensieve at user level (~/.claude/skills/pensieve), then re-run migrate to clean up this project-level legacy path.",
        )
    else:
        add_finding(
            "STR-101", "MUST_FIX", "deprecated_path", p,
            f"Legacy v1 data directory found: {p}",
            "Run migrate to automatically move user data into .pensieve/ and clean up legacy paths.",
        )

for target, template in critical_files:
    if not target.is_file():
        add_finding(
            "STR-201", "MUST_FIX", "missing_critical_file", target,
            "Missing critical seed file.",
            "Run migrate to force-align critical files.",
        )
        continue
    if not template.is_file():
        add_finding(
            "STR-901", "MUST_FIX", "scanner_template_missing", template,
            "Template required for scanning is missing, cannot complete verification: Critical file template missing, cannot verify critical file alignment",
            "Fix the skill installation or update to a complete version, then retry.",
        )
        continue
    target_text = normalize_critical_file_content(target, read_text_normalized(target))
    template_text = normalize_critical_file_content(template, read_text_normalized(template))
    if target_text != template_text:
        add_finding(
            "STR-202", "MUST_FIX", "critical_file_drift", target,
            "Critical file body content differs from template (context link value differences ignored).",
            "Run migrate to back up and replace, restoring critical workflow file body alignment with the template.",
        )

system_skill_description = core_module.load_skill_description(system_skill_file)
if system_skill_description is None:
    add_finding(
        "STR-901", "MUST_FIX", "scanner_template_missing", system_skill_file,
        "Template required for scanning is missing, cannot complete verification: System skill description missing, cannot verify MEMORY.md Pensieve guidance block",
        "Fix the skill installation or update to a complete version, then retry.",
    )
else:
    if not memory_file.is_file():
        add_finding(
            "STR-501", "MUST_FIX", "missing_memory_file", memory_file,
            "Claude Code auto memory entry MEMORY.md is missing.",
            "Run init/migrate/doctor to trigger auto memory creation, or manually add the Pensieve guidance block to ~/.claude/projects/<project>/memory/MEMORY.md.",
        )
    else:
        memory_text = read_text_normalized(memory_file)
        memory_block = extract_pensieve_memory_block(memory_text)
        if system_skill_description not in memory_block or not has_memory_guidance(memory_block):
            add_finding(
                "STR-502", "MUST_FIX", "memory_content_drift", memory_file,
                "MEMORY.md is missing the Pensieve description, or its content is not aligned with the skill description.",
                "Run init/migrate/doctor to trigger auto memory alignment, ensuring MEMORY.md matches the SKILL.md description and includes the pensieve skill guidance.",
            )

# Check for inline graph in state.md (should be a reference pointer, not full content).
if state_file.is_file():
    state_text = read_text_normalized(state_file)
    if "```mermaid" in state_text:
        add_finding(
            "STR-601", "SHOULD_FIX", "state_inline_graph", state_file,
            "state.md contains inline mermaid graph. Graph should be a reference to .state/pensieve-user-data-graph.md.",
            "Run migrate or doctor to regenerate state.md with graph reference pointer.",
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
    "has_missing_critical_files": any(f.finding_id == "STR-201" for f in findings),
    "has_critical_file_drift": any(f.finding_id == "STR-202" for f in findings),
    "has_missing_memory_file": any(f.finding_id == "STR-501" for f in findings),
    "has_memory_content_drift": any(f.finding_id == "STR-502" for f in findings),
    "has_state_inline_graph": any(f.finding_id == "STR-601" for f in findings),
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
