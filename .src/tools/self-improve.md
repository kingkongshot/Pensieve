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

After writing user data, refresh the project state and graph:

> All `.src/` paths below are relative to the skill root (`$PENSIEVE_SKILL_ROOT`, typically `~/.claude/skills/pensieve/`).

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/maintain-project-state.sh" --event self-improve --note "description"
```

In a Claude Code environment this is triggered automatically by hooks; in other environments it must be run manually.
