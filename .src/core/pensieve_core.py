from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


class SchemaError(RuntimeError):
    pass


def _read_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except Exception as exc:  # noqa: BLE001
        raise SchemaError(f"failed to parse schema: {path} ({exc})") from exc
    if not isinstance(data, dict):
        raise SchemaError(f"schema root must be object: {path}")
    return data


def load_schema(schema_file: Path) -> dict[str, Any]:
    if not schema_file.is_file():
        raise SchemaError(f"schema file missing: {schema_file}")

    schema = _read_json(schema_file)

    required_top = {
        "required_dirs",
        "critical_files",
        "memory",
        "doctor",
    }
    missing = sorted(k for k in required_top if k not in schema)
    if missing:
        raise SchemaError(f"schema missing keys: {', '.join(missing)}")

    version = schema.get("schema_version")
    if version != 2:
        raise SchemaError(f"unsupported schema_version: {version!r} (expected 2)")

    return schema


def classify_state(
    *,
    has_missing_root: bool,
    has_missing_directories: bool,
    has_missing_critical_files: bool,
    must_fix_count: int,
) -> str:
    # Explicit state machine for project data lifecycle.
    if has_missing_root or has_missing_directories:
        return "EMPTY"
    if has_missing_critical_files:
        return "SEEDED"
    if must_fix_count == 0:
        return "ALIGNED"
    return "DRIFTED"


# ---------------------------------------------------------------------------
# Shared normalization for critical file comparison (used by scan-structure
# and run-migrate to ignore context-link value differences).
# ---------------------------------------------------------------------------

_CONTEXT_LINK_LINE_RE = re.compile(
    r"^(\s*-\s*(?:基于|导致|相关|[Bb]ased[ -]on|[Ll]eads[ -]to|[Rr]elated)[:：])\s*.*$"
)

_PIPELINE_BASENAMES = frozenset({
    "run-when-reviewing-code.md",
    "pipeline.run-when-reviewing-code.md",
    "run-when-committing.md",
    "pipeline.run-when-committing.md",
})


def normalize_context_link_line(line: str) -> str:
    """Replace the value portion of a context-link line with a placeholder."""
    m = _CONTEXT_LINK_LINE_RE.match(line)
    if not m:
        return line.rstrip()
    return f"{m.group(1)} <context-value>"


def normalize_critical_file_content(basename: str, text: str) -> str:
    """Normalize a critical file's content for comparison.

    For pipeline files, context-link values are replaced with placeholders so
    that trivial link-target differences do not trigger drift detection.
    """
    if basename in _PIPELINE_BASENAMES:
        lines = [normalize_context_link_line(line) for line in text.split("\n")]
        return "\n".join(lines).rstrip() + "\n"
    return text


# ---------------------------------------------------------------------------
# SKILL.md frontmatter description extraction (used by scan-structure and
# maintain-auto-memory to read the skill description from SKILL.md).
# ---------------------------------------------------------------------------

_FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n?", flags=re.MULTILINE | re.DOTALL)


def load_skill_description(path: Path) -> str | None:
    """Extract the ``description`` value from a SKILL.md frontmatter block.

    Returns the description string, or ``None`` if the file is missing,
    has no valid frontmatter, or has no ``description`` field.
    """
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")
    m = _FRONTMATTER_RE.search(text)
    if not m:
        return None
    lines = m.group(1).splitlines()
    for i, line in enumerate(lines):
        if not line.startswith("description:"):
            continue
        value = line.split(":", 1)[1].strip()
        if value in (">-", ">", "|", "|-"):
            parts: list[str] = []
            for cont in lines[i + 1 :]:
                if cont and cont[0] in (" ", "\t"):
                    parts.append(cont.strip())
                else:
                    break
            if parts:
                sep = " " if value.startswith(">") else "\n"
                return sep.join(parts)
            return None
        return value if value else None
    return None
