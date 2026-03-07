# Shared Rules

## Root Rules

1. `.src/` is the system file directory; do not write user data or runtime state into it.
2. `.state/` is the hidden runtime state directory; reports, markers, caches, and other ephemeral data go here.
3. `maxims/decisions/knowledge/pipelines` are user data directories; besides these, only the root-level generated `SKILL.md` can be rewritten by maintenance scripts.
4. Confirm before executing. Do not automatically run long processes unless the user explicitly requests it.
5. Read specs before writing data: before writing a maxim/decision/knowledge/pipeline, read the corresponding spec in `.src/references/`.
6. Keep links connected: `decision/pipeline` must have at least one `[[...]]` link.

## Path conventions

- Tool specs: `.src/tools/*.md`
- Execution scripts: `.src/scripts/*.sh`
- Hidden templates: `.src/templates/**`
- Hidden runtime state: `.state/**`
- User data:
  - `maxims/*.md`
  - `decisions/*.md`
  - `knowledge/*/content.md`
  - `pipelines/run-when-*.md`

## Semantic layers

- `knowledge` = IS (facts)
- `decision` = WANT (trade-offs)
- `maxim` = MUST (hard rules)
- `pipeline` = HOW (processes)

## When to use migrate / upgrade

- Old paths, key file drift, legacy graph remnants: `migrate`
- Updating skill source code or refreshing installation: `upgrade`
