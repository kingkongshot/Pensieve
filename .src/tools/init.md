---
description: Initialize the current user data root directory and populate seed files. Perform baseline exploration and code review, producing settleable candidates. Idempotent; does not overwrite existing user data.
---

# Init Tool

> Tool boundaries: see `.src/references/tool-boundaries.md` | Shared rules: see `.src/references/shared-rules.md`

## Use when

- First time onboarding to Pensieve
- User needs post-install initialization or re-populating the default structure after reinstall
- Missing base directories: `maxims/decisions/knowledge/pipelines`
- Missing default pipeline or taste-review knowledge

If the user first asks "how to install/reinstall Pensieve", read `.src/references/skill-lifecycle.md` first, then execute this tool.

## Failure fallback

- `.src/scripts/init-project-data.sh` missing: stop and report skill installation is incomplete
- Init script fails: output the failure reason, stop subsequent actions

## Standard execution

```bash
bash .src/scripts/init-project-data.sh
```

Then:

1. Read `pipelines/run-when-reviewing-code.md`
2. Perform an exploration based on recent commits and hot files
3. Produce a "settleable candidates list", but do not auto-write
4. Finally remind the user to manually run doctor:

```bash
bash .src/scripts/run-doctor.sh --strict
```
