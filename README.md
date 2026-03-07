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

## Upgrading from older versions (< 1.0)

1.0 restructured the installation architecture. If your current version is below 1.0, **do not use `git pull`** — you need a full uninstall and reinstall.

How to tell: if you installed Pensieve via `claude plugin install`, or you cannot find `.claude/skills/pensieve/.src/manifest.json`, you are on an older version.

User data (`maxims/`, `decisions/`, `knowledge/`, `pipelines/`) will be preserved; everything else will be cleaned up:

```bash
# 1. Uninstall Claude plugin and cache
claude plugin uninstall pensieve 2>/dev/null
rm -rf ~/.claude/plugins/cache/kingkongshot-marketplace/pensieve

# 2. Clean skill directory (keep user data only)
cd .claude/skills/pensieve
rm -rf .src agents .git .gitignore SKILL.md LICENSE README.md .state .backup .obsidian temp resource

# 3. Clean other possible legacy skill paths
rm -rf .agents/skills/pensieve

# 4. Reinstall
cd ../../..
git clone -b main https://github.com/kingkongshot/Pensieve.git /tmp/pensieve-new
cp -r /tmp/pensieve-new/{.git,.gitignore,.src,agents,LICENSE,README.md} .claude/skills/pensieve/
rm -rf /tmp/pensieve-new

# 5. Initialize + health check
bash .claude/skills/pensieve/.src/scripts/init-project-data.sh
bash .claude/skills/pensieve/.src/scripts/run-doctor.sh --strict
```

## Installation

Prerequisites: `git`, `bash`, `Python 3.8+`.

```bash
# 1. Install skill
git clone -b main https://github.com/kingkongshot/Pensieve.git .claude/skills/pensieve

# 2. Initialize (create user data directories, seed default content, generate SKILL.md router file)
bash .claude/skills/pensieve/.src/scripts/init-project-data.sh

# 3. Install Claude hooks (required for Claude Code users, skip for other clients)
claude plugin marketplace add kingkongshot/Pensieve#claude-plugin
claude plugin install pensieve@kingkongshot-marketplace --scope project
```

The skill and hooks have different update mechanisms — the skill uses `git pull`, hooks use `claude plugin update` — so they live on two separate branches, each upgrading independently without affecting the other.

## Updating

```bash
cd .claude/skills/pensieve
git pull --ff-only
bash .src/scripts/run-doctor.sh --strict
```

`git pull` only updates system files (`.src/`, `agents/`). User data is protected by `.gitignore` and will not be overwritten. **Do not delete user data directories before updating** — they are your accumulated project memory, and once deleted they are gone.

For complete installation, update, reinstall, and uninstall instructions, see [skill-lifecycle.md](.src/references/skill-lifecycle.md).

## Self-Reinforcing Loop

You don't need to maintain the knowledge base manually — everyday development feeds it automatically:

```
    Develop --> Commit --> Review (pipeline)
     ^                      |
     |   <-- auto-capture <-|
     |                      v
     +-- maxim / decision / knowledge / pipeline
```

- **On commit**: PostToolUse hook automatically triggers experience extraction
- **On review**: Executes per-project pipeline, conclusions flow back as knowledge
- **On retrospective**: Actively request capture, insights are written to the appropriate layer

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
| `migrate` | Clean legacy paths, align seed files | "Clean up old structure" |
| `doctor` | Read-only scan, check structure and formatting | "Check if my data has any issues" |
| `self-improve` | Extract insights from conversations and diffs, write to four-layer knowledge | "Capture what we learned this time" |

For tool boundaries and redirect rules, see [tool-boundaries.md](.src/references/tool-boundaries.md).

<details>
<summary><b>Architecture Details</b></summary>

### Directory Structure

```text
<project>/
├── .claude/skills/pensieve/   # Skill root directory (git clone target)
│   ├── .src/                  # System files (tracked)
│   ├── agents/                # Agent configs (tracked)
│   ├── SKILL.md               # Router file (generated by init, gitignored)
│   ├── maxims/                # User data (gitignored)
│   ├── decisions/             # User data (gitignored)
│   ├── knowledge/             # User data (gitignored)
│   └── pipelines/             # User data (gitignored)
└── .state/                    # Runtime artifacts: reports, markers, graph snapshots
```

`.src/manifest.json` is the anchor for the skill root directory — scripts use it to locate all paths.

### Design Principles

- **Separate system capabilities from user data** — Updates never overwrite your accumulated project knowledge
- **Single source of truth for rules** — Directories, key files, and legacy paths are all defined in `.src/core/schema.json`
- **Confirm before executing** — When scope is unclear, ask first; don't auto-start long-running processes
- **Read specs before writing data** — Before creating any user data, read the format specs in `.src/references/`

</details>

## About the Linus Prompt

Pensieve was originally known for a Linus Torvalds-style system prompt — using "good taste," "never break userspace," and "simplicity obsession" to constrain agent behavior.

That engineering philosophy is still at the core of Pensieve, but it is no longer an isolated prompt. It is now distributed across executable structures: default maxims define hard rules, taste-review knowledge provides review criteria, and review/commit pipelines put those rules into practice. What was once a one-off prompt has become a continuously effective engineering capability.

## License

MIT
