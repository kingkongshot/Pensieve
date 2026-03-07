# Directory Layout

Pensieve has three fixed anchor points:

- **skill root directory**: system files from the git clone
- **user data directories**: local knowledge data that coexists alongside the skill root but is ignored by git
- **project root directory**: hidden runtime state

The recommended installation method is to clone the `main` branch directly into `.claude/skills/pensieve/` within the project. The default layout is as follows:

```text
<skill-root>/
├── SKILL.md                # generated routing file (generated, gitignored)
├── .src/                   # system scripts, templates, specs (tracked)
├── agents/                 # agent configuration (tracked)
├── maxims/                 # user data (ignored)
├── decisions/              # user data (ignored)
├── knowledge/              # user data (ignored)
└── pipelines/              # user data (ignored)

<project-root>/
└── .state/                 # runtime state, reports, markers, caches, graph snapshots
```

Notes:

- `.src/`, `agents/` are tracked system files, updated with `git pull`
- The root-level `SKILL.md` is a generated file at a fixed location, refreshed by `init/doctor/migrate/upgrade/self-improve/sync`, and ignored by `.gitignore`
- `maxims/decisions/knowledge/pipelines` are user data, created locally after initialization, and ignored by the root `.gitignore`
- `.state/` defaults to the project root directory, used for storing doctor reports, migration backups, session markers, auto-generated graphs, and other runtime artifacts
- `maintain-project-skill.sh` rewrites the root-level `SKILL.md`
- `generate-user-data-graph.sh` / `doctor` outputs the graph to `.state/pensieve-user-data-graph.md` by default
- As long as a directory contains `.src/manifest.json`, it is the current system skill root directory; `SKILL.md` can be generated afterwards

## Legacy paths within the project

Within the project workspace, the following paths are considered legacy remnants and should be cleaned up by `migrate`:

- `skills/pensieve/`
- `.claude/pensieve/`
- Standalone graph files: `_pensieve-graph*.md`, `pensieve-graph*.md`, `graph*.md`
