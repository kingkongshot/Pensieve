# Pensieve adapter for pi

This subtree adapts Pensieve to [pi](https://github.com/mariozechner/pi-coding-agent)
without forking the core. It is opt-in: Claude Code users see no change.

## What's here

```
pi/
├── README.md                          ← this file
├── install.sh                         ← idempotent installer
├── extensions/
│   └── pensieve-context/              ← Layer 2: knowledge graph injection
│       ├── package.json
│       └── index.ts
└── skills/
    └── pensieve-wand/                 ← knowledge retrieval specialist
        └── SKILL.md
```

> **Auto-sediment** (formerly Layer 3) moved to [pi-sediment](https://github.com/alfadb/pi-sediment) — a standalone pi package that writes to both Pensieve and gbrain.

## What this gives you

| Layer | Goal | Implementation |
|---|---|---|
| **1. Skill (free)** | Six tools (init / upgrade / migrate / doctor / self-improve / refine), four-layer memory model, project data dir | The unmodified `SKILL.md` + `.src/` already work via pi's [Agent Skills](https://agentskills.io) support. Just place the repo at `~/.pi/agent/skills/pensieve/`. |
| **2. Knowledge graph injection** | Tell the LLM there is a project memory and when to read it; keep the graph fresh after edits | `pi/extensions/pensieve-context/index.ts` — appends a small navigation card to the system prompt and bridges pi's `tool_result` event to Pensieve's `sync-project-skill-graph.sh`. |
| **pensieve-wand skill** | Structured knowledge retrieval with System 1/System 2 decision model and cognitive budget | `pi/skills/pensieve-wand/SKILL.md` — pi-native adaptation of the Claude Code subagent. Invoke via `/skill:pensieve-wand`. |

## Install

The recommended path is to add this repo as a submodule under `~/.pi`:

```bash
cd ~/.pi
git submodule add -b pi \
  https://github.com/kingkongshot/Pensieve.git agent/skills/pensieve
git commit -am "add pensieve submodule"

bash agent/skills/pensieve/pi/install.sh
```

The installer:
1. Verifies the skill is present.
2. Writes `pi/skills` and `pi/extensions` paths into `~/.pi/agent/settings.json`.
3. Cleans up legacy symlinks from older versions.
4. If `cwd` is a real project (not the dotfiles repo itself), runs
   `init-project-data.sh` with `PENSIEVE_HARNESS=pi`.

If you already have a Pensieve checkout somewhere else (e.g. `~/.claude/skills/pensieve`),
point the installer at it:

```bash
PENSIEVE_SKILL_PATH=~/.claude/skills/pensieve bash pi/install.sh --no-init-project
```

The extension picks up that path automatically (priority order: `$PENSIEVE_SKILL_ROOT`
env > `~/.pi/agent/skills/pensieve` > `~/.claude/skills/pensieve`).

## Verify it works

```bash
cd <some project that has .pensieve/>
pi -p --no-tools \
  "Without using tools: what do you know about Pensieve memory in this project?"
```

You should get an answer that mentions counts of `maxims/`, `decisions/`,
`knowledge/`, `pipelines/` and the location of the mermaid graph.

## How the graph stays fresh

`pensieve-context` listens to pi's `tool_result` event. When the LLM uses
`edit` or `write` on a file inside `<cwd>/.pensieve/`, the extension launches
`.src/scripts/sync-project-skill-graph.sh` in the background — the same
script Claude Code triggers via its `PostToolUse` hook. Output is dropped;
graph staleness is recoverable, so we don't bother surfacing failures.

## Design notes

- **Single source of truth**. All real logic lives in `.src/scripts/*.sh` and
  is shared between Claude Code and pi. The pi adapter is intentionally a
  thin event router (~150 LOC of TypeScript).
- **Minimum upstream change**. The only modification to the original
  Pensieve code is a 6-line `PENSIEVE_HARNESS` guard in
  `init-project-data.sh` so non-Claude-Code harnesses don't touch
  `~/.claude/settings.json`.
- **Environment variable injection**. On `session_start`, the extension sets
  `PENSIEVE_SKILL_ROOT`, `PENSIEVE_PROJECT_ROOT`, `PENSIEVE_HARNESS=pi`,
  and (when `.pensieve/` exists) `PENSIEVE_DATA_ROOT` + `PENSIEVE_STATE_ROOT`
  on `process.env`. All subsequent `bash` tool calls inherit these, so
  Pensieve scripts work without manual env-var boilerplate.
- **Ranked goals**: P1 = knowledge graph context injection ✅ (this layer).
  Auto-sediment moved to [pi-sediment](https://github.com/alfadb/pi-sediment).
  Pure core Pensieve usage requires neither.
- **No global state pollution**. Disabling pi's auto-discovery (`--no-extensions`)
  cleanly removes the navigation card and the graph-sync hook; the skill
  itself keeps working because it's a static markdown asset.
