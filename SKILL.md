---
name: pensieve
description: >-
  Project knowledge base and workflow router.
  knowledge/ caches previously explored file locations, module boundaries, and call chains for direct reuse;
  decisions/maxims are established architectural decisions and coding standards to follow, not re-debate;
  pipelines are reusable workflows.
  Use self-improve after completing tasks to capture new insights.
  Provides five tools: init, upgrade, migrate, doctor, and self-improve.
---

# Pensieve

Route user requests to the correct tool. When in doubt, confirm first.

## Routing
- Init: Initialize the current project's user data directory and populate seed files. Tool spec: `.src/tools/init.md`.
- Upgrade: Refresh Pensieve skill source code in the global git clone. Tool spec: `.src/tools/upgrade.md`.
- Migrate: Structural migration and legacy cleanup. Tool spec: `.src/tools/migrate.md`.
- Doctor: Read-only scan of the current project's user data directory. Tool spec: `.src/tools/doctor.md`.
- Self-Improve: Extract reusable conclusions and write them to user data. Tool spec: `.src/tools/self-improve.md`.
- Graph View: Read `<project-root>/.pensieve/.state/pensieve-user-data-graph.md`.

## Project Data
Project-level user data is stored in `<project-root>/.pensieve/`.
See `.pensieve/state.md` for the current project's lifecycle state; see `.pensieve/.state/pensieve-user-data-graph.md` for the knowledge graph (read on demand).
