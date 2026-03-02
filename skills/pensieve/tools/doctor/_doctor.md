---
description: Read-only check tool that outputs PASS/PASS_WITH_WARNINGS/FAIL with a MUST_FIX/SHOULD_FIX/INFO evidence list based on README specs. Does not modify user data files. Trigger words: doctor, health check, check.
---
# Doctor Flow

> Tool boundaries: `<SYSTEM_SKILL_ROOT>/references/tool-boundaries.md` | Shared rules: `<SYSTEM_SKILL_ROOT>/references/shared-rules.md` | Directory layout: `<SYSTEM_SKILL_ROOT>/references/directory-layout.md`

### Use when
- User requests health check, compliance check, or post-migration validation
- Need to produce `MUST_FIX/SHOULD_FIX` findings with evidence
- Need to confirm old-path parallels, naming conflicts, or non-project-level legacy residue

### Failure fallback
- Spec file unreadable: abort judgment, mark "unable to determine"
- Quick-check script failed: do not issue final conclusion, report the blocker first
- Graph read failed: do not issue final conclusion, fix graph step first

Derive check items from specs rather than hardcoding.

---
Spec sources (see `shared-rules.md` section on spec sources): `<SYSTEM_SKILL_ROOT>/maxims/README.md`, `decisions/README.md`, `pipelines/README.md`, `knowledge/README.md`, `tools/doctor/migrations/README.md`, `tools/upgrade/_upgrade.md` (upgrade flow only).

Check scope: project-level user data (latest per `migrations/README.md`) and legacy path candidates (deprecated list). Plugin config: `~/.claude/settings.json`, `<project>/.claude/settings.json`.

## Severity Rules
**MUST_FIX**:
1. Old and new parallel dual sources exist
2. Violates README `must / required / hard rule / at least one`
3. `decision`/`pipeline` missing link fields or all links are invalid
4. User data root directory or critical category directories missing
5. `pipeline` substitutes task orchestration with large knowledge dumps without decomposing into linked references
6. `pipeline` filename does not use the `run-when-*.md` pattern
7. User data directory exists but missing initial seeds
8. `enabledPlugins` retains both old and new keys simultaneously, or missing the new key
9. Found plugin-level/user-level pensieve skill copies not converged to project-level
10. Found standalone graph files (`_pensieve-graph*.md`/`pensieve-graph*.md`/`graph*.md`)
11. Found legacy spec README copies in project-level subdirectories
12. `~/.claude/projects/<project>/memory/MEMORY.md` missing Pensieve guidance block or not aligned with system SKILL.md `description`

**SHOULD_FIX**: recommended/prefer rules not met but do not block the main flow. Includes `decision` missing "Exploration Shortcut" section or missing "What to ask less next time"/"What to look up less next time"/"Invalidation conditions".

**INFO**: observations, statistics, or tradeoff items requiring user decision.

**Status determination** (hard rule): `MUST_FIX > 0` -> `FAIL` (-> `upgrade`) | `MUST_FIX = 0` and `SHOULD_FIX + INFO > 0` -> `PASS_WITH_WARNINGS` (-> `self-improve`) | all zero -> `PASS` (-> `none`)

**Execution principle (simplified)**: Prefer running `run-doctor.sh` and use its summary/report as the sole basis for judgment; do not add manual inference.

---
## Phase 1: Read specs and generate check matrix
**Goal**: Extract all check items from spec files and build an internal check matrix.
**Actions**:
1. Read all "spec source" files, extract directory structure, naming, required sections/fields, link rules
2. Extract latest/deprecated lists from `migrations/README.md`
3. Structure checks are implemented by `scan-structure.sh`

## Phase 2: Scan files and validate
**Goal**: Run shared structure scan and incorporate results into the judgment.
**Actions**:
0. Prefer the all-in-one script (recommended):
```bash
bash <SYSTEM_SKILL_ROOT>/tools/doctor/scripts/run-doctor.sh --strict
```
> This script serially executes structure scan, frontmatter check, graph generation, report summary, and SKILL/MEMORY maintenance. If using this script, skip manual steps 1-3 below.
1. Run:
```bash
bash <SYSTEM_SKILL_ROOT>/tools/doctor/scripts/scan-structure.sh --output .state/pensieve-structure-scan.json
```
2. Read `status`, `summary.must_fix_count`/`should_fix_count`, `flags.*`, `findings[]`
3. If `must_fix_count > 0`, conclusion is at least `FAIL`, recommended action prioritizes `upgrade`

## Phase 2.2: Frontmatter quick check
**Goal**: Cover frontmatter format validation and incorporate into judgment.
**Actions**:
1. Run:
```bash
bash <SYSTEM_SKILL_ROOT>/tools/doctor/scripts/check-frontmatter.sh --format text
```
2. Read files scanned, MUST_FIX/SHOULD_FIX counts and details
3. Frontmatter syntax errors/missing/required field missing/invalid values -> `MUST_FIX`; pipeline naming violations (`FM-301/FM-302`) -> `MUST_FIX`; `decision` exploration shortcut missing (`FM-401~FM-404`) -> `SHOULD_FIX`

## Phase 2.5: Generate graph and verify links
**Goal**: Verify knowledge network link connectivity.
**Actions**:
1. Run:
```bash
bash <SYSTEM_SKILL_ROOT>/tools/upgrade/scripts/generate-user-data-graph.sh
```
2. Read note count/link count/resolved/unresolved, sample at least first 5 unresolved links
3. When file scan conflicts with graph, use the more conservative judgment

## Phase 3: Output fixed-format report
**Goal**: Output using fixed template; every finding must include its rule source.
**Actions**:
1. Template:

```markdown
# Pensieve Doctor Report

## 0) Header
- Check time: {YYYY-MM-DD HH:mm:ss}
- Project root: `{absolute-path}`
- Data root: `{absolute-path}/.claude/skills/pensieve`

## 1) Executive Summary (read this first)
- Overall status: {PASS | PASS_WITH_WARNINGS | FAIL}
- MUST_FIX: {n}
- SHOULD_FIX: {n}
- INFO: {n}
- Recommended next step: {`upgrade` | `self-improve` | `none`}

## 1.5) Graph Summary (pre-conclusion evidence)
- Graph file: `{<project>/.claude/skills/pensieve/SKILL.md#Graph}`
- Notes scanned: {n}
- Links found: {n}
- Links resolved: {n}
- Links unresolved: {n}
- Observation: {one sentence}

## 2) Priority Fixes (MUST_FIX, by priority)
1. [D-001] {one-line issue}
File: `{path}`
Rule source: `{rule source}`
Fix: {one-line fix suggestion}

## 3) Recommended Fixes (SHOULD_FIX)
1. [D-101] {one-line issue} (`{path}`)

## 4) Migration & Structure Check
- Legacy paths found: {yes/no}
- Old/new parallel sources found: {yes/no}
- Non-project-level skill root found: {yes/no}
- Standalone graph files found: {yes/no}
- Missing critical directories: {yes/no}
- MEMORY.md missing/drifted: {yes/no}
- Suggested action: {`upgrade` or `none`}

## 5) Three-Step Action Plan
1. {step 1 (specific, actionable)}
2. {step 2}
3. {step 3}

## 6) Rule Hit Details (Appendix)
| ID | Severity | Category | File/Path | Rule Source | Issue | Fix |
|---|---|---|---|---|---|---|

## 7) Graph Broken Links (Appendix)
| Source File | Unresolved Link | Note |
|---|---|---|

## 8) Frontmatter Quick Check Results (Appendix)
| File | Level | Code | Issue |
|---|---|---|---|
```

2. When `FAIL` and migration-related, `next step` prioritizes `upgrade`; `decision`/`pipeline` broken links are at least `MUST_FIX`
3. Doctor does not modify user data files; only allowed to auto-maintain `SKILL.md` and auto memory

## Phase 3.5: Maintain project-level SKILL + MEMORY
**Goal**: Sync SKILL and MEMORY after report output.
**Actions**:
1. Run:
```bash
bash <SYSTEM_SKILL_ROOT>/tools/project-skill/scripts/maintain-project-skill.sh --event doctor --note "doctor summary: status={PASS|PASS_WITH_WARNINGS|FAIL}, must_fix={n}, should_fix={n}"
```
2. Only maintain `.claude/skills/pensieve/SKILL.md` and `~/.claude/projects/<project>/memory/MEMORY.md` guidance block

## Phase 4: Auto Memory alignment check
**Goal**: Confirm auto memory contains Pensieve guidance block; missing/drifted is MUST_FIX and cannot be downgraded.
**Actions**:
1. Read `<SYSTEM_SKILL_ROOT>/SKILL.md` frontmatter `description` and project `MEMORY.md`
2. Check that guidance block contains a description consistent with system `description` and a "prefer invoking `pensieve` skill" guidance line
3. Missing or drifted: mark `MUST_FIX`, execute alignment write (only maintain guidance block, do not alter other content)
