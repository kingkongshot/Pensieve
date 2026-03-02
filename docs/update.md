# 更新指南

## 插件更新（Marketplace）

如果你通过 Marketplace 安装：

```bash
claude plugin marketplace update kingkongshot/Pensieve
claude plugin update pensieve@kingkongshot-marketplace --scope user
```

然后重启 Claude Code 使更新生效。

如果你是在 Claude Code 会话里让模型代执行命令，`claude` 会检测嵌套会话并拦截；此时请在命令前加 `CLAUDECODE=` 清空该变量：

```bash
CLAUDECODE= claude plugin marketplace update kingkongshot/Pensieve
CLAUDECODE= claude plugin update pensieve@kingkongshot-marketplace --scope user
```

这两条命令可重复执行；如果已经是最新版本，通常不会产生变更。

> 如果你是项目级安装，请把 `--scope user` 改为 `--scope project`。

如果你是通过 `.claude/settings.json` URL 安装，重启 Claude Code 即可拉取更新。

### 更新失败兜底

如果更新命令失败（网络、权限、CLI 版本问题等），先查看 GitHub 上的最新文档再继续：

- [docs/update.md（main 分支）](https://github.com/kingkongshot/Pensieve/blob/main/docs/update.md)

在更新失败未解决前，不建议继续执行 Upgrade 工具。

---

## 系统 Skills

系统提示词（tools/scripts/system knowledge）随插件打包，并跟随插件更新。

---

## 更新后流程

重启 Claude Code 后，输入 `loop` 验证更新是否生效。

### 脚本化最短路径（推荐）

如果你希望尽量减少 LLM 参与，直接执行：

```bash
bash <SYSTEM_SKILL_ROOT>/tools/upgrade/scripts/run-upgrade.sh
```

只跑体检（可作为 CI 严格检查）：

```bash
bash <SYSTEM_SKILL_ROOT>/tools/doctor/scripts/run-doctor.sh --strict
```

`run-upgrade.sh` 会自动执行：版本对比 → 拉取最新 → 插件键与旧插件名清理（不做 doctor，不做结构迁移）。

**Upgrade 核心逻辑（脚本化简版）**：
- 只做版本相关动作：比对升级前后版本 + 拉取最新版本
- 只做插件配置清理：旧插件键、旧插件名
- 不做升级前结构检查，也不在 Upgrade 阶段运行 Doctor
- 升级完成后，由用户手动运行 Doctor 做体检
- 结构迁移（旧目录/关键文件/历史残留）单独通过 `run-migrate.sh` 处理

然后：
- 仅在需要版本更新时执行 Upgrade（不要把 Upgrade 当成体检或迁移步骤）
- 升级完成后手动执行一次 Doctor
- 如果 doctor 报告迁移/结构问题，再按报告继续处理
- 如果 doctor 通过，按需执行 Self-Improve 沉淀经验
- Doctor、Self-Improve（以及执行迁移后的流程）应维护：
  - 项目级 `.claude/skills/pensieve/SKILL.md`（固定路由 + graph）
  - Claude auto memory `~/.claude/projects/<project>/memory/MEMORY.md` 的 Pensieve 引导块（描述与系统 skill `description` 对齐）

推荐顺序：
1. 运行 Upgrade（版本对比 + 拉取 + 插件配置清理）
2. 若升级了版本，重启 Claude Code
3. 运行一次 Doctor（必须，手动触发）
4. 若 doctor 报告迁移类问题，运行：
```bash
bash <SYSTEM_SKILL_ROOT>/tools/migrate/scripts/run-migrate.sh
```
5. 迁移后再跑一次 Doctor，确认 MUST_FIX 清零
6. 需要沉淀经验时再运行 Self-Improve

如果你在指导用户，提醒他们只需表达这几个意图：
- loop 执行
- doctor 体检
- self-improve 沉淀
- upgrade 升级版本
- migrate 结构迁移
- 看图谱（直接读项目级 `SKILL.md` 的 `## Graph`）

---

## 用户数据保留策略

项目级用户数据 `.claude/skills/pensieve/` 不会被插件更新覆盖：

| 目录 | 内容 |
|------|------|
| `.claude/skills/pensieve/maxims/` | 自定义准则 |
| `.claude/skills/pensieve/decisions/` | 决策记录 |
| `.claude/skills/pensieve/knowledge/` | 自定义知识 |
| `.claude/skills/pensieve/pipelines/` | 项目 pipelines |
| `.claude/skills/pensieve/loop/` | loop 历史 |
