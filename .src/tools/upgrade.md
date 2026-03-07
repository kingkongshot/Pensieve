---
description: Refresh the Pensieve skill source code in the current git clone. Upgrade only uses git pull --ff-only; does not perform structural migration or doctor grading.
---

# Upgrade Tool

> Tool boundaries: see `.src/references/tool-boundaries.md` | Shared rules: see `.src/references/shared-rules.md`

## Use when

- User requests a Pensieve upgrade
- Need to confirm version changes before and after upgrade

If the user first asks "how to update Pensieve", read `.src/references/skill-lifecycle.md` first, then execute this tool.

This tool is only responsible for the current skill checkout.
Hook updates for the Claude plugin branch follow Claude's own plugin lifecycle and are not handled here.

## Standard execution

```bash
bash .src/scripts/run-upgrade.sh
```

Optional dry-run:

```bash
bash .src/scripts/run-upgrade.sh --dry-run
```

After upgrade, manually run:

```bash
bash .src/scripts/run-doctor.sh --strict
```
