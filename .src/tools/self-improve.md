---
description: Extract reusable conclusions from conversations, diffs, and review results, write them to short-term or long-term directories, and sync the graph.
---

# Self-Improve Tool

> Tool boundaries: see `.src/references/tool-boundaries.md` | Shared rules: see `.src/references/shared-rules.md`

## Use when

- A task round ends with clear reusable conclusions
- Repeatedly extractable patterns emerge during review

## Write targets

### New files -> Write to short-term by default

- `maxim` → `short-term/maxims/{one-sentence-conclusion}.md`
- `decision` → `short-term/decisions/{date}-{conclusion}.md`
- `pipeline` → `short-term/pipelines/run-when-*.md`
- `knowledge` → `short-term/knowledge/{name}/content.md`

Naming conventions match the corresponding long-term directories. `[[...]]` links do not include the `short-term/` prefix.

### Modifying existing files -> Edit in place

Files already in `maxims/decisions/knowledge/pipelines` are edited directly in place, not via short-term.

### Exception: When the user explicitly requests writing directly to long-term directories, short-term can be skipped.

Read before writing:

- `.src/references/maxims.md`
- `.src/references/decisions.md`
- `.src/references/pipelines.md`
- `.src/references/knowledge.md`
- `.src/references/short-term.md`

## Post-write refresh

After writing user data, refresh the project state and graph:

> All `.src/` paths below are relative to the skill root (`$PENSIEVE_SKILL_ROOT`, typically `~/.claude/skills/pensieve/`).

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/maintain-project-state.sh" --event self-improve --note "description"
```

In a Claude Code environment this is triggered automatically by hooks; in other environments it must be run manually.
