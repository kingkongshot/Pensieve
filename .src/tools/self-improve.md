---
description: 从对话、diff、review 结果中提取可复用结论，写入 short-term 或长期目录，并同步图谱。
---

# Self-Improve Tool

> Tool boundaries: see `.src/references/tool-boundaries.md` | Shared rules: see `.src/references/shared-rules.md`

## Use when

- A task round ends with clear reusable conclusions
- Repeatedly extractable patterns emerge during review

## Write targets

### 新建文件 → 默认写入 short-term

- `maxim` → `short-term/maxims/{one-sentence-conclusion}.md`
- `decision` → `short-term/decisions/{date}-{conclusion}.md`
- `pipeline` → `short-term/pipelines/run-when-*.md`
- `knowledge` → `short-term/knowledge/{name}/content.md`

命名规范与对应长期目录一致。`[[...]]` 链接不含 `short-term/` 前缀。

### 修改已有文件 → 原地修改

已在 `maxims/decisions/knowledge/pipelines` 中的文件直接原地修改，不走 short-term。

### 例外：用户明确要求直接写入长期目录时可跳过 short-term。

Read before writing:

- `.src/references/maxims.md`
- `.src/references/decisions.md`
- `.src/references/pipelines.md`
- `.src/references/knowledge.md`
- `.src/references/short-term.md`

## Post-write refresh

After writing user data, refresh the project state and graph:

> All `.src/` paths below are relative to the skill root (`$PENSIEVE_SKILL_ROOT`, typically `~/.claude/skills/pensieve/`).

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/maintain-project-state.sh" --event self-improve --note "description"
```

In a Claude Code environment this is triggered automatically by hooks; in other environments it must be run manually.
