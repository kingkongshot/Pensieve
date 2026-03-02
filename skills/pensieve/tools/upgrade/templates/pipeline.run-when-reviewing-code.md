---
id: run-when-reviewing-code
type: pipeline
title: Code Review Pipeline
status: active
created: 2026-02-11
updated: 2026-02-28
tags: [pensieve, pipeline, review]
name: run-when-reviewing-code
description: Code review stage flow -- first explore commit history and code hotspots, extract capturable candidates, then produce high-signal taste review conclusions following a fixed Task Blueprint. Trigger words: review, code review, check code.

stages: [tasks]
gate: auto
---

# Code Review Pipeline

This pipeline only handles task orchestration. Review standards and deeper rationale are kept in Knowledge to avoid duplication here.

**Knowledge reference**: `.claude/skills/pensieve/knowledge/taste-review/content.md`

**Context links (at least one)**:
- Based on: [[knowledge/taste-review/content]]
- Leads to: [[decisions/2026-xx-xx-review-policy]]
- Related: [[decisions/2026-xx-xx-review-strategy]]

---

## Signal Quality Rules

The value of a review report depends on its signal-to-noise ratio -- too many low-signal issues drown out what truly matters.

- Only report high-signal issues: reproducible, locatable, affecting correctness/stability/user-visible behavior.
- Candidate issues must be validated before entering the final report, because unverified speculation wastes fix time.
- Default confidence threshold: `>= 80` to enter the final report.
- Do not report pure style suggestions, subjective preferences, or risk items that rely on guesswork.

---

## Task Blueprint (Create tasks in order)

### Task 1: Baseline Exploration (Commit History + Actual Code)

**Goal**: Identify hotspots and capturable candidates first to avoid blind review

**Read Inputs**:
1. `git log` (default: last 30 commits; can be overridden by user-specified scope)
2. Actual code (prioritize recently high-churn files)
3. `.claude/skills/pensieve/knowledge/taste-review/content.md`

**Steps**:
1. Summarize high-frequency files/modules and main change types from recent commits
2. Read the corresponding code; identify complexity hotspots and areas with unclear boundaries
3. Output two lists:
   - Review file list (prioritized)
   - Capturable candidate list (annotated with suggested type: `knowledge/decision/maxim/pipeline`, each with evidence)

**Done When**: Actionable review scope + capturable candidate list obtained (both evidence-backed)

---

### Task 2: Prepare Review Context

**Goal**: Clarify review boundaries to avoid missed coverage

**Read Inputs**:
1. User-specified files / commits / PR scope (if any)
2. Task 1 output: review file list and candidate information
3. `.claude/skills/pensieve/knowledge/taste-review/content.md`

**Steps**:
1. Merge user scope with Task 1 findings; determine final review scope
2. Identify technical language, business constraints, and risk points
3. Finalize the review file list (prioritized)

**Done When**: Scope is clear, with a finalized review file list

---

### Task 3: Per-File Review with Evidence

**Goal**: Produce a candidate issue list (with evidence and confidence scores)

**Read Inputs**:
1. Finalized review file list from Task 2
2. `.claude/skills/pensieve/knowledge/taste-review/content.md`

**Steps**:
1. Apply the review checklist to each file (theory and rationale are in Knowledge; do not duplicate here)
2. Record only "possibly real" candidate issues, each with a confidence score (0-100)
3. Annotate each candidate issue with precise code location and evidence
4. Record user-visible behavior change risk (if any)

**Done When**: Candidate issue list obtained (with confidence, evidence, and locations)

---

### Task 4: Validate Candidates and Filter False Positives

**Goal**: Retain only high-signal, verifiable issues

**Read Inputs**:
1. Candidate issue list from Task 3
2. Corresponding code context and rule rationale

**Steps**:
1. Validate each candidate issue for real reproducibility
2. Update final confidence for each issue; remove items `< 80`
3. Remove issues with insufficient evidence, unclear scope, or reliance on guesswork
4. Produce the "validated issue list"

**Done When**: High-signal issue list obtained (each locatable, explainable, confidence >= 80)

---

### Task 5: Produce Actionable Review Report

**Goal**: Output directly actionable fix suggestions with priority

**Read Inputs**:
1. Validated issue list from Task 4

**Steps**:
1. Summarize key issues by severity (CRITICAL -> WARNING)
2. Provide concrete fix suggestions or rewrite direction for each issue
3. Clearly state user-visible behavior changes and regression risks
4. If no issues found, explicitly output "no high-signal issues"

**Done When**: Report contains only validated issues with clear fix ordering

---

### Task 6: Capture Reusable Conclusions (Optional)

**Goal**: Persist reusable conclusions into the existing four categories

**Read Inputs**:
1. Review report from Task 5

**Steps**:
1. If the conclusion is a project choice, capture as `decision`
2. If the conclusion is a general external method, capture as `knowledge`
3. Add `Based on/Leads to/Related` links in captured entries (at least one, if it is a decision)
4. If no reusable conclusions, explicitly record "no new captures"

**Done When**: Capture result is explicit (written or explicitly skipped)

---

## Failure Fallback

Each anomalous scenario has a corresponding handling approach to avoid producing misleading conclusions when information is insufficient.

1. Cannot retrieve commit history (non-Git project or no history): mark `SKIPPED` and continue from Task 2 (review based on existing code only).
2. Review scope unclear: return missing information and stop; do not enter Task 3 -- reviewing with unclear scope easily leads to drift.
3. Cannot validate a candidate issue: mark "cannot verify" and filter out; do not include in the final report.
4. All candidates filtered: output "no high-signal issues." Padding the report with low-quality suggestions undermines its credibility.

## Execution Rules (For loop use)

1. When this pipeline is triggered, create tasks in order: Task 1 -> Task 2 -> Task 3 -> Task 4 -> Task 5 -> Task 6.
2. Default 1:1 mapping; do not merge or skip tasks.
3. If information is missing, fill it within the current task; do not add extra phases.
