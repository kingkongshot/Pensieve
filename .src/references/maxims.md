# Maxims

Cross-project, cross-problem, long-term MUST-level rules.

## Criteria for inclusion

Only entries that satisfy all of the following belong in `maxims/`:

1. Still holds when switching projects
2. Still holds when switching languages
3. Violating it significantly increases regression risk
4. Can be stated in one sentence

If it is only valid in the current project, it is not a `maxim` — it is a `decision`.

## Storage location

```text
<skill-root>/maxims/
└── {one-sentence-conclusion}.md
```

One file per maxim.
During initialization, default entries are seeded from `.src/templates/maxims/`; afterwards users can freely modify them, and upgrades will not overwrite.

## Recommended format

```markdown
# {One-line Conclusion}

## One-line Conclusion
> {One actionable sentence}

## Guidance
- Rule 1
- Rule 2

## Boundaries
- When it does not apply

## Context Links (recommended)
- Based on: [[related decision or knowledge]]
- Leads to: [[related pipeline or decision]]
- Related: [[related maxim]]
```

## Rules

- `maxim` should remain scarce — do not stuff one-off preferences in here
- Links are recommended, but when sources exist they should be clearly stated
- `Based on` can only point to `knowledge/decision`
- `Leads to` can only point to `pipeline/decision`
- `Related` is suitable for pointing to parallel `maxim` entries
