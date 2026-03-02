---
description: 初始化 `.claude/skills/pensieve/` 目录并补齐种子文件，执行基线探索与代码审查，产出可沉淀候选。幂等不覆盖已有数据。
---

# Init 工具

> 工具边界见 `<SYSTEM_SKILL_ROOT>/references/tool-boundaries.md` | 共享规则见 `<SYSTEM_SKILL_ROOT>/references/shared-rules.md`

初始化项目级用户数据目录，确保新项目开箱可用且依赖自包含。

## Tool Contract

### Use when
- 新项目首次接入 Pensieve
- `.claude/skills/pensieve/` 不存在或缺少基础目录/种子文件
- 初始化后需快速建立项目级审查基线

### Failure fallback
- 脚本执行失败：输出失败原因与重试命令
- 缺少 `<SYSTEM_SKILL_ROOT>`：提示重启/检查插件注入，停止执行
- 仓库无提交记录或 Git 不可用：跳过探索与代码审查，标记 `SKIPPED`

## Phase 1: 目录与种子初始化

**Goal**: 创建项目数据目录并补齐所有种子文件。

**Actions**:
1. 检查 `<SYSTEM_SKILL_ROOT>/tools/loop/scripts/init-project-data.sh` 是否存在。
2. 运行：
```bash
bash <SYSTEM_SKILL_ROOT>/tools/loop/scripts/init-project-data.sh
```
3. 核验最小结果：`{maxims,decisions,knowledge,pipelines,loop}` 目录已存在；`pipelines/run-when-reviewing-code.md`、`pipelines/run-when-committing.md`、`knowledge/taste-review/content.md` 已存在。
4. 核验项目级 SKILL：`.claude/skills/pensieve/SKILL.md` 包含自动生成标记与 graph 段落；`~/.claude/projects/<project>/memory/MEMORY.md` 包含 Pensieve 引导块。
5. 若扫描到历史目录（`skills/pensieve/` 或 `.claude/pensieve/`），提醒运行 `migrate`。

## Phase 2: 基线探索

**Goal**: 只读扫描 Git 历史与代码结构，产出可沉淀候选清单。

**Actions**:
1. 读取最近提交记录（默认 30 条，或用户指定窗口）。
2. 汇总高频变更文件/模块与风险热点。
3. 产出候选清单（标注建议类型：`knowledge/decision/maxim/pipeline`），每条附证据，无证据不列入。

## Phase 3: 代码审查与收尾

**Goal**: 基于热点执行 review pipeline 审查，输出汇总与下一步指引。

**Actions**:
1. 加载 `.claude/skills/pensieve/pipelines/run-when-reviewing-code.md`，以"热点文件 + 最近关键提交"作为审查范围。
2. 输出审查摘要（复杂度热点、特殊分支、潜在破坏性改动风险）。
3. 收尾输出：初始化结果 + 候选摘要 + 审查摘要。
4. 下一步：运行 `doctor` 检查种子文件格式；若需写入沉淀：运行 `self-improve`。

## 约束

- 初始化可附带只读探索与代码审查，但不直接写入沉淀内容，由 `self-improve` 负责。
- 不做迁移清理，由 `migrate` 负责。
- 不覆盖已有用户文件。
- 不输出 `doctor` 风格的合规分级结论。
