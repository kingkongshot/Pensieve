# 安装指南

Pensieve 使用**官方插件结构**：

- **插件（系统能力）**：skills + hooks（默认启用 graph 自动同步），仅通过插件升级更新
- **项目用户数据**：`.claude/skills/pensieve/`，永不被插件覆盖

## 快速安装

### 1.（推荐）通过 Marketplace 安装并固定到 `main`

这样可以按分支或标签安装（例如 `main`）。

添加 marketplace（固定 `main`）：

```bash
claude plugin marketplace add kingkongshot/Pensieve#main
```

安装插件（用户级）：

```bash
claude plugin install pensieve@kingkongshot-marketplace --scope user
```

> `kingkongshot-marketplace` 来自 `.claude-plugin/marketplace.json` 的 `name` 字段。

如果你希望在团队仓库共享，可按项目级安装：

```bash
claude plugin install pensieve@kingkongshot-marketplace --scope project
```

### 2. 配置 `CLAUDE.md`（推荐）

> **给 LLM 的指令**：如果你是执行安装的 agent，请**创建或更新**该文件。保持简洁，不覆盖已有内容。

在项目根目录添加（仅 `CLAUDE.md`）：

```markdown
## Pensieve

先探索项目，再决定是否使用 Pensieve 工具。

当用户需要结构化工作流时：
- Upgrade 仅用于版本更新与插件键对齐（按需）
- Migrate 仅用于旧数据迁移与残留清理（按需）
- 使用 Init 工具初始化项目级用户数据，并生成首轮探索与品味基线（新项目首次接入）
- 使用 Loop 工具进行拆解 + 自动循环执行
- 查看图谱时直接读取项目级 `SKILL.md` 的 `## Graph`

当用户要求改进 Pensieve（pipelines/scripts/rules/behavior）时，
必须使用 Self-Improve 工具：
`tools/self-improve/_self-improve.md`
```

### 3. 初始化项目用户数据（推荐）

项目用户数据位于 `.claude/skills/pensieve/`（插件升级不会覆盖）。

> 必须顺序：**安装插件后先初始化，再重启 Claude Code**。  
> 未初始化就重启，AI 可能不知道项目内置准则与默认审查 pipeline 已经可用。

方式 A：

```bash
mkdir -p .claude/skills/pensieve/{maxims,decisions,knowledge,pipelines,loop}
```

方式 B（推荐）：运行初始化脚本（会种子化**初始 maxims + 审查 pipeline + 审查 knowledge**，不会覆盖已有文件）：

```bash
<SYSTEM_SKILL_ROOT>/tools/loop/scripts/init-project-data.sh
```

> `<SYSTEM_SKILL_ROOT>` 可由 `CLAUDE_PLUGIN_ROOT` 推导：`$CLAUDE_PLUGIN_ROOT/skills/pensieve`。
> 初始化脚本会自动维护项目级 `SKILL.md`：写入固定路由 + 最新 graph（自动生成，请勿手改）。
> 同时会自动维护 Claude auto memory：`~/.claude/projects/<project>/memory/MEMORY.md` 的 Pensieve 引导块（描述与系统 skill `description` 对齐，并引导优先使用 `pensieve` skill）。
> 说明：脚本只负责"目录 + 种子 + SKILL 同步"。新增的"提交记录/代码探索 + review pipeline 品味分析"由 Init 工具执行，不在脚本内自动运行。

### 4. 重启 Claude Code

初始化完成后再重启 Claude Code，然后直接说“用 loop 完成一个小任务”验证安装。

---

## 历史迁移

如果你之前把系统内容复制到了项目里（例如 `skills/pensieve/`），请使用 Migrate 工具做迁移和清理：

- 合并项目级 maxims
- 对齐关键模块与文件位置（含 `run-when-*.md`、`knowledge/taste-review/content.md`）
- 关键文件内容不一致时执行替换（先备份）
- 移除历史系统副本与旧目录（README 与 `_*.md` 以及 deprecated 路径）

---

## 用户级安装

如果你希望对所有项目生效，使用用户级安装：

```bash
claude plugin install pensieve@kingkongshot-marketplace --scope user
```

---

## 给 LLM Agent 的说明

如果你是 LLM agent：
1. 安装插件
2. 初始化 `.claude/skills/pensieve/`
3. 基于提交记录与代码做一次探索，并用 review pipeline 产出首轮品味分析
4. 重启 Claude Code（不要跳过）
5. **告诉用户只需表达几个基础意图**：
   - 升级版本（Upgrade）
   - 迁移结构（Migrate）
   - 初始化（Init）
   - 拆解执行（Loop）
   - 体检（Doctor，初始化后必跑；升级后必跑）
   - 沉淀（Self-Improve）
   - 看图谱（直接读项目级 `SKILL.md` 的 `## Graph`）

说明保持简短，目标是降低用户认知负担。

---

## 更新

参见 **[更新指南](update.md)**。

---

## 卸载

1. 卸载插件：`claude plugin uninstall pensieve@kingkongshot-marketplace --scope user`（或使用 `/plugin`）
2. （可选）删除项目数据前先询问用户是否需要备份：`rm -rf .claude/skills/pensieve`

---

## 验证安装

安装后：

1. 先执行 Init 工具（或等价脚本：`<SYSTEM_SKILL_ROOT>/tools/loop/scripts/init-project-data.sh`）
2. 确认种子文件存在：
   - `.claude/skills/pensieve/maxims/*.md` 至少 1 个
   - `.claude/skills/pensieve/pipelines/run-when-reviewing-code.md`
   - `.claude/skills/pensieve/pipelines/run-when-committing.md`
   - `.claude/skills/pensieve/knowledge/taste-review/content.md`
   - `.claude/skills/pensieve/SKILL.md` 已存在
   - `SKILL.md` 包含自动生成标记与 graph 段落
   - `~/.claude/projects/<project>/memory/MEMORY.md` 已存在并包含 Pensieve 引导块（与系统 skill `description` 对齐）
3. 若走 Init 工具完整流程，确认输出包含：
   - 提交记录与代码热点探索摘要
   - 可沉淀候选清单（仅候选，不自动写入）
   - 基于 review pipeline 的品味分析摘要
4. 重启 Claude Code
5. 直接说“用 loop 完成一个小任务”，应触发 Loop 工具流程
6. 通过 `/help` 确认 `pensieve` skill 已可见

> 说明：`init-loop.sh` 只会创建 loop 目录与 `_agent-prompt.md`。  
> `_context.md` 在 Phase 2 由主窗口创建并填充。

---

## 常见问题

### 安装后没有反应？

1. 确认已重启 Claude Code
2. 检查 `.claude/settings.json`
3. 使用 `/plugin` 确认插件已启用

### Hooks 没有触发？

当前包含两个 hooks：
- `SessionStart`：检查项目目录下的 marker（`<project>/.state/pensieve-session-marker.json`，记录版本 / 初始化状态 / doctor 自检版本）。仅当状态不满足时注入提示，并给出 marker 绝对路径；由主窗口在修复完成后主动执行 `pensieve-session-marker.sh --mode record --event ...` 更新。首次 `record` 会自动创建 `<project>/.state/.gitignore`（忽略 `.state` 内运行时文件）。
- `PostToolUse`：在编辑用户数据后自动同步 `SKILL.md` 图谱，并维护 Claude auto memory `~/.claude/projects/<project>/memory/MEMORY.md` 的 Pensieve 引导块（loop 不依赖 hooks）。

### Skill 没有加载？

系统 skills 随插件分发。如果仍未加载：

1. 重启 Claude Code
2. 检查插件是否启用（`/plugin`）
