from __future__ import annotations

import datetime as dt
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


def _load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(f"Failed to parse json: {path} ({exc})")
    if not isinstance(data, dict):
        raise SystemExit(f"Invalid json root type: {path}")
    return data


def _parse_graph(path: Path) -> tuple[dict[str, int], list[tuple[str, str]]]:
    text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    stats = {
        "notes": 0,
        "links": 0,
        "resolved": 0,
        "unresolved": 0,
    }

    patterns = {
        "notes": re.compile(r"^- Notes scanned:\s*(\d+)\s*$", flags=re.MULTILINE),
        "links": re.compile(r"^- Links found:\s*(\d+)\s*$", flags=re.MULTILINE),
        "resolved": re.compile(r"^- Links resolved:\s*(\d+)\s*$", flags=re.MULTILINE),
        "unresolved": re.compile(r"^- Links unresolved:\s*(\d+)\s*$", flags=re.MULTILINE),
    }
    for key, pat in patterns.items():
        m = pat.search(text)
        if m:
            stats[key] = int(m.group(1))

    unresolved: list[tuple[str, str]] = []
    for m in re.finditer(r"^- `([^`]+)` -> `\[\[([^\]]+)\]\]`\s*$", text, flags=re.MULTILINE):
        unresolved.append((m.group(1), m.group(2)))

    return stats, unresolved


@dataclass
class Finding:
    finding_id: str
    severity: str
    category: str
    path: str
    rule_source: str
    message: str
    recommendation: str


def _yes_no(v: object) -> str:
    return "yes" if bool(v) else "no"


def _next_step(must_fix: list[Finding], schema: dict[str, Any]) -> tuple[str, bool, bool]:
    doctor_cfg = schema.get("doctor") if isinstance(schema.get("doctor"), dict) else {}
    next_cfg = doctor_cfg.get("next_step") if isinstance(doctor_cfg.get("next_step"), dict) else {}
    migrate_categories = {str(x) for x in next_cfg.get("migrate_categories", [])}
    upgrade_categories = {str(x) for x in next_cfg.get("upgrade_categories", [])}

    has_migrate = any(f.category in migrate_categories for f in must_fix)
    has_upgrade = any(f.category in upgrade_categories for f in must_fix)

    if must_fix:
        if has_migrate:
            return "migrate", has_migrate, has_upgrade
        if has_upgrade:
            return "upgrade", has_migrate, has_upgrade
        return "self-improve", has_migrate, has_upgrade

    return "none", has_migrate, has_upgrade


def _build_report(
    *,
    status: str,
    next_step: str,
    check_time: str,
    project_root: str,
    user_root: str,
    graph_file: Path,
    graph_stats: dict[str, int],
    unresolved_links: list[tuple[str, str]],
    findings: list[Finding],
    must_fix: list[Finding],
    should_fix: list[Finding],
    info: list[Finding],
    flags: dict[str, Any],
    has_migrate_must_fix: bool,
    has_upgrade_must_fix: bool,
) -> str:
    if graph_stats["unresolved"] == 0:
        graph_observation = "All graph links resolved."
    else:
        hard = sum(1 for src, _ in unresolved_links if src.startswith("decisions/") or src.startswith("pipelines/"))
        graph_observation = f"{graph_stats['unresolved']} unresolved links ({hard} decision/pipeline broken links)."

    lines: list[str] = []
    lines.append("# Pensieve Doctor Report")
    lines.append("")
    lines.append("## 0) Header")
    lines.append(f"- Check time: {check_time}")
    lines.append(f"- Project root: `{project_root}`")
    lines.append(f"- Data root: `{user_root}`")
    lines.append("")
    lines.append("## 1) Executive Summary")
    lines.append(f"- Overall status: {status}")
    lines.append(f"- MUST_FIX: {len(must_fix)}")
    lines.append(f"- SHOULD_FIX: {len(should_fix)}")
    lines.append(f"- INFO: {len(info)}")
    lines.append(f"- Suggested next step: `{next_step}`")
    lines.append("")
    lines.append("## 1.5) Graph Summary")
    lines.append(f"- Graph file: `{graph_file}`")
    lines.append(f"- Notes scanned: {graph_stats['notes']}")
    lines.append(f"- Links found: {graph_stats['links']}")
    lines.append(f"- Links resolved: {graph_stats['resolved']}")
    lines.append(f"- Links unresolved: {graph_stats['unresolved']}")
    lines.append(f"- Observation: {graph_observation}")
    lines.append("")
    lines.append("## 2) Must Fix (by priority)")
    if not must_fix:
        lines.append("- (none)")
    else:
        for i, f in enumerate(must_fix, start=1):
            lines.append(f"{i}. [{f.finding_id}] {f.message}")
            lines.append(f"   File: `{f.path}`")
            lines.append(f"   Rule: `{f.rule_source}`")
            lines.append(f"   Fix: {f.recommendation}")
            lines.append("")
    if lines and lines[-1] == "":
        lines.pop()
    lines.append("")
    lines.append("## 3) Should Fix")
    if not should_fix:
        lines.append("- (none)")
    else:
        for i, f in enumerate(should_fix, start=1):
            lines.append(f"{i}. [{f.finding_id}] {f.message} (`{f.path}`)")
    lines.append("")
    lines.append("## 4) Migration & Structure Check")
    lines.append(f"- Legacy v1 paths found: {_yes_no(flags.get('has_deprecated_paths'))}")
    lines.append(f"- Missing required dirs: {_yes_no(flags.get('has_missing_directories'))}")
    lines.append(f"- Critical file drift: {_yes_no(flags.get('has_critical_file_drift'))}")
    lines.append(
        f"- MEMORY.md missing/drifted: {_yes_no(flags.get('has_missing_memory_file') or flags.get('has_memory_content_drift'))}"
    )
    lines.append(f"- state.md inline graph: {_yes_no(flags.get('has_state_inline_graph'))}")
    lines.append(f"- Suggested action: `{next_step if next_step in {'migrate', 'upgrade', 'self-improve'} else 'none'}`")
    lines.append("")
    lines.append("## 5) Action Plan")
    if must_fix and has_migrate_must_fix:
        lines.append("1. Run `migrate` to complete structure migration and align key files.")
        lines.append("2. Re-run `doctor` to confirm MUST_FIX count is zero.")
        lines.append("3. If SHOULD_FIX/INFO remain, fix them by priority.")
    elif must_fix and has_upgrade_must_fix:
        lines.append("1. Run `upgrade` to update skill source code.")
        lines.append("2. Re-run `doctor` to confirm MUST_FIX count is zero.")
        lines.append("3. If structure migration issues appear later, run `migrate`.")
    elif must_fix:
        lines.append("1. Fix MUST_FIX items per report (frontmatter/broken links/MEMORY). No need to run `migrate` first.")
        lines.append("2. Re-run `doctor` to confirm MUST_FIX count is zero.")
        lines.append("3. If migration issues appear later (deprecated paths/file drift), run `migrate`.")
    elif should_fix or info:
        lines.append("1. Fix SHOULD_FIX items to maintain long-term spec compliance.")
        lines.append("2. Re-run `doctor` to confirm status is PASS.")
        lines.append("3. Capture effective fixes via `self-improve`.")
    else:
        lines.append("1. No structural fixes needed.")
        lines.append("2. Continue using self-improve as usual.")
        lines.append("3. Re-run doctor after next upgrade.")
    lines.append("")
    lines.append("## 6) Findings Detail (Appendix)")
    lines.append("| ID | Severity | Category | File/Path | Rule Source | Issue | Recommendation |")
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
    lines.append("## 7) Broken Links Detail (Appendix)")
    lines.append("| Source File | Unresolved Link | Note |")
    lines.append("|---|---|---|")
    if unresolved_links:
        for src, target in unresolved_links:
            memo = "decision/pipeline broken link (MUST_FIX)" if (src.startswith("decisions/") or src.startswith("pipelines/")) else "general broken link"
            lines.append(f"| {src} | [[{target}]] | {memo} |")
    else:
        lines.append("| - | - | No broken links |")
    lines.append("")
    lines.append("## 8) Frontmatter Check Results (Appendix)")
    lines.append("| File | Severity | Code | Issue |")
    lines.append("|---|---|---|---|")
    fm_issues = [f for f in findings if f.category == "frontmatter"]
    if fm_issues:
        for f in fm_issues:
            msg = f.message.replace("|", "\\|")
            lines.append(f"| {f.path} | {f.severity} | {f.finding_id} | {msg} |")
    else:
        lines.append("| - | - | - | No frontmatter issues |")

    return "\n".join(lines).rstrip() + "\n"


def run(argv: list[str]) -> int:
    if len(argv) != 9:
        raise SystemExit(
            "usage: doctor_engine.py <scan-json> <frontmatter-json> <graph-md> <report-md> <summary-json> <project-root> <data-root> <check-time> <schema-json>"
        )

    scan_file = Path(argv[0])
    frontmatter_file = Path(argv[1])
    graph_file = Path(argv[2])
    report_file = Path(argv[3])
    summary_file = Path(argv[4])
    project_root = argv[5]
    user_root = argv[6]
    check_time = argv[7]
    schema_file = Path(argv[8])

    scan = _load_json(scan_file)
    frontmatter = _load_json(frontmatter_file)
    schema = _load_json(schema_file)
    graph_stats, unresolved_links = _parse_graph(graph_file)

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
                rule_source=".src/references/directory-layout.md",
                message=str(item.get("message", "")),
                recommendation=str(item.get("recommended_action", "Fix per recommendation and re-run doctor")),
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
                rule_source=".src/scripts/check-frontmatter.sh",
                message=str(issue.get("message", "")),
                recommendation="Fix frontmatter fields and naming rules, then re-run doctor",
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
                rule_source=".src/tools/doctor.md",
                message=f"Unresolved link [[{target}]]",
                recommendation="Create the target file or fix the link target name",
            )
        )

    # Check for short-term items due for refine
    short_term_dir = Path(user_root) / "short-term"
    if short_term_dir.is_dir():
        today_date = dt.date.today()
        ttl_days = 7
        date_re = re.compile(r"^created:\s*(\d{4}-\d{2}-\d{2})", re.MULTILINE)
        stm_idx = 0
        for md_file in sorted(short_term_dir.rglob("*.md")):
            if not md_file.is_file():
                continue
            text = md_file.read_text(encoding="utf-8", errors="replace")[:1024]
            fm_end = text.find("\n---", 4)
            if fm_end < 0:
                continue
            fm_block = text[:fm_end]
            tags_idx = fm_block.find("tags:")
            if tags_idx >= 0 and "seed" in fm_block[tags_idx:].split("\n")[0].lower():
                continue
            m = date_re.search(fm_block)
            if not m:
                continue
            try:
                created = dt.date.fromisoformat(m.group(1))
            except ValueError:
                continue
            if (today_date - created).days >= ttl_days:
                stm_idx += 1
                rel_path = str(md_file.relative_to(Path(user_root)))
                days_overdue = (today_date - created).days - ttl_days
                findings.append(
                    Finding(
                        finding_id=f"STM-{stm_idx:03d}",
                        severity="SHOULD_FIX",
                        category="short_term_due_refine",
                        path=rel_path,
                        rule_source=".src/references/short-term.md",
                        message=f"Short-term item due for refine (created {m.group(1)}, {days_overdue}d overdue). Promote or delete.",
                        recommendation="Run refine tool to review short-term items",
                    )
                )

    must_fix = [f for f in findings if f.severity == "MUST_FIX"]
    should_fix = [f for f in findings if f.severity == "SHOULD_FIX"]
    info = [f for f in findings if f.severity == "INFO"]

    next_step, has_migrate_must_fix, has_upgrade_must_fix = _next_step(must_fix, schema)

    if must_fix:
        status = "FAIL"
    elif should_fix or info:
        status = "PASS_WITH_WARNINGS"
        next_step = "self-improve"
    else:
        status = "PASS"
        next_step = "none"

    flags = scan.get("flags", {}) if isinstance(scan.get("flags"), dict) else {}

    report_text = _build_report(
        status=status,
        next_step=next_step,
        check_time=check_time,
        project_root=project_root,
        user_root=user_root,
        graph_file=graph_file,
        graph_stats=graph_stats,
        unresolved_links=unresolved_links,
        findings=findings,
        must_fix=must_fix,
        should_fix=should_fix,
        info=info,
        flags=flags,
        has_migrate_must_fix=has_migrate_must_fix,
        has_upgrade_must_fix=has_upgrade_must_fix,
    )
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
    return 0


if __name__ == "__main__":
    raise SystemExit(run(sys.argv[1:]))
