<div align="center">

# Pensieve

**给 AI agent 一套持续生长的项目记忆。**

[![GitHub Stars](https://img.shields.io/github/stars/kingkongshot/Pensieve?color=ffcb47&labelColor=black&style=flat-square)](https://github.com/kingkongshot/Pensieve/stargazers)
[![License](https://img.shields.io/badge/license-MIT-white?labelColor=black&style=flat-square)](LICENSE)

[English README](https://github.com/kingkongshot/Pensieve/blob/main/README.md)

</div>

## 没有 Pensieve vs 有 Pensieve

| 没有 | 有 |
|---|---|
| 每次都要重新解释项目规范 | 规范存为 maxim，自动加载 |
| 代码审查标准看心情 | 审查标准固化为可执行的 pipeline |
| 上周犯的错这周再犯一次 | 教训自动沉淀，下次直接跳过 |
| 三个月后忘了当初为什么这么设计 | decision 记录上下文和替代方案 |
| 每次都要重新翻文档定位模块边界 | knowledge 缓存探索结果，直接复用 |

## 从旧版本升级（< 1.0）

1.0 重构了安装架构。如果你当前版本低于 1.0，**不要用 `git pull`**，需要完整卸载后重装。

判断方法：如果你的 Pensieve 是通过 `claude plugin install` 安装的，或者找不到 `.claude/skills/pensieve/.src/manifest.json`，你就是旧版本。

用户数据（`maxims/`、`decisions/`、`knowledge/`、`pipelines/`）会保留，其余全部清理：

```bash
# 1. 卸载 Claude 插件和缓存
claude plugin uninstall pensieve 2>/dev/null
rm -rf ~/.claude/plugins/cache/kingkongshot-marketplace/pensieve

# 2. 清理 skill 目录（只保留用户数据）
cd .claude/skills/pensieve
rm -rf .src agents .git .gitignore SKILL.md LICENSE README.md .state .backup .obsidian temp resource

# 3. 清理其他可能的旧 skill 路径
rm -rf .agents/skills/pensieve

# 4. 重新安装
cd ../../..
git clone -b experimental https://github.com/kingkongshot/Pensieve.git /tmp/pensieve-new
cp -r /tmp/pensieve-new/{.git,.gitignore,.src,agents,LICENSE,README.md} .claude/skills/pensieve/
rm -rf /tmp/pensieve-new

# 5. 初始化 + 体检
bash .claude/skills/pensieve/.src/scripts/init-project-data.sh
bash .claude/skills/pensieve/.src/scripts/run-doctor.sh --strict
```

## 安装

```bash
# 1. 安装 skill
git clone -b experimental https://github.com/kingkongshot/Pensieve.git .claude/skills/pensieve

# 2. 初始化（创建用户数据目录，种子化默认内容，生成 SKILL.md 路由文件）
bash .claude/skills/pensieve/.src/scripts/init-project-data.sh

# 3. 安装 Claude hooks（Claude Code 用户必装，其他客户端跳过）
claude plugin marketplace add kingkongshot/Pensieve#claude-plugin
claude plugin install pensieve@kingkongshot-marketplace --scope project
```

Skill 和 hooks 的更新机制不同——skill 用 `git pull`，hooks 用 `claude plugin update`——所以它们放在两个分支里，各自独立升级，互不影响。

## 更新

```bash
cd .claude/skills/pensieve
git pull --ff-only
bash .src/scripts/run-doctor.sh --strict
```

`git pull` 只更新系统文件（`.src/`、`agents/`）。用户数据由 `.gitignore` 保护，不会被覆盖。**不要在更新前删除用户数据目录**——它们是你积累的项目记忆，删了就没了。

完整的安装、更新、重装、卸载说明见 [skill-lifecycle.md](.src/references/skill-lifecycle.md)。

## 自增强循环

你不需要手动维护知识库——日常开发自动喂养它：

```
    开发 ──→ 提交 ──→ 审查（pipeline）
     ↑                      │
     │   ← 自动沉淀经验 ←   │
     │                      ↓
     └── maxim / decision / knowledge / pipeline
```

- **提交时**：PostToolUse hook 自动触发经验提取
- **审查时**：按项目 pipeline 执行，结论回流为 knowledge
- **复盘时**：主动要求沉淀，洞察写入对应层

你只管写代码，知识库自己长。

## 四层知识模型

| 层 | 类型 | 回答什么 | 跨项目？ |
|---|---|---|---|
| **MUST** | maxim | 什么绝对不能违反？ | 是——换项目换语言都成立 |
| **WANT** | decision | 为什么选这个方案？ | 否——当前项目的主动取舍 |
| **HOW** | pipeline | 这个流程应该怎么跑？ | 视情况 |
| **IS** | knowledge | 当前事实是什么？ | 否——可验证的系统事实 |

层与层之间通过 `基于 / 导致 / 相关` 三类语义链接形成图谱。

详细规范见 `.src/references/` 下的 [maxims.md](.src/references/maxims.md)、[decisions.md](.src/references/decisions.md)、[knowledge.md](.src/references/knowledge.md)、[pipelines.md](.src/references/pipelines.md)。

## 五个工具

| 工具 | 做什么 | 触发示例 |
|---|---|---|
| `init` | 创建数据目录，种子化默认内容 | "帮我初始化 pensieve" |
| `upgrade` | 刷新 skill 源码 | "升级 pensieve" |
| `migrate` | 清理旧路径，对齐种子文件 | "清理旧结构" |
| `doctor` | 只读扫描，检查结构和格式 | "检查数据有没有问题" |
| `self-improve` | 从对话和 diff 中提取洞察，写入四层知识 | "把这次经验沉淀下来" |

工具边界与重定向规则见 [tool-boundaries.md](.src/references/tool-boundaries.md)。

<details>
<summary><b>架构细节</b></summary>

### 目录结构

```text
<project>/
├── .claude/skills/pensieve/   # git clone 的 skill 根目录
│   ├── .src/                  # 系统文件（tracked）
│   ├── agents/                # agent 配置（tracked）
│   ├── SKILL.md               # 路由文件（init 生成，gitignored）
│   ├── maxims/                # 用户数据（gitignored）
│   ├── decisions/             # 用户数据（gitignored）
│   ├── knowledge/             # 用户数据（gitignored）
│   └── pipelines/             # 用户数据（gitignored）
└── .state/                    # 运行时产物：报告、marker、图谱快照
```

`.src/manifest.json` 是 skill 根目录的锚点——脚本通过它定位所有路径。

### 设计原则

- **系统能力与用户数据分离** — 更新永远不覆盖你积累的项目知识
- **规则单一来源** — 目录、关键文件、旧路径统一由 `.src/core/schema.json` 定义
- **先确认再执行** — 范围不明确时先问，不自动启动长流程
- **先读规范再写数据** — 创建任何用户数据前先读 `.src/references/` 的格式规范

</details>

## 关于 Linus 引导词

Pensieve 最初以一段 Linus Torvalds 风格的引导词为人所知——用"良好的品味"、"不破坏用户态"、"偏执于简单"来约束 agent 的行为。

那套工程哲学仍然是 Pensieve 的内核，但不再是一段孤立的提示词。它现在分布在可执行的结构里：默认 maxim 定义硬规则，taste-review knowledge 提供审查标准，review / commit pipeline 把规则落到实际流程中。从一次性 prompt 变成了持续生效的工程能力。

## 许可证

MIT
