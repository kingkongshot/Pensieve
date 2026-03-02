#!/bin/bash
# Quick frontmatter + structural validator for project-level Pensieve user data.
# No external dependency; uses Python stdlib only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../loop/scripts/_lib.sh"

ROOT=""
FORMAT="text"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || { echo "Missing value for --root" >&2; exit 1; }
      ROOT="$2"
      shift 2
      ;;
    --format)
      [[ $# -ge 2 ]] || { echo "Missing value for --format" >&2; exit 1; }
      FORMAT="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  check-frontmatter.sh [--root <path>] [--format <text|json>]

Options:
  --root <path>      Scan root. Default: <project>/.claude/skills/pensieve
  --format <fmt>     Output format: text | json. Default: text
  -h, --help         Show help
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

case "$FORMAT" in
  text|json)
    ;;
  *)
    echo "Unsupported --format: $FORMAT (expected: text|json)" >&2
    exit 1
    ;;
esac

if [[ -z "$ROOT" ]]; then
  ROOT="$(user_data_root)"
fi
ROOT="$(to_posix_path "$ROOT")"

PYTHON_BIN="$(python_bin || true)"
[[ -n "$PYTHON_BIN" ]] || { echo "Python not found" >&2; exit 1; }

"$PYTHON_BIN" - "$ROOT" "$FORMAT" <<'PY'
from __future__ import annotations

import datetime as dt
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

root = Path(sys.argv[1])
fmt = sys.argv[2]

allowed_types = {"maxim", "decision", "knowledge", "pipeline"}
allowed_status = {"draft", "active", "archived"}
required_keys = ["id", "type", "title", "status", "created", "updated", "tags"]
id_re = re.compile(r"^[a-z0-9][a-z0-9-]*$")
date_re = re.compile(r"^\d{4}-\d{2}-\d{2}$")
pipeline_name_re = re.compile(r"^run-when-[a-z0-9-]+\.md$")


@dataclass
class Issue:
    level: str  # MUST_FIX / SHOULD_FIX
    code: str
    path: str
    message: str


def list_markdown_files(base: Path) -> list[Path]:
    if not base.exists():
        return []
    files: list[Path] = []
    for cat in ["maxims", "decisions", "knowledge", "pipelines"]:
        cat_dir = base / cat
        if not cat_dir.exists():
            continue
        for p in cat_dir.rglob("*.md"):
            if p.name.startswith("graph"):
                continue
            if cat == "maxims" and p.name == "custom.md":
                # Legacy maxim index; not part of current required model.
                continue
            files.append(p)
    return sorted(files)


def parse_frontmatter(text: str) -> tuple[dict[str, object] | None, list[str], str | None]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, [], None

    end_idx = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end_idx = i
            break
    if end_idx is None:
        return None, [], "unclosed"

    fm_lines = lines[1:end_idx]
    data: dict[str, object] = {}
    errors: list[str] = []

    current_key: str | None = None
    mode: str | None = None  # None | list | block

    i = 0
    while i < len(fm_lines):
        line = fm_lines[i].rstrip("\n")
        stripped = line.strip()

        if mode == "block":
            if line.startswith(" ") or line.startswith("\t") or stripped == "":
                if stripped:
                    prev = data.get(current_key or "", "")
                    assert isinstance(prev, str)
                    data[current_key or ""] = (prev + "\n" if prev else "") + line.lstrip()
                i += 1
                continue
            mode = None
            current_key = None
            continue  # reprocess current line

        if mode == "list":
            if line.lstrip().startswith("- "):
                item = line.split("- ", 1)[1].strip()
                cast = data.get(current_key or "")
                if not isinstance(cast, list):
                    errors.append(f"malformed list item: {line}")
                elif item:
                    cast.append(item)
                i += 1
                continue
            if line.startswith(" ") or line.startswith("\t"):
                errors.append(f"malformed list item: {line}")
                i += 1
                continue
            mode = None
            current_key = None
            continue  # reprocess current line

        if not stripped or stripped.startswith("#"):
            i += 1
            continue

        if ":" not in line:
            errors.append(f"malformed line: {line}")
            i += 1
            continue

        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()

        if not key:
            errors.append(f"empty key line: {line}")
            i += 1
            continue
        if key in data:
            errors.append(f"duplicate key: {key}")
            i += 1
            continue

        if value in {"|", ">", "|-", ">-", "|+", ">+"}:
            data[key] = ""
            current_key = key
            mode = "block"
            i += 1
            continue

        if value == "":
            data[key] = []
            current_key = key
            mode = "list"
            i += 1
            continue

        if value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            items = [] if inner == "" else [x.strip().strip('"').strip("'") for x in inner.split(",")]
            data[key] = [x for x in items if x]
            current_key = key
            mode = None
            i += 1
            continue

        data[key] = value.strip('"').strip("'")
        current_key = key
        mode = None
        i += 1

    return data, errors, None


def body_without_frontmatter(text: str) -> str:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "\n".join(lines[i + 1 :])
    return text


def valid_date(s: str) -> bool:
    if not date_re.match(s):
        return False
    try:
        dt.date.fromisoformat(s)
    except ValueError:
        return False
    return True


issues: list[Issue] = []
files = list_markdown_files(root)

if not root.exists():
    issues.append(Issue("MUST_FIX", "FM-000", str(root), "用户数据根目录不存在"))

for p in files:
    rel = str(p.relative_to(root))

    if rel.startswith("pipelines/"):
        if p.name == "review.md":
            issues.append(
                Issue(
                    "MUST_FIX",
                    "FM-301",
                    rel,
                    "legacy pipeline 文件名 `review.md` 已废弃，必须改为 `run-when-*.md`（推荐 `run-when-reviewing-code.md`）",
                )
            )
        elif not pipeline_name_re.match(p.name):
            issues.append(
                Issue(
                    "MUST_FIX",
                    "FM-302",
                    rel,
                    "pipeline 文件名必须为 `run-when-*.md`，从文件名可直接判断触发场景",
                )
            )

    text = p.read_text(encoding="utf-8", errors="replace")
    fm, parse_errors, fm_state = parse_frontmatter(text)

    if fm is None:
        if fm_state == "unclosed":
            issues.append(Issue("MUST_FIX", "FM-101", rel, "frontmatter 起始存在但未闭合（缺少结束 ---）"))
        else:
            issues.append(Issue("MUST_FIX", "FM-102", rel, "缺少 frontmatter（必须添加统一顶部元数据）"))
        continue

    for err in parse_errors:
        issues.append(Issue("MUST_FIX", "FM-103", rel, f"frontmatter 语法错误: {err}"))

    missing = [k for k in required_keys if k not in fm]
    if missing:
        issues.append(Issue("MUST_FIX", "FM-104", rel, f"缺少必填字段: {', '.join(missing)}"))

    v_type = fm.get("type")
    if isinstance(v_type, str) and v_type and v_type not in allowed_types:
        issues.append(Issue("MUST_FIX", "FM-201", rel, f"type 非法: {v_type}（允许: {', '.join(sorted(allowed_types))}）"))

    v_status = fm.get("status")
    if isinstance(v_status, str) and v_status and v_status not in allowed_status:
        issues.append(Issue("MUST_FIX", "FM-202", rel, f"status 非法: {v_status}（允许: {', '.join(sorted(allowed_status))}）"))

    v_id = fm.get("id")
    if isinstance(v_id, str) and v_id and not id_re.match(v_id):
        issues.append(Issue("MUST_FIX", "FM-203", rel, "id 非法（仅允许小写字母/数字/中划线，且不能以中划线开头）"))

    for key in ["created", "updated"]:
        v = fm.get(key)
        if isinstance(v, str) and v and not valid_date(v):
            issues.append(Issue("MUST_FIX", "FM-204", rel, f"{key} 非法（应为 YYYY-MM-DD）"))

    v_tags = fm.get("tags")
    if v_tags is not None and not isinstance(v_tags, list):
        issues.append(Issue("MUST_FIX", "FM-205", rel, "tags 非法（应为数组，如 [pensieve, maxim]）"))

    if rel.startswith("decisions/"):
        body = body_without_frontmatter(text)
        if not re.search(r"^\s*##\s*(?:探索减负|Exploration Reduction)\s*$", body, flags=re.MULTILINE):
            issues.append(
                Issue(
                    "SHOULD_FIX",
                    "FM-401",
                    rel,
                    "decision 建议包含 `## 探索减负` / `## Exploration Reduction` 段",
                )
            )
        else:
            if "下次可以少问什么" not in body and "What to ask less" not in body:
                issues.append(
                    Issue(
                        "SHOULD_FIX",
                        "FM-402",
                        rel,
                        "探索减负 段缺少“下次可以少问什么 / What to ask less”条目",
                    )
                )
            if "下次可以少查什么" not in body and "What to look up less" not in body:
                issues.append(
                    Issue(
                        "SHOULD_FIX",
                        "FM-403",
                        rel,
                        "探索减负 段缺少“下次可以少查什么 / What to look up less”条目",
                    )
                )
            if "失效条件" not in body and "Invalidation condition" not in body:
                issues.append(
                    Issue(
                        "SHOULD_FIX",
                        "FM-404",
                        rel,
                        "探索减负 段缺少“失效条件 / Invalidation conditions”条目",
                    )
                )

must_fix = [x for x in issues if x.level == "MUST_FIX"]
should_fix = [x for x in issues if x.level == "SHOULD_FIX"]

if fmt == "json":
    out = {
        "root": str(root),
        "files_scanned": len(files),
        "summary": {
            "must_fix_count": len(must_fix),
            "should_fix_count": len(should_fix),
            "total_issues": len(issues),
        },
        "issues": [
            {
                "level": i.level,
                "code": i.code,
                "path": i.path,
                "message": i.message,
            }
            for i in issues
        ],
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))
else:
    print("# Frontmatter 快检报告")
    print()
    print(f"- Root: `{root}`")
    print(f"- Files scanned: {len(files)}")
    print(f"- MUST_FIX: {len(must_fix)}")
    print(f"- SHOULD_FIX: {len(should_fix)}")
    print()

    print("## MUST_FIX")
    if not must_fix:
        print("- (none)")
    else:
        for i in must_fix:
            print(f"- [{i.code}] `{i.path}`: {i.message}")
    print()

    print("## SHOULD_FIX")
    if not should_fix:
        print("- (none)")
    else:
        for i in should_fix:
            print(f"- [{i.code}] `{i.path}`: {i.message}")
PY
