---
id: run-when-planning
type: pipeline
title: 规划前知识检索 Pipeline
status: active
created: 2026-04-09
updated: 2026-04-09
tags: [pensieve, pipeline, planning, knowledge-retrieval]
name: run-when-planning
description: >
  规划前自动检索已有知识，避免重复踩坑和推翻 active decision。
  跳过代价：重复踩已记录的坑、重新讨论已定的决策。
  触发词：plan、规划、设计、架构、方案、评审。

stages: [tasks]
gate: auto
---

# 规划前知识检索 Pipeline

规划开始前，从现有知识库检索相关历史经验，避免重复踩坑和推翻已有决策。

**上下文链接（至少一条）**：
- 基于：[[decisions/2026-03-26-cherry-pick-harness-mechanisms]]
- 相关：[[knowledge/taste-review/content]]

---

## 信号判断规则

- 只呈现与当前规划直接相关的条目；无关条目不呈现。
- active decision 的"探索减负"优先级最高：它直接告诉你"下次不用再问什么"。
- 无匹配是正常结果，不为凑数量呈现弱相关条目。

---

## Task Blueprint（按顺序创建任务）

### Task 1：提取规划关键词

**目标**：从用户需求中提取可用于检索的关键词

**读取输入**：
1. 用户描述的任务/需求
2. 当前会话上下文

**执行步骤**：
1. 从任务描述中提取 3-8 个关键词（技术栈、模块名、问题域、工具名）
2. 若用户未明确描述需求，从会话上下文推断
3. 关键词应覆盖：功能模块、技术方案、已知约束

**完成标准**：关键词列表（3-8 个）

---

### Task 2：检索 Pensieve 历史

**目标**：从 decisions/knowledge/maxims 中找到与当前规划相关的已有条目

**读取输入**：
1. Task 1 的关键词列表
2. `.pensieve/decisions/*.md`
3. `.pensieve/knowledge/*/content.md`
4. `.pensieve/maxims/*.md`

**执行步骤**：
1. 用每个关键词 grep `decisions/`、`knowledge/`、`maxims/` 三个目录
2. 对每个匹配的文件，读取：
   - 一句话结论（decision）或 Summary（knowledge）或 One-line Conclusion（maxim）
   - 上下文链接（基于/导致/相关）
3. **CRITICAL**：对 active decision，额外提取"探索减负"三项：
   - 下次可以少问什么
   - 下次可以少查什么
   - 失效条件
4. 去重（同一文件被多个关键词命中只呈现一次）

**完成标准**：相关条目摘要列表（包含路径、类型、摘要、探索减负），0 条也是有效结果

---

### Task 3：呈现先验知识并继续规划

**目标**：分层呈现检索结果，然后进入实际规划

**读取输入**：
1. Task 2 的检索结果

**执行步骤**：
1. 按优先级分层呈现：
   - **必须遵守**：active decision（标注探索减负）
   - **建议参考**：相关 knowledge 和 maxim
2. 若无相关条目，输出"无历史先验，从零规划"
3. 呈现完成后，继续实际规划流程（gstack review skill 或用户自行推进）

**完成标准**：先验知识已呈现（或明确无先验），可继续规划

---

## 失败回退

1. `.pensieve/` 目录不存在（项目未初始化）：跳过全部 Task，输出"项目未初始化 Pensieve，跳过知识检索"。
2. 关键词提取失败：使用任务标题整体作为关键词，继续 Task 2。
3. grep 全部无结果：输出"无历史先验"，继续规划。
