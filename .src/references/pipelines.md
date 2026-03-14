# Pipelines（流程）

Pipeline 只负责一件事：把任务顺序、验证闭环和失败回退写清楚。

## 什么时候该写 pipeline

满足下面三条再新建：

1. 同类任务已经重复出现
2. 步骤顺序不可交换
3. 每一步都能写出可验证完成标准

如果问题主要是“知识分散”或“边界不清”，先写 `knowledge/decision`，别滥建 pipeline。

## 存储位置

```text
<project>/.pensieve/pipelines/
└── run-when-*.md
```

初始化或迁移时，系统会从 `.src/templates/` 种子化默认 pipeline。  
之后 `pipelines/` 里的文件就是用户侧真实数据。

## 强制规则

- 文件名必须是 `run-when-*.md`
- pipeline 主体只写任务编排、验证闭环、失败回退
- 任何长背景、原理、约束都应拆到 `knowledge/decision/maxim` 再链接回来
- 每条 pipeline 至少带一条 `[[...]]` 上下文链接

## 推荐骨架

```markdown
# Pipeline 名称

---
id: run-when-xxx
type: pipeline
title: Pipeline 名称
status: active
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags: [pensieve, pipeline]
description: [触发场景、跳过代价、触发词]
---

## 信号判断规则
- 只保留可复现、可定位、有证据的结果

## Task Blueprint
### Task 1
- 目标
- 读取输入
- 执行步骤
- 完成标准

### Task 2
...

## 失败回退
1. 输入缺失时停止
2. 证据不足时过滤
3. 无高信号结果时明确说明
```
| frontmatter 必填 | `id/type/title/status/created/updated/tags/description` |
| `description` | 位于 frontmatter，包含触发词 |
| 信号判断规则 | 必须声明高信号阈值与不报告项 |
| 不堆知识 | 长背景放到 Knowledge/Maxims/Decisions/Skills |
| 内容拆分 | 若段落不影响 task 编排，必须拆分并改为 `[[...]]` 引用 |
| Task Blueprint | 必须显式 `Task 1/2/3...` 顺序 |
| **目标** | 每个任务必须有 |
| **读取输入** | 文件/路径必须写清 |
| **执行步骤** | 编号、具体、可执行 |
| **完成标准** | 必须可验证 |
| **CRITICAL** / **DO NOT SKIP** | 关键步骤强提示 |
| 失败回退 | 必须有明确 fallback |
| 链接 | 正文至少一条有效链接 |

## 备注

- Pipeline 应轻量且可执行
- 每次只解决一个闭环问题，避免超大流程
- 不确定时先最小可运行版本，再迭代
