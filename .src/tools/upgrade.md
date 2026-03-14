---
description: 刷新当前 git clone 的 Pensieve skill 源码。优先 git pull --ff-only，远程 force push 时自动回退到 fetch+reset；不做结构迁移与 doctor 分级。
---

# Upgrade 工具

> 工具边界见 `.src/references/tool-boundaries.md` | 共享规则见 `.src/references/shared-rules.md`

## Use when

- 用户要求升级 Pensieve
- 需要确认升级前后版本变化

如果用户先问"怎么更新 Pensieve"，先读 `.src/references/skill-lifecycle.md`，再执行本工具。

这个工具只负责全局 skill checkout（`~/.claude/skills/pensieve/`）。
Hooks 通过 `install-hooks.sh` 全局安装，不需要单独更新。

## 标准执行

> All `.src/` paths below are relative to the skill root (`$PENSIEVE_SKILL_ROOT`, typically `~/.claude/skills/pensieve/`).

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/run-upgrade.sh"
```

可选 dry-run：

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/run-upgrade.sh" --dry-run
```

升级后手动跑：

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/run-doctor.sh" --strict
```
