from __future__ import annotations

import json
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
        "legacy_paths",
        "legacy_graph_patterns",
        "plugin_keys",
        "memory",
        "doctor",
        "findings",
    }
    missing = sorted(k for k in required_top if k not in schema)
    if missing:
        raise SchemaError(f"schema missing keys: {', '.join(missing)}")

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
    if must_fix_count > 0:
        return "DRIFTED"
    return "DRIFTED"
