<div align="center">

# Pensieve

**A continuously growing project memory for AI agents.**

[![GitHub Stars](https://img.shields.io/github/stars/kingkongshot/Pensieve?color=ffcb47&labelColor=black&style=flat-square)](https://github.com/kingkongshot/Pensieve/stargazers)
[![License](https://img.shields.io/badge/license-MIT-white?labelColor=black&style=flat-square)](LICENSE)

[中文 README](https://github.com/kingkongshot/Pensieve/blob/zh/README.md)

</div>

## Without Pensieve vs With Pensieve

| Without | With |
|---|---|
| Re-explain project conventions every time | Conventions stored as maxims, loaded automatically |
| Code review standards depend on mood | Review standards codified as executable pipelines |
| Repeat last week's mistakes this week | Lessons learned are captured automatically, skipped next time |
| Forget the reasoning behind a design three months later | Decisions record context and alternatives |
| Re-read docs to locate module boundaries every time | Knowledge caches exploration results for direct reuse |

## Installation

Prerequisites: `git`, `bash`, `Python 3.8+`.

> **Multi-client note**: The examples below use the Claude Code path `~/.claude/skills/pensieve`. For other clients, substitute the corresponding path:
> | Client | Install path |
> |--------|----------|
> | Claude Code | `~/.claude/skills/pensieve` |
> | Cursor | `~/.cursor/skills/pensieve` |
> | Generic Agent | `~/.agents/skills/pensieve` |

```bash
# 1. Install system code globally (one-time, shared by all projects)
git clone -b main https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve

# 2. Install global hooks (Claude Code only, one-time)
#    Other clients skip this step — hooks are a Claude Code-specific feature
bash ~/.claude/skills/pensieve/.src/scripts/install-hooks.sh

# 3. Initialize user data in your project
cd <your-project>
bash ~/.claude/skills/pensieve/.src/scripts/init-project-data.sh
```

System code is installed once globally at `~/.claude/skills/pensieve/`, while user data is stored per project at `<project>/.pensieve/`. Ten projects share the same system code, each maintaining its own independent project knowledge.

### AI Agent Auto-Install Reference

When a user asks an AI agent to install Pensieve, the agent should follow this decision flow:

**Step 1: Check global installation status**

```bash
# Check if already installed
if [[ -d ~/.claude/skills/pensieve/.src ]]; then
    echo "Pensieve is already installed globally, skipping clone"
else
    # Check if ~/.claude is a git repo (some users sync ~/.claude config with git)
    if git -C ~/.claude rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        # ~/.claude is a git repo — install as submodule
        git -C ~/.claude submodule add -b main https://github.com/kingkongshot/Pensieve.git skills/pensieve
    else
        git clone -b main https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve
    fi
    # Hooks are a Claude Code-specific feature; other clients skip this step
    bash ~/.claude/skills/pensieve/.src/scripts/install-hooks.sh
fi
```

**Step 2: Determine whether to run project initialization**

```bash
# If the current directory is ~/.claude, do not auto-initialize project data
# (unless the user explicitly states they are developing ~/.claude itself as a project)
CURRENT_DIR="$(pwd)"
CLAUDE_DIR="$(cd ~/.claude 2>/dev/null && pwd)"
if [[ "$CURRENT_DIR" == "$CLAUDE_DIR" ]]; then
    echo "Current directory is ~/.claude, skipping project initialization. If you need Pensieve here, please confirm explicitly."
    exit 0
fi
```

**Step 3: Check for legacy data and initialize**

```bash
# Check if the current project has legacy user data
# Criteria: a legacy directory contains maxims/decisions/knowledge/pipelines subdirectories
# Note: under ~/.claude, skills/pensieve is the v2 install location, but if it contains
# user data subdirectories (maxims/, etc.), that indicates v1 project-level install remnants
# that still need migration
HAS_LEGACY=0
for legacy_dir in .claude/skills/pensieve .agents/skills/pensieve skills/pensieve .claude/pensieve; do
    if [[ -d "$legacy_dir" ]] && [[ -d "$legacy_dir/maxims" || -d "$legacy_dir/decisions" || -d "$legacy_dir/knowledge" || -d "$legacy_dir/pipelines" ]]; then
        HAS_LEGACY=1
        break
    fi
done

if [[ "$HAS_LEGACY" -eq 1 ]]; then
    # Legacy data found — ask user whether to migrate
    echo "Legacy Pensieve user data detected. Migrate to v2?"
    # After user confirms:
    bash ~/.claude/skills/pensieve/.src/scripts/init-project-data.sh
    bash ~/.claude/skills/pensieve/.src/scripts/run-migrate.sh
    bash ~/.claude/skills/pensieve/.src/scripts/run-doctor.sh --strict
elif [[ -d .pensieve ]]; then
    echo "Pensieve is already initialized in the current project"
else
    bash ~/.claude/skills/pensieve/.src/scripts/init-project-data.sh
fi
```

> **Key takeaway**: Check global installation first -> determine whether `~/.claude` is a git repo to decide clone vs. submodule -> skip project initialization for the `~/.claude` directory -> detect legacy data to decide init vs. migrate.

## Updating

```bash
# Update system code (one operation, takes effect for all projects)
cd ~/.claude/skills/pensieve
git pull --ff-only || { git fetch origin && git reset --hard "origin/$(git rev-parse --abbrev-ref HEAD)"; }

# Run a health check in your project (optional but recommended)
cd <your-project>
bash ~/.claude/skills/pensieve/.src/scripts/run-doctor.sh --strict
```

`git pull --ff-only` handles normal updates. If the remote branch was force-pushed (e.g., after a squash and republish), ff-only will fail, and `fetch + reset` will sync your local copy to the latest remote state. This is safe -- the skill directory only contains tracked system files; user data lives in `<project>/.pensieve/` and will not be overwritten.

For complete installation, update, reinstall, and uninstall instructions, see [skill-lifecycle.md](.src/references/skill-lifecycle.md).

## Upgrading from an Older Version

If your Pensieve was installed at the project level (code in `<project>/.claude/skills/pensieve/`), or installed via `claude plugin install`, you need to migrate to the v2 architecture:

```bash
# 1. Install system code globally (if not already installed)
if [[ ! -d ~/.claude/skills/pensieve ]]; then
    # Check if ~/.claude is a git repo
    if git -C ~/.claude rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C ~/.claude submodule add -b main https://github.com/kingkongshot/Pensieve.git skills/pensieve
    else
        git clone -b main https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve
    fi
fi

# 2. Install global hooks (Claude Code only)
#    Other clients skip this step — hooks are a Claude Code-specific feature
bash ~/.claude/skills/pensieve/.src/scripts/install-hooks.sh

# 3. Run migration in each project
cd <your-project>
bash ~/.claude/skills/pensieve/.src/scripts/init-project-data.sh
bash ~/.claude/skills/pensieve/.src/scripts/run-migrate.sh
bash ~/.claude/skills/pensieve/.src/scripts/run-doctor.sh --strict

# 4. Uninstall the old plugin (if any)
claude plugin uninstall pensieve 2>/dev/null || true
```

`run-migrate.sh` automatically moves user data (`maxims/`, `decisions/`, `knowledge/`, `pipelines/`) from the old path into `<project>/.pensieve/`, moves runtime state from `<project>/.state/` into `<project>/.pensieve/.state/`, cleans up old graph files and README copies, and then removes the legacy directory.

## Self-Reinforcing Loop

You don't need to maintain the knowledge base manually — everyday development feeds it automatically:

```
    Develop --> Commit --> Review (pipeline)
     ^                      |
     |   <-- auto-capture <-|
     |                      v
     +-- maxim / decision / knowledge / pipeline
```

- **While editing**: The PostToolUse hook automatically syncs the state.md knowledge graph after Write/Edit (Claude Code only; other clients need to trigger `self-improve` manually)
- **While reviewing**: Executes per-project pipelines, with conclusions fed back as knowledge
- **While reflecting**: Proactively request capture; insights are written to the appropriate layer

You just write code — the knowledge base grows on its own.

## Four-Layer Knowledge Model

| Layer | Type | What it answers | Cross-project? |
|---|---|---|---|
| **MUST** | maxim | What must never be violated? | Yes — holds across projects and languages |
| **WANT** | decision | Why was this approach chosen? | No — deliberate trade-offs for the current project |
| **HOW** | pipeline | How should this process run? | Depends |
| **IS** | knowledge | What are the current facts? | No — verifiable system facts |

Layers are connected through three types of semantic links: `based-on / leads-to / related`.

For detailed specifications, see [maxims.md](.src/references/maxims.md), [decisions.md](.src/references/decisions.md), [knowledge.md](.src/references/knowledge.md), and [pipelines.md](.src/references/pipelines.md) under `.src/references/`.

## Five Tools

| Tool | What it does | Trigger example |
|---|---|---|
| `init` | Create data directories, seed default content | "Initialize pensieve for me" |
| `upgrade` | Refresh skill source code | "Upgrade pensieve" |
| `migrate` | Migrate legacy data, align seed files | "Migrate to v2" |
| `doctor` | Read-only scan, check structure and formatting | "Check if the data has any issues" |
| `self-improve` | Extract insights from conversations and diffs, write to four knowledge layers | "Capture what we learned this time" |

For tool boundaries and redirect rules, see [tool-boundaries.md](.src/references/tool-boundaries.md).

<details>
<summary><b>Architecture Details</b></summary>

### Directory Structure

```text
~/.claude/skills/pensieve/          # User-level (single global installation)
├── SKILL.md                        #   Static routing file (tracked)
├── .src/                           #   System code, templates, references, core engine
│   ├── core/
│   ├── scripts/
│   ├── templates/
│   ├── references/
│   └── tools/
└── agents/                         #   Agent configurations

<project>/.pensieve/                # Project-level (per-project, can be version-controlled)
├── maxims/                         #   Engineering principles
├── decisions/                      #   Architecture decisions
├── knowledge/                      #   Cached exploration results
├── pipelines/                      #   Reusable workflows
├── state.md                        #   Dynamic: lifecycle state + knowledge graph
└── .state/                         #   Runtime artifacts (gitignored)
```

`.src/manifest.json` is the anchor for the skill root directory — scripts use it to locate all paths.

### Design Principles

- **Physical separation of system code and user data** -- System code lives in `~/.claude/skills/pensieve/`, user data in `<project>/.pensieve/`; a `git pull` to update the system can never touch project data
- **Single source of truth for rules** -- Directories, key files, and migration paths are all defined by `.src/core/schema.json`
- **Confirm before executing** -- When scope is unclear, ask first; never auto-start long-running processes
- **Read the spec before writing data** -- Always read the format specifications in `.src/references/` before creating any user data

</details>

## About the Linus Prompt

Pensieve was originally known for a Linus Torvalds-style system prompt — using "good taste," "never break userspace," and "simplicity obsession" to constrain agent behavior.

That engineering philosophy is still at the core of Pensieve, but it is no longer an isolated prompt. It is now distributed across executable structures: default maxims define hard rules, taste-review knowledge provides review criteria, and review/commit pipelines put those rules into practice. What was once a one-off prompt has become a continuously effective engineering capability.

## License

MIT
