# Shared Rules

## Root Rules

1. `.src/` is the system file directory (located at the skill root); do not write user data or runtime state into it.
2. `.pensieve/.state/` is the hidden runtime state directory; write reports, markers, caches, and other transient data here.
3. `.pensieve/{maxims,decisions,knowledge,pipelines}` are user data directories; besides these, only `.pensieve/state.md` may be rewritten by maintenance scripts.
4. `SKILL.md` at the skill root is a static, tracked file — do not modify it.
5. Confirm before executing. Do not automatically run long processes unless the user explicitly requests it.
6. Read the spec before writing data: before writing a maxim/decision/knowledge/pipeline, read the corresponding spec in `.src/references/`.
7. Keep links connected: every `decision/pipeline` must have at least one `[[...]]` link.

## Path conventions

- System skill root: `~/.claude/skills/pensieve/`
- Tool specs: `.src/tools/*.md`
- Execution scripts: `.src/scripts/*.sh`
- Hidden templates: `.src/templates/**`
- Project user data: `<project>/.pensieve/`
- Hidden runtime state: `<project>/.pensieve/.state/**`
- User data:
  - `.pensieve/maxims/*.md`
  - `.pensieve/decisions/*.md`
  - `.pensieve/knowledge/*/content.md`
  - `.pensieve/pipelines/run-when-*.md`

## Semantic layers

- `knowledge` = IS (facts)
- `decision` = WANT (trade-offs)
- `maxim` = MUST (hard rules)
- `pipeline` = HOW (processes)

## When to use migrate / upgrade

- Old paths, key file drift, legacy graph remnants: `migrate`
- Updating skill source code or refreshing installation: `upgrade`
