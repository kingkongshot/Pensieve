# 共享规则

所有工具的跨领域硬规则。各 tool file 引用此处，不再内联。

## 版本相关路由（Hard Rule）

`upgrade` 只负责版本动作；`migrate` 只负责迁移动作；都不负责项目体检结论。

- 涉及"更新版本/插件兼容问题"时，路由 `upgrade`。
- 涉及"迁移旧数据/清理旧残留"时，路由 `migrate`。
- `init` / `doctor` / `self-improve` / `loop` 不要求前置执行 `upgrade` 或 `migrate`。
- 项目体检（PASS/FAIL、MUST_FIX/SHOULD_FIX）统一由 `doctor` 输出。
- `init` 完成后，必须执行一次 `doctor`。
- 推荐顺序（按需）：`upgrade`（仅版本）→ `migrate`（仅迁移）→ `doctor`（体检）→ `self-improve`（沉淀）。

## 确认再执行（Hard Rule）

用户未显式下达工具命令时，先用一句话确认再执行。禁止按候选意图自动开跑。

- Loop Phase 2 上下文摘要必须获得用户确认后才进入 Phase 3。
- Self-Improve 在显式触发或 pipeline 触发时可直接写入，无需额外确认。
- 写操作以各工具文件为准，不额外增加全局"先草稿后写入"硬限制。

## 语义链接规则（Hard Rule）

三种链接关系：`基于` / `导致` / `相关`。

关联强度要求：
- `decision`：**至少一条有效 `[[...]]` 链接必填**
- `pipeline`：**至少一条有效 `[[...]]` 链接必填**
- `knowledge`：建议填写链接（可空）
- `maxim`：建议填写来源链接（可空）

Loop 输出若成为 `decision` 或 `pipeline`，必须在 wrap-up 前补齐链接。

## 数据边界

- **系统能力**（随插件更新）：`<SYSTEM_SKILL_ROOT>/`（`skills/pensieve/` 内，插件管理）
  - 包含 tools / scripts / system knowledge / 格式 README
  - 不内置 pipelines / maxims 内容
- **用户数据**（项目级，默认不覆盖）：`<USER_DATA_ROOT>/`（`<project>/.claude/skills/pensieve/`）
  - 唯一例外：`migrate` 对关键文件（`run-when-*.md`、`knowledge/taste-review/content.md`）做内容对齐时，可先备份再覆盖。
  - 完整目录结构见 `<SYSTEM_SKILL_ROOT>/references/directory-layout.md`

路径约定（由 SessionStart hook 注入）：
- `<SYSTEM_SKILL_ROOT>` = 插件内 `skills/pensieve/` 绝对路径
- `<USER_DATA_ROOT>` = 项目级 `.claude/skills/pensieve/` 绝对路径

## 规范来源（先读后写）

创建或检查任何类型的用户数据前，先读取对应的格式规范 README：

1. `<SYSTEM_SKILL_ROOT>/maxims/README.md`
2. `<SYSTEM_SKILL_ROOT>/decisions/README.md`
3. `<SYSTEM_SKILL_ROOT>/pipelines/README.md`
4. `<SYSTEM_SKILL_ROOT>/knowledge/README.md`

约束：
- 规范没有明确写 `must / required / hard rule / at least one` 的，不得判为 MUST_FIX。
- 允许基于规范做有限推断，但必须标注"推断项"。

## 状态机（Hard Rule）

用户数据状态由共享引擎统一判定，避免工具各自推断：

- `EMPTY`：根目录或关键分类目录缺失
- `SEEDED`：目录已存在，但缺失关键种子文件
- `ALIGNED`：无 MUST_FIX
- `DRIFTED`：存在 MUST_FIX（但不属于 `EMPTY/SEEDED`）

约束：
- 状态判定由 core 模块实现（`tools/core/pensieve_core.py`），工具侧不得重复实现一套状态判定 if 分支。

## 置信度要求（Pipeline 输出质量）

Pipeline 输出中每个候选问题标注置信度（0-100）：

| 范围 | 处理 |
|------|------|
| >= 80 | 进入最终报告 |
| 50-79 | 标注"待验证"，不直接输出为定论 |
| < 50 | 丢弃 |

仅报告 >= 80 的问题作为确定性结论。
