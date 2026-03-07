<div align="center">

# Pensieve

**项目级结构化记忆。`main` 分支是 skill，`claude-plugin` 分支是 Claude hooks。**

[![GitHub Stars](https://img.shields.io/github/stars/kingkongshot/Pensieve?color=ffcb47&labelColor=black&style=flat-square)](https://github.com/kingkongshot/Pensieve/stargazers)
[![License](https://img.shields.io/badge/license-MIT-white?labelColor=black&style=flat-square)](LICENSE)

[English README](https://github.com/kingkongshot/Pensieve/blob/main/README.md)

</div>

## 问题

Agent 每次对话天然都接近一张白纸。

它不记得你的项目规范，不知道上次为什么选了方案 A，也不会把失败和修复沉淀成下次能直接复用的知识。同样的坑，你会一遍又一遍地踩。

Pensieve 的目标不是再给你一份提示词，而是给 agent 一套持续生长的项目记忆：规范、决策、知识、流程，随着日常开发不断积累。用得越久，它越懂你的项目。

## 30 秒开始

### 1. 安装 Claude hooks 插件

```bash
claude plugin marketplace add kingkongshot/Pensieve#claude-plugin
claude plugin install pensieve@kingkongshot-marketplace --scope project
```

### 2. 安装 skill

```bash
git clone -b experimental https://github.com/kingkongshot/Pensieve.git .claude/skills/pensieve
```

> **已有用户数据？** 如果 `.claude/skills/pensieve/` 已存在（里面有 `decisions/`、`knowledge/` 等），**不要删除它**。clone 到临时位置，把系统文件搬进去即可：
>
> ```bash
> git clone -b experimental https://github.com/kingkongshot/Pensieve.git /tmp/pensieve-skill
> cp -r /tmp/pensieve-skill/{.git,.gitignore,.src,agents,SKILL.md,LICENSE,README.md} .claude/skills/pensieve/
> rm -rf /tmp/pensieve-skill
> ```

### 3. 初始化

```bash
bash .claude/skills/pensieve/.src/scripts/init-project-data.sh
```

或者直接对 Claude 说：

> 帮我初始化 pensieve

### 更新

```bash
cd .claude/skills/pensieve
git pull --ff-only
bash .src/scripts/run-doctor.sh --strict
```

> **铁律：任何操作都不应删除用户数据。** `git pull` 只更新系统文件，用户数据由 `.gitignore` 保护。更新后跑一次 `doctor` 确认数据完整即可。

完整的安装、更新、卸载说明见 [.src/references/skill-lifecycle.md](.src/references/skill-lifecycle.md)。

## 这次重构解决了什么

旧方案依赖 `npx skills add --copy`。更新时它会整目录覆盖，用户积累的 `decisions/knowledge/maxims/pipelines` 很容易被抹掉。

现在结构变成：

- `main` 分支：skill 根目录，用户直接 `git clone`
- `claude-plugin` 分支：只放 Claude hooks，通过 marketplace 安装
- `SKILL.md`：git tracked 的静态版本，init 后由 `maintain-project-skill.sh` 在本地覆盖更新
- 用户数据目录由根 `.gitignore` 忽略，不参与系统更新
- `git pull` 只更新 tracked 系统文件（`.src/`、`agents/`、`SKILL.md`），用户数据不受影响
- 运行期产物单独放在 `<project>/.state/`

## 内置五个工具

同一份权威 skill 提供五个工具：

- `init`
- `upgrade`
- `migrate`
- `doctor`
- `self-improve`

### `init`

创建用户数据目录，种子化默认 maxim、pipeline 与 taste-review knowledge。

### `upgrade`

刷新当前 git clone 的 Pensieve skill 源码，只做版本层动作。

### `migrate`

清理旧路径、对齐关键种子文件、删除历史残留。

### `doctor`

只读扫描用户数据根，检查 frontmatter、目录结构、关键种子文件、链接与 auto memory 对齐情况。

### `self-improve`

从对话、diff、执行结果里提取洞察，按语义写入 `maxim / decision / knowledge / pipeline`。

## 四层知识模型

Pensieve 把项目知识分成四层：

| 层 | 类型 | 回答什么 |
|---|---|---|
| **MUST** | maxim | 什么绝对不能违反？ |
| **WANT** | decision | 为什么选这个方案？ |
| **HOW** | pipeline | 这个流程应该怎么跑？ |
| **IS** | knowledge | 当前事实是什么？ |

层与层之间通过 `基于 / 导致 / 相关` 这三类语义链接形成图谱。

## 架构

### 分支职责

| 分支 | 内容 | 安装方式 |
|---|---|---|
| `main` | `SKILL.md`、`.src/`、`agents/` | `git clone` |
| `claude-plugin` | `.claude-plugin/`、`hooks/`、`hooks-handlers/` | `claude plugin marketplace add` |

### 目录布局

```text
<project>/
├── .claude/
│   └── skills/
│       └── pensieve/
│           ├── SKILL.md      # tracked, updated locally by init
│           ├── .src/
│           ├── agents/
│           ├── maxims/      # local only, gitignored
│           ├── decisions/   # local only, gitignored
│           ├── knowledge/   # local only, gitignored
│           └── pipelines/   # local only, gitignored
└── .state/                  # reports, markers, graph snapshots
```

一句话：

**plugin 和 skill 生命周期分离，但它们读写的是同一套 Pensieve 数据。**

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
