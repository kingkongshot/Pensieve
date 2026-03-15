---
id: architecture-v2
type: spec
title: "Architecture v2: User-Level System + Project-Level Data"
status: draft
created: 2026-03-10
tags: [architecture, refactor, v2]
---

# Architecture v2: User-Level System + Project-Level Data

## 1. Problem Statement

### 1.1 System Code Duplicated Per Project

Every project requires `git clone` of a full copy of `.src/`, `agents/`, templates, and reference docs into `<project>/.claude/skills/pensieve/`. Ten projects = ten identical copies. Updating requires entering each project's skill directory individually to run `git pull`.

### 1.2 User Data Physically Mixed with System Code

User data directories (`maxims/`, `decisions/`, `knowledge/`, `pipelines/`) reside inside the git clone directory, isolated only by `.gitignore`. They physically coexist with `.git/`, `.src/`, and other tracked files. A single `git clean -fd` would destroy all user data. This is "untracked" rather than "truly isolated."

### 1.3 Dual-Track Installation

Installing Pensieve requires two independent steps from two different branches:

1. `git clone -b main` -> skill code
2. `claude plugin marketplace add` + `claude plugin install` -> hooks (claude-plugin branch)

Updates also follow two paths: `git pull` for skills, `claude plugin update` for hooks. Users must understand that "two branches of the same repo are two independent installation units" -- this is not a natural mental model.

### 1.4 User Data Trapped Inside `.claude/`

User data at `<project>/.claude/skills/pensieve/maxims/` is by convention invisible to version control (`.claude/` is typically gitignored). If users want to commit their engineering memory -- which they should -- they must either un-ignore the entire `.claude/` (exposing other Claude configs) or write complex ignore rules. The data path is also tied to a specific client (`.claude/`), contradicting the tool-agnostic nature of the knowledge itself.

### 1.5 SKILL.md Serves Both Static and Dynamic Roles

The generated `SKILL.md` contains:

- **Static parts**: frontmatter (name, description), routing table, tool descriptions -- identical across all projects
- **Dynamic parts**: project paths, lifecycle state, knowledge graph -- different per project

When system code is shared globally, a single SKILL.md cannot serve both roles simultaneously.

---

## 2. Target Architecture

### 2.1 Directory Layout

```
~/.claude/skills/pensieve/          # User-level (single global installation)
├── SKILL.md                        #   Static: frontmatter + routing (skill discovery entry)
├── .src/                           #   System code, templates, reference docs, core engine
│   ├── core/
│   ├── scripts/                    #   Execution scripts + hook scripts (dispatched by run-hook.sh)
│   ├── templates/
│   ├── references/
│   └── tools/
└── agents/                         #   Agent configurations

<project>/.pensieve/                # Project-level (per-project, version-controlled)
├── maxims/                         #   Engineering principles
├── decisions/                      #   Architecture decisions
├── knowledge/                      #   Cached exploration results
├── pipelines/                      #   Reusable workflows
├── state.md                        #   Dynamic: lifecycle state + knowledge graph
└── .state/                         #   Runtime artifacts (gitignored)
```

### 2.2 Key Design Decisions

**SKILL.md stays at user-level and becomes static.**

Claude Code discovers skills by scanning `~/.claude/skills/*/SKILL.md` (user-level) and `<project>/.claude/skills/*/SKILL.md` (project-level). No SKILL.md means no skill. Since system code lives at user-level, SKILL.md must be there too.

Each project's dynamic state (lifecycle events, graph) moves to `<project>/.pensieve/state.md`. The static SKILL.md instructs Claude to read the project-level state file for context.

**User data goes in `<project>/.pensieve/`, not `<project>/.claude/pensieve/`.**

Rationale:

1. **Version control**: `.pensieve/` is naturally committable. `.claude/` is conventionally gitignored.
2. **Tool-agnostic**: `.pensieve/` is not bound to any AI client. The knowledge model is universal.
3. **Discoverability**: Team members can spot `.pensieve/` at the project root at a glance, without deep nesting.
4. **Precedent**: `lib.sh` already handles multiple client paths (`.claude/`, `.agents/`, `.codex/`, `.cursor/`). A dedicated `.pensieve/` directory replaces all of them as the user data location.

**Hooks merge into the main branch, installed globally once.**

The `claude-plugin` branch is retired. Hook scripts live in `~/.claude/skills/pensieve/.src/scripts/`, alongside other execution scripts (dispatched uniformly by `run-hook.sh`). Hook configuration is written to user-level `~/.claude/settings.json`, installed once and effective globally -- no per-project configuration needed. All hook scripts implement graceful degradation: they silently exit (`exit 0`) when a project has not initialized Pensieve, causing zero impact on unrelated projects.

**`.state/` moves inside `.pensieve/`.**

Runtime artifacts (reports, markers, graph snapshots, migration backups) move from `<project>/.state/` to `<project>/.pensieve/.state/`. All Pensieve-related project files are consolidated under a single directory tree. The `.state/` subdirectory is excluded via `.pensieve/.gitignore`.

---

## 3. SKILL.md Split Design

### 3.1 Static SKILL.md (User-Level)

Location: `~/.claude/skills/pensieve/SKILL.md`

```markdown
---
name: pensieve
description: >-
  Project knowledge base and workflow router.
  knowledge/ caches explored file locations, module boundaries, and call chains for direct reuse;
  decisions/maxims are established architecture decisions and coding standards -- follow, don't re-debate;
  pipelines are reusable workflows.
  Use self-improve to capture new insights after completing tasks.
  Provides five tools: init, upgrade, migrate, doctor, self-improve.
---

# Pensieve

Route user requests to the correct tool. When uncertain, confirm first.

## Routing
- Init: Initialize the current project's user data directory and populate seed files. Tool spec: `.src/tools/init.md`.
- Upgrade: Refresh Pensieve skill source code in the global git clone. Tool spec: `.src/tools/upgrade.md`.
- Migrate: Structural migration and legacy cleanup. Tool spec: `.src/tools/migrate.md`.
- Doctor: Read-only scan of the current project's user data directory. Tool spec: `.src/tools/doctor.md`.
- Self-Improve: Extract reusable conclusions and write to user data. Tool spec: `.src/tools/self-improve.md`.
- Graph View: Read the `## Graph` section of `<project-root>/.pensieve/state.md`.

## Project Data
Project-level user data is stored in `<project-root>/.pensieve/`.
The current project's lifecycle state and knowledge graph are in `.pensieve/state.md`.
```

This file is **tracked by git** (not gitignored) and updated only via `git pull`. It is the skill's interface declaration, written by the skill maintainer -- users should not modify it. The init script no longer generates it.

### 3.2 Dynamic state.md (Project-Level)

Location: `<project>/.pensieve/state.md`

```markdown
# Pensieve Project State

## Lifecycle State
- Last Event: install/init
- Last Note: seeded project data via init-project-data.sh

## Project Paths
- Project Root: `/path/to/project`
- User Data: `.pensieve/`
- Runtime State: `.pensieve/.state/`

## Graph

(Knowledge graph content)
```

This file is generated/updated by `maintain-project-state.sh` (formerly `maintain-project-skill.sh`). Users may choose whether to version-control it.

---

## 4. Path Resolution Changes

### 4.1 lib.sh Core Changes

```bash
# Before: user data root == skill root
user_data_root() {
    if [[ -n "${PENSIEVE_DATA_ROOT:-}" ]]; then
        to_posix_path "$PENSIEVE_DATA_ROOT"
        return 0
    fi
    skill_root "${1:-$(pwd)}"
}

# After: user data root == project root / .pensieve
user_data_root() {
    if [[ -n "${PENSIEVE_DATA_ROOT:-}" ]]; then
        to_posix_path "$PENSIEVE_DATA_ROOT"
        return 0
    fi
    echo "$(project_root "${1:-$(pwd)}")/.pensieve"
}
```

```bash
# Before: state root == project root / .state
state_root() {
    # ...
    echo "$pr/.state"
}

# After: state root == project root / .pensieve / .state
# Note: when project_root() fails, the error should propagate rather than silently producing a bad path.
state_root() {
    if [[ -n "${PENSIEVE_STATE_ROOT:-}" ]]; then
        # (Environment variable override logic unchanged)
    fi
    local pr
    pr="$(project_root "${1:-$(pwd)}")" || return 1
    echo "$pr/.pensieve/.state"
}
```

```bash
# Before: SKILL.md located at user_data_root
project_skill_file() {
    local dr
    dr="$(user_data_root "${1:-$(pwd)}")"
    echo "$dr/SKILL.md"
}

# After: project state file at user_data_root; SKILL.md at skill_root
project_state_file() {
    local dr
    dr="$(user_data_root "${1:-$(pwd)}")"
    echo "$dr/state.md"
}

skill_md_file() {
    local sr
    sr="$(skill_root "${1:-$(pwd)}")"
    echo "$sr/SKILL.md"
}
```

The v1 `project_skill_file()` alias has been removed -- it mapped SKILL.md semantics onto state.md, which has a completely different format, silently misleading callers. In v2, use `skill_md_file()` to get SKILL.md and `project_state_file()` to get state.md.

### 4.2 project_root() Simplification

After user data lives in `<project>/.pensieve/`, the `project_root()` function no longer needs to strip client-specific skill paths (`.claude/skills/*`, `.agents/skills/*`, etc.). The skill root is always `~/.claude/skills/pensieve/`, and the project root is discovered via `$CLAUDE_PROJECT_DIR`, `git rev-parse --show-toplevel`, or `pwd`.

The legacy case branches (client path stripping logic) in `lib.sh`'s `project_root()` function become legacy code and can be removed after the transition period.

---

## 5. Installation and Lifecycle Changes

### 5.1 Installation (New)

```bash
# One step: install system code globally (zh branch for Chinese users, main branch for English users)
git clone -b zh https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve

# One step: install global hooks (first time only)
# The init script automatically writes hook configuration to ~/.claude/settings.json
bash ~/.claude/skills/pensieve/.src/scripts/install-hooks.sh

# Per project: initialize user data
cd <your-project>
bash ~/.claude/skills/pensieve/.src/scripts/init-project-data.sh
```

No separate plugin installation. No marketplace. No per-project hook configuration.

### 5.2 Updates (New)

```bash
# Update system code (one operation, effective for all projects)
cd ~/.claude/skills/pensieve
git pull --ff-only

# Per-project health check (optional but recommended)
cd <your-project>
bash ~/.claude/skills/pensieve/.src/scripts/run-doctor.sh --strict
```

### 5.3 Hooks Installation

Hooks are part of the system code, installed to user-level `~/.claude/settings.json`, effective globally with a single installation.

```json
{
  "hooks": {
    "SessionStart": [...],
    "PreToolUse": [...],
    "PostToolUse": [...]
  }
}
```

Hook scripts are located via `$HOME/.claude/skills/pensieve/.src/scripts/` -- no project-level configuration needed. Each hook checks whether the current project has a `.pensieve/` directory before execution; if not, it exits with `exit 0`, ensuring zero interference with projects not using Pensieve.

The `SKILL_ROOT` default value in `run-hook.sh` changes accordingly:

```bash
# Before (project-level)
SKILL_ROOT="$(to_posix_path "${PENSIEVE_SKILL_ROOT:-$PROJECT_ROOT/.claude/skills/pensieve}")"

# After (user-level)
SKILL_ROOT="$(to_posix_path "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}")"
```

### 5.4 Uninstallation

```bash
# Remove global hooks (delete pensieve-related hook entries from ~/.claude/settings.json)
# Remove system code
rm -rf ~/.claude/skills/pensieve

# Remove per-project data (optional, per project)
rm -rf <project>/.pensieve
```

---

## 6. Migration Path

### 6.1 Migration Is a One-Time Operation

The v2 migration is designed as a one-time operation: run `init` once per project and it's done. The system code retains no v1 backward-compatibility burden -- no legacy path detection, no automatic old-format conversion, no dual code paths.

If a project is still using the v1 layout, the manual migration steps are:

```bash
# 1. Move user data out of the skill directory
mkdir -p .pensieve
for dir in maxims decisions knowledge pipelines; do
    if [[ -d .claude/skills/pensieve/$dir ]]; then
        mv .claude/skills/pensieve/$dir .pensieve/$dir
    fi
done

# 2. Move runtime state
if [[ -d .state ]]; then
    mv .state .pensieve/.state
fi

# 3. Delete the old project-level skill clone
rm -rf .claude/skills/pensieve

# 4. Install globally (if not already installed)
if [[ ! -d ~/.claude/skills/pensieve ]]; then
    git clone -b zh https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve
fi

# 5. Re-initialize (generates state.md, creates .pensieve/.gitignore)
bash ~/.claude/skills/pensieve/.src/scripts/init-project-data.sh

# 6. Install global hooks (if not already installed)
bash ~/.claude/skills/pensieve/.src/scripts/install-hooks.sh

# 7. Uninstall the old plugin (if any)
claude plugin uninstall pensieve 2>/dev/null || true
```

---

## 7. Compatibility Notes

### 7.1 Multi-Client Support

The skill root at `~/.claude/skills/pensieve/` is specific to Claude Code. For other clients:

- Codex: `~/.codex/skills/pensieve/` (or symlink)
- Cursor: `~/.cursor/skills/pensieve/` (or symlink)

User data at `<project>/.pensieve/` is client-agnostic -- all clients read the same project knowledge.

### 7.2 PENSIEVE_* Environment Variables

All existing environment variable overrides (`PENSIEVE_SKILL_ROOT`, `PENSIEVE_DATA_ROOT`, `PENSIEVE_STATE_ROOT`, `PENSIEVE_PROJECT_ROOT`) remain in effect. The only change is the default resolution logic when environment variables are not set.

### 7.3 claude-plugin Branch

After v2 release, the `claude-plugin` branch should be archived (not deleted), with its README pointing to the new installation method. Existing users running `claude plugin update pensieve` should see a deprecation notice.

---

## 8. Language Branch Strategy

### 8.1 Maintaining Bilingual Branches

The repository maintains three branches:

- **experimental**: Development branch
- **zh** (Chinese): Chinese release branch
- **main** (English): English release branch

Development flow: experimental development -> merge to zh and main once finalized (text content on the main branch is translated by AI).

```
experimental (dev) ──merge──> zh (Chinese release)
                   ──merge + AI translation──> main (English release)
```

### 8.2 Translation Scope

The differences between the two branches are **limited to text content only** -- code logic is identical. File types that involve translation:

| File Type | Path | Reader |
|-----------|------|--------|
| README | `README.md` | Human users |
| Reference docs | `.src/references/*.md` | LLM |
| Tool specs | `.src/tools/*.md` | LLM |
| Seed templates | `.src/templates/*.md` | LLM + users |
| SKILL.md | `SKILL.md` | LLM (Claude Code skill discovery) |

### 8.3 How v2 Improves the Branch Strategy

The v2 architecture makes bilingual branch maintenance cleaner:

1. **User data is branch-independent**: User data lives in `<project>/.pensieve/`, not inside the git clone directory. Users write data in whatever language they prefer, independent of the installed branch.
2. **Smaller translation surface**: In v1, SKILL.md was dynamically generated per project, containing project-specific content. In v2, SKILL.md is static with a single global copy -- only that one copy needs translation.
3. **No accidental user data overwrites**: In v1, `git pull` ran in the same directory as user data. Although gitignore protected the data, the proximity caused psychological burden. In v2, `git pull` runs in `~/.claude/skills/pensieve/`, physically isolated from project data.

### 8.4 Users Choose a Branch

Select language via the `-b` flag during installation:

```bash
# Chinese users
git clone -b zh https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve

# English users
git clone -b main https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve
```

Switching language:

```bash
cd ~/.claude/skills/pensieve
git checkout zh   # or main
git pull --ff-only
```

Since system code is globally unique and user data is project-level, switching language does not affect any project's user data.

---

## 9. Design Decisions

### 9.1 SKILL.md Is a Tracked Read-Only File

SKILL.md is the skill's interface declaration -- its frontmatter description controls when Claude triggers the skill, and the routing table controls how requests are dispatched to tools. These are written by the skill maintainer, not configured by users. All project-level dynamic content (lifecycle state, knowledge graph) has been split out to `<project>/.pensieve/state.md`.

Therefore: SKILL.md is a **tracked file in the repository**, updated via `git pull` alongside other system code. The init script no longer generates it. Users should not modify it.

### 9.2 Hooks Installed to User-Level `~/.claude/settings.json`

The `claude-plugin` branch and marketplace distribution method are retired. Hook configuration is written to user-level `~/.claude/settings.json` during first installation, effective globally with no per-project configuration needed.

Rationale:

1. **Consistent with skill**: The skill is at user-level, hooks are at user-level -- unified mental model.
2. **Zero-config new projects**: Running `init` on a new project only needs to initialize user data, no hook configuration required.
3. **Graceful degradation**: All hook scripts silently exit (`exit 0`) when a project has not initialized Pensieve, causing zero impact on unrelated projects.
   - `pensieve-session-marker.sh`: exits when `.pensieve/` directory is not found
   - `explore-prehook.sh`: checks whether the project's `state.md` exists; exits if missing (SKILL.md is a global static file, no check needed)
   - `sync-project-skill-graph.sh`: exits when the edited file is not under `USER_DATA_ROOT`
4. **Simple uninstallation**: Remove hook entries from `~/.claude/settings.json` + delete the skill directory.

### 9.3 No Version Pinning

YAGNI. Pensieve is an engineering conventions tool, not a compiler -- its outputs are Markdown text and shell scripts with no API compatibility surface. A single global version, upgraded via `git pull` for all projects, is the core advantage of user-level installation. If breaking changes occur, the existing `schema_version` + `migrate` mechanism handles them. Per-project version pinning would reintroduce "one copy per project" -- the very problem v2 aims to solve.

If issues arise after an upgrade, `git log` to review history and `git checkout <commit>` to roll back to a known-good version. This is native git capability, requiring no additional mechanism.

### 9.4 `.pensieve/.gitignore` Only Excludes `.state/`

User data (maxims, decisions, knowledge, pipelines) should be version-controlled -- this is the core motivation for placing data in `<project>/.pensieve/`. The default `.gitignore` only excludes `.state/` (runtime artifacts: reports, markers, graph snapshots). No fine-grained templates are provided. Users with special needs add their own ignore rules.
