---
id: knowledge-readme
type: knowledge
title: Knowledge Specification
status: active
created: 2026-02-28
updated: 2026-03-06
tags: [pensieve, knowledge, spec]
---

# Knowledge

`knowledge` only carries IS: system facts, external references, verifiable behavior.

## When to write knowledge

When a piece of information, if not written down, will repeatedly slow down execution:

- Having to re-search documentation every time
- Having to guess boundaries from code every time
- Model training data is outdated
- A process depends on scattered external standards

If it is "how we decided to do it," write it in `decisions/`.
If it is "must be done this way," write it in `maxims/`.

## Storage location

```text
<skill-root>/knowledge/{name}/
├── content.md
└── source/        # optional
```

During initialization, the system seeds default entries from `.src/templates/knowledge/`.
Once placed in `knowledge/`, it becomes user-side maintainable data.

## Recommended format

```markdown
# {Knowledge title}

## Source
[Original link, code path, or conversation source]

## Summary
[One sentence explaining what exploration friction it resolves]

## Content
[Body]

## When to Use
[In what scenarios to read it first]

## Context Links (recommended)
- Based on: [[prerequisite knowledge or decision]]
- Leads to: [[affected decision or process]]
- Related: [[related topic]]
```

## Exploratory knowledge suggestions

If this knowledge entry is primarily for quickly locating problems, try to include:

- State transitions
- Symptom -> root cause -> localization
- Boundaries and ownership
- Anti-patterns
- Verification signals

Do not turn `knowledge` into an opinion collection. It must be verifiable or traceable.
