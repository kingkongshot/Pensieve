# Short-Term

`short-term/` is the staging area for new knowledge. Entries created by `self-improve` land here by default.

## Workflow

1. `self-improve` creates an entry -> writes to `short-term/{type}/`
2. Each entry carries a `created` date; it is considered expired after 7 days by default
3. Expired entries trigger reminders via session hook / doctor / commit pipeline
4. The user decides whether to promote (`mv` to the long-term directory) or delete

## Storage location

`short-term/` mirrors the long-term directory structure:

```text
<project>/.pensieve/short-term/
├── maxims/
├── decisions/
├── knowledge/
└── pipelines/
```

File naming follows the same convention as the corresponding long-term directory (e.g. `decisions/{date}-{statement}.md`).

## Link rules

`[[...]]` links must **not** include the `short-term/` prefix:

```markdown
- Based on: [[decisions/2026-03-16-foo]]     ✅
- Based on: [[short-term/decisions/2026-03-16-foo]]  ❌
```

When the graph resolver processes files inside short-term it strips the prefix, sharing node IDs with long-term files.
On promote you only need to `mv` the file -- zero reference updates required.

## TTL rules

- Based on the `created` date + 7 days (schema.json `short_term.default_ttl_days`)
- Used for reminders only; files are never moved or deleted automatically
- Files whose frontmatter tags include `seed` skip the TTL check

## When to skip short-term

- Modifying a file that already exists in a long-term directory: edit it in place
- The user explicitly requests writing directly to a long-term directory
