/**
 * Pensieve Auto-Sediment Extension (pi adapter, Layer 3) — in-process sidecar mode
 *
 * Per-prompt evaluation of "should this agent response be sedimented?"
 * Reuses the upstream `stop-hook-auto-sediment.sh` filter chain unmodified
 * (recursion / pensieve_exists / config_enabled / substantial / question_heuristic).
 *
 * When the filter chain says PASS, we DO NOT inject a follow-up user message
 * into the main session. Instead we launch a detached in-process "sidecar"
 * promise that:
 *
 *   1. Calls a configurable DECISION model on the last assistant message
 *      → strict JSON {sediment, kind, slug, label, reason}
 *   2. If sediment=true, calls a configurable WRITER model
 *      → markdown body conforming to .src/references/{kind}.md
 *   3. Writes short-term/<kind>/<slug>.md
 *   4. Spawns maintain-project-state.sh to refresh state.md / graph
 *
 * Main-session impact: 0 tokens, 0 latency, 0 transcript pollution.
 *
 * Configuration (highest precedence first):
 *   - env: PENSIEVE_SEDIMENT_MODEL / PENSIEVE_SEDIMENT_DECISION_MODEL /
 *          PENSIEVE_SEDIMENT_WRITER_MODEL
 *   - .pensieve/config.json -> auto_sediment.{model, decision_model,
 *          writer_model, min_message_length, decision_timeout_ms,
 *          writer_timeout_ms, enabled}
 *   - fallback: ctx.model (the main session's model)
 *
 * History context:
 *   - The Claude Code sidecar dispatch design (2026-04-11) was archived
 *     because `claude -r ... -p` silently blocks on multi-section prompts.
 *     pi has no such CLI middleman: extensions are in-process Node and call
 *     the LLM API directly via @mariozechner/pi-ai. See
 *     ~/.pi/.pensieve/short-term/decisions/2026-04-30-pi-auto-sediment-inprocess-sidecar.md
 *     and ~/.pi/.pensieve/short-term/knowledge/pi-sidecar-is-inprocess-llm-call/.
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

import { loadConfig, type SedimentConfig } from "./config.js";
import { runSidecar } from "./sidecar.js";

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
// Extract plain text from an assistant message's content array.
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
// The script encodes the entire filter chain (recursion / .pensieve exists /
// config_enabled / ralph_loop / substantial / question_heuristic). We only
// look at whether it emits decision:block — the prompt text is irrelevant
// in sidecar mode (we generate our own).
// ─────────────────────────────────────────────────────────────────────────────
async function evaluateFilterChain(
	sessionId: string,
	lastAssistantMsg: string,
	projectRoot: string,
	minLength: number,
	signal?: AbortSignal,
): Promise<boolean> {
	if (!SKILL_ROOT) return false;
	const script = path.join(SKILL_ROOT, ".src", "scripts", "stop-hook-auto-sediment.sh");
	if (!fs.existsSync(script)) return false;

	const sampleLog = path.join(
		os.homedir(),
		".pi",
		"agent",
		"data",
		"pensieve",
		"filter-samples.jsonl",
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
				PENSIEVE_SKILL_ROOT: SKILL_ROOT!,
				PENSIEVE_PROJECT_ROOT: projectRoot,
				CLAUDE_PROJECT_DIR: projectRoot,
				PENSIEVE_HARNESS: "pi",
				// Mirror resolved minLength into env so the bash filter chain's
				// substantial check uses the same threshold as the TS pre-filter.
				PENSIEVE_SEDIMENT_MIN_LENGTH: String(minLength),
				HOME: os.homedir(),
				PENSIEVE_SAMPLE_LOG: sampleLog,
			},
			stdio: ["pipe", "pipe", "pipe"],
			detached: false,
		});

		proc.stdout.on("data", (c: Buffer) => {
			stdout += c.toString();
		});
		// stderr discarded — script exits 0 on filter rejection, non-0 means tooling error
		proc.stderr.on("data", () => {});

		proc.on("close", () => {
			let result: any;
			try {
				result = JSON.parse(stdout.trim());
			} catch {
				resolve(false);
				return;
			}
			resolve(result?.decision === "block");
		});

		if (signal) {
			signal.addEventListener(
				"abort",
				() => {
					proc.kill();
					resolve(false);
				},
				{ once: true },
			);
		}

		proc.on("error", () => resolve(false));
		proc.stdin.end(payload);
	});
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-session run-state for concurrency control.
//
// Three states:
//   - absent (idle)         → start sidecar, mark running
//   - running               → upgrade to running-with-pending; remember msg
//   - running-with-pending  → overwrite pendingMsg with the newest one
//                              (we only ever "queue" the latest turn — older
//                               pending msgs are dropped)
//
// Rationale (vs. dropping the second turn outright):
//   if the user fires N substantial turns back-to-back, we don't want to
//   permanently lose the insight from turn N. A single "latest-wins" queue
//   slot bounds the worst case to one extra sidecar run, regardless of N.
//
// Cross-process concurrency is intentionally NOT handled here. Two pi
// processes pointed at the same .pensieve/ produce at worst two near-duplicate
// short-term files (caught by refine), and all writes are append-safe:
//   - markdown files use a `-N` suffix on collision (sidecar.ts)
//   - sidecar-sediment.log is appendFileSync (POSIX O_APPEND atomic <PIPE_BUF)
//   - maintain-project-state.sh is append-only state
// ─────────────────────────────────────────────────────────────────────────────
type RunState =
	| { status: "running" }
	| { status: "running-with-pending"; pendingMsg: string };

// ─────────────────────────────────────────────────────────────────────────────
// Extension entry point
// ─────────────────────────────────────────────────────────────────────────────
export default function pensieveAutoSediment(pi: ExtensionAPI) {
	let pensieveDir: string | null = null;
	const runState = new Map<string, RunState>();

	pi.on("session_start", (_event: SessionStartEvent, ctx) => {
		const dir = path.join(ctx.cwd, ".pensieve");
		pensieveDir = fs.existsSync(dir) && fs.statSync(dir).isDirectory() ? dir : null;
	});

	/**
	 * Inputs to launch a sidecar run. We capture all ctx-derived values up
	 * front (in agent_end) so re-entrant queued runs can be triggered later
	 * without touching a possibly-stale ctx.
	 */
	interface DispatchInputs {
		sid: string;
		lastMsg: string;
		projectRoot: string;
		localPensieveDir: string;
		/** Resolved once at agent_end entry; reused for filter chain + sidecar. */
		config: SedimentConfig;
		modelRegistry: import("@mariozechner/pi-coding-agent").ExtensionContext["modelRegistry"];
		fallbackModel: import("@mariozechner/pi-coding-agent").ExtensionContext["model"];
		parentSignal: AbortSignal | undefined;
		ui: import("@mariozechner/pi-coding-agent").ExtensionContext["ui"];
		hasUI: boolean;
	}

	function launchSidecar(inputs: DispatchInputs): void {
		const { sid, projectRoot, localPensieveDir } = inputs;
		runState.set(sid, { status: "running" });

		// Show persistent status in footer so the user knows a background task
		// is running and won't quit pi before sediment completes.
		if (inputs.hasUI) {
			try { inputs.ui.setStatus("pensieve-sediment", "Pensieve 沉淀中..."); } catch {}
		}

		void (async () => {
			try {
				const result = await runSidecar({
					sessionId: sid,
					pensieveDir: localPensieveDir,
					skillRoot: SKILL_ROOT!,
					projectRoot,
					lastAssistantMessage: inputs.lastMsg,
					config: inputs.config,
					modelRegistry: inputs.modelRegistry,
					fallbackModel: inputs.fallbackModel,
					parentSignal: inputs.parentSignal,
				});
				if (!result.skipped && inputs.hasUI && result.label) {
					try {
						inputs.ui.notify(`pensieve sedimented: ${result.label}`, "info");
					} catch {
						/* ui may be torn down (print mode) */
					}
				}
			} catch (e: any) {
				// Last-resort safety net — runSidecar already swallows its own errors.
				try {
					fs.appendFileSync(
						path.join(localPensieveDir, ".state", "sidecar-sediment.log"),
						`${new Date().toISOString()} sidecar:uncaught ${e?.message ?? String(e)}\n`,
					);
				} catch {
					/* truly silent */
				}
			} finally {
				const state = runState.get(sid);
				if (state?.status === "running-with-pending") {
					// Pending re-entry: kick off another full pass with the latest
					// queued message (re-runs filter chain too — cheap, and keeps
					// the question_heuristic / substantial gates honest).
					// Status stays "沉淀中..." — another run starts immediately.
					const pendingMsg = state.pendingMsg;
					runState.delete(sid);
					try {
						fs.appendFileSync(
							path.join(localPensieveDir, ".state", "sidecar-sediment.log"),
							`${new Date().toISOString()} sid=${sid.slice(0, 8)} pending:replay\n`,
						);
					} catch {}
					dispatchAfterFilter({ ...inputs, lastMsg: pendingMsg });
				} else {
					runState.delete(sid);
					// Clear footer status — sidecar chain is done.
					if (inputs.hasUI) {
						try { inputs.ui.setStatus("pensieve-sediment", undefined); } catch {}
					}
				}
			}
		})();
	}

	async function dispatchAfterFilter(inputs: DispatchInputs): Promise<void> {
		const passed = await evaluateFilterChain(
			inputs.sid,
			inputs.lastMsg,
			inputs.projectRoot,
			inputs.config.minLength,
			inputs.parentSignal,
		);
		if (!passed) return;
		launchSidecar(inputs);
	}

	pi.on("agent_end", async (_event: AgentEndEvent, ctx) => {
		// ── Synchronous capture of ctx-dependent values BEFORE any await.
		//     In print mode, ctx may go stale immediately after agent_end
		//     finishes; we never read ctx fields again after this block.
		if (!pensieveDir || !SKILL_ROOT) return;

		const sid = ctx.sessionManager.getSessionFile() ?? "ephemeral";
		const cwd = ctx.cwd;
		const projectRoot = cwd;
		const modelRegistry = ctx.modelRegistry;
		const fallbackModel = ctx.model;
		const parentSignal = ctx.signal;
		const ui = ctx.ui;
		const hasUI = ctx.hasUI;
		const localPensieveDir = pensieveDir;

		// ── Load config (hot, every fire). Short-circuit on disabled.
		const config = loadConfig(localPensieveDir);
		if (!config.enabled) return;

		// ── Extract last assistant message synchronously.
		const branch = ctx.sessionManager.getBranch();
		const lastAssistant = [...branch]
			.reverse()
			.find((e) => e.type === "message" && e.message?.role === "assistant");
		if (!lastAssistant || lastAssistant.type !== "message") return;
		const lastMsg = extractText(lastAssistant.message.content);
		if (lastMsg.length < Math.max(50, Math.floor(config.minLength / 4))) return; // cheap pre-filter

		// ── Concurrency: if a sidecar is already running for this session,
		//     queue this turn's message as the latest pending (overwriting any
		//     older pending — only the newest substantial turn is replayed).
		const current = runState.get(sid);
		if (current) {
			runState.set(sid, { status: "running-with-pending", pendingMsg: lastMsg });
			try {
				fs.appendFileSync(
					path.join(localPensieveDir, ".state", "sidecar-sediment.log"),
					`${new Date().toISOString()} sid=${sid.slice(0, 8)} pending:queued (was ${current.status})\n`,
				);
			} catch {}
			return;
		}

		// ── No prior run. Go through the upstream filter chain, then dispatch.
		const inputs: DispatchInputs = {
			sid,
			lastMsg,
			projectRoot,
			localPensieveDir,
			config,
			modelRegistry,
			fallbackModel,
			parentSignal,
			ui,
			hasUI,
		};
		await dispatchAfterFilter(inputs);
	});
}
