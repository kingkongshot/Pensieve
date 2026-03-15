# Four-Layer Memory Architecture Analysis

> Status: Pending decision
> Created: 2026-03-11
> Related: `docs/maxim-and-auto-memory-analysis.md` (deleted, superseded by this document)

---

## 1. Analysis Objective

Evaluate whether the design intent of Pensieve's four-layer semantic model (IS/WANT/MUST/HOW) aligns with execution reality, identify AI misinterpretation risks, and propose directions for improvement.

---

## 2. Current State Overview

| Layer | Semantics | Admission Criteria | Storage | Seed Template |
|---|---|---|---|---|
| Knowledge | IS (facts) | Would repeatedly slow execution if not written down | `knowledge/{name}/content.md` | taste-review |
| Decision | WANT (choices) | Removing it makes future mistakes more likely | `decisions/{date}-{statement}.md` | None |
| Maxim | MUST (principles) | Cross-project + cross-language + regression risk + one sentence | `maxims/{conclusion}.md` | 4 philosophical principles |
| Pipeline | HOW (processes) | Recurring + non-interchangeable order + verifiable | `pipelines/run-when-*.md` | reviewing-code, committing |

---

## 3. Layer-by-Layer Evaluation

### 3.1 Knowledge -- Clearest

- Clean definition: IS semantics + "would repeatedly slow execution if not written down" admission criteria
- "Don't turn knowledge into an opinion collection -- it must be verifiable or traceable" is an effective guardrail
- **Low risk**. The only concern is that the suggested list for exploratory knowledge (state transitions, symptom -> root cause -> localization...) may cause AI to over-formalize

### 3.2 Decision -- Most Successful

- Admission threshold is reasonable, with a clear boundary from knowledge (facts vs choices)
- **"Exploration offloading" is the most valuable design in the entire system** -- forcing documentation of "what to ask less next time, what to look up less, when it expires"
- **Medium-low risk**. Format requirements are somewhat heavy; AI may fill in low-value content to satisfy the format, but this is acceptable

### 3.3 Maxim -- Most Problematic

See Section 4 below for details.

### 3.4 Pipeline -- Well-Crafted but Narrow Use Case

- Three admission criteria are clear and reasonable; `run-when-*` naming directly implies trigger conditions
- The two seed pipelines are high-quality examples
- **Medium risk**. Format requirements are very heavy (8 frontmatter fields + signal detection + Task Blueprint + failure fallback + links); high creation cost contradicts "when uncertain, start with a minimum viable version"

---

## 4. Core Problems with the Maxim Layer

### 4.1 Design Intent Contradicts Storage Location

| Dimension | Documentation Claims | Reality |
|---|---|---|
| Scope | "Cross-project, cross-language" | Stored in `<project>/.pensieve/maxims/` -- a project-level directory |
| Admission criteria | All four must be met simultaneously | Seed templates satisfy them, but users can almost never add new ones in practice |
| Relationship with decision | "Only valid in this project -> that's a decision" | Many MUST-level rules are project-specific (e.g., "all APIs in this project must be idempotent") |
| self-improve classification | AI must judge maxim vs decision | The high threshold causes AI to almost always choose decision |

### 4.2 Three Specific Misleading Points

**Misleading Point 1: Threshold too high, rendering the layer effectively unused**

"Must still hold when switching languages" restricts maxims to the purely philosophical level. Rules like "all mutations must go through the command bus" are excluded despite being project-level hard rules -- exactly the kind of thing that most needs to be marked as MUST.

**Misleading Point 2: Seed templates set the wrong abstraction level**

All four seed maxims are Linus Torvalds-style universal philosophy. AI consequently believes maxims should be at this abstraction level and won't write concrete, actionable project principles.

**Misleading Point 3: Overlaps with CLAUDE.md functionality**

CLAUDE.md already contains the same Linus philosophy (good taste, never break userspace, pragmatism, simplicity above all). The seed maxims repeat the same ideas. When AI sees identical directives in two places, it becomes uncertain about the priority relationship.

---

## 5. Cross-Layer Interaction Issues

### 5.1 Classification Ambiguity During self-improve

AI is forced to judge simultaneously along two dimensions: semantic level (IS/WANT/MUST/HOW) and scope (project-level/cross-project). Examples:

- "Error codes in this project must use enums" -- by definition a decision (project-specific), but semantically a MUST
- "React useEffect cleanup order is X" -- is this knowledge, or should it be ignored (AI can look it up next time)

### 5.2 Link Requirements Increase Write Friction

Decision and pipeline require at least one `[[...]]` link. self-improve happens at the end of a task, when AI may not know which existing node to link to. Possible outcomes:
- Link points to a nonexistent node (doctor reports unresolved)
- Meaningless link added just to satisfy the requirement
- self-improve is skipped entirely

### 5.3 No Write-Time Validation

self-improve is the only write entry point, but there is no write-time validation. Format/link/frontmatter compliance is entirely deferred to doctor for after-the-fact checking. Write quality depends entirely on AI's understanding of the reference spec.

---

## 6. Implicit Assumptions in the Execution Mechanism

1. **Asymmetric hook injection**: state.md is injected into the Explore/Plan agent, but they have no write capability; actual writes happen in the main conversation, which may not have read state.md
2. **One-time seed template seeding**: Upgrades don't overwrite seeds; seed quality permanently defines the user's first impression of each layer
3. **Python dependency**: All core logic (doctor/migrate/maintain-project-state) requires Python 3.8+

---

## 7. Pending Decision: The Future of the Maxim Layer

### Option A: Redefine as Project-Level MUST

- Remove cross-project/cross-language requirements
- Change admission criteria to: "Hard rules that this project has repeatedly proven must be followed"
- Distinguish from decision as MUST vs SHOULD
- Rewrite `maxims.md` and seed templates
- **Cost**: Requires redesigning seed template content

### Option B: Merge into the Decision Layer

- Remove the maxim layer
- Add `priority: must | should` field to decision
- Move seed philosophy into CLAUDE.md or knowledge
- **Cost**: Decision layer gets "heavier," but removes one concept and simplifies self-improve classification

### Option C: Keep as-is but Fix the Description

- Acknowledge that maxims are "pre-installed coding philosophy" with no expectation for user additions
- Remove the self-improve write path to maxim
- Reduces maintenance cost but also reduces the layer's value
- **Cost**: Maxim becomes a read-only layer, its presence further diminished

### Decision Input

The core question to answer: **Do Pensieve users actually need an independent MUST layer, or is decision + priority field sufficient?**

If the answer is "yes," go with Option A. If the answer is "no," go with Option B. Option C is a compromise that does not solve the fundamental problem.
