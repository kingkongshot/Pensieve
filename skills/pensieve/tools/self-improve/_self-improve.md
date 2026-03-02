---
description: Automatically persist reusable conclusions into knowledge/decision/maxim/pipeline during commits or retrospectives, writing directly to user data.
---

# Auto Self-Improve

> Tool boundaries: see `<SYSTEM_SKILL_ROOT>/references/tool-boundaries.md` | Shared rules: see `<SYSTEM_SKILL_ROOT>/references/shared-rules.md`

Write experience and patterns into Pensieve's four user data types: `maxim / decision / pipeline / knowledge`.

## Tool Contract

### Use when
- Commit pipeline (`run-when-committing.md`) calls it (auto-trigger)
- Post-loop wrap-up and knowledge capture
- User explicitly requests "capture, record, retrospective, standardize"

### Failure fallback
- Structural issues found (old path parallelism / directory missing / widespread format violations): skip writing, suggest running `doctor`
- Cannot determine classification in one pass: split by three layers (IS -> `knowledge`, WANT -> `decision`, MUST -> `maxim`)

---

## Semantic Layer Assignment

Determine the semantic layer first, then decide which type to write:
1. **knowledge (IS)**: system facts, current state, boundaries, mechanisms
2. **decision (WANT)**: project preferences, strategic trade-offs, target direction
3. **maxim (MUST)**: cross-project hard constraints and bottom lines

The same insight can be split and written into multiple layers. `pipeline` only expresses HOW (execution order and verification loops) and does not replace IS/WANT/MUST.

### Pipeline Creation Criteria
- Same task type has recurred across multiple sessions/loops
- Execution order significantly affects outcome (steps cannot be arbitrarily swapped)
- Each step has a verifiable completion criterion

---

## Core Principles
- **Auto-capture**: execute directly when triggered by pipeline
- **Read before write**: read the corresponding README before creating any file
- **Stable classification**: only use `maxim / decision / pipeline / knowledge`
- **Conclusion-first**: title and first sentence must independently convey the conclusion
- **One maxim per file**: each `maxim` is a standalone file
- **Pipelines only orchestrate**: `pipeline` retains only task orchestration and validation; theory/background goes to external links
- **Goal is to reduce exploration**: capture should make the "symptom-to-locating" path shorter next time

---

## Locating Acceleration Knowledge Model

When a problem requires "exploring the codebase to answer" and the content belongs to IS (fact layer), `knowledge` should cover:
1. **State transitions**: after an action triggers, how data and views change
2. **Symptom -> root cause -> locating**: what phenomenon is seen, where to look, why
3. **Boundaries and ownership**: who has write access, who can only call, how cross-module flows work
4. **Does not exist / removed**: which capabilities are not in the current system, to avoid repeated misjudgment
5. **Anti-patterns and forbidden zones**: paths that look feasible but will fail, and why

### Locating Acceleration Checklist (For Exploration-Type Problems)
- At least 1 "symptom -> root cause -> locating" mapping
- At least 1 "boundaries and ownership" constraint
- At least 1 "anti-pattern / do not do this"
- Provide a verification signal (one of: logs, tests, runtime result, observable behavior)

---

## Phase 1: Extract and Classify

**Goal**: Extract insights from session context + diff and determine classification.

**Actions**:
1. Read session context and `git diff --cached`
2. Extract core insights (can be multiple); determine semantic layer (IS/WANT/MUST); split into multiple writes when multi-layer
3. Determine whether `pipeline` (HOW) is needed: only create when creation criteria are met
4. Path rules:
   - `maxim`: `.claude/skills/pensieve/maxims/{one-sentence-conclusion}.md`
   - `decision`: `.claude/skills/pensieve/decisions/{date}-{conclusion}.md`
   - `pipeline`: `.claude/skills/pensieve/pipelines/run-when-*.md`
   - `knowledge`: `.claude/skills/pensieve/knowledge/{name}/content.md`

---

## Phase 2: Read Spec + Write

**Goal**: Write according to spec and maintain link connectivity.

**Actions**:
1. Read the target README (`<SYSTEM_SKILL_ROOT>/{type}/README.md`); generate content following its format: conclusion-style title + one-line conclusion + core content + semantic links (`<SYSTEM_SKILL_ROOT>/references/shared-rules.md` section: Semantic Link Rules)
2. Type-specific requirements:
   - `decision`: include locating acceleration triad (what to skip asking next time / what to skip searching next time / invalidation conditions)
   - Exploration-type `knowledge`: include locating acceleration checklist items
   - `pipeline`: self-check "have all paragraphs not affecting task orchestration been linked externally?"
3. Write to target path; add back-links in related documents (if needed)
4. Maintain project-level SKILL:
   ```bash
   bash <SYSTEM_SKILL_ROOT>/tools/project-skill/scripts/maintain-project-skill.sh --event self-improve --note "auto-improve: {file1,file2,...}"
   ```
5. Output brief summary (write path + capture type)
