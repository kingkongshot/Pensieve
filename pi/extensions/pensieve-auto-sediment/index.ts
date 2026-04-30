/**
 * Pensieve Auto-Sediment Extension (pi adapter, Layer 3)
 *
 * Per-prompt evaluation of "should this agent response be sedimented?"
 * Reuses the upstream `stop-hook-auto-sediment.sh` filter chain unmodified;
 * the extension is a thin event router (~100 LOC) that:
 *
 * 1. Listens to pi's `agent_end` event.
 * 2. Extracts the last assistant message from SessionManager.
 * 3. Constructs a Claude-Code-compatible stdin JSON payload.
 * 4. Spawns the upstream bash script.
 * 5. If the script outputs `decision:block`, sends the sediment
 *    evaluation prompt as a follow-up user message.
 *
 * Filters (handled by the bash script, not TS):
 *   - recursion_guard     (stop_hook_active replay)
 *   - pensieve_project    (.pensieve/ must exist)
 *   - config_toggle       (.pensieve/config.json auto_sediment.enabled)
 *   - substantial         (last message ≥ MIN_MSG_LENGTH chars)
 *   - pending_question    (heuristic, low-cost in per-prompt mode)
 *
 * Filters *not* needed on pi:
 *   - ralph_loop          (pi has no Ralph-Loop)
 *
 * Design notes:
 *   - per-prompt, not per-turn. pi's `agent_end` fires after the entire
 *     agent loop; this is a semantic downgrade from Claude Code's
 *     per-turn Stop hook, but aligns with pi's interaction model.
 *   - recursion is prevented by an in-memory `Set<sessionId>` flag.
 *   - The upstream script path and sample log path are configurable via
 *     environment variables.
 *   - `/pensieve` in the eval prompt is rewritten to `/skill:pensieve`
 *     so the follow-up message invokes Pensieve correctly on pi.
 */

import type {
	AgentEndEvent,
	ExtensionAPI,
	SessionStartEvent,
} from "@mariozechner/pi-coding-agent";
import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

// ─────────────────────────────────────────────────────────────────────────────
// Locate the Pensieve skill root.
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
// Extract plain text from an assistant message's content.
// pi stores message content as `string | (TextContent | ImageContent)[]`.
// ─────────────────────────────────────────────────────────────────────────────
function extractText(content: unknown): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	const parts: string[] = [];
	for (const block of content as any[]) {
		if (block && block.type === "text" && typeof block.text === "string") {
			parts.push(block.text);
		}
	}
	return parts.join("\n");
}

// ─────────────────────────────────────────────────────────────────────────────
// Run the upstream stop-hook-auto-sediment.sh and return parsed stdout.
// ─────────────────────────────────────────────────────────────────────────────
async function evaluateSediment(
	sessionId: string,
	lastAssistantMsg: string,
	projectRoot: string,
	signal?: AbortSignal,
): Promise<string> {
	if (!SKILL_ROOT) return "";

	const script = path.join(SKILL_ROOT, ".src", "scripts", "stop-hook-auto-sediment.sh");
	if (!fs.existsSync(script)) return "";

	// pi-specific sample log (separate from Claude Code's)
	const sampleLog = path.join(
		os.homedir(),
		".pi", "agent", "data", "pensieve", "filter-samples.jsonl",
	);

	const payload = JSON.stringify({
		session_id: sessionId,
		stop_hook_active: false,
		last_assistant_message: lastAssistantMsg,
	});

	return new Promise((resolve) => {
		let stdout = "";
		const proc = spawn("bash", [script], {
			cwd: projectRoot,
			env: {
				...process.env,
				PENSIEVE_SKILL_ROOT: SKILL_ROOT,
				PENSIEVE_PROJECT_ROOT: projectRoot,
				CLAUDE_PROJECT_DIR: projectRoot,
				PENSIEVE_HARNESS: "pi",
				PENSIEVE_SEDIMENT_MIN_LENGTH: process.env.PENSIEVE_SEDIMENT_MIN_LENGTH ?? "200",
				// Override Claude-Code-specific sample log path
				HOME: os.homedir(),
				PENSIEVE_SAMPLE_LOG: sampleLog,
			},
			stdio: ["pipe", "pipe", "pipe"],
			detached: false,
		});

		let stderr = "";
		proc.stdout.on("data", (c: Buffer) => { stdout += c.toString(); });
		proc.stderr.on("data", (c: Buffer) => { stderr += c.toString(); });

		proc.on("close", (code) => {
			if (code !== 0) {
				// Silent — the bash script exits 0 on every filter rejection;
				// non-0 means a real error (missing jq, broken pipe, etc.).
				process.stderr.write(
					`[pensieve-auto-sediment] script exited ${code}: ${stderr.trim().slice(0, 200)}\n`,
				);
				resolve("");
				return;
			}
			resolve(stdout.trim());
		});

		if (signal) {
			signal.addEventListener("abort", () => { proc.kill(); resolve(""); }, { once: true });
		}

		proc.on("error", () => { resolve(""); });
		proc.stdin.end(payload);
	});
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension
// ─────────────────────────────────────────────────────────────────────────────
export default function pensieveAutoSediment(pi: ExtensionAPI) {
	const sedimentInProgress = new Set<string>(); // per-session recursion guard
	let pensieveDir: string | null = null;

	pi.on("session_start", (_event: SessionStartEvent, ctx) => {
		const dir = path.join(ctx.cwd, ".pensieve");
		pensieveDir = fs.existsSync(dir) && fs.statSync(dir).isDirectory() ? dir : null;
	});

	pi.on("agent_end", async (_event: AgentEndEvent, ctx) => {
		// ── Pre-fetch all ctx-dependent data synchronously.
		//     After the first `await` (spawn), the ctx may become
		//     stale in print mode where the session is finalized
		//     asynchronously.
		const sid = ctx.sessionManager.getSessionFile() ?? "ephemeral";
		const cwd = ctx.cwd;
		const hasUI = ctx.hasUI;
		const signal = ctx.signal;

		// ── Guard: not a Pensieve project
		if (!pensieveDir) return;

		// ── Guard: recursion (we just fired a sediment evaluation, and the
		//     follow-up turn's agent_end is now firing — skip)
		if (sedimentInProgress.has(sid)) {
			sedimentInProgress.delete(sid);
			return;
		}

		// ── Extract last assistant message (synchronous ctx access)
		const branch = ctx.sessionManager.getBranch();
		const lastAssistant = [...branch]
			.reverse()
			.find((e) => e.type === "message" && e.message?.role === "assistant");
		if (!lastAssistant || lastAssistant.type !== "message") return;
		const lastMsg = extractText(lastAssistant.message.content);
		if (lastMsg.length < 50) return; // short-circuit: too short to be substantive

		// ── Run upstream filter chain (async — ctx becomes stale after this)
		const stdout = await evaluateSediment(sid, lastMsg, cwd, signal);
		if (!stdout) return;

		// ── Parse output: expect {"decision":"block","reason":"..."}
		let result: any;
		try { result = JSON.parse(stdout); } catch { return; }
		if (result.decision !== "block" || typeof result.reason !== "string") return;

		// ── Rewrite `/pensieve` → `/skill:pensieve` for pi compatibility
		const reason = result.reason.replace(/\/pensieve\b/g, "/skill:pensieve");

		// ── Mark recursion guard BEFORE sending the follow-up
		sedimentInProgress.add(sid);

		// ── Interactive mode: inject the sediment evaluation prompt as
		//     a follow-up user message. The LLM picks it up in the next
		//     turn and decides whether to invoke /skill:pensieve self-improve.
		if (hasUI) {
			pi.sendUserMessage(reason, { deliverAs: "followUp" });
		}
	});
}
