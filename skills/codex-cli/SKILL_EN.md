| name | description |
|---|---|
| codex-cli | Orchestrate OpenAI Codex CLI for parallel task execution. As orchestrator, analyze tasks, inject context, manage sessions, and coordinate parallel instances. Use when delegating coding tasks to Codex or running multi-agent workflows. (user) |

# Codex CLI Orchestrator

**Role**: Claude Code is the orchestrator, Codex is the executor.

**Core Value**: Through intelligent orchestration, make Codex faster, more accurate, and more token-efficient.

## Quick Decision Flow

```
Receive Task
│
├─ 1. Can pre-inject context? ──→ Yes → Collect code/errors, inject prompt
│
├─ 2. Related to existing session? ────→ Yes → Reuse session (resume)
│
├─ 3. Can split into independent sub-tasks? → Yes → Execute in parallel
│
└─ 4. None of the above ───────────→ Create new single session and execute serially
```

## Three Optimization Strategies

### Strategy 1: Context Pre-Injection (Most Important)

**Principle**: Claude Code first collects relevant information, injects it into the prompt, allowing Codex to skip exploration.

| Injection Content | Command Example |
|---|---|
| File paths | `codex exec "Fix bug in: src/auth/login.ts, src/utils/token.ts"` |
| Error messages | `codex exec "Fix: $(npm run build 2>&1 \| grep error)"` |
| Code snippets | `codex exec "Optimize: $(cat src/slow.ts)"` |
| Dependencies | `codex exec "Refactor A, deps: B→C→D"` |

**Template**:

```
codex exec "[Task]

## Files: $FILES
## Errors: $ERRORS
## Code:
\`\`\`
$CODE
\`\`\`

Constraints: Only modify the files above, start directly."
```

### Strategy 2: Session Reuse

**Principle**: Reuse existing sessions for related tasks, inherit context, avoid repeated analysis.

```bash
# First execution
codex exec "analyze src/auth for issues"

# Reuse session (pass prompt via stdin to avoid CLI bug)
echo "fix the issues you found" | codex exec resume --last

# Or use --full-auto to allow modifications
echo "fix the issues" | codex exec resume --last --full-auto
```

> **Note**: `codex exec resume --last "prompt"` has a CLI parsing bug. Must use stdin to pass prompt.

**When to reuse**:

- Analyze then fix → Reuse (know what was found)
- Implement then test → Reuse (know what was implemented)
- Test then fix → Reuse (know what failed)

### Strategy 3: Parallel Execution

**Principle**: Execute well-isolated tasks simultaneously to save total time.

**Can parallelize**:

- Different directories/modules
- Different analysis dimensions (security/performance/quality)
- Read-only operations

**Must serialize**:

- Writing to same file
- Dependent on previous results

```bash
# Parallel execution
codex exec "analyze auth" > auth.txt 2>&1 &
codex exec "analyze api" > api.txt 2>&1 &
wait

# Parallel + reuse
codex exec resume $AUTH_SID --full-auto "fix" &
codex exec resume $API_SID --full-auto "fix" &
wait
```

## Prompt Design Key Points

### Structure Formula

```
[Verb] + [Scope] + [Requirements] + [Output Format] + [Constraints]
```

### Verb Selection

| Read-only | Write |
|---|---|
| analyze, review, find, explain | fix, refactor, implement, add |

### Good vs. Bad

| Bad | Good |
|---|---|
| `review code` | `review src/auth for SQL injection, XSS. Output: markdown, severity levels.` |
| `find bugs` | `find bugs in src/utils. Output: file:line, description, fix suggestion.` |
| `improve code` | `refactor Button.tsx to hooks. Preserve props. Don't modify others.` |

### Keep consistency when parallelizing

```bash
# Consistent structure, unified output format, easy to aggregate
codex exec "analyze src/auth for security. Output JSON." &
codex exec "analyze src/api for security. Output JSON." &
codex exec "analyze src/db for security. Output JSON." &
wait
```

## Comprehensive Examples

### Example 1: Full pipeline optimization (pre-inject + parallel + reuse)

```bash
# Phase 1: Claude Code collects information
ERRORS=$(npm run lint 2>&1)
AUTH_ERR=$(echo "$ERRORS" | grep "src/auth")
API_ERR=$(echo "$ERRORS" | grep "src/api")

# Phase 2: Parallel execution with pre-injected errors
codex exec --json --full-auto "Fix lint errors: $AUTH_ERR Only modify src/auth/" > auth.jsonl 2>&1 &
codex exec --json --full-auto "Fix lint errors: $API_ERR Only modify src/api/" > api.jsonl 2>&1 &
wait

# Phase 3: If needed, reuse session
AUTH_SID=$(grep -o '"thread_id":"[^"]*"' auth.jsonl | head -1 | cut -d'"' -f4)
codex exec resume $AUTH_SID "verify fixes and run tests"
```

### Example 2: Iterative development (single session, multi-turn reuse)

```bash
# Round 1: Analyze
codex exec "analyze codebase, plan auth implementation"

# Round 2-4: Reuse same session, inherit full context (via stdin)
echo "implement as planned" | codex exec resume --last --full-auto
echo "add tests" | codex exec resume --last --full-auto
echo "fix failures" | codex exec resume --last --full-auto
```

### Example 3: Code review (4-way parallel, each reuses for fixes)

```bash
# Parallel review
codex exec --json "audit security" > sec.jsonl &
codex exec --json "audit performance" > perf.jsonl &
codex exec --json "audit quality" > qual.jsonl &
codex exec --json "audit practices" > prac.jsonl &
wait

# Extract session IDs
SEC=$(grep -o '"thread_id":"[^"]*"' sec.jsonl | head -1 | cut -d'"' -f4)
PERF=$(grep -o '"thread_id":"[^"]*"' perf.jsonl | head -1 | cut -d'"' -f4)
# ...

# Parallel fixes, each reuses
codex exec resume $SEC --full-auto "fix security issues" &
codex exec resume $PERF --full-auto "fix performance issues" &
# ...
wait
```

## Quick Reference

### Commands

```bash
codex exec "prompt"                              # Read-only
codex exec --full-auto "prompt"                  # Can write
codex exec --cd /path "prompt"                   # Specify directory
codex exec --json "prompt"                       # JSON output
echo "prompt" | codex exec resume --last         # Reuse latest session
echo "prompt" | codex exec resume --last --full-auto  # Reuse + can write
```

### Background parallel

```bash
codex exec "task1" > out1.txt 2>&1 &
codex exec "task2" > out2.txt 2>&1 &
wait
```

### Extract session ID

```bash
SID=$(grep -o '"thread_id":"[^"]*"' output.jsonl | head -1 | cut -d'"' -f4)
```

## Detailed Reference

See [REFERENCE_EN.md](./REFERENCE_EN.md) for:

- Complete command-line parameters
- Prompt design detailed guide
- Parallel execution guide
- Configuration file options
