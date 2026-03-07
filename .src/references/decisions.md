# Decisions

Record the choices actively made in the current project, and why they were made.

## When to write a decision

Worth recording if any of the following apply:

1. Removing it would make future mistakes more likely
2. Someone reading it three months later would avoid many detours
3. It clarifies module boundaries, responsibilities, or trade-offs

If the content describes an objective fact, write it in `knowledge/`.
If the content is a cross-project hard rule, promote it to `maxims/`.

## Storage location

| Stage | Location | Description |
|---|---|---|
| Finalized | `decisions/` | Long-term project decisions |

Formal file naming:

```text
<skill-root>/decisions/{date}-{statement}.md
```

## Mandatory requirements

- Each `decision` must have at least one valid `[[...]]` link
- Must clearly state `Context` and `Alternatives Considered`
- Must include "What to ask less next time / What to look up less next time / Invalidation condition"

## Recommended format

```markdown
# {Decision title}

## One-line Conclusion
> {Final choice}

## Context Links
- Based on: [[prerequisite knowledge or decision]]
- Leads to: [[subsequent process or decision]]
- Related: [[parallel topic]]

## Context

## Problem

## Alternatives Considered
- Option A: why not used
- Option B: why not used

## Decision

## Consequence

## Exploration Reduction
- What to ask less next time:
- What to look up less next time:
- Invalidation condition:
```
