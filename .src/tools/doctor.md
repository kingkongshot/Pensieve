---
description: Read-only scan of the current user data root directory. Checks frontmatter, links, directory structure, critical seed files, and auto memory alignment. Outputs a fixed-format report.
---

# Doctor Tool

> Tool boundaries: see `.src/references/tool-boundaries.md` | Shared rules: see `.src/references/shared-rules.md` | Directory conventions: see `.src/references/directory-layout.md`

## Use when

- Post-initialization verification
- Post-upgrade verification
- Confirming MUST_FIX count is zero after migration
- Suspected drift in graph, frontmatter, directory structure, or memory pointers

## Standard execution

```bash
bash .src/scripts/run-doctor.sh --strict
```

Doctor only maintains:

- `SKILL.md` generated at the root directory (lifecycle state + Graph)
- Runtime graph outputs such as `.state/pensieve-user-data-graph.md`
- Claude auto memory `~/.claude/projects/<project>/memory/MEMORY.md`

It will not modify your business code.
