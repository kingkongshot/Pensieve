<div align="center">

# Pensieve

**Project-level structured memory for Claude Code.**

[![GitHub Stars](https://img.shields.io/github/stars/kingkongshot/Pensieve?color=ffcb47&labelColor=black&style=flat-square)](https://github.com/kingkongshot/Pensieve/stargazers)
[![License](https://img.shields.io/badge/license-MIT-white?labelColor=black&style=flat-square)](LICENSE)

[中文 README](https://github.com/mamajiaa/pensieve-claude-plugin/blob/zh/README.md)

</div>

## The Problem

Claude Code starts every conversation from scratch.

It doesn't remember your project conventions, doesn't know why you chose approach A last time, and won't learn from past failures. You'll fall into the same traps over and over again.

Pensieve gives Claude Code structured memory. Every review, every commit, every complex task automatically accumulates project knowledge. **The longer you use it, the better it understands your project.**

## Without Pensieve vs With Pensieve

| Without | With |
|---|---|
| Re-explain project conventions every time | Conventions stored as maxims, loaded automatically |
| Complex tasks spiral out of control halfway through | Loop auto-decomposes, isolates execution, verifies each step |
| Code review standards depend on your mood that day | Review standards hardened into executable pipelines |
| Same mistake from last week happens again this week | Lessons learned auto-distilled, skipped next time |
| Forget why a technical decision was made three months later | Decision records include context and mitigation checklists |

## What Happens After You Start

**Day 1** — Install → Initialize → Auto-scan project hotspot modules → Output code-taste baseline report

**Week 1** — Use `loop` to tackle complex dev tasks. Claude decomposes work according to your maxims, sub-agents execute in isolation, and lessons are auto-distilled at wrap-up.

**Month 1** — Your project has accumulated its own conventions, technical decision records, review workflows, and reference knowledge. Every commit and review silently enriches this knowledge base.

**After that** — Claude understands your project better and better. When new team members join, Pensieve serves as a living project handbook.

## 30-Second Start

```bash
# 1. Add the marketplace source
claude plugin marketplace add kingkongshot/Pensieve#main

# 2. Install
claude plugin install pensieve@kingkongshot-marketplace --scope user

# 3. Restart Claude Code, then say:
```

> Initialize pensieve for me

That's it. Then say **"use loop to finish this task"** to kick off your first task.

[Installation Guide](docs/installation.md) · [Update Guide](docs/update.md) · [Uninstall](docs/installation.md#uninstall)

## Five Built-in Tools

Ready to use after install, no extra configuration needed. Just describe what you want in plain language.

### `init` — Initialize a Project

Scans your git history, identifies hotspot modules, and runs a code-taste baseline analysis. Creates the project-level knowledge directory (maxims / decisions / knowledge / pipelines) and seeds default review and commit pipelines. **Analyze-only, no writes** — you decide which findings are worth keeping.
Must run `doctor` once after completion for structure and format verification.

> "Initialize pensieve for me"

### `loop` — Decompose and Execute Complex Tasks

Breaks a large requirement into sub-tasks, confirms scope before starting. The main window orchestrates while sub-agents execute each task in isolation, keeping contexts clean. At wrap-up, automatically asks whether to distill lessons learned. Small tasks skip loop and run directly.

> "Use loop to finish this task"

### `self-improve` — Distill Lessons Learned

Extracts insights from conversations, diffs, and loop executions. Classifies them as maxim (hard rule), decision (technical decision), knowledge (reference fact), or pipeline (executable workflow), writes to the corresponding location, and updates the knowledge graph. Also auto-triggers on commit.

> "Distill lessons from this session"

### `doctor` — Health Check

Read-only scan of all user data: frontmatter format, semantic link integrity, directory structure compliance. Outputs a fixed-format PASS / PASS_WITH_WARNINGS / FAIL report with a three-step action plan. Does not modify user data files by default; only auto-maintains the `SKILL.md` and Claude auto memory (`~/.claude/projects/<project>/memory/MEMORY.md`) Pensieve guidance blocks.

> "Check if there are any data issues"

### `upgrade` — Version Upgrade and Migration

Highest priority. Runs scripted version comparison and pull, and cleans up legacy version residue (old plugin keys / old plugin names / old directories). After upgrade completes, guides you to manually run doctor for verification.

> "Upgrade pensieve"

## Four-Layer Knowledge Model

Pensieve organizes project knowledge into four layers, each solving a different problem:

| Layer | Type | Answers What | Example |
|---|---|---|---|
| **MUST** | maxim | What must never be violated? | "State changes must be atomic" |
| **WANT** | decision | Why was this approach chosen? | "Chose JWT over sessions because..." |
| **HOW** | pipeline | How to execute this workflow? | "During review, check in this order" |
| **IS** | knowledge | What are the facts? | "This module's concurrency model is..." |

Layers are linked via `[[based-on]]` `[[leads-to]]` `[[related]]` semantic links, forming a knowledge graph.

## Self-Reinforcing Loop

This is Pensieve's core mechanism — you don't manually maintain the knowledge base; **your daily development workflow feeds it automatically**:

```
    develop (loop) ──→ commit ──→ review (pipeline)
         ↑                            │
         │    ← auto-distill lessons ←│
         │                            ↓
         └── maxim / decision / knowledge / pipeline
```

- **On commit**: PostToolUse hook auto-triggers lesson extraction
- **On review**: Executes per project pipeline, conclusions flow back as knowledge
- **On loop wrap-up**: Proactively asks whether to distill lessons from this round

You just write code. The knowledge base grows on its own.

<details>
<summary><b>Architecture Details</b> (for the curious)</summary>

### Bound to Claude Code Native Capabilities

| Mechanism | Purpose |
|---|---|
| **Skills** | Route intent to the right tool — no guessing, no auto-execution |
| **Hooks** | PostToolUse syncs the knowledge graph immediately after file edits |
| **Task** | Claude's native task system drives loop rhythm |
| **Agent** | Main window orchestrates, sub-agents execute individual tasks in isolation |

Reusing native capabilities means: no extra wrappers, and when Claude Code upgrades, Pensieve benefits automatically.

### Design Principles

- **System capabilities separated from user data** — plugin updates never overwrite your accumulated project knowledge
- **Confirm before executing** — when scope is unclear, confirm first; never auto-start
- **Read before write** — read format specs before creating any user data
- **Confidence requirements** — pipeline outputs require ≥80% confidence to report; no guesswork in output

### Directory Structure

```
.claude/skills/pensieve/          ← your project knowledge (user data, never overwritten by plugin)
├── maxims/                       ← hard rules
├── decisions/                    ← technical decision records
├── knowledge/                    ← reference knowledge
├── pipelines/                    ← executable workflows
├── loop/                         ← historical loop execution records
└── SKILL.md                      ← auto-maintained routing + graph
```

</details>

## For Users Looking for the Linus Prompt

The methodology you know has been upgraded: Linus-style principles are now default maxims, and review capabilities are delivered as pipeline + knowledge. What you get is no longer a prompt — it's an engineering-grade package: prompting, workflow, and execution mechanics delivered together.

## Community

<img src="./QRCode.png" alt="WeChat group QR code" width="200">

## License

MIT
