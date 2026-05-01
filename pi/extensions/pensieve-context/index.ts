/**
 * Pensieve Context Extension (pi adapter, Layer 2)
 *
 * Goal — give the LLM a *navigation card* into the project's Pensieve memory
 * without burning context on the full graph dump. The card is appended to the
 * system prompt only when the active project has `.pensieve/`. Detailed
 * lookup is delegated back to the model (read graph → read entry).
 *
 * Also wires the upstream `sync-project-skill-graph.sh` script to pi's
 * `tool_result` event so editing files inside `.pensieve/` keeps the graph
 * fresh — the pi-side equivalent of Claude Code's
 * `PostToolUse` matcher=`Write|Edit|MultiEdit` hook.
 *
 * Design notes:
 * - Hot-detect `.pensieve/` per session (cwd may differ across sessions).
 * - Card is intentionally small (~300 tokens) — Pensieve's own philosophy is
 *   "skill 按需路由，极少占用上下文" (README.md). Full graph stays on disk.
 * - We feed the upstream bash script the same JSON shape it expects from
 *   Claude Code (`tool_name`, `tool_input.file_path`, `tool_response.success`,
 *   `cwd`) so the script itself stays single-source-of-truth.
 */

import type {
	BeforeAgentStartEvent,
	BeforeAgentStartEventResult,
	ExtensionAPI,
	SessionStartEvent,
	ToolResultEvent,
} from "@mariozechner/pi-coding-agent";
import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

// ─────────────────────────────────────────────────────────────────────────────
// Locate the Pensieve skill root.
// Priority: PENSIEVE_SKILL_ROOT env > submodule path under ~/.pi > legacy ~/.claude.
// ─────────────────────────────────────────────────────────────────────────────
function locateSkillRoot(): string | null {
	const candidates = [
		process.env.PENSIEVE_SKILL_ROOT,
		path.join(os.homedir(), ".pi", "agent", "skills", "pensieve"),
		path.join(os.homedir(), ".claude", "skills", "pensieve"),
	].filter((p): p is string => !!p);
	for (const c of candidates) {
		if (fs.existsSync(path.join(c, ".src", "manifest.json"))) return c;
	}
	return null;
}

const SKILL_ROOT = locateSkillRoot();

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────
function countMd(dir: string): number {
	try {
		return fs
			.readdirSync(dir, { withFileTypes: true })
			.filter((e) => e.isFile() && e.name.endsWith(".md") && e.name.toLowerCase() !== "readme.md").length;
	} catch {
		return 0;
	}
}

function buildNavigationCard(pensieveDir: string): string {
	const layers = [
		["maxims", "MUST — engineering rules"],
		["decisions", "WANT — architectural choices"],
		["knowledge", "IS — cached facts & call chains"],
		["pipelines", "HOW — reusable workflows"],
	] as const;
	const counts = layers.map(([d, label]) => `- **${d}/** (${label}): ${countMd(path.join(pensieveDir, d))} entries`).join("\n");
	const graphPath = path.join(pensieveDir, ".state", "pensieve-user-data-graph.md");
	const hasGraph = fs.existsSync(graphPath);
	const statePath = path.join(pensieveDir, "state.md");
	const hasState = fs.existsSync(statePath);

	return `

## Pensieve Project Memory

This project carries structured long-term memory. Always check it before
exploring code or making architectural decisions — exploration cached here
is cheaper to read than to recompute.

${counts}
${hasGraph ? `- **graph**: \`.pensieve/.state/pensieve-user-data-graph.md\` (mermaid; nodes + semantic links across all layers)` : ""}
${hasState ? `- **state**: \`.pensieve/state.md\` (lifecycle + recent changes)` : ""}

### When to consult Pensieve

- **Before planning / designing** → read graph, locate relevant nodes, follow links to active \`decisions/\` and \`maxims/\`. Don't re-litigate decided questions.
- **Before exploring code** → grep \`.pensieve/knowledge/\` for cached file maps, module boundaries, call chains. Reuse beats re-discovering.
- **Before suggesting a refactor** → check \`maxims/\` for hard rules ("must / must not") that constrain the design space.

### When to write to Pensieve

After producing a durable insight (root cause found, design tradeoff settled,
non-obvious pitfall hit), invoke \`/skill:pensieve self-improve\` to crystallize
it into the right layer. Pure transient back-and-forth doesn't need to be saved.

The full skill spec, tool boundaries, and reference docs live at
\`${SKILL_ROOT ? path.relative(pensieveDir, SKILL_ROOT) || SKILL_ROOT : "<pensieve-skill-root>"}/SKILL.md\`
and \`<skill-root>/.src/references/\`. Use \`/skill:pensieve\` to load the router.
`;
}

// ─────────────────────────────────────────────────────────────────────────────
// Bridge to upstream sync script
// ─────────────────────────────────────────────────────────────────────────────
function runSyncGraph(filePath: string, toolName: string, cwd: string): void {
	if (!SKILL_ROOT) return;
	const script = path.join(SKILL_ROOT, ".src", "scripts", "sync-project-skill-graph.sh");
	if (!fs.existsSync(script)) return;

	// Map pi tool names to the Claude Code matchers the script's switch expects.
	// The script only reads tool_name to decide whether the event came from a
	// file mutation; it doesn't otherwise care about exact spelling.
	const claudeStyleName =
		toolName === "edit" ? "Edit" : toolName === "write" ? "Write" : toolName === "multi_edit" ? "MultiEdit" : toolName;

	const payload = JSON.stringify({
		tool_name: claudeStyleName,
		tool_input: { file_path: filePath },
		tool_response: { success: true },
		cwd,
	});

	const proc = spawn("bash", [script], {
		cwd,
		env: {
			...process.env,
			PENSIEVE_SKILL_ROOT: SKILL_ROOT,
			PENSIEVE_PROJECT_ROOT: cwd,
			CLAUDE_PROJECT_DIR: cwd,
			PENSIEVE_HARNESS: "pi",
		},
		stdio: ["pipe", "ignore", "ignore"],
		detached: false,
	});
	proc.on("error", () => {
		/* fail silent — graph staleness is recoverable, missing tool is not fatal */
	});
	proc.stdin.end(payload);
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension
// ─────────────────────────────────────────────────────────────────────────────
export default function pensieveContext(pi: ExtensionAPI) {
	let pensieveDir: string | null = null;

	pi.on("session_start", (_event: SessionStartEvent, ctx) => {
		// ── Inject Pensieve env vars into process.env so all subsequent
		// bash tool calls inherit them. lib.sh can auto-detect these,
		// but explicit injection is more reliable and avoids walking
		// the filesystem on every invocation.
		if (SKILL_ROOT) {
			process.env.PENSIEVE_SKILL_ROOT = SKILL_ROOT;
		}
		process.env.PENSIEVE_PROJECT_ROOT = ctx.cwd;
		process.env.PENSIEVE_HARNESS = "pi";

		const dir = path.join(ctx.cwd, ".pensieve");
		pensieveDir = fs.existsSync(dir) && fs.statSync(dir).isDirectory() ? dir : null;
		if (pensieveDir) {
			process.env.PENSIEVE_DATA_ROOT = pensieveDir;
			process.env.PENSIEVE_STATE_ROOT = path.join(pensieveDir, ".state");
			ctx.ui.setStatus("pensieve", "pensieve");
		} else {
			ctx.ui.setStatus("pensieve", undefined);
		}
	});

	pi.on("session_shutdown", (_event, ctx) => {
		ctx.ui.setStatus("pensieve", undefined);
	});

	pi.on("before_agent_start", (event: BeforeAgentStartEvent): BeforeAgentStartEventResult | undefined => {
		if (!pensieveDir) return undefined;
		const card = buildNavigationCard(pensieveDir);
		return { systemPrompt: event.systemPrompt + card };
	});

	pi.on("tool_result", (event: ToolResultEvent, ctx) => {
		if (!pensieveDir || event.isError) return;
		if (event.toolName !== "edit" && event.toolName !== "write") return;
		const raw = (event.input as { path?: string }).path;
		if (!raw) return;
		const abs = path.isAbsolute(raw) ? raw : path.resolve(ctx.cwd, raw);
		// Only fire when the edited file is inside this project's .pensieve/
		if (!abs.startsWith(pensieveDir + path.sep) && abs !== pensieveDir) return;
		runSyncGraph(abs, event.toolName, ctx.cwd);
	});
}
