---
id: skill-lifecycle
type: knowledge
title: Pensieve Installation and Updates
status: active
created: 2026-03-06
updated: 2026-03-10
tags: [pensieve, install, update, operations]
---

# Pensieve Installation and Updates

When the user asks how to install, initialize, update, reinstall, or uninstall Pensieve itself, read this file first.

## Installation

### Step 1: Install system code (global, one-time)

Clone the repository to the user-level skill directory:

```bash
# English users
git clone -b main https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve

# Chinese users
git clone -b zh https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve
```

Notes:

- System files (`.src/`, `agents/`, `SKILL.md`) are tracked by git
- `SKILL.md` is a static, tracked file — the skill interface declaration
- A single installation serves all projects

### Step 2: Install hooks (global, one-time)

```bash
bash ~/.claude/skills/pensieve/.src/scripts/install-hooks.sh
```

This writes hook configuration to `~/.claude/settings.json`. Hooks automatically apply to all projects. Projects without `.pensieve/` are unaffected (hooks exit silently).

### Step 3: Initialize project data (per project)

```bash
cd <your-project>
bash ~/.claude/skills/pensieve/.src/scripts/init-project-data.sh
```

Or have the agent run `init`.

This creates `maxims/decisions/knowledge/pipelines` under `<project>/.pensieve/` and seeds default content.

## Post-initialization verification

```bash
bash ~/.claude/skills/pensieve/.src/scripts/run-doctor.sh --strict
```

PASS conditions:

- Skill root contains `.src/`
- Skill root contains `SKILL.md` (static, tracked)
- `<project>/.pensieve/{maxims,decisions,knowledge,pipelines}` directories are all present
- `<project>/.pensieve/.state/` has been generated
- `<project>/.pensieve/state.md` has been generated
- Default pipeline and taste-review knowledge have been seeded

## Updates

### Update system code

```bash
cd ~/.claude/skills/pensieve
git pull --ff-only || { git fetch origin && git reset --hard "origin/$(git rev-parse --abbrev-ref HEAD)"; }
```

`--ff-only` works for normal updates; falls back to `fetch + reset` when the remote has been force-pushed (the skill directory contains only tracked files, so this is safe).

A single update takes effect for all projects. After updating:

```bash
cd <your-project>
bash ~/.claude/skills/pensieve/.src/scripts/run-doctor.sh --strict
```

If `doctor` reports structural migration issues:

```bash
bash ~/.claude/skills/pensieve/.src/scripts/run-migrate.sh
bash ~/.claude/skills/pensieve/.src/scripts/run-doctor.sh --strict
```

## Reinstallation

If you have corrupted the system files yourself:

1. Back up project user data: `<project>/.pensieve/` (for each project)
2. Delete the old skill checkout: `rm -rf ~/.claude/skills/pensieve`
3. Clone again (Step 1)
4. Run `init` for each project (Step 3)
5. Run `doctor`

If this is just a normal upgrade, do not reinstall — use the upgrade tool or manually run `git pull`.

## Uninstallation

```bash
# Manually remove pensieve hook entries from ~/.claude/settings.json
# Delete system code
rm -rf ~/.claude/skills/pensieve

# Delete project data (optional, per project)
rm -rf <project>/.pensieve
```

## Hook capabilities

After installing hooks, the following additional capabilities are available:

- SessionStart marker check
- PreToolUse Explore/Plan prompt injection (SKILL.md + state.md)
- PostToolUse graph and auto-memory sync

## Routing rules

- Ask "How do I install/reinstall Pensieve":
  Read this file first, then direct to `init`
- Ask "How do I update Pensieve":
  Read this file first, then direct to `upgrade`
- Ask "How do I clean up old structures/old graph":
  Read this file first, then direct to `migrate`
- Ask "How do I verify everything is working after installation":
  Read this file first, then direct to `doctor`
