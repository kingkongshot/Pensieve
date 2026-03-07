---
id: skill-lifecycle
type: knowledge
title: Pensieve 安装与更新
status: active
created: 2026-03-06
updated: 2026-03-07
tags: [pensieve, install, update, operations]
---

# Pensieve 安装与更新

当用户询问如何安装、初始化、更新、重装、卸载 Pensieve 本身时，先读本文件。

## 安装

### 方式 A：安装 main 分支 skill（必需）

把仓库直接 clone 到项目里的 skill 目录：

```bash
git clone -b experimental https://github.com/kingkongshot/Pensieve.git .claude/skills/pensieve
```

说明：

- `main` 分支仓库根就是 skill 根，不再有 `skill-source/pensieve/` 这一层
- tracked 系统文件是 `.src/`、`agents/`
- 根目录 `SKILL.md` 是生成文件，初始化后写入固定位置，并由 `.gitignore` 忽略
- 用户数据目录是 `maxims/decisions/knowledge/pipelines/loop`
- 用户数据目录与生成的 `SKILL.md` 都由根 `.gitignore` 忽略，所以 `git pull` 不会覆盖它们
- 不再依赖 `npx skills add --copy`

安装后：

1. 让 agent 执行 `init`
2. 或者在 skill 根目录手工执行：

```bash
bash .src/scripts/init-project-data.sh
```

### 方式 B：安装 Claude plugin hooks（可选增量）

hooks 不在 `main` 分支，单独放在 `claude-plugin` 分支，通过 marketplace 安装：

```bash
claude plugin marketplace add kingkongshot/Pensieve#claude-plugin
claude plugin install pensieve@kingkongshot-marketplace --scope project
```

说明：

- plugin 只提供 hooks，不携带 skill 内容
- hooks 和 skill 生命周期解耦：plugin 用 marketplace 更新，skill 用 git 更新
- 如果你要 Claude hooks，仍然需要先完成方式 A 的 skill clone

## 初始化后验证

```bash
bash .src/scripts/run-doctor.sh --strict
```

PASS 条件：

- `.src/` 存在
- `agents/` 存在
- 根目录 `SKILL.md` 已生成
- `maxims/decisions/knowledge/pipelines/loop` 目录齐全
- 项目根目录生成 `.state/`
- 默认 pipeline 与 taste-review knowledge 已种子化

## 更新

### 更新 main 分支 skill

```bash
cd .claude/skills/pensieve
git pull --ff-only
```

更新后固定顺序：

```bash
bash .src/scripts/run-doctor.sh --strict
```

如果 `doctor` 报结构迁移类问题，再执行：

```bash
bash .src/scripts/run-migrate.sh
bash .src/scripts/run-doctor.sh --strict
```

### 更新 claude-plugin 分支 hooks

```bash
claude plugin update pensieve
```

交互式等价命令：

```text
/plugin update pensieve
```

它只更新 hooks，不影响 main 分支 skill clone 里的用户数据。

## 重装

如果系统文件被你自己改乱了，最简单的重装方式是：

1. 备份本地用户数据目录：`maxims/`、`decisions/`、`knowledge/`、`pipelines/`、`loop/`
2. 删除旧的 skill checkout
3. 重新执行安装
4. 跑 `init`
5. 跑 `doctor`

如果只是正常升级，不要重装，直接 `git pull --ff-only`

## 卸载

删除已安装的 skill 根目录即可。

如果还要保留用户数据，先备份：

- `maxims/`
- `decisions/`
- `knowledge/`
- `pipelines/`
- `loop/`
- `.state/`（如果想保留体检报告、迁移备份、session marker）

## Claude 增量能力

如果额外安装了 `claude-plugin` 分支，还会多出：

- SessionStart marker 检查
- PreToolUse Explore/Plan prompt 注入
- PostToolUse 图谱与 auto memory 自动同步
- Claude 原生 `/plugin update` 生命周期

## 路由规则

- 问“怎么安装/重装 Pensieve”：
  先读本文件，再引导到 `init`
- 问“怎么更新 Pensieve”：
  先读本文件，再引导到 `upgrade`
- 问“怎么清理旧结构/旧 graph”：
  先读本文件，再引导到 `migrate`
- 问“安装后怎么确认正常”：
  先读本文件，再引导到 `doctor`
