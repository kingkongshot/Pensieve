---
description: Refresh the current git clone of the Pensieve skill source. Prefers git pull --ff-only; automatically falls back to fetch+reset when the remote has been force-pushed. Does not perform structural migration or doctor grading.
---

# Upgrade Tool

> Tool boundaries: see `.src/references/tool-boundaries.md` | Shared rules: see `.src/references/shared-rules.md`

## Use when

- User requests a Pensieve upgrade
- Need to confirm version changes before and after upgrade

If the user first asks "how to update Pensieve", read `.src/references/skill-lifecycle.md` first, then run this tool.

This tool is only responsible for the global skill checkout (`~/.claude/skills/pensieve/`).
Hooks are installed globally via `install-hooks.sh` and do not need to be updated separately.

## Standard execution

> All `.src/` paths below are relative to the skill root (`$PENSIEVE_SKILL_ROOT`, typically `~/.claude/skills/pensieve/`).

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/run-upgrade.sh"
```

Optional dry-run:

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/run-upgrade.sh" --dry-run
```

After upgrade, manually run:

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/run-doctor.sh" --strict
```
