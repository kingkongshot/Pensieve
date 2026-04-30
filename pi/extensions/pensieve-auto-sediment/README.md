# pensieve-auto-sediment (pi extension, in-process sidecar mode)

Per-prompt auto-sediment for Pensieve on pi. **Zero main-session impact**:
no token cost, no latency, no transcript pollution.

## How it works

```
agent_end
  └─► upstream stop-hook-auto-sediment.sh   (filter chain — unchanged)
        └─► decision:block ?
              └─► YES → detached in-process sidecar (NOT awaited)
                    ├─ DECISION llm  → JSON {sediment, kind, slug, label, reason}
                    ├─ if sediment:
                    │    ├─ WRITER llm → markdown body
                    │    ├─ write to .pensieve/short-term/<kind>/<slug>.md
                    │    └─ spawn maintain-project-state.sh
                    └─ all events → .pensieve/.state/sidecar-sediment.log
```

The main session keeps running normally. The sidecar runs in the background,
calling LLMs directly via `@mariozechner/pi-ai` — no `claude -r` CLI, no
subprocess prompt encoding, no recursion concerns.

## Recommended model selection

Decision and writer have very different workloads, and benefit from
different-tier models:

| Stage    | Workload                                   | Recommended tier |
|----------|--------------------------------------------|------------------|
| Decision | Classify + name (1 message + slug list → strict JSON) | **Haiku-class** (cheap, fast) |
| Writer   | Structured markdown matching reference template, faithful to source, correct `[[...]]` links | **Sonnet-class** (quality, not bargain-bin) |

Default recommendation:

```json
{
  "auto_sediment": {
    "decision_model": "anthropic/claude-haiku-4-5",
    "writer_model":   "anthropic/claude-sonnet-4-6"
  }
}
```

Why not all-Haiku:
  - Haiku writer empirically invents `[[...]]` link IDs (e.g. produces
    `[[CC sidecar dispatch archive]]` when the real entry is
    `decisions/2026-04-11-sidecar-sediment-dispatch-design`). Polluting the
    knowledge graph with broken links costs more in later refine work than
    the per-call savings.

Why not Opus / main-session model:
  - The main session model (often Opus) is optimized for complex tool use
    and long-horizon planning. Sediment writing is structured-text
    generation — Sonnet is plenty.
  - **The fallback to `ctx.model` is a safety net, not a default.** If you
    leave models unconfigured and your main session runs Opus, every
    sediment hit costs Opus prices. Always set at least `decision_model`.

When in doubt: drop the recommended snippet above into
`~/.pi/.pensieve-auto-sediment.json` (one-time, applies to all your
Pensieve projects — see § Configuration → Global below).

## Configuration

Four-tier override (highest precedence first):

```
env vars
  ↓
project  .pensieve/config.json          ← cross-harness; CC also reads `enabled` / `min_message_length`
  ↓
global   ~/.pi/.pensieve-auto-sediment.json   ← pi-only; sidecar model defaults
  ↓
fallback ctx.model                       ← main-session model (NOT recommended for cost-sensitive setups)
```

Within each layer: a specific field (`decision_model` / `writer_model`)
overrides the common `model` field.

### 1. Environment variables

```bash
# Set both decision and writer to the same model:
export PENSIEVE_SEDIMENT_MODEL="anthropic/claude-haiku-4-5"

# Or set them independently (specific overrides common):
export PENSIEVE_SEDIMENT_DECISION_MODEL="anthropic/claude-haiku-4-5"
export PENSIEVE_SEDIMENT_WRITER_MODEL="anthropic/claude-sonnet-4-6"

# Override the substantial-message threshold:
export PENSIEVE_SEDIMENT_MIN_LENGTH=200
```

### 2. Project: `.pensieve/config.json`

Project-specific overrides. Lives next to project state, harness-shared
(CC reads `enabled` / `min_message_length` from this same file via bash).

```json
{
  "auto_sediment": {
    "enabled": true,
    "model": "anthropic/claude-haiku-4-5",
    "decision_model": "anthropic/claude-haiku-4-5",
    "writer_model": "anthropic/claude-sonnet-4-6",
    "min_message_length": 200,
    "decision_timeout_ms": 30000,
    "writer_timeout_ms": 90000
  }
}
```

- `enabled: false` disables auto-sediment entirely (the upstream `.sh` filter
  chain also enforces this; both points are checked).
- `model` is the common fallback for both `decision_model` and `writer_model`
  when those are not specified.
- Hot-reloaded: changes take effect on the next `agent_end` — no pi restart.

### 3. Global: `~/.pi/.pensieve-auto-sediment.json`

**Configure once, used by every Pensieve project on this machine.** Recommended
for most users so you don't have to copy `decision_model` / `writer_model`
into every `.pensieve/config.json`.

```json
{
  "auto_sediment": {
    "decision_model": "anthropic/claude-haiku-4-5",
    "writer_model": "anthropic/claude-sonnet-4-6",
    "decision_timeout_ms": 30000,
    "writer_timeout_ms": 90000
  }
}
```

The global file also accepts `"model": "<provider>/<id>"` as a common
fallback when you want decision and writer to share a model:

```json
{ "auto_sediment": { "model": "anthropic/claude-sonnet-4-6" } }
```

This is equivalent to setting both `decision_model` and `writer_model`
to the same value, but the dedicated `decision_model` / `writer_model`
fields take precedence if also set.

**Schema is intentionally narrower than the project file.** The global file
is read **only** by the pi sidecar. It deliberately does *not* honor
`enabled` or `min_message_length`:

  - `enabled` belongs to the per-project Pensieve memory store (also read
    by Claude Code's bash filter chain). Putting it in a pi-only global
    file would silently desynchronize CC and pi behavior on the same project.
  - `min_message_length` similarly is a per-project tuning knob shared
    across harnesses.

**Why not `~/.config/pensieve/config.json`?** Because Claude Code's
auto-sediment runs *inline* (sidecar-dispatch was archived — see
`~/.claude/.pensieve/decisions/2026-04-11-sidecar-sediment-dispatch-design.md`)
and never reads `decision_model` / `writer_model`. A "global pensieve" path
would mislead users into expecting CC to honor them. The pi-specific path
name makes the scope explicit.

Override the path for tests with `PENSIEVE_AUTO_SEDIMENT_GLOBAL_CONFIG`.

### 4. Fallback

If no model is configured at any of the above layers, the sidecar uses the
main session's current model (`ctx.model`). **This is a safety net, not a
default** — if your main session runs Opus, every sediment hit costs Opus
prices. Always set at least `decision_model` (global file is the easiest
place).

## Model string format

`<provider>/<modelId>`, e.g. `anthropic/claude-haiku-4-5`,
`google/gemini-2.5-flash`, `openai/gpt-5.2`.

The provider must be registered in pi's model registry (built-in or via
`models.json` custom providers / extensions).

## Files

| File         | Purpose                                                                |
|--------------|------------------------------------------------------------------------|
| `index.ts`   | Extension entry. Hooks `agent_end`, runs filter chain, fires sidecar.  |
| `config.ts`  | Four-tier config resolution (env > project `.pensieve/config.json` > global `~/.pi/.pensieve-auto-sediment.json` > `ctx.model` fallback). |
| `prompts.ts` | Decision + writer system prompts and prompt builders.                  |
| `sidecar.ts` | The detached pipeline: model resolve → decision → writer → file write. |

## Observability

All sidecar events are logged to `.pensieve/.state/sidecar-sediment.log`:

```
2026-04-30T11:47:04.450Z sid=00000000 sidecar:start msglen=696
2026-04-30T11:47:04.450Z sid=00000000 decision-model:ready anthropic/claude-haiku-4-5
2026-04-30T11:47:06.611Z sid=00000000 decision:sediment kind=decision slug=... label="..."
2026-04-30T11:47:06.611Z sid=00000000 writer-model:ready anthropic/claude-sonnet-4-6
2026-04-30T11:47:19.179Z sid=00000000 written:short-term/decisions/2026-04-30-...md
2026-04-30T11:47:19.184Z sid=00000000 sidecar:done
```

On success, a single `ctx.ui.notify("pensieve sedimented: <label>", "info")`
is shown in the TUI. Failures are silent (logged only).

### Concurrency log lines

When multiple substantial turns arrive while a sidecar is in flight, you'll
see lines like:

```
... sid=abcd1234 pending:queued (was running)
... sid=abcd1234 sidecar:done
... sid=abcd1234 pending:replay
... sid=abcd1234 sidecar:start msglen=...
```

## Concurrency

Per-session in-memory state machine (no filesystem locks, no cross-process
sync). Three states:

| State                     | Next turn action                                |
|---------------------------|--------------------------------------------------|
| _idle_ (no entry in map)  | Run filter chain → launch sidecar.              |
| `running`                 | Stash the new turn's message as `pendingMsg`. Do **not** spawn a second sidecar. |
| `running-with-pending`    | **Overwrite** `pendingMsg` with the newer one. Older pending is dropped. |

When the running sidecar finishes:
  - `pendingMsg` present → re-run filter chain + launch a fresh sidecar with
    that message.
  - otherwise → clear state and go idle.

**Latest-wins, single-slot queue.** N substantial turns fired back-to-back
produce **at most one extra** sidecar run — not N. The extra run carries
turn N's message, which is the most-recent-and-most-relevant insight.

### Why no cross-process file lock

Intentional. Two pi processes pointed at the same `.pensieve/` produce
at worst two near-duplicate short-term files (refine handles dedup), and
all writes are append-safe:
  - Markdown files use a `-N` suffix on path collision (`sidecar.ts`).
  - `sidecar-sediment.log` is `appendFileSync` (POSIX `O_APPEND` is atomic
    below `PIPE_BUF`).
  - `maintain-project-state.sh` is append-only state.

A file lock would add stale-PID detection and TTL handling without
preventing any actual data corruption.

## Why not inline / why not spawn `claude -r`?

The Claude Code per-turn `inline` mode (the predecessor here) injects a
follow-up evaluation prompt into the main session. That works but costs
600-50k main-session tokens per substantial turn and pollutes the transcript
with `NO_SEDIMENT:` / `SEDIMENT_SCHEDULED:` markers.

The CC `sidecar dispatch` design (2026-04-11, archived) tried to spawn a
detached `claude -r ... -p` subprocess. It failed in production: the CLI
silently blocks (0 bytes for 90+ s) on multi-section prompts. See
`~/.claude/.pensieve/decisions/2026-04-11-sidecar-sediment-dispatch-design.md`.

In pi, extensions are in-process Node modules with direct access to
`ctx.modelRegistry`. We call the LLM API directly — no CLI middleman, no
subprocess black-box, no `--bare` / session-id / PID-lock concerns.

## Testing

Smoke test (loads all 4 modules, validates exports):

```bash
PI_PKG=$(npm root -g)/@mariozechner/pi-coding-agent  # adjust if needed
cd "$PI_PKG"
node --input-type=module -e '
import { createJiti } from "@mariozechner/jiti";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
const __d = path.dirname(fileURLToPath(import.meta.url));
const jiti = createJiti(import.meta.url, {
  interopDefault: true,
  alias: {
    "@mariozechner/pi-coding-agent": path.join(__d, "dist/index.js"),
    "@mariozechner/pi-ai": path.join(__d, "node_modules/@mariozechner/pi-ai/dist/index.js"),
  },
});
const m = await jiti.import("'$HOME'/.pi/agent/extensions/pensieve-auto-sediment/index.ts", { default: true });
console.log("OK:", typeof m === "function" ? "factory loaded" : "FAIL");
'
```

End-to-end (requires a real model and key — see this directory's commit
history for an e2e harness). Took 15 s with `claude-haiku-4-5` on a 696-char
substantial message and produced a fully-formed decision markdown file.
