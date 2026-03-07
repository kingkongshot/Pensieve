---
id: skill-lifecycle
type: knowledge
title: Pensieve Installation and Updates
status: active
created: 2026-03-06
updated: 2026-03-07
tags: [pensieve, install, update, operations]
---

# Pensieve Installation and Updates

When the user asks how to install, initialize, update, reinstall, or uninstall Pensieve itself, read this file first.

## Installation

### Method A: Install the main branch skill (required)

Clone the repository directly into the project's skill directory:

```bash
git clone -b main https://github.com/kingkongshot/Pensieve.git .claude/skills/pensieve
```

Notes:

- The `main` branch repository root is the skill root — there is no longer a `skill-source/pensieve/` layer
- Tracked system files are `.src/`, `agents/`
- The root-level `SKILL.md` is a generated file, written to a fixed location after initialization, and ignored by `.gitignore`
- User data directories are `maxims/decisions/knowledge/pipelines`
- User data directories and the generated `SKILL.md` are both ignored by the root `.gitignore`, so `git pull` will not overwrite them
- No longer depends on `npx skills add --copy`

After installation:

1. Have the agent run `init`
2. Or manually execute in the skill root directory:

```bash
bash .src/scripts/init-project-data.sh
```

### Method B: Install Claude plugin hooks (optional add-on)

Hooks are not on the `main` branch; they are on a separate `claude-plugin` branch, installed via marketplace:

```bash
claude plugin marketplace add kingkongshot/Pensieve#claude-plugin
claude plugin install pensieve@kingkongshot-marketplace --scope project
```

Notes:

- The plugin only provides hooks; it does not carry skill content
- Hooks and skill lifecycles are decoupled: the plugin updates via marketplace, the skill updates via git
- If you want Claude hooks, you still need to complete Method A's skill clone first

## Post-initialization verification

```bash
bash .src/scripts/run-doctor.sh --strict
```

PASS conditions:

- `.src/` exists
- `agents/` exists
- Root-level `SKILL.md` has been generated
- `maxims/decisions/knowledge/pipelines` directories are all present
- `.state/` is generated in the project root
- Default pipelines and taste-review knowledge have been seeded

## Updates

### Updating the main branch skill

```bash
cd .claude/skills/pensieve
git pull --ff-only
```

Fixed sequence after updating:

```bash
bash .src/scripts/run-doctor.sh --strict
```

If `doctor` reports structural migration issues, then run:

```bash
bash .src/scripts/run-migrate.sh
bash .src/scripts/run-doctor.sh --strict
```

### Updating claude-plugin branch hooks

```bash
claude plugin update pensieve
```

Interactive equivalent command:

```text
/plugin update pensieve
```

This only updates hooks and does not affect user data in the main branch skill clone.

## Reinstallation

If system files have been corrupted by your own changes, the simplest reinstallation method is:

1. Back up local user data directories: `maxims/`, `decisions/`, `knowledge/`, `pipelines/`
2. Delete the old skill checkout
3. Re-run the installation
4. Run `init`
5. Run `doctor`

If it is just a normal upgrade, do not reinstall — use `git pull --ff-only` directly.

## Uninstallation

Simply delete the installed skill root directory.

If you also want to preserve user data, back up first:

- `maxims/`
- `decisions/`
- `knowledge/`
- `pipelines/`
- `.state/` (if you want to keep health check reports, migration backups, session markers)

## Claude add-on capabilities

If the `claude-plugin` branch is also installed, you additionally get:

- SessionStart marker check
- PreToolUse Explore/Plan prompt injection
- PostToolUse graph and auto memory auto-sync
- Claude native `/plugin update` lifecycle

## Routing rules

- Question "How to install/reinstall Pensieve":
  Read this file first, then guide to `init`
- Question "How to update Pensieve":
  Read this file first, then guide to `upgrade`
- Question "How to clean up old structures/old graph":
  Read this file first, then guide to `migrate`
- Question "How to verify everything is fine after installation":
  Read this file first, then guide to `doctor`
