---
description: Initialize the current project's .pensieve/ user data directory and provision seed files. Performs baseline exploration and code review, producing candidates for persistence. Idempotent; does not overwrite existing user data.
---

# Init Tool

> Tool boundaries: see `.src/references/tool-boundaries.md` | Shared rules: see `.src/references/shared-rules.md`

## Use when

- First time integrating Pensieve into a project
- User needs post-install initialization or post-reinstall default structure provisioning
- Missing base directories: `<project>/.pensieve/{maxims,decisions,knowledge,pipelines}`
- Missing default pipeline or taste-review knowledge

If the user first asks "how to install/reinstall Pensieve", read `.src/references/skill-lifecycle.md` first, then run this tool.

## Failure fallback

- `.src/scripts/init-project-data.sh` missing: stop and report skill installation is incomplete
- Init script fails: output the failure reason, stop subsequent actions

## Standard execution

> All `.src/` paths below are relative to the skill root (`$PENSIEVE_SKILL_ROOT`, typically `~/.claude/skills/pensieve/`).

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/init-project-data.sh"
```

Then:

1. Read `<project>/.pensieve/pipelines/run-when-reviewing-code.md`
2. Explore based on recent commits and hot files
3. Produce a "candidates for persistence" list, but do not write automatically
4. Finally, remind the user to run doctor manually:

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/run-doctor.sh" --strict
```
