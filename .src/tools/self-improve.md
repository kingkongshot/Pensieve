---
description: 从对话、diff、review 结果中提取可复用结论，写入 short-term 或长期目录，并同步图谱。
---

# Self-Improve 工具

> 工具边界见 `.src/references/tool-boundaries.md` | 共享规则见 `.src/references/shared-rules.md`

## Use when

- 一轮任务结束后有明确可复用结论
- review 里出现反复可提炼的模式

## 写入位置

### 新建文件 → 默认写入 short-term

- `maxim` → `short-term/maxims/{one-sentence-conclusion}.md`
- `decision` → `short-term/decisions/{date}-{conclusion}.md`
- `pipeline` → `short-term/pipelines/run-when-*.md`
- `knowledge` → `short-term/knowledge/{name}/content.md`

命名规范与对应长期目录一致。`[[...]]` 链接不含 `short-term/` 前缀。

### 修改已有文件 → 原地修改

已在 `maxims/decisions/knowledge/pipelines` 中的文件直接原地修改，不走 short-term。

### 例外：用户明确要求直接写入长期目录时可跳过 short-term。

写入前先读：

- `.src/references/maxims.md`
- `.src/references/decisions.md`
- `.src/references/pipelines.md`
- `.src/references/knowledge.md`
- `.src/references/short-term.md`

## 写入后刷新

写入用户数据后，刷新项目状态和图谱：

> All `.src/` paths below are relative to the skill root (`$PENSIEVE_SKILL_ROOT`, typically `~/.claude/skills/pensieve/`).

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/maintain-project-state.sh" --event self-improve --note "描述"
```

Claude Code 环境下由 hook 自动触发，其他环境须手动运行。
