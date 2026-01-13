# Codex CLI Reference

## Prompt Design Guide

### Structure of a Good Prompt

```
[Task Verb] + [Target Scope] + [Specific Requirements] + [Output Format] + [Constraints]
```

**Example breakdown**:

```
Review src/auth/                              # Task verb + target scope
for SQL injection risks.                       # Specific requirements
List each vulnerability                        # Output format
with file:line, code snippet, and fix.        # Output details
Do not modify any files.                       # Constraints
```

### Verb Selection Guide

| Verb | Meaning | Use Case |
|---|---|---|
| `analyze` | Analyze and report | Read-only understanding |
| `review` | Review and evaluate | Code review |
| `find` | Find and list | Search and locate |
| `explain` | Explain and describe | Documentation/understanding |
| `refactor` | Restructure code | Structure improvement |
| `fix` | Fix issues | Bug fixing |
| `implement` | Implement feature | New feature development |
| `add` | Add content | Incremental development |
| `migrate` | Migrate/convert | Upgrade/conversion |
| `optimize` | Optimize performance | Performance tuning |

### Output Format Control

**Markdown report**:
```
codex exec "... Output as markdown with ## headings for each category."
```

**JSON structured**:
```
codex exec "... Output as JSON array: [{file, line, issue, severity}]"
```

**Plain text list**:
```
codex exec "... Output as numbered list, one issue per line."
```

**Table format**:
```
codex exec "... Output as markdown table with columns: File | Line | Issue | Fix"
```

### Scope Limiting Techniques

**Directory scoping**:
```
codex exec --cd src/auth "..."                 # Work directory scoping
codex exec "analyze only files in src/utils/"  # Prompt scoping
```

**File type filtering**:
```
codex exec "review only *.ts files, ignore *.test.ts"
```

**Depth limiting**:
```
codex exec "analyze top-level architecture, do not dive into details"
```

**Exclusion scoping**:
```
codex exec "refactor all components except shared/legacy/"
```

### Parallel Prompt Design

**Rule 1: Consistent structure**

All parallel tasks use the same prompt structure, only replacing variable parts:

```bash
# Good: Consistent structure
codex exec "analyze src/auth for security. Output JSON." &
codex exec "analyze src/api for security. Output JSON." &
codex exec "analyze src/db for security. Output JSON." &

# Bad: Inconsistent structure, hard to aggregate
codex exec "check auth security" &
codex exec "find api vulnerabilities and list them" &
codex exec "security audit for database layer, markdown format" &
```

**Rule 2: Unified output format**

```bash
FORMAT="Output as JSON: {category, items: [{file, line, description}]}"
codex exec "review code quality. $FORMAT" &
codex exec "review security. $FORMAT" &
codex exec "review performance. $FORMAT" &
```

**Rule 3: Clear task boundaries**

```bash
# Good: Clear boundaries, no overlap
codex exec "review authentication logic in src/auth/" &
codex exec "review authorization logic in src/authz/" &
codex exec "review session management in src/session/" &

# Bad: Blurred boundaries, possible duplication
codex exec "review security" &
codex exec "find vulnerabilities" &
codex exec "check for security issues" &
```

### Common Prompt Anti-patterns

| Anti-pattern | Problem | Fix |
|---|---|---|
| Too broad | "improve code" | Be specific about aspect |
| No output format | "find bugs" | Add output format requirement |
| Implicit expectations | "review code" | Specify what to check |
| Negative instructions | "don't be verbose" | Use "be concise" instead |
| Mixed goals | "fix bugs and add tests and refactor" | Split into separate tasks |

## Complete Command-line Parameters

### codex exec

| Parameter | Short | Description |
|---|---|---|
| `--model` | `-m` | Specify model (o3, o4-mini, gpt-5.1, gpt-5.1-codex-max) |
| `--full-auto` | | Allow file editing (workspace-write sandbox) |
| `--sandbox` | | Sandbox mode: `read-only`, `workspace-write`, `danger-full-access` |
| `--json` | | JSON Lines output mode |
| `--output-last-message` | `-o` | Output final message to file or stdout |
| `--output-schema` | | Use JSON Schema for structured output |
| `--cd` | `-C` | Specify working directory |
| `--add-dir` | | Add extra writable directory |
| `--skip-git-repo-check` | | Skip Git repository check |
| `--profile` | | Use configuration profile |
| `--ask-for-approval` | `-a` | Approval strategy |
| `--image` | `-i` | Attach image files (comma-separated) |

## Sandbox Modes Explained

### read-only (default)

- Can read any file
- Cannot write files
- Cannot access network

```
codex exec "analyze this code"
```

### workspace-write

- Can read/write files in working directory
- Can read/write $TMPDIR and /tmp
- .git/ directory is read-only
- Cannot access network

```
codex exec --full-auto "fix the bug"
# Equivalent to:
codex exec --sandbox workspace-write "fix the bug"
```

### danger-full-access

- Full disk access
- Full network access
- **Use with caution**

```
codex exec --sandbox danger-full-access "install deps and run tests"
```

## Approval Strategies

| Strategy | Description |
|---|---|
| `untrusted` | Untrusted commands require approval |
| `on-failure` | Request approval on failure retry |
| `on-request` | Model decides when to request approval |
| `never` | Never request approval (exec default) |

## Troubleshooting and Best Practices

### Best Practices

**1. Analyze before executing**
- First run: read-only analysis to understand scope
- Based on analysis results, decide parallelization strategy
- Then execute with appropriate sandbox mode

**2. Progressive permission escalation**
- First verify plan with read-only mode
- "explain how you would fix this bug"
- Confirm plan, then execute with --full-auto
- "fix the bug as explained"

**3. Result verification**
- Parallel execution: run parallel tasks
- Then verify results with read-only analysis
- "verify that all new tests pass"

**4. Conflict prevention**

When writing, ensure:
- Different instances operate on different files
- Or use `--cd` to isolate working directories
- Or use serial execution

## Integration with Claude Code

### Division of Responsibilities

| Role | Responsibilities |
|---|---|
| **Claude Code** | Planning, orchestration, review, precise editing |
| **Codex** | Batch execution, automation, test running |

### Model Selection Guide

| Model | Characteristics | Recommended Use |
|---|---|---|
| `gpt-5.1-codex-max` | Balanced default | General tasks |
| `o3` | Strong reasoning | Complex algorithms, architecture |
| `o4-mini` | Fast | Simple tasks, quick iterations |
| `gpt-5.1` | General purpose | Code generation, refactoring |
| `gpt-5.1-codex` | Code optimization | Programming tasks |
