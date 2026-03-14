---
id: skill-lifecycle
type: knowledge
title: Pensieve 安装与更新
status: active
created: 2026-03-06
updated: 2026-03-10
tags: [pensieve, install, update, operations]
---

# Pensieve 安装与更新

当用户询问如何安装、初始化、更新、重装、卸载 Pensieve 本身时，先读本文件。

## 安装

### 第一步：安装系统代码（全局，一次性）

把仓库 clone 到用户级 skill 目录：

```bash
# 英文用户
git clone -b main https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve

# 中文用户
git clone -b zh https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve
```

说明：

- 系统文件（`.src/`、`agents/`、`SKILL.md`）由 git 跟踪
- `SKILL.md` 是静态、tracked 文件——skill 接口声明
- 一次安装服务所有项目

### 第二步：安装 hooks（全局，一次性）

```bash
bash ~/.claude/skills/pensieve/.src/scripts/install-hooks.sh
```

这会把 hook 配置写入 `~/.claude/settings.json`。hooks 自动对所有项目生效。没有 `.pensieve/` 的项目不受影响（hooks 静默退出）。

### 第三步：初始化项目数据（每个项目）

```bash
cd <your-project>
bash ~/.claude/skills/pensieve/.src/scripts/init-project-data.sh
```

或者让 agent 执行 `init`。

这会在 `<project>/.pensieve/` 下创建 `maxims/decisions/knowledge/pipelines` 并种子化默认内容。

## 初始化后验证

```bash
bash ~/.claude/skills/pensieve/.src/scripts/run-doctor.sh --strict
```

PASS 条件：

- skill 根目录存在 `.src/`
- skill 根目录存在 `SKILL.md`（静态、tracked）
- `<project>/.pensieve/{maxims,decisions,knowledge,pipelines}` 目录齐全
- `<project>/.pensieve/.state/` 已生成
- `<project>/.pensieve/state.md` 已生成
- 默认 pipeline 与 taste-review knowledge 已种子化

## 更新

### 更新系统代码

```bash
cd ~/.claude/skills/pensieve
git pull --ff-only || { git fetch origin && git reset --hard "origin/$(git rev-parse --abbrev-ref HEAD)"; }
```

`--ff-only` 适用于正常更新；远程被 force push 时回退到 `fetch + reset`（skill 目录只有 tracked 文件，安全）。

一次更新对所有项目生效。更新后：

```bash
cd <your-project>
bash ~/.claude/skills/pensieve/.src/scripts/run-doctor.sh --strict
```

如果 `doctor` 报结构迁移类问题：

```bash
bash ~/.claude/skills/pensieve/.src/scripts/run-migrate.sh
bash ~/.claude/skills/pensieve/.src/scripts/run-doctor.sh --strict
```

## 重装

如果系统文件被你自己改乱了：

1. 备份项目用户数据：`<project>/.pensieve/`（每个项目）
2. 删除旧的 skill checkout：`rm -rf ~/.claude/skills/pensieve`
3. 重新 clone（第一步）
4. 对每个项目跑 `init`（第三步）
5. 跑 `doctor`

如果只是正常升级，不要重装，直接用 upgrade 工具或手动 `git pull`

## 卸载

```bash
# 从 ~/.claude/settings.json 中手动移除 pensieve hook 条目
# 删除系统代码
rm -rf ~/.claude/skills/pensieve

# 删除项目数据（可选，每个项目）
rm -rf <project>/.pensieve
```

## Hook 增量能力

安装 hooks 后，还会多出：

- SessionStart marker 检查
- PreToolUse Explore/Plan prompt 注入（SKILL.md + state.md）
- PostToolUse 图谱与 auto memory 自动同步

## 路由规则

- 问"怎么安装/重装 Pensieve"：
  先读本文件，再引导到 `init`
- 问"怎么更新 Pensieve"：
  先读本文件，再引导到 `upgrade`
- 问"怎么清理旧结构/旧 graph"：
  先读本文件，再引导到 `migrate`
- 问"安装后怎么确认正常"：
  先读本文件，再引导到 `doctor`
