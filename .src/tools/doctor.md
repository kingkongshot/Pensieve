---
description: Read-only scan of the current project's .pensieve/ user data directory. Checks frontmatter, links, directory structure, critical seed files, and auto-memory alignment, then outputs a fixed-format report.
---

# Doctor Tool

> Tool boundaries: see `.src/references/tool-boundaries.md` | Shared rules: see `.src/references/shared-rules.md` | Directory conventions: see `.src/references/directory-layout.md`

## Use when

- Post-initialization verification
- Post-upgrade verification
- Confirming MUST_FIX count is zero after migration
- Suspected drift in graph, frontmatter, directory structure, or memory pointers

## Standard execution

> All `.src/` paths below are relative to the skill root (`$PENSIEVE_SKILL_ROOT`, typically `~/.claude/skills/pensieve/`).

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/run-doctor.sh" --strict
```

Doctor only maintains:

- `<project>/.pensieve/state.md` (lifecycle state + Graph)
- Runtime graph output such as `.pensieve/.state/pensieve-user-data-graph.md`
- Claude auto memory `~/.claude/projects/<project>/memory/MEMORY.md`

It will not modify your business code.
