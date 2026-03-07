# Pipelines

A pipeline is responsible for one thing only: clearly defining task sequence, verification loops, and failure fallbacks.

## When to write a pipeline

Create a new one only when all three conditions are met:

1. The same type of task has already recurred
2. Step order is non-interchangeable
3. Each step has a verifiable completion criterion

If the problem is mainly "scattered knowledge" or "unclear boundaries," write a `knowledge/decision` first — do not over-create pipelines.

## Storage location

```text
<skill-root>/pipelines/
└── run-when-*.md
```

During initialization or migration, the system seeds default pipelines from `.src/templates/`.
Afterwards, files in `pipelines/` are real user-side data.

## Mandatory rules

- Filename must be `run-when-*.md`
- Pipeline body should only contain task orchestration, verification loops, and failure fallbacks
- Any lengthy background, rationale, or constraints should be split into `knowledge/decision/maxim` and linked back
- Each pipeline must have at least one `[[...]]` context link

## Recommended skeleton

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
description: [trigger scenario, cost of skipping, trigger keywords]
---

## Signal Rules
- Only keep reproducible, locatable, evidence-backed results

## Task Blueprint
### Task 1
- Goal
- Input
- Execution steps
- Completion criteria

### Task 2
...

## Failure Fallback
1. Stop when input is missing
2. Filter when evidence is insufficient
3. Explicitly state when no high-signal results exist
```
| Mandatory frontmatter | `id/type/title/status/created/updated/tags/description` |
| `description` | Located in frontmatter, contains trigger keywords |
| Signal Rules | Must declare high-signal threshold and non-reportable items |
| No knowledge stacking | Lengthy background goes into Knowledge/Maxims/Decisions/Skills |
| Content splitting | If a paragraph does not affect task orchestration, it must be split out and replaced with a `[[...]]` reference |
| Task Blueprint | Must explicitly use `Task 1/2/3...` ordering |
| **Goal** | Required for each task |
| **Input** | Files/paths must be clearly specified |
| **Execution steps** | Numbered, specific, actionable |
| **Completion criteria** | Must be verifiable |
| **CRITICAL** / **DO NOT SKIP** | Strong prompt for critical steps |
| Failure Fallback | Must have explicit fallback |
| Links | Body must contain at least one valid link |

## Notes

- Pipelines should be lightweight and executable
- Each pipeline solves one closed-loop problem only — avoid oversized processes
- When uncertain, start with a minimal runnable version, then iterate
