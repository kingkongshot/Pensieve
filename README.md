<div align="center">

# Pensieve

**Claude Code 的项目级结构化记忆。**

[![GitHub Stars](https://img.shields.io/github/stars/kingkongshot/Pensieve?color=ffcb47&labelColor=black&style=flat-square)](https://github.com/kingkongshot/Pensieve/stargazers)
[![License](https://img.shields.io/badge/license-MIT-white?labelColor=black&style=flat-square)](LICENSE)

[English README](https://github.com/kingkongshot/Pensieve/blob/main/README.md)

</div>

## 问题

Claude Code 每次对话都是一张白纸。

它不记得你的项目规范，不知道上次为什么选了方案 A，也不会从失败中学到教训。同样的坑，你会一遍又一遍地踩。

Pensieve 给 Claude Code 装上结构化记忆。每次 review、每次 commit、每次复杂任务，都在自动积累项目知识。**用得越久，它越懂你的项目。**

## 没有 Pensieve vs 有了 Pensieve

| 没有 | 有了 |
|---|---|
| 每次都要重新解释项目规范 | 规范存为 maxim，自动加载 |
| 复杂任务做到一半失控 | loop 自动拆解、隔离执行、逐个验收 |
| 代码审查标准全凭当时心情 | 审查标准固化为可执行 pipeline |
| 上周踩的坑这周又踩 | 经验自动沉淀，下次直接跳过 |
| 技术决策三个月后忘了为什么 | 决策记录附带上下文和探索缓解清单 |

## 用了之后会怎样

**第一天** — 安装 → 初始化 → 自动扫描项目热点模块 → 输出代码品味基线报告

**第一周** — 用 `loop` 完成复杂开发任务。Claude 按你的 maxim 拆解任务、子代理隔离执行、收尾时自动沉淀经验。

**第一个月** — 你的项目已经积累了自己的规范、技术决策记录、审查流程和参考知识。每次 commit 和 review 都在静默丰富这个知识库。

**之后** — Claude 越来越懂你的项目。新人加入时，Pensieve 就是活的项目手册。

## 30 秒开始

```bash
# 1. 添加市场源
claude plugin marketplace add kingkongshot/Pensieve#main

# 2. 安装
claude plugin install pensieve@kingkongshot-marketplace --scope user

# 3. 重启 Claude Code，然后说：
```

> 帮我初始化 pensieve

就这样。之后说 **"用 loop 完成开发"** 开始第一个任务。

[安装指南](docs/installation.md) · [更新指南](docs/update.md) · [卸载](docs/installation.md#卸载)

## 内置六个工具

安装即可用，不需要额外配置。说人话就能触发。

### `init` — 初始化项目

扫描你的 git 历史，识别热点模块，跑一轮代码品味基线分析。创建项目级知识目录（maxims / decisions / knowledge / pipelines），种子化默认的审查和提交 pipeline。**只分析不写入**，你决定哪些发现值得保留。
完成后必须跑一次 `doctor` 做结构与格式复检。

> "帮我初始化 pensieve"

### `loop` — 复杂任务拆解与循环执行

把一个大需求拆成多个子任务，先确认范围再动手。主窗口调度，子代理隔离执行每个任务，互不污染上下文。收尾时自动询问是否沉淀本轮经验。小任务不开 loop，直接完成。

> "用 loop 完成这个需求"

### `self-improve` — 沉淀经验

从对话、diff、loop 执行中提取洞察，分类为 maxim（硬规则）、decision（技术决策）、knowledge（参考事实）或 pipeline（可执行流程），写入对应位置并更新知识图谱。commit 时也会自动触发。

> "这次的经验沉淀一下"

### `doctor` — 体检

只读扫描全部用户数据：frontmatter 格式、语义链接完整性、目录结构合规性。输出固定格式的 PASS / PASS_WITH_WARNINGS / FAIL 报告和三步行动计划。默认不改用户数据文件，仅自动维护 `SKILL.md` 与 Claude auto memory（`~/.claude/projects/<project>/memory/MEMORY.md`）的 Pensieve 引导块。

> "检查一下数据有没有问题"

### `upgrade` — 版本升级

只做版本层动作：版本比对、拉取最新、插件键对齐与旧插件名清理。不做目录迁移和内容修复。升级完成后引导你手动跑 doctor 复检。

> "升级 pensieve"

### `migrate` — 结构迁移与残留清理

只做用户数据结构动作：旧目录迁移、关键种子文件对齐、旧 graph/README 残留清理。不做版本更新，不输出 PASS/FAIL。完成后引导手动跑 doctor 复检。

> "迁移 pensieve 历史数据"

## 四层知识模型

Pensieve 把项目知识分成四层，每层解决不同的问题：

| 层 | 类型 | 回答什么 | 例子 |
|---|---|---|---|
| **MUST** | maxim | 什么绝对不能违反？ | "状态变更必须是原子的" |
| **WANT** | decision | 为什么选了这个方案？ | "选 JWT 不选 session，因为…" |
| **HOW** | pipeline | 怎么执行这个流程？ | "review 时按这个顺序检查" |
| **IS** | knowledge | 事实是什么？ | "这个模块的并发模型是…" |

层与层之间通过 `[[基于]]` `[[导致]]` `[[相关]]` 语义链接形成知识图谱。

## 自增强闭环

这是 Pensieve 的核心机制 —— 不是你手动维护知识库，而是**日常开发过程自动喂养它**：

```
    开发（loop）──→ 提交 ──→ 审查（pipeline）
         ↑                        │
         │    ← 自动沉淀经验 ←    │
         │                        ↓
         └── maxim / decision / knowledge / pipeline
```

- **commit 时**：PostToolUse hook 自动触发经验提取
- **review 时**：按项目 pipeline 执行，结论回流为知识
- **loop 收尾时**：主动询问是否沉淀本轮经验

你只管写代码，知识库自己生长。

<details>
<summary><b>架构细节</b>（给好奇的人）</summary>

### 绑定 Claude Code 原生能力

| 机制 | 用途 |
|---|---|
| **Skills** | 路由意图到对应工具，不猜测不自动执行 |
| **Hooks** | PostToolUse 编辑文件后立即同步知识图谱 |
| **Task** | Claude 原生任务系统驱动 loop 节奏 |
| **Agent** | 主窗口调度，子代理隔离执行单个任务 |

复用原生能力意味着：不额外封装，Claude Code 升级时 Pensieve 同步受益。

### 设计原则

- **系统能力与用户数据分离** — 插件更新不覆盖你积累的项目知识
- **规则单一事实源** — 目录/关键文件/旧路径/插件键统一由 `tools/core/schema.json` 定义
- **确认再执行** — 范围不明确时先确认，不自动开跑
- **先读后写** — 创建任何用户数据前先读格式规范
- **置信度要求** — pipeline 输出 ≥80% 置信度才报告，不输出猜测

### 目录结构

```
.claude/skills/pensieve/          ← 你的项目知识（用户数据，不被插件覆盖）
├── maxims/                       ← 硬规则
├── decisions/                    ← 技术决策记录
├── knowledge/                    ← 参考知识
├── pipelines/                    ← 可执行流程
├── loop/                         ← 历次 loop 执行记录
└── SKILL.md                      ← 自动维护的路由 + 图谱
```

</details>

## 如果你在找 Linus 引导词

你熟悉的那套方法已经升级：Linus 风格准则现在是默认 maxim，审查能力以 pipeline + knowledge 形式落地。你拿到的不再是提示词，而是工程能力级封装 —— 提示词、流程和执行机制一起交付。

## 社区

<img src="./QRCode.png" alt="微信交流群二维码" width="200">

## 许可证

MIT
