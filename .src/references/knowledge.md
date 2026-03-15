---
id: knowledge-readme
type: knowledge
title: Knowledge 规范
status: active
created: 2026-02-28
updated: 2026-03-06
tags: [pensieve, knowledge, spec]
---

# Knowledge（知识）

`knowledge` 只承载 IS：系统事实、外部参考、可验证行为。

## 什么时候写 knowledge

当一条信息不写下来，会反复拖慢执行：

- 每次都要重新搜文档
- 每次都要从代码猜边界
- 模型训练数据过时
- 某个流程依赖分散的外部标准

如果它是“我们决定怎么做”，写到 `decisions/`。  
如果它是“必须这样做”，写到 `maxims/`。

## 存储位置

```text
<project>/.pensieve/knowledge/{name}/
├── content.md
└── source/        # 可选
```

初始化时，系统会从 `.src/templates/knowledge/` 种子化默认条目。  
一旦落到 `knowledge/`，它就是用户侧可维护数据。

## 推荐格式

```markdown
# {知识标题}

## Source
[原始链接、代码路径或会话来源]

## Summary
[一句话说明它解决什么探索摩擦]

## Content
[正文]

## When to Use
[什么场景下先读它]

## 上下文链接（推荐）
- 基于：[[前置知识或决策]]
- 导致：[[受影响的决策或流程]]
- 相关：[[相关主题]]
```

## 探索型知识建议

如果这条知识主要用于快速定位问题，尽量包含：

- 状态转换
- 症状 -> 根因 -> 定位
- 边界与所有权
- 反模式
- 验证信号

别把 `knowledge` 写成观点集。它必须能被验证或追溯。
