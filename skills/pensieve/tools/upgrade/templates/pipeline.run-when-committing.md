---
id: run-when-committing
type: pipeline
title: Commit Pipeline
status: active
created: 2026-02-28
updated: 2026-02-28
tags: [pensieve, pipeline, commit, self-improve]
name: run-when-committing
description: Mandatory commit-stage flow -- first determine whether there are capturable insights; if so, auto-capture via self-improve, then perform atomic commits. Trigger words: commit, git commit.

stages: [tasks]
gate: auto
---

# Commit Pipeline

Automatically extract insights from session context + diff before committing, capture them, then execute atomic commits. No user confirmation required throughout.

**Self-improve reference**: `<SYSTEM_SKILL_ROOT>/tools/self-improve/_self-improve.md`

**Context links (at least one)**:
- Based on: [[knowledge/taste-review/content]]
- Related: [[decisions]]

---

## Signal Quality Rules

The value of capture lies in reuse next time; evidence-free guesses would mislead future decisions.

- Only capture insights that are "reusable and evidence-backed"; unverifiable guesses do not enter the knowledge base.
- Classification follows the semantic layer: IS -> `knowledge`, WANT -> `decision`, MUST -> `maxim`.
- Assign by semantics, not by "knowledge-first" default -- incorrect classification leads to mismatched constraint strength (writing something that should be MUST as knowledge makes it easy to ignore later).

---

## Task Blueprint (Create tasks in order)

### Task 1: Determine Whether to Capture -- Check if Capturable Insights Exist

**Goal**: Quickly determine if this commit has experience worth capturing; if not, skip directly to Task 3

**Read Inputs**:
1. `git diff --cached` (changes about to be committed)
2. Current session context

**Steps**:
1. Run `git diff --cached --stat` to understand the change scope
2. Review the current session for any of the following signals (any one triggers capture):
   - Identified a bug root cause (debugging session)
   - Made an architectural or design decision (considered multiple options)
   - Discovered a new pattern or anti-pattern
   - Exploration produced a "symptom -> root cause -> locating" mapping
   - Clarified boundaries, ownership, or constraints
   - Discovered a capability that does not exist / has been removed from the system
3. If none of the above signals exist (purely mechanical changes: formatting, renaming, dependency upgrades, simple fixes), mark "skip capture" and jump directly to Task 3

**Done When**: Clear determination of "capture needed" or "skip capture" with a one-sentence rationale

---

### Task 2: Auto-Capture -- Extract Insights and Write

**Goal**: Extract insights from session context + diff and write to user data without asking the user

**Read Inputs**:
1. Task 1 determination (if "skip", skip this Task)
2. `git diff --cached`
3. Current session context
4. `<SYSTEM_SKILL_ROOT>/tools/self-improve/_self-improve.md`

**Steps**:
1. Read `_self-improve.md` and execute per its Phase 1 (Extract and Classify) + Phase 2 (Read Spec + Write)
2. Extract core insights from the session (can be multiple)
3. For each insight, determine the semantic layer and classify (IS->knowledge, WANT->decision, MUST->maxim; multiple layers can be written simultaneously when needed)
4. Read the target type's README and generate content per spec
5. Type-specific requirements:
   - `decision`: include "exploration reduction triad" (what to skip asking / what to skip searching / invalidation conditions)
   - Exploration-type `knowledge`: include (state transitions / symptom->root cause->locating / boundaries and ownership / anti-patterns / verification signals)
   - `pipeline`: must meet creation criteria (recurrence + non-swappable order + verifiable)
6. Write to target path; add related links
7. Run project-level SKILL maintenance:
   ```
   bash <SYSTEM_SKILL_ROOT>/tools/project-skill/scripts/maintain-project-skill.sh --event self-improve --note "auto-improve: {files}"
   ```
8. Output brief summary (write path + capture type)

**DO NOT**: Do not ask for user confirmation, do not present drafts for approval -- write directly

**Done When**: Insights written to user data (or explicitly determined that no capture is needed); project-level `SKILL.md` synchronized

---

### Task 3: Atomic Commit

**Goal**: Execute atomic git commits

**Read Inputs**:
1. `git diff --cached`
2. User's commit intent (commit message or context)

**Steps**:
1. Analyze staged changes and cluster by change reason
2. If multiple independent change groups exist, commit them separately (one atomic commit per group)
3. Commit message conventions:
   - Title: imperative mood, <50 characters, specific
   - Body: explain "why" rather than "what"
4. Execute `git commit`

**Done When**: All staged changes committed; each commit is independent and revertible

---

## Failure Fallback

1. `git diff --cached` is empty: skip Task 2/Task 3; output "no staged changes, nothing to commit."
2. Capture step fails: record the blocking reason and skip capture; continue with Task 3; append "suggest running `doctor`" at the end.
3. Project-level SKILL maintenance fails: preserve already-captured content; report the failed command and retry suggestion; do not roll back written files.

## Execution Rules (For loop use)

1. When this pipeline is triggered, execute in order: Task 1 -> Task 2 -> Task 3.
2. When Task 1 determines "skip capture," jump directly to Task 3.
3. No user confirmation throughout (both self-improve and commit execute automatically).
4. If user data structure anomalies are detected (directory missing / format corruption), skip capture and only execute commit; suggest running `doctor` afterward.
