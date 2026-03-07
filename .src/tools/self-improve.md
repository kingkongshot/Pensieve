---
description: Extract reusable conclusions from conversations, diffs, and review results. Write them to maxim/decision/knowledge/pipeline and sync the graph.
---

# Self-Improve Tool

> Tool boundaries: see `.src/references/tool-boundaries.md` | Shared rules: see `.src/references/shared-rules.md`

## Use when

- A task round ends with clear reusable conclusions
- Repeatedly extractable patterns emerge during review

## Write targets

- `maxim` → `maxims/{one-sentence-conclusion}.md`
- `decision` → `decisions/{date}-{conclusion}.md`
- `pipeline` → `pipelines/run-when-*.md`
- `knowledge` → `knowledge/{name}/content.md`

Read before writing:

- `.src/references/maxims.md`
- `.src/references/decisions.md`
- `.src/references/pipelines.md`
- `.src/references/knowledge.md`

## Post-write refresh

After writing user data, refresh the generated SKILL.md and graph:

```bash
bash .src/scripts/maintain-project-skill.sh --event self-improve --note "description"
```

In a Claude Code environment this is triggered automatically by hooks; in other environments it must be run manually.
