<div align="center">

# Pensieve

**项目级结构化记忆。Claude 走 plugin，Codex/Vercel 走 skill；权威内容只有一套。**

[![GitHub Stars](https://img.shields.io/github/stars/kingkongshot/Pensieve?color=ffcb47&labelColor=black&style=flat-square)](https://github.com/kingkongshot/Pensieve/stargazers)
[![License](https://img.shields.io/badge/license-MIT-white?labelColor=black&style=flat-square)](LICENSE)

[English README](https://github.com/kingkongshot/Pensieve/blob/experimental/README.md)

</div>

## 问题

Agent 每次对话天然都接近一张白纸。

它不记得你的项目规范，不知道上次为什么选了方案 A，也不会把失败和修复沉淀成下次能直接复用的知识。同样的坑，你会一遍又一遍地踩。

Pensieve 的目标不是再给你一份提示词，而是给 agent 一套持续生长的项目记忆：规范、决策、知识、流程，随着日常开发不断积累。用得越久，它越懂你的项目。

## 没有 Pensieve vs 有了 Pensieve

| 没有 | 有了 |
|---|---|
| 每次都要重新解释项目规范 | 规范沉淀为 maxim，后续直接复用 |
| 复杂任务做到一半失控 | loop 把任务拆开，隔离执行，逐个收口 |
| 代码审查全靠当时感觉 | 审查标准固化为 pipeline + knowledge |
| 上周踩的坑这周又踩 | 经验沉淀为 decision / knowledge，下次直接跳过 |
| 三个月后忘了为什么选这个方案 | 决策记录带上下文、边界和适用条件 |

## 用了之后会怎样

**第一天**：安装、初始化，生成项目级用户数据根和首份路由 SKILL，种子化默认 maxim、pipeline、taste-review knowledge。

**第一周**：开始用 `loop` 跑复杂任务，用 `doctor` 复检结构，用 `self-improve` 把有价值的经验沉淀下来。

**第一个月**：项目里已经积累起自己的规范、决策、知识和流程。Claude plugin 模式下，hooks 会继续自动同步图谱和 auto memory。

**之后**：它不再只是“会聊天的 agent”，而是越来越像一份活的项目手册。

## 30 秒开始

### Claude Code 插件模式（推荐）

通过 marketplace 远程安装，**无需 clone 仓库**：

```bash
claude plugin marketplace add kingkongshot/Pensieve/tree/experimental
claude plugin install pensieve@kingkongshot-marketplace --scope project
```

本地开发直接加载（仅开发调试用）：

```bash
claude --plugin-dir /path/to/Pensieve
```

然后直接对 Claude 说：

> 帮我初始化 pensieve

### 通用 skill 模式

给 Codex、Vercel skills 或其他兼容 agent，远程安装，**无需 clone 仓库**：

```bash
npx skills add kingkongshot/Pensieve/skills/pensieve --branch experimental --copy
```

> **注意**：路径格式是 `<owner>/<repo>/skills/pensieve`，不要使用 GitHub URL 风格的 `tree/<branch>/` 前缀，分支通过 `--branch` 参数指定。

本地调试也可以直接装 skill 子目录：

```bash
npx skills add /path/to/Pensieve/skills/pensieve -a codex --copy
```

然后直接对 agent 说：

> 帮我初始化 pensieve

完整的安装、更新、卸载说明见 [skill-lifecycle.md](skills/pensieve/.src/references/skill-lifecycle.md)。

## 内置六个工具

同一份权威 skill 提供六个工具，不因为安装方式分叉：

- `init`
- `upgrade`
- `migrate`
- `doctor`
- `self-improve`
- `loop`

### `init` — 初始化项目记忆骨架

创建用户数据目录，种子化默认 maxim、pipeline 与 taste-review knowledge，生成项目级 `SKILL.md` 路由和首份图谱。它是 bootstrap，不是大而全的“自动分析一切”。

> “帮我初始化 pensieve”

### `loop` — 复杂任务拆解与循环执行

把一个复杂需求拆成多个可验证任务，主窗口调度，子代理隔离执行。适合跨文件、多阶段、需要反复验证的工作；小任务别硬上 loop。

> “用 loop 完成这个需求”

### `self-improve` — 沉淀经验

从对话、diff、执行结果里提取洞察，按语义写入 `maxim / decision / knowledge / pipeline`，并更新项目图谱。

> “把这次经验沉淀一下”

### `doctor` — 结构体检

只读扫描用户数据根，检查 frontmatter、目录结构、关键种子文件、链接与 auto memory 对齐，输出固定格式报告。默认不改你的业务代码。

> “检查一下数据有没有问题”

### `upgrade` — 系统升级

只做版本层动作：在 skill 模式下走 `npx skills update` / `git pull`，在 Claude plugin 模式下优先走 `claude plugin update pensieve`。不负责结构迁移。

> “升级 pensieve”

### `migrate` — 结构迁移与残留清理

只做用户数据层动作：清理旧路径、对齐关键种子文件、删除历史 graph 残留。完成后再跑 doctor。

> “迁移 pensieve 历史数据”

## 四层知识模型

Pensieve 把项目知识分成四层，每层回答不同的问题：

| 层 | 类型 | 回答什么 | 例子 |
|---|---|---|---|
| **MUST** | maxim | 什么绝对不能违反？ | “状态变更必须是原子的” |
| **WANT** | decision | 为什么选了这个方案？ | “选 JWT 不选 session，因为…” |
| **HOW** | pipeline | 这个流程应该怎么跑？ | “review 时按这个顺序检查” |
| **IS** | knowledge | 当前事实是什么？ | “这个模块的并发模型是…” |

层与层之间通过 `[[基于]]` `[[导致]]` `[[相关]]` 语义链接形成图谱。

## 自增强闭环

Pensieve 的价值不是手工维护文档，而是让日常开发持续喂养知识库：

```text
开发（loop）──→ 提交 / 修改 ──→ 审查（pipeline）
     ↑                                  │
     │         ← 经验沉淀与图谱更新 ←     │
     └──── maxim / decision / knowledge / pipeline
```

- Claude plugin 模式下：SessionStart、PreToolUse、PostToolUse hooks 自动接线
- 通用 skill 模式下：同一套知识和工具仍可用，只是少了 Claude 专属自动化
- 不管哪种安装方式，最后读写的仍是同一套 Pensieve 数据模型

<details>
<summary><b>架构细节</b></summary>

### 一个仓库，两种安装方式

- `skills/pensieve/`：唯一权威 skill 源
- `.claude-plugin/` + `hooks/` + `hooks-handlers/`：Claude 专属薄壳
- `skills/pensieve/.src/`：系统规则、脚本、模板
- `skills/pensieve/maxims|decisions|knowledge|pipelines|loop/`：skill 模式下的用户数据根
- `<project>/.claude/skills/pensieve/`：Claude plugin 模式下的用户数据根
- `<project>/.state/`：运行时状态、报告、marker、缓存

一句话：

**Claude 和 Codex 可以装得不一样，但它们读的是同一份 `skills/pensieve/`。**

### 设计原则

- **单一事实源**：规则、脚本、模板只在 `skills/pensieve/` 维护一份
- **系统与用户数据分离**：更新 plugin 或 skill，不覆盖用户沉淀
- **增量只放安装壳上**：Claude plugin 多的是 hooks 自动化，不是第二套知识
- **运行时状态单独隐藏**：`.state/` 只放报告、marker、缓存，不污染知识数据

```text
repo-root/
├── .claude-plugin/
├── hooks/
├── hooks-handlers/
├── skills/
│   └── pensieve/
│       ├── SKILL.md
│       ├── agents/
│       │   └── openai.yaml
│       ├── .src/
│       ├── maxims/
│       ├── decisions/
│       ├── knowledge/
│       ├── pipelines/
│       └── loop/
└── README.md
```

仓库根不再充当 skill 根。  
根目录是 **plugin/package 根**；真正的 skill 根是 `skills/pensieve/`。

</details>

## 如果你在找 Linus 引导词

那套味道还在，只是现在不再是一段孤立提示词。

它已经被拆成：

- 默认 maxim
- 审查 knowledge
- review / commit pipeline
- 可执行脚本和结构体检

拿到的是工程能力，不是一次性 prompt。

## 许可证

MIT
