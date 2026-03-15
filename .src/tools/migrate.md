---
description: Migration tool. Automatically migrates legacy user data to the v2 directory structure and aligns critical seed files. Does not perform version upgrades or doctor grading.
---

# Migrate Tool

> Tool boundaries: see `.src/references/tool-boundaries.md` | Shared rules: see `.src/references/shared-rules.md`

## Use when

- Migrating from v1 (project-level install) to v2 (user-level system + project-level data)
- Doctor reports critical file missing or critical file drift
- Need to fill in directory structure or re-align seed files

## Standard execution

> All `.src/` paths below are relative to the skill root (`$PENSIEVE_SKILL_ROOT`, typically `~/.claude/skills/pensieve/`).

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/run-migrate.sh"
```

Optional dry-run:

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/run-migrate.sh" --dry-run
```
