---
description: Refine the Pensieve knowledge base: review entries through a five-question decision process (triage), compress knowledge through abstraction and induction (compress).
---

# Refine Tool

> Tool boundaries: see `.src/references/tool-boundaries.md` | Shared rules: see `.src/references/shared-rules.md`

## Use when

- Session start reminds of due short-term memories
- doctor reports `short_term_due_refine`
- User requests "organize" / "triage" / "deduplicate" / "clean up" / "find connections"
- Periodic knowledge base quality maintenance

---

## Subtask 1: Triage — Five-Question Decision Review

Run the five-question decision on entries one by one. Applies to short-term due items, specified entries, or full-library review.

### Scope

| Scenario | Scan Range |
|---|---|
| Short-term due | Entries under `short-term/` where `created + 7 days < today` (skip entries with `seed` in tags) |
| Specified entries | Files specified by the user |
| Full library | `maxims/` + `decisions/` + `knowledge/` + `pipelines/` + `short-term/` |

### Five-Question Decision

Answer sequentially; stop when a termination condition is met.

| # | Question | No -> | Yes -> |
|---|---|---|---|
| Q1 | If deleted, would we repeat the same mistake or redundant exploration in the future? | **DELETE** | Q2 |
| Q2 | Is it backed by evidence (code, documentation, experiment results)? | **DELETE** | Q3 |
| Q3 | Is it already covered by an existing entry? | Q4 | **DELETE** (merge into existing entry) |
| Q4 | Is the context at the time of writing still valid? | **DELETE** | Q5 |
| Q5 | Does it meet the content specification of the target layer? | Fill gaps or **DELETE** | **KEEP/PROMOTE** |

Q5 specification files:

| type | Specification |
|---|---|
| `maxim` | `.src/references/maxims.md` |
| `decision` | `.src/references/decisions.md` |
| `knowledge` | `.src/references/knowledge.md` |
| `pipeline` | `.src/references/pipelines.md` |

### Execution

- **PROMOTE** (short-term entries): `mv short-term/{type}/file.md {type}/file.md`, change status to `active`
- **KEEP** (long-term entries): No action needed
- **Fill gaps**: Fill in missing content per specification, then KEEP/PROMOTE
- **DELETE**: Delete the file. If Q3 determines duplication, merge valuable content into the existing entry before deleting

---

## Subtask 2: Compress — Compress the Knowledge Base

Review all entries from a holistic perspective, **reducing total entry count while increasing information density** through abstraction and induction.

### Three Compression Techniques

#### A. Upward Abstraction: Multiple entries -> One higher-level entry

When multiple entries exhibit the same pattern, distill a higher-level abstraction that covers them; original entries can be deleted.

> Example: Three knowledge entries separately record "API A must be idempotent", "API B must be idempotent", "API C must be idempotent"
> -> Distill one maxim "All external APIs must be idempotent", delete the three knowledge entries.

#### B. Extract Shared Content: Repeated content -> Independent entry + references

When multiple entries reference the same facts or premises, extract the shared portion as an independent knowledge entry, and change original entries to `[[...]]` references.

> Example: Three decisions all redundantly describe the same authentication flow
> -> Extract as `knowledge/auth-flow/content.md`, change the three decisions to `Based on: [[knowledge/auth-flow/content]]`.

#### C. Eliminate Special Cases: Discover deeper principles that replace surface rules

From a holistic perspective, discover that seemingly different entries are actually special cases of the same deeper principle; write the deeper principle, delete the surface rules.

> Example: One maxim "Don't directly operate the database in handlers" + one decision "Service layer manages transactions uniformly"
> -> They are both special cases of "separation of concerns". Write a deeper maxim, and demote the original entries to `[[...]]` references or delete them.

### Execution

1. Read all entries in long-term directories + short-term, build a global view
2. Read the graph (`.pensieve/.state/pensieve-user-data-graph.md`), understand the link structure
3. Look for compression opportunities (A/B/C techniques)
4. For each compression plan:
   - Describe the entries involved and the compression technique
   - Write the new entry (per target layer specification, via short-term)
   - Run the five-question Q1-Q3 on replaced old entries, delete after confirming they can be removed
   - Preserve `[[...]]` link connectivity

---

## Refresh State

After any write operation, refresh the project state:

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/maintain-project-state.sh" --event sync --note "refine: description"
```
