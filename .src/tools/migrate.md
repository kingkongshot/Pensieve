---
description: Structural migration and legacy cleanup. Only handles old path migration, critical seed file alignment, and historical remnant cleanup; does not perform version upgrades or doctor grading.
---

# Migrate Tool

> Tool boundaries: see `.src/references/tool-boundaries.md` | Shared rules: see `.src/references/shared-rules.md`

## Use when

- Legacy path remnants exist under the skill root directory
- Doctor reports critical file missing, critical file drift, or old graph remnants

## Standard execution

```bash
bash .src/scripts/run-migrate.sh
```

Optional dry-run:

```bash
bash .src/scripts/run-migrate.sh --dry-run
```
