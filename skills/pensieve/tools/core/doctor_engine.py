from __future__ import annotations

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
    lines.append(f"- 发现旧路径: {_yes_no(flags.get('has_deprecated_paths'))}")
    lines.append(f"- 发现新旧并行: {_yes_no(flags.get('has_deprecated_paths'))}")
    lines.append(f"- 发现非项目级 skill 根: {_yes_no(flags.get('has_deprecated_paths'))}")
    lines.append(f"- 发现独立 graph 文件: {_yes_no(flags.get('has_legacy_graph_files'))}")
    lines.append(f"- 缺失关键目录: {_yes_no(flags.get('has_missing_directories'))}")
    lines.append(
        f"- MEMORY.md 缺失/漂移: {_yes_no(flags.get('has_missing_memory_file') or flags.get('has_memory_content_drift'))}"
    )
    lines.append(f"- 建议动作: `{next_step if next_step in {'migrate', 'upgrade', 'self-improve'} else 'none'}`")
    lines.append("")
    lines.append("## 5) 三步行动计划")
    if must_fix and has_migrate_must_fix:
        lines.append("1. 先运行 `migrate` 脚本完成结构迁移与关键文件对齐。")
        lines.append("2. 再运行一次 `doctor`，确认 MUST_FIX 清零。")
        lines.append("3. 若仍有 SHOULD_FIX/INFO，再按优先级逐项修复。")
    elif must_fix and has_upgrade_must_fix:
        lines.append("1. 先运行 `upgrade` 脚本完成版本更新与插件键对齐。")
        lines.append("2. 再运行一次 `doctor`，确认 MUST_FIX 清零。")
        lines.append("3. 若后续出现结构迁移类问题，再执行 `migrate`。")
    elif must_fix:
        lines.append("1. 先按报告逐项修复 MUST_FIX（frontmatter/断链/MEMORY 等内容问题），无需先执行 `migrate`。")
        lines.append("2. 修复后重跑 `doctor`，确认 MUST_FIX 清零。")
        lines.append("3. 若后续出现迁移类问题（旧路径/关键文件漂移），再执行 `migrate`。")
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
                rule_source="tools/doctor/migrations/README.md",
                message=str(item.get("message", "")),
                recommendation=str(item.get("recommended_action", "按建议修复后重跑 doctor")),
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
