---
id: run-when-committing
type: pipeline
title: 提交 Pipeline
status: active
created: 2026-02-28
updated: 2026-02-28
tags: [pensieve, pipeline, commit, self-improve]
name: run-when-committing
description: 提交阶段强制流程：先判断是否有可沉淀洞察，命中则先自改进沉淀，再做原子化提交。触发词：commit、提交、git commit。

stages: [tasks]
gate: auto
---

# 提交 Pipeline

提交前自动从会话上下文 + diff 中提取洞察并沉淀，然后执行原子化提交。全程不询问用户确认。

**自改进参考**：`.src/tools/self-improve.md`

**上下文链接（至少一条）**：
- 基于：[[knowledge/taste-review/content]]
- 相关：none

---

## 信号判断规则

沉淀的价值在于下次能复用，没有证据支撑的猜测反而会误导后续决策。

- 只沉淀"可复用且有证据"的洞察；无法验证的猜测不落库。
- 分类遵守语义分层：IS → `knowledge`，WANT → `decision`，MUST → `maxim`。
- 用语义而非"knowledge 优先"来分配，因为错误分类会导致约束力度不匹配（本该是 MUST 的写成了 knowledge，后续容易被忽略）。

---

## Task Blueprint（按顺序创建任务）

### Task 1：先判断要不要沉淀 — 判断是否有可沉淀洞察

**目标**：快速判断本次提交是否有值得沉淀的经验，跳过则直接进入 Task 3

**读取输入**：
1. `git diff --cached`（即将提交的变更）
2. 当前会话上下文

**执行步骤**：
1. 运行 `git diff --cached --stat` 了解变更范围
2. 回顾当前会话，检查是否存在以下信号（任一即触发沉淀）：
   - 识别了 bug 根因（调试会话）
   - 做了架构或设计决策（考虑了多个方案）
   - 发现了新模式或反模式
   - 探索产出了"症状 → 根因 → 定位"映射
   - 澄清了边界、所有权、约束
   - 发现了系统中不存在/已废弃的能力
3. 若以上信号均不存在（纯机械改动：格式化、重命名、依赖升级、简单修复），标记"跳过沉淀"，直接跳到 Task 3

**完成标准**：明确判定"需要沉淀"或"跳过沉淀"，附一句理由

---

### Task 2：自动沉淀 — 提取洞察并写入

**目标**：从会话上下文 + diff 中提取洞察，写入用户数据，不询问用户

**读取输入**：
1. Task 1 判定结果（若为"跳过"则跳过本 Task）
2. `git diff --cached`
3. 当前会话上下文
4. `.src/tools/self-improve.md`

**执行步骤**：
1. 读取 `self-improve.md`，按其 Phase 1（提取与分类）+ Phase 2（读取规范+写入）执行
2. 从会话中提取核心洞察（可以是多条）
3. 为每条洞察先判定语义层并分类（IS->knowledge, WANT->decision, MUST->maxim；必要时可多层同时落地）
4. 读取 `.src/references/` 中目标类型的规范，按规范生成内容
5. 类型特定要求：
   - `decision`：包含"探索减负三项"（下次少问/少查/失效条件）
   - 探索型 `knowledge`：包含（状态转换 / 症状→根因→定位 / 边界与所有权 / 反模式 / 验证信号）
   - `pipeline`：需满足条件（重复出现 + 不可交换 + 可验证）
6. 写入目标路径，补关联链接
7. 刷新 Pensieve 项目状态：
   ```
   bash "$PENSIEVE_SKILL_ROOT/.src/scripts/maintain-project-state.sh" --event self-improve --note "auto-improve: {files}"
   ```
8. 输出简短摘要（写入路径 + 沉淀类型）

**DO NOT**：不询问用户确认，不展示草稿等待批准，直接写入

**完成标准**：洞察已写入用户数据（或明确无需沉淀），`state.md` 与 `.state/pensieve-user-data-graph.md` 已刷新

---

### Task 3：原子化提交

**目标**：执行原子化 git 提交

**读取输入**：
1. `git diff --cached`
2. 用户的提交意图（commit message 或上下文）

**执行步骤**：
1. 分析 staged changes，按变更原因聚类
2. 若存在多组独立变更，分别提交（每组一个原子提交）
3. 提交信息规范：
   - 标题：祈使句，<50 字符，具体
   - 正文：解释"为什么"而非"做了什么"
4. 执行 `git commit`

**完成标准**：所有 staged changes 已提交，每个提交独立且可回滚

---

## 短期记忆提示

提交完成后，若 `short-term/` 中有到期条目，追加一行提示：

> 短期记忆有 N 条待整理，可运行 pensieve refine 完成处理。工具规格：`.src/tools/refine.md`。

不在提交流程中执行整理，仅提醒。

## 失败回退

1. `git diff --cached` 为空：跳过 Task 2/Task 3，输出"无 staged 变更，不提交"。
2. 沉淀步骤失败：记录阻塞原因并跳过沉淀，继续 Task 3；结尾追加"建议运行 `doctor`"。
3. `state.md` 维护失败：保留已沉淀内容，报告失败命令与重试建议，不回滚已写入文件。
