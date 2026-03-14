# Decisions（决策）

记录当前项目下主动做出的选择，以及为什么这么选。

## 什么时候写 decision

满足任一条就值得记：

1. 删掉它，未来更容易犯错
2. 三个月后的人读完它，能少走很多弯路
3. 它明确了模块边界、职责或取舍

如果内容描述的是客观事实，写到 `knowledge/`。  
如果内容是跨项目硬规则，升级到 `maxims/`。

## 存储位置

| 阶段 | 位置 | 说明 |
|---|---|---|
| 固化后 | `decisions/` | 项目长期决策 |

正式文件命名：

```text
<project>/.pensieve/decisions/{date}-{statement}.md
```

## 强制要求

- 每条 `decision` 至少带一条有效 `[[...]]` 链接
- 必须写清 `Context` 和 `Alternatives Considered`
- 必须写“下次少问什么 / 少查什么 / 何时失效”

## 推荐格式

```markdown
# {决策标题}

## 一句话结论
> {最终选择}

## 上下文链接
- 基于：[[前置知识或决策]]
- 导致：[[后续流程或决策]]
- 相关：[[平行主题]]

## Context

## Problem

## Alternatives Considered
- 方案 A：为何不用
- 方案 B：为何不用

## Decision

## Consequence

## 探索减负
- 下次可以少问什么：
- 下次可以少查什么：
- 失效条件：
```
