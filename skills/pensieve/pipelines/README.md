# Pipelines

Executable workflows that define a full loop from input through validation to output.

> Note: Built-in tools were moved to `tools/`. The plugin no longer ships pipelines. Initial pipelines are seeded at install/migration into `.claude/skills/pensieve/pipelines/` and are user-editable.

## Purpose

The goal of a pipeline is to build **verifiable execution loops**, not to pile up information.

In Pensieve, determine the semantic layer first, then decide whether a pipeline is needed:
- `knowledge` = IS (this is how it is)
- `decision` = WANT (I want it this way)
- `maxim` = MUST (it must be this way)
- `pipeline` = HOW (how to execute in order and verify)

Pipelines orchestrate flow -- they do not store knowledge. Background information should be split into other carriers and referenced via links:

- **Knowledge**: external standards, references, checklists
- **Maxims**: cross-scenario principles
- **Decisions**: context-specific choices and rationale
- **External skills/tools**: specialized capabilities and heavy instructions

## Pre-Pipeline Self-Check (Mandatory)

Before writing, ask:

**"Does this content directly change the task's ordering, inputs, steps, or completion criteria?"**

- If "no": the content does not belong in the pipeline body; it must be extracted and referenced via `[[...]]`.
- If "yes": keep it in the pipeline body.

Quick split rules:
1. Theory, principles, long explanations -> `knowledge`
2. Project trade-offs, strategy conclusions -> `decision`
3. Cross-scenario principles -> `maxim`
4. Pipeline retains only: task orchestration + validation loop + key constraints

### When NOT to Write a Pipeline

By default, do not create a new pipeline when:

- The main problem is "slow locating, slow judgment," not "confused step ordering"
- Conclusions are primarily constraints/boundaries/anti-patterns with no fixed steps
- Similar tasks have not yet recurred, and the process is still evolving

These should be written into `knowledge` / `decision` / `maxim` by semantic layer, not directly as a pipeline.

Closed-loop model:

```
Input -> Execute -> Validate -> Output
         ^        |
         +-- Feedback --+
```

## What Makes a Good Pipeline

| Trait | Value (LLM Perspective) |
|-------|------------------------|
| Clear closed loop | Prevents drift; clear when to start/end |
| Uses real signals | Validates via actual output, not "looks right" |
| File-based trail | Traceable; can locate the problem step |
| Testable | Does not depend on "feeling correct" |
| Tool-friendly | Clear which steps should leverage tools to reduce uncertainty |

## Validation Must Be Based on Real Feedback

Anti-pattern: read code -> feels correct -> continue

Correct approach: execute -> get output/logs -> judge based on results

| Validation type | Real feedback source |
|-----------------|----------------------|
| Build | Compiler output, build logs |
| Tests | Test results, coverage |
| Runtime | Application logs, error stacks |
| Integration | API responses, DB state |

Key point: prioritize system feedback; do not rely on model inference.

## Capture Criteria

Core question: **If this workflow is not solidified, which decisions will be repeatedly re-made?**

### Do We Need a New Pipeline?

First ask: can we solve this by composing existing pipelines?

| Situation | Action |
|-----------|--------|
| Existing pipeline combination covers it | Compose/reorder; do not add new |
| Only missing a validation step | Add to an existing pipeline |
| Entirely different execution loop | Create a new pipeline |

Before adding, pass one more check:

- The same task structure has appeared multiple times
- Step ordering cannot be swapped
- Each step can define a verifiable completion criterion

### Signals Worth Capturing

| Signal | Explanation |
|--------|-------------|
| Multiple loops share the same task structure | Steps have stabilized; ready to extract |
| A step is repeatedly missed | Pipeline needed to enforce completeness |
| Execution depends on multiple knowledge sources | Pipeline should unify orchestration |

### Evolution Path

1. First reach a runnable baseline (even if validation is manual)
2. Then tool-ify fragile/repeated steps
3. Finally reorder steps to reduce backtracking

Anti-pattern: pursuing "perfect design" before it has ever run.

## Relationships & Evolution

| Direction | Description |
|-----------|-------------|
| Pipeline <- Knowledge | External standards constrain the flow |
| Pipeline -> Tasks | Pipeline defines the blueprint; tasks are runtime instances |
| Pipeline <-> Decision | Decisions from execution can feed back into the flow |

## Link Rules (Pipeline-Mandatory)

Every pipeline body must include at least one explicit link for tracing sources and impact.

Recommended fields:
- `Based on`: which decisions/knowledge it depends on
- `Leads to`: what outputs or subsequent flows it triggers
- `Related`: adjacent flows or related topics

Hard rule:
- Any long paragraph that does not directly serve task orchestration must be migrated to a linked file.

## Pipeline vs Tasks

| Type | Essence | Focus |
|------|---------|-------|
| Pipeline | Task blueprint + validation loop | "In what order to do what" |
| Tasks | Runtime instances | "Execute this step now" |

Pipelines should directly produce instantiable task templates.

## Writing Guide

### Directory Structure

```
.claude/skills/pensieve/pipelines/
├── run-when-*.md
```

### Naming Convention

Hard rule (mandatory):
- Pipeline filenames must use the trigger-intent style: `run-when-*.md`
- Legacy naming is not preserved for compatibility (e.g. `review.md` must be renamed)

| Pattern | Type | Notes |
|---------|------|-------|
| `run-when-*.md` | user-defined | Filename directly reveals "when to call it" |
| `_*.md` | forbidden | Legacy system naming, no longer used |

### File Template

```markdown
# Pipeline Name

---
id: run-when-xxx
type: pipeline
title: Pipeline Name
status: active
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags: [pensieve, pipeline]
description: [Constrained scenario + cost of skipping + trigger words]. Example: this pipeline must be run in X scenario; skipping causes Y risk. Trigger words: a, b, c.
---

## Signal Quality Rules (Mandatory)

- Only output high-signal results (reproducible, locatable, evidence-backed)
- Candidate issues must be validated before entering final output
- Declare confidence threshold (e.g. >= 80)
- Declare "do not report" items (style preferences, speculative risks, etc.)

## Task Blueprint (Create tasks in order)

### Task 1: Task Name

**Goal**: This task's objective

**Read Inputs**:
1. Required file/path
2. Required file/path

**Steps**:
1. Specific action
2. Specific action

**Done When**: Verifiable completion criteria

---

### Task 2: Task Name

**Goal**: This task's objective

**Read Inputs**:
1. Previous task's output

**Steps**:
1. Specific action
2. **Validate candidate results and filter false positives**

**Done When**: Only high-signal results remain

---

### Task 3: Final Output

**Goal**: Produce actionable results

**Read Inputs**:
1. Preceding task outputs

**Steps**:
1. Output final results sorted by severity
2. Attach evidence to each conclusion (file/line number/rule source)
3. Provide fix priority and next steps

**Done When**: Report is directly actionable

---

## Failure Fallback (Mandatory)

1. Input missing: return missing items and stop; do not force execution.
2. Insufficient evidence: mark "cannot verify" and filter out; do not include in final output.
3. All candidates filtered: explicitly output "no high-signal issues."

## Execution Rules

1. Create execution tasks in 1:1 order with the Task Blueprint; do not merge or skip.
2. Fill missing information within the current task; do not add extra phases.
3. Only persist to knowledge/decision/maxim/pipeline when reusable and evidence-backed.

## Related Files (Optional)

- `path/to/file` -- description
```

### Format Checklist

| Element | Requirement |
|---------|------------|
| Filename | Must be `run-when-*.md`; trigger scenario discernible from filename |
| Required frontmatter | `id/type/title/status/created/updated/tags/description` |
| `description` | In frontmatter; includes trigger words |
| Signal quality rules | Must declare high-signal threshold and "do not report" items |
| No knowledge dump | Long background goes to Knowledge/Maxims/Decisions/Skills |
| Content split | If a paragraph does not affect task orchestration, it must be split out and referenced via `[[...]]` |
| Task Blueprint | Must have explicit `Task 1/2/3...` in order |
| **Goal** | Every task must have one |
| **Read Inputs** | Files/paths must be explicit |
| **Steps** | Numbered, concrete, executable |
| **Done When** | Must be verifiable |
| **CRITICAL** / **DO NOT SKIP** | Strong markers for key steps |
| Failure fallback | Must have explicit fallback handling |
| Links | Body must contain at least one valid link |

## Notes

- Pipelines should be lightweight and executable
- Solve one closed-loop problem at a time; avoid oversized workflows
- When uncertain, start with a minimal runnable version and iterate
