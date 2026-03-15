---
id: architecture-v2
type: spec
title: "架构 v2：用户级系统 + 项目级数据"
status: draft
created: 2026-03-10
tags: [architecture, refactor, v2]
---

# 架构 v2：用户级系统 + 项目级数据

## 1. 问题陈述

### 1.1 系统代码按项目重复安装

每个项目都要 `git clone` 一份完整的 `.src/`、`agents/`、模板和参考文档到 `<project>/.claude/skills/pensieve/`。十个项目 = 十份相同的副本。更新时需要逐个进入每个项目的 skill 目录执行 `git pull`。

### 1.2 用户数据与系统代码物理混合

用户数据目录（`maxims/`、`decisions/`、`knowledge/`、`pipelines/`）位于 git clone 目录内部，仅靠 `.gitignore` 隔离。它们与 `.git/`、`.src/` 及其他受跟踪文件物理上共处一室。一次 `git clean -fd` 就会摧毁全部用户数据。这是"不跟踪"而非"真正隔离"。

### 1.3 双轨安装

安装 Pensieve 需要从两个不同分支执行两个独立步骤：

1. `git clone -b main` → skill 代码
2. `claude plugin marketplace add` + `claude plugin install` → hooks（claude-plugin 分支）

更新也分两条路径：skill 用 `git pull`，hooks 用 `claude plugin update`。用户必须理解"同一个仓库的两个分支是两个独立的安装单元"——这不是自然的心智模型。

### 1.4 用户数据困在 `.claude/` 内

`<project>/.claude/skills/pensieve/maxims/` 处的用户数据按惯例对版本控制不可见（`.claude/` 通常被 gitignore）。如果用户想提交他们的工程记忆——他们应该这样做——要么取消 ignore 整个 `.claude/`（暴露其他 Claude 配置），要么编写复杂的 ignore 规则。数据路径也绑定了特定客户端（`.claude/`），与知识本身的工具无关性相矛盾。

### 1.5 SKILL.md 同时承担静态和动态职责

生成的 `SKILL.md` 包含：

- **静态部分**：frontmatter（name、description）、路由表、工具描述——所有项目完全相同
- **动态部分**：项目路径、生命周期状态、知识图谱——每个项目不同

当系统代码全局共享时，单个 SKILL.md 无法同时承担两种角色。

---

## 2. 目标架构

### 2.1 目录布局

```
~/.claude/skills/pensieve/          # 用户级（全局唯一安装）
├── SKILL.md                        #   静态：frontmatter + 路由（skill 发现入口）
├── .src/                           #   系统代码、模板、参考文档、核心引擎
│   ├── core/
│   ├── scripts/                    #   执行脚本 + hook 脚本（run-hook.sh 调度）
│   ├── templates/
│   ├── references/
│   └── tools/
└── agents/                         #   代理配置

<project>/.pensieve/                # 项目级（每项目独立，纳入版本控制）
├── maxims/                         #   工程准则
├── decisions/                      #   架构决策
├── knowledge/                      #   缓存的探索结果
├── pipelines/                      #   可复用工作流
├── state.md                        #   动态：生命周期状态 + 知识图谱
└── .state/                         #   运行时产物（gitignored）
```

### 2.2 关键设计决策

**SKILL.md 留在用户级，变为静态。**

Claude Code 通过扫描 `~/.claude/skills/*/SKILL.md`（用户级）和 `<project>/.claude/skills/*/SKILL.md`（项目级）发现 skill。没有 SKILL.md 就不是 skill。系统代码在用户级，SKILL.md 也必须在那里。

每个项目的动态状态（生命周期事件、图谱）移至 `<project>/.pensieve/state.md`。静态 SKILL.md 指示 Claude 读取项目级状态文件获取上下文。

**用户数据放在 `<project>/.pensieve/`，而非 `<project>/.claude/pensieve/`。**

理由：

1. **版本控制**：`.pensieve/` 天然可提交。`.claude/` 按惯例被 gitignore。
2. **工具无关**：`.pensieve/` 不绑定任何 AI 客户端。知识模型是通用的。
3. **可发现性**：团队成员在项目根目录一眼就能看到 `.pensieve/`，无需深层嵌套。
4. **先例**：`lib.sh` 已处理多种客户端路径（`.claude/`、`.agents/`、`.codex/`、`.cursor/`）。专用的 `.pensieve/` 目录统一取代它们作为用户数据位置。

**Hooks 合入主分支，全局安装一次。**

`claude-plugin` 分支被淘汰。Hook 脚本位于 `~/.claude/skills/pensieve/.src/scripts/`，与其他执行脚本共存（由 `run-hook.sh` 统一调度）。Hook 配置写入用户级 `~/.claude/settings.json`，安装一次全局生效，不需要每个项目单独配置。所有 hook 脚本均已实现优雅降级——项目未初始化 Pensieve 时静默退出（`exit 0`），对无关项目零影响。

**`.state/` 移入 `.pensieve/` 内部。**

运行时产物（报告、标记、图谱快照、迁移备份）从 `<project>/.state/` 移至 `<project>/.pensieve/.state/`。Pensieve 相关的项目文件全部归入一棵目录树。`.state/` 子目录通过 `.pensieve/.gitignore` 排除。

---

## 3. SKILL.md 拆分设计

### 3.1 静态 SKILL.md（用户级）

位置：`~/.claude/skills/pensieve/SKILL.md`

```markdown
---
name: pensieve
description: >-
  项目知识库和工作流路由器。
  knowledge/ 缓存已探索的文件位置、模块边界和调用链，可直接复用；
  decisions/maxims 是已确立的架构决策和编码标准，遵循而非重新讨论；
  pipelines 是可复用工作流。
  完成任务后使用 self-improve 捕获新洞察。
  提供 init、upgrade、migrate、doctor、self-improve 五个工具。
---

# Pensieve

将用户请求路由到正确的工具。不确定时先确认。

## Routing
- Init: 初始化当前项目用户数据目录并填充种子文件。工具规格：`.src/tools/init.md`。
- Upgrade: 刷新全局 git clone 中的 Pensieve skill 源代码。工具规格：`.src/tools/upgrade.md`。
- Migrate: 结构迁移和遗留清理。工具规格：`.src/tools/migrate.md`。
- Doctor: 只读扫描当前项目用户数据目录。工具规格：`.src/tools/doctor.md`。
- Self-Improve: 提取可复用结论并写入用户数据。工具规格：`.src/tools/self-improve.md`。
- Graph View: 读取 `<project-root>/.pensieve/state.md` 的 `## Graph` 部分。

## Project Data
项目级用户数据存储在 `<project-root>/.pensieve/`。
当前项目的生命周期状态和知识图谱见 `.pensieve/state.md`。
```

此文件**由 git 跟踪**（不 gitignore），仅通过 `git pull` 更新。它是 skill 的接口声明，由 skill 维护者编写，用户不应修改。init 脚本不再生成它。

### 3.2 动态 state.md（项目级）

位置：`<project>/.pensieve/state.md`

```markdown
# Pensieve 项目状态

## Lifecycle State
- Last Event: install/init
- Last Note: seeded project data via init-project-data.sh

## Project Paths
- Project Root: `/path/to/project`
- User Data: `.pensieve/`
- Runtime State: `.pensieve/.state/`

## Graph

（知识图谱内容）
```

此文件由 `maintain-project-state.sh`（原 `maintain-project-skill.sh`）生成/更新。用户可选择是否纳入版本控制。

---

## 4. 路径解析变更

### 4.1 lib.sh 核心变更

```bash
# 改前：user data root == skill root
user_data_root() {
    if [[ -n "${PENSIEVE_DATA_ROOT:-}" ]]; then
        to_posix_path "$PENSIEVE_DATA_ROOT"
        return 0
    fi
    skill_root "${1:-$(pwd)}"
}

# 改后：user data root == project root / .pensieve
user_data_root() {
    if [[ -n "${PENSIEVE_DATA_ROOT:-}" ]]; then
        to_posix_path "$PENSIEVE_DATA_ROOT"
        return 0
    fi
    echo "$(project_root "${1:-$(pwd)}")/.pensieve"
}
```

```bash
# 改前：state root == project root / .state
state_root() {
    # ...
    echo "$pr/.state"
}

# 改后：state root == project root / .pensieve / .state
# 注意：当 project_root() 失败时应传播错误而非静默产生坏路径。
state_root() {
    if [[ -n "${PENSIEVE_STATE_ROOT:-}" ]]; then
        # （环境变量覆盖逻辑不变）
    fi
    local pr
    pr="$(project_root "${1:-$(pwd)}")" || return 1
    echo "$pr/.pensieve/.state"
}
```

```bash
# 改前：SKILL.md 位于 user_data_root
project_skill_file() {
    local dr
    dr="$(user_data_root "${1:-$(pwd)}")"
    echo "$dr/SKILL.md"
}

# 改后：项目状态文件位于 user_data_root；SKILL.md 位于 skill_root
project_state_file() {
    local dr
    dr="$(user_data_root "${1:-$(pwd)}")"
    echo "$dr/state.md"
}

skill_md_file() {
    local sr
    sr="$(skill_root "${1:-$(pwd)}")"
    echo "$sr/SKILL.md"
}
```

v1 的 `project_skill_file()` 别名已移除——它将 SKILL.md 语义映射到 state.md，格式完全不同，会静默误导调用方。v2 中使用 `skill_md_file()` 获取 SKILL.md，使用 `project_state_file()` 获取 state.md。

### 4.2 project_root() 简化

用户数据在 `<project>/.pensieve/` 后，`project_root()` 函数不再需要剥离客户端特定的 skill 路径（`.claude/skills/*`、`.agents/skills/*` 等）。skill root 始终是 `~/.claude/skills/pensieve/`，project root 通过 `$CLAUDE_PROJECT_DIR`、`git rev-parse --show-toplevel` 或 `pwd` 发现。

`lib.sh` 中 `project_root()` 函数的 legacy case 分支（客户端路径剥离逻辑）变为遗留代码，过渡期后可移除。

---

## 5. 安装和生命周期变更

### 5.1 安装（新）

```bash
# 一步：全局安装系统代码（中文用户用 zh 分支，英文用户用 main 分支）
git clone -b zh https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve

# 一步：安装全局 hooks（仅首次）
# init 脚本自动将 hook 配置写入 ~/.claude/settings.json
bash ~/.claude/skills/pensieve/.src/scripts/install-hooks.sh

# 每个项目：初始化用户数据
cd <your-project>
bash ~/.claude/skills/pensieve/.src/scripts/init-project-data.sh
```

无需单独安装插件。无需 marketplace。无需每个项目配置 hooks。

### 5.2 更新（新）

```bash
# 更新系统代码（一次操作，所有项目生效）
cd ~/.claude/skills/pensieve
git pull --ff-only

# 每个项目健康检查（可选但推荐）
cd <your-project>
bash ~/.claude/skills/pensieve/.src/scripts/run-doctor.sh --strict
```

### 5.3 Hooks 安装

Hooks 是系统代码的一部分，安装到用户级 `~/.claude/settings.json`，一次安装全局生效。

```json
{
  "hooks": {
    "SessionStart": [...],
    "PreToolUse": [...],
    "PostToolUse": [...]
  }
}
```

hook 脚本通过 `$HOME/.claude/skills/pensieve/.src/scripts/` 定位，无需项目级配置。每个 hook 在执行前检查当前项目是否有 `.pensieve/` 目录，没有则 `exit 0`，确保对未使用 Pensieve 的项目零干扰。

`run-hook.sh` 中的 `SKILL_ROOT` 默认值相应变更：

```bash
# 改前（项目级）
SKILL_ROOT="$(to_posix_path "${PENSIEVE_SKILL_ROOT:-$PROJECT_ROOT/.claude/skills/pensieve}")"

# 改后（用户级）
SKILL_ROOT="$(to_posix_path "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}")"
```

### 5.4 卸载

```bash
# 移除全局 hooks（从 ~/.claude/settings.json 中删除 pensieve 相关 hook 条目）
# 移除系统代码
rm -rf ~/.claude/skills/pensieve

# 移除每个项目数据（可选，按项目操作）
rm -rf <project>/.pensieve
```

---

## 6. 迁移路径

### 6.1 迁移是一次性操作

v2 迁移设计为一次性操作：每个项目执行一次 `init` 即完成。系统代码不保留任何 v1 向后兼容负担——没有 legacy 路径检测、没有旧格式自动转换、没有双轨代码路径。

如果项目仍在使用 v1 布局，手动迁移步骤如下：

```bash
# 1. 将用户数据移出 skill 目录
mkdir -p .pensieve
for dir in maxims decisions knowledge pipelines; do
    if [[ -d .claude/skills/pensieve/$dir ]]; then
        mv .claude/skills/pensieve/$dir .pensieve/$dir
    fi
done

# 2. 移动运行时状态
if [[ -d .state ]]; then
    mv .state .pensieve/.state
fi

# 3. 删除旧的项目级 skill clone
rm -rf .claude/skills/pensieve

# 4. 全局安装（如果尚未安装）
if [[ ! -d ~/.claude/skills/pensieve ]]; then
    git clone -b zh https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve
fi

# 5. 重新初始化（生成 state.md，创建 .pensieve/.gitignore）
bash ~/.claude/skills/pensieve/.src/scripts/init-project-data.sh

# 6. 安装全局 hooks（如果尚未安装）
bash ~/.claude/skills/pensieve/.src/scripts/install-hooks.sh

# 7. 卸载旧插件（如有）
claude plugin uninstall pensieve 2>/dev/null || true
```

---

## 7. 兼容性说明

### 7.1 多客户端支持

skill root 位于 `~/.claude/skills/pensieve/` 是 Claude Code 特有的。其他客户端：

- Codex：`~/.codex/skills/pensieve/`（或符号链接）
- Cursor：`~/.cursor/skills/pensieve/`（或符号链接）

`<project>/.pensieve/` 处的用户数据与客户端无关——所有客户端读取相同的项目知识。

### 7.2 PENSIEVE_* 环境变量

所有现有环境变量覆盖（`PENSIEVE_SKILL_ROOT`、`PENSIEVE_DATA_ROOT`、`PENSIEVE_STATE_ROOT`、`PENSIEVE_PROJECT_ROOT`）继续有效。唯一的变化是未设置环境变量时的默认解析逻辑。

### 7.3 claude-plugin 分支

v2 发布后，`claude-plugin` 分支应归档（不删除），其 README 指向新的安装方式。运行 `claude plugin update pensieve` 的现有用户应看到弃用通知。

---

## 8. 语言分支策略

### 8.1 保留双语分支

仓库维持三个分支：

- **experimental**：开发分支
- **zh**（中文）：中文发布分支
- **main**（英文）：英文发布分支

开发流程：experimental 开发 → 确定后 merge 到 zh 和 main（main 分支的文本内容由 AI 翻译）。

```
experimental (开发) ──merge──> zh (中文发布)
                    ──merge + AI 翻译──> main (英文发布)
```

### 8.2 翻译范围

两个分支的差异**仅限文本内容**，代码逻辑完全一致。涉及翻译的文件类型：

| 文件类型 | 路径 | 读者 |
|----------|------|------|
| README | `README.md` | 人类用户 |
| 参考文档 | `.src/references/*.md` | LLM |
| 工具规格 | `.src/tools/*.md` | LLM |
| 种子模板 | `.src/templates/*.md` | LLM + 用户 |
| SKILL.md | `SKILL.md` | LLM（Claude Code skill 发现） |

### 8.3 v2 对分支策略的改善

v2 架构让双语分支的维护变得更干净：

1. **用户数据与分支无关**：用户数据在 `<project>/.pensieve/`，不在 git clone 目录内。用户用什么语言写数据完全自主，与安装的分支无关。
2. **翻译面收窄**：v1 中 SKILL.md 是动态生成的，每个项目都会生成一份，包含项目特定内容。v2 中 SKILL.md 是静态的，全局只有一份，翻译只需维护这一份。
3. **不会意外覆盖用户数据**：v1 中 `git pull` 在用户数据同目录执行，虽然 gitignore 保护了数据，但操作上有心理负担。v2 中 `git pull` 在 `~/.claude/skills/pensieve/` 执行，与项目数据完全物理隔离。

### 8.4 用户选择分支

安装时通过 `-b` 参数选择语言：

```bash
# 中文用户
git clone -b zh https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve

# 英文用户
git clone -b main https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve
```

切换语言：

```bash
cd ~/.claude/skills/pensieve
git checkout zh   # 或 main
git pull --ff-only
```

由于系统代码全局唯一、用户数据在项目级，切换语言不影响任何项目的用户数据。

---

## 9. 设计决策

### 9.1 SKILL.md 是受跟踪的只读文件

SKILL.md 是 skill 的接口声明——其 frontmatter description 控制 Claude 何时触发该 skill，路由表控制请求如何分发到工具。这些由 skill 维护者编写，不由用户配置。所有项目级动态内容（生命周期状态、知识图谱）已拆分到 `<project>/.pensieve/state.md`。

因此：SKILL.md 是**仓库中的受跟踪文件**，通过 `git pull` 与其他系统代码一起更新。init 脚本不再生成它。用户不应修改它。

### 9.2 Hooks 安装到用户级 `~/.claude/settings.json`

`claude-plugin` 分支和 marketplace 分发方式被淘汰。首次安装时将 hook 配置写入用户级 `~/.claude/settings.json`，一次安装全局生效，不需要每个项目单独配置。

理由：

1. **与 skill 一致**：skill 在用户级，hooks 也在用户级，心智模型统一。
2. **零配置新项目**：对新项目执行 `init` 只需初始化用户数据，无需再配 hooks。
3. **优雅降级**：所有 hook 脚本在项目未初始化 Pensieve 时静默退出（`exit 0`），对无关项目零影响。
   - `pensieve-session-marker.sh`：找不到 `.pensieve/` 目录时退出
   - `explore-prehook.sh`：检查项目 `state.md` 是否存在；缺失则退出（SKILL.md 是全局静态文件，无需检查）
   - `sync-project-skill-graph.sh`：编辑文件不在 `USER_DATA_ROOT` 下时退出
4. **卸载简单**：从 `~/.claude/settings.json` 删除 hook 条目 + 删 skill 目录即可。

### 9.3 不做版本锁定

YAGNI。Pensieve 是工程约定工具，不是编译器——其输出是 Markdown 文本和 shell 脚本，没有 API 兼容性表面。全局单版本安装、`git pull` 一次升级所有项目，这正是用户级安装的核心优势。如果发生破坏性变更，现有的 `schema_version` + `migrate` 机制处理。按项目锁版本会重新引入"每项目一份副本"——正是 v2 要解决的问题。

如果升级后出现问题，可通过 `git log` 查看历史、`git checkout <commit>` 回退到已知正常版本。这是 git 的原生能力，无需额外机制。

### 9.4 `.pensieve/.gitignore` 仅排除 `.state/`

用户数据（maxims、decisions、knowledge、pipelines）应被版本控制——这是将数据放在 `<project>/.pensieve/` 的核心动机。默认 `.gitignore` 仅排除 `.state/`（运行时产物：报告、标记、图谱快照）。不提供细粒度模板。有特殊需求的用户自行添加 ignore 规则。
