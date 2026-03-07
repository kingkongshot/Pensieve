---
description: 从对话、diff、review 结果中提取可复用结论，写入 maxim/decision/knowledge/pipeline，并同步图谱。
---

# Self-Improve 工具

> 工具边界见 `.src/references/tool-boundaries.md` | 共享规则见 `.src/references/shared-rules.md`

## Use when

- 一轮任务结束后有明确可复用结论
- review 里出现反复可提炼的模式

## 写入位置

- `maxim` → `maxims/{one-sentence-conclusion}.md`
- `decision` → `decisions/{date}-{conclusion}.md`
- `pipeline` → `pipelines/run-when-*.md`
- `knowledge` → `knowledge/{name}/content.md`

写入前先读：

- `.src/references/maxims.md`
- `.src/references/decisions.md`
- `.src/references/pipelines.md`
- `.src/references/knowledge.md`
