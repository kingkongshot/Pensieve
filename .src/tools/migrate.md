---
description: 迁移工具。将旧版本用户数据自动迁移到 v2 目录结构，并对齐关键种子文件；不做版本升级，不给 doctor 分级。
---

# Migrate 工具

> 工具边界见 `.src/references/tool-boundaries.md` | 共享规则见 `.src/references/shared-rules.md`

## Use when

- 从 v1（项目级安装）迁移到 v2（用户级系统 + 项目级数据）
- doctor 报告关键文件缺失或 critical file drift
- 需要补齐目录结构或重新对齐种子文件

## 标准执行

> All `.src/` paths below are relative to the skill root (`$PENSIEVE_SKILL_ROOT`, typically `~/.claude/skills/pensieve/`).

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/run-migrate.sh"
```

可选 dry-run：

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/run-migrate.sh" --dry-run
```
