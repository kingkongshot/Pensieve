---
name: pensieve
description: Project knowledge base and workflow routing. Knowledge contains previously explored file locations, module boundaries, and call chains — reuse directly instead of re-locating; decisions/maxims are settled architectural decisions and coding principles — follow them, don't re-debate; pipelines are reusable workflows. Use self-improve to capture new findings after tasks. Provides init, upgrade, doctor, self-improve, and loop tools.
---

# Pensieve

Route user requests to the correct tool. When uncertain, confirm first.

## Intent Routing

1. **Explicit intent takes priority**: if the user explicitly names a tool or trigger word, route directly.
2. **Infer from session stage** (when no explicit command is given):
   - New project or blank context → `init` | Version/migration uncertainty → `upgrade`
   - Exploring codebase or locating issues → check `<USER_DATA_ROOT>/knowledge/` first, then use `self-improve` to write findings
   - Development complete or retrospective signals → `self-improve` | Complex task needing decomposition → `loop`
3. **When uncertain, confirm first**.

<example>
User: "Initialize pensieve" → Route: tools/init/_init.md
User: "Check if there are any data issues" → Route: tools/doctor/_doctor.md
User: "This task is complex, run it with loop" → Route: tools/loop/_loop.md
</example>

## Global Rules (Summary)

1. **Upgrade priority**: version/compatibility/migration issues go through upgrade for version confirmation first.
2. **Confirm before executing**: when the user has not explicitly issued a command, confirm first.
3. **Keep links connected**: `decision/pipeline` must have at least one `[[...]]` link.
4. **Read spec before writing data**: read the corresponding README before creating/checking user data.

> Full rules in `references/shared-rules.md`

## Tool Execution Protocol

Before executing any tool, read its `### Use when` section to confirm applicability. For tool boundaries and redirect rules, see `references/tool-boundaries.md`.

## Routing Table

| Intent | Tool spec (read first) | Trigger words |
|--------|------------------------|---------------|
| Initialize | `<SYSTEM_SKILL_ROOT>/tools/init/_init.md` | init, initialize |
| Version update | `<SYSTEM_SKILL_ROOT>/tools/upgrade/_upgrade.md` | upgrade, migrate, version |
| Health check | `<SYSTEM_SKILL_ROOT>/tools/doctor/_doctor.md` | doctor, check, format check |
| Archive experience | `<SYSTEM_SKILL_ROOT>/tools/self-improve/_self-improve.md` | self-improve, archive, reflect |
| Iterative execution | `<SYSTEM_SKILL_ROOT>/tools/loop/_loop.md` | loop, iterative execution, execute pipeline |

## Routing Failure Fallback

1. **Ambiguous intent**: return candidate routes and ask the user to confirm.
2. **Tool entry unreadable**: stop and report the missing path.
3. **Incomplete input**: collect missing information before executing.

`<SYSTEM_SKILL_ROOT>` is injected by the SessionStart hook; user data path is fixed at `<project>/.claude/skills/pensieve/`.
