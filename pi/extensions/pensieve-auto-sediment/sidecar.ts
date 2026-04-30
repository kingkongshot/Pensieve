/**
 * In-process auto-sediment sidecar.
 *
 * Runs *outside* the main session's await chain (detached promise) and never
 * sends messages back to the main session. All success / failure is observable
 * via .pensieve/.state/sidecar-sediment.log only.
 *
 * Two-stage pipeline:
 *   1. Decision LLM   → JSON {sediment, kind, slug, label, reason}
 *   2. Writer  LLM    → markdown body for short-term/<kind>/<slug>.md
 *
 * Each stage uses an independent timeout + AbortController. The whole sidecar
 * is wrapped in try/catch — any error appends a single line to the log and
 * exits silently.
 *
 * Key non-goals:
 *   - We do NOT use pi.sendUserMessage / sendMessage. Output is silent.
 *   - We do NOT mutate the session tree. Only filesystem writes.
 *   - We do NOT call /skill:pensieve self-improve. We replicate the relevant
 *     subset (write to short-term/, refresh state.md) directly.
 */

import { complete, type Model, type Api } from "@mariozechner/pi-ai";
import type { ModelRegistry } from "@mariozechner/pi-coding-agent";
import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

import {
	formatModelRef,
	type ModelRef,
	type SedimentConfig,
} from "./config.js";
import {
	buildDecisionPrompt,
	buildWriterPrompt,
	DECISION_SYSTEM_PROMPT,
	WRITER_SYSTEM_PROMPT,
} from "./prompts.js";

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────
export interface SidecarInput {
	sessionId: string;
	pensieveDir: string;
	skillRoot: string;
	projectRoot: string;
	lastAssistantMessage: string;
	config: SedimentConfig;
	modelRegistry: ModelRegistry;
	fallbackModel: Model<any> | undefined;
	parentSignal: AbortSignal | undefined;
}

export interface SidecarResult {
	skipped: boolean;
	reason: string;
	label?: string;
	kind?: string;
	slug?: string;
	filePath?: string;
}

interface DecisionJson {
	sediment: boolean;
	kind: "maxim" | "decision" | "knowledge" | null;
	slug: string | null;
	label: string | null;
	reason: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// Logging
// ─────────────────────────────────────────────────────────────────────────────
function logLine(stateRoot: string, line: string): void {
	try {
		fs.mkdirSync(stateRoot, { recursive: true });
		fs.appendFileSync(
			path.join(stateRoot, "sidecar-sediment.log"),
			`${new Date().toISOString()} ${line}\n`,
		);
	} catch {
		// log failure must not break sidecar
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Model resolution
// ─────────────────────────────────────────────────────────────────────────────
interface ResolvedModel {
	model: Model<Api>;
	apiKey: string;
	headers?: Record<string, string>;
	display: string;
}

async function resolveModel(
	ref: ModelRef | null,
	registry: ModelRegistry,
	fallback: Model<any> | undefined,
): Promise<ResolvedModel | { error: string }> {
	const tryRef = async (r: ModelRef): Promise<ResolvedModel | { error: string }> => {
		const m = registry.find(r.provider, r.modelId);
		if (!m) return { error: `model not found: ${formatModelRef(r)}` };
		const auth = await registry.getApiKeyAndHeaders(m);
		if (!auth.ok) return { error: `auth failed for ${formatModelRef(r)}: ${auth.error}` };
		if (!auth.apiKey) return { error: `no api key for ${formatModelRef(r)}` };
		return { model: m, apiKey: auth.apiKey, headers: auth.headers, display: formatModelRef(r) };
	};

	if (ref) {
		const r = await tryRef(ref);
		if ("error" in r) {
			// fall through to fallback, but remember error
			if (!fallback) return r;
			const fb = await tryRef({ provider: fallback.provider, modelId: fallback.id });
			if ("error" in fb) return { error: `${r.error}; fallback also failed: ${fb.error}` };
			return { ...fb, display: `${fb.display} (fallback after: ${r.error})` };
		}
		return r;
	}

	if (!fallback) return { error: "no model configured and no main-session fallback" };
	return tryRef({ provider: fallback.provider, modelId: fallback.id });
}

// ─────────────────────────────────────────────────────────────────────────────
// JSON parsing — permissive (model may wrap in fences or add prose)
// ─────────────────────────────────────────────────────────────────────────────
function extractDecisionJson(text: string): DecisionJson | null {
	// 1. Try fenced ```json block first
	let body = text;
	const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
	if (fence) body = fence[1];
	// 2. Otherwise look for first {...} block
	const open = body.indexOf("{");
	const close = body.lastIndexOf("}");
	if (open === -1 || close === -1 || close <= open) return null;
	const candidate = body.slice(open, close + 1);
	let parsed: any;
	try {
		parsed = JSON.parse(candidate);
	} catch {
		return null;
	}
	if (typeof parsed !== "object" || parsed === null) return null;
	const sediment = parsed.sediment === true;
	const kind = ["maxim", "decision", "knowledge"].includes(parsed.kind) ? parsed.kind : null;
	const slug = typeof parsed.slug === "string" ? parsed.slug.trim() : null;
	const label = typeof parsed.label === "string" ? parsed.label.trim() : null;
	const reason = typeof parsed.reason === "string" ? parsed.reason.trim() : "";
	return { sediment, kind, slug, label, reason };
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers — slug sanitize, recent slugs, reference snippet
// ─────────────────────────────────────────────────────────────────────────────
function sanitizeSlug(raw: string): string {
	return raw
		.toLowerCase()
		.replace(/[^a-z0-9-]+/g, "-")
		.replace(/^-+|-+$/g, "")
		.replace(/-+/g, "-")
		.slice(0, 80);
}

function listRecentShortTermSlugs(pensieveDir: string): string[] {
	const out: string[] = [];
	for (const kind of ["decisions", "knowledge", "maxims"]) {
		const dir = path.join(pensieveDir, "short-term", kind);
		try {
			for (const name of fs.readdirSync(dir)) {
				out.push(`${kind}/${name.replace(/\.md$/, "")}`);
			}
		} catch {
			// no dir → skip
		}
	}
	return out;
}

function readReferenceSnippet(skillRoot: string, kind: string): string {
	const refPath = path.join(skillRoot, ".src", "references", `${kind}s.md`);
	try {
		const txt = fs.readFileSync(refPath, "utf8");
		// Cap to ~6000 chars to keep prompt small
		return txt.length > 6000 ? `${txt.slice(0, 6000)}\n...(truncated)` : txt;
	} catch {
		return `(reference template not found at ${refPath} — emit the standard frontmatter + body for a ${kind})`;
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// LLM call wrapper with timeout + parent-signal forwarding
// ─────────────────────────────────────────────────────────────────────────────
async function callLLM(
	resolved: ResolvedModel,
	systemPrompt: string,
	userPrompt: string,
	timeoutMs: number,
	parentSignal: AbortSignal | undefined,
): Promise<string> {
	const ac = new AbortController();
	const timer = setTimeout(() => ac.abort(new Error(`timeout after ${timeoutMs}ms`)), timeoutMs);
	const onParentAbort = () => ac.abort(new Error("parent aborted"));
	parentSignal?.addEventListener("abort", onParentAbort, { once: true });

	try {
		const response = await complete(
			resolved.model,
			{
				systemPrompt,
				messages: [
					{
						role: "user" as const,
						content: [{ type: "text" as const, text: userPrompt }],
						timestamp: Date.now(),
					},
				],
			},
			{
				apiKey: resolved.apiKey,
				headers: resolved.headers,
				signal: ac.signal,
				maxTokens: 4096,
			},
		);
		if (response.stopReason === "error") {
			throw new Error(response.errorMessage || "llm error");
		}
		if (response.stopReason === "aborted") {
			throw new Error("aborted");
		}
		return response.content
			.filter((c): c is { type: "text"; text: string } => c.type === "text")
			.map((c) => c.text)
			.join("\n")
			.trim();
	} finally {
		clearTimeout(timer);
		parentSignal?.removeEventListener("abort", onParentAbort);
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Filesystem write
// ─────────────────────────────────────────────────────────────────────────────
function writeShortTermFile(
	pensieveDir: string,
	kind: "maxim" | "decision" | "knowledge",
	slug: string,
	dateIso: string,
	body: string,
): string {
	// Directory naming is asymmetric in Pensieve: `decisions/`, `maxims/`,
	// but `knowledge/` (singular). Naively appending "s" would land knowledge
	// entries under `short-term/knowledges/`, invisible to graph-sync / refine.
	const kindDir = kind === "knowledge" ? "knowledge" : `${kind}s`;
	const baseDir = path.join(pensieveDir, "short-term", kindDir);
	fs.mkdirSync(baseDir, { recursive: true });

	let target: string;
	if (kind === "knowledge") {
		// knowledge uses a directory with content.md
		const dir = path.join(baseDir, slug);
		fs.mkdirSync(dir, { recursive: true });
		target = path.join(dir, "content.md");
	} else if (kind === "decision") {
		target = path.join(baseDir, `${dateIso}-${slug}.md`);
	} else {
		// maxim — single sentence file
		target = path.join(baseDir, `${slug}.md`);
	}

	// Don't overwrite existing files — append `-N` if collision
	let final = target;
	let i = 2;
	while (fs.existsSync(final)) {
		const ext = path.extname(target);
		const without = target.slice(0, -ext.length);
		final = `${without}-${i}${ext}`;
		i++;
		if (i > 50) break; // safety
	}
	fs.writeFileSync(final, body, "utf8");
	return final;
}

// ─────────────────────────────────────────────────────────────────────────────
// State refresh — reuse upstream maintain-project-state.sh
// ─────────────────────────────────────────────────────────────────────────────
function refreshState(skillRoot: string, projectRoot: string, note: string): void {
	const script = path.join(skillRoot, ".src", "scripts", "maintain-project-state.sh");
	if (!fs.existsSync(script)) return;
	try {
		const proc = spawn(
			"bash",
			[script, "--event", "self-improve", "--note", note],
			{
				cwd: projectRoot,
				env: {
					...process.env,
					PENSIEVE_SKILL_ROOT: skillRoot,
					PENSIEVE_PROJECT_ROOT: projectRoot,
					PENSIEVE_HARNESS: "pi",
				},
				stdio: "ignore",
				detached: true,
			},
		);
		proc.on("error", () => {
			/* silent */
		});
		// Don't keep pi alive waiting for state-refresh in print mode; the
		// script has its own internal timeouts for any LLM calls it makes.
		proc.unref();
	} catch {
		// silent
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Main entry point
// ─────────────────────────────────────────────────────────────────────────────
export async function runSidecar(input: SidecarInput): Promise<SidecarResult> {
	const stateRoot = path.join(input.pensieveDir, ".state");
	const tag = `sid=${input.sessionId.slice(0, 8)}`;
	logLine(stateRoot, `${tag} sidecar:start msglen=${input.lastAssistantMessage.length}`);

	// 1. Resolve decision model
	const decisionResolved = await resolveModel(
		input.config.decisionModel,
		input.modelRegistry,
		input.fallbackModel,
	);
	if ("error" in decisionResolved) {
		logLine(stateRoot, `${tag} decision-model:error ${decisionResolved.error}`);
		return { skipped: true, reason: `decision model unavailable: ${decisionResolved.error}` };
	}
	logLine(stateRoot, `${tag} decision-model:ready ${decisionResolved.display}`);

	// 2. Decision call
	let decisionRaw: string;
	try {
		decisionRaw = await callLLM(
			decisionResolved,
			DECISION_SYSTEM_PROMPT,
			buildDecisionPrompt({
				lastAssistantMessage: input.lastAssistantMessage,
				recentShortTermSlugs: listRecentShortTermSlugs(input.pensieveDir),
			}),
			input.config.decisionTimeoutMs,
			input.parentSignal,
		);
	} catch (e: any) {
		logLine(stateRoot, `${tag} decision-call:fail ${e?.message ?? String(e)}`);
		return { skipped: true, reason: `decision call failed: ${e?.message ?? e}` };
	}

	const decision = extractDecisionJson(decisionRaw);
	if (!decision) {
		logLine(stateRoot, `${tag} decision-parse:fail rawlen=${decisionRaw.length}`);
		return { skipped: true, reason: "decision JSON parse failed" };
	}

	if (!decision.sediment || !decision.kind || !decision.slug || !decision.label) {
		logLine(
			stateRoot,
			`${tag} decision:skip reason="${decision.reason.slice(0, 200)}"`,
		);
		return { skipped: true, reason: decision.reason || "decision: skip" };
	}

	const slug = sanitizeSlug(decision.slug);
	if (!slug) {
		logLine(stateRoot, `${tag} decision:bad-slug raw="${decision.slug}"`);
		return { skipped: true, reason: `invalid slug: ${decision.slug}` };
	}

	logLine(
		stateRoot,
		`${tag} decision:sediment kind=${decision.kind} slug=${slug} label="${decision.label}"`,
	);

	// 3. Resolve writer model (independent of decision)
	const writerResolved = await resolveModel(
		input.config.writerModel,
		input.modelRegistry,
		input.fallbackModel,
	);
	if ("error" in writerResolved) {
		logLine(stateRoot, `${tag} writer-model:error ${writerResolved.error}`);
		return { skipped: true, reason: `writer model unavailable: ${writerResolved.error}` };
	}
	logLine(stateRoot, `${tag} writer-model:ready ${writerResolved.display}`);

	// 4. Writer call
	const dateIso = new Date().toISOString().slice(0, 10);
	let body: string;
	try {
		body = await callLLM(
			writerResolved,
			WRITER_SYSTEM_PROMPT,
			buildWriterPrompt({
				kind: decision.kind,
				slug,
				label: decision.label,
				lastAssistantMessage: input.lastAssistantMessage,
				dateIso,
				skillReferenceSnippet: readReferenceSnippet(input.skillRoot, decision.kind),
			}),
			input.config.writerTimeoutMs,
			input.parentSignal,
		);
	} catch (e: any) {
		logLine(stateRoot, `${tag} writer-call:fail ${e?.message ?? String(e)}`);
		return { skipped: true, reason: `writer call failed: ${e?.message ?? e}` };
	}

	if (!body || body.length < 100) {
		logLine(stateRoot, `${tag} writer-output:too-short len=${body?.length ?? 0}`);
		return { skipped: true, reason: "writer produced empty/short output" };
	}

	// Strip accidental code fences around the whole body
	body = body.replace(/^```(?:markdown|md)?\s*\n/i, "").replace(/\n```\s*$/i, "");

	// 5. Write file
	let filePath: string;
	try {
		filePath = writeShortTermFile(input.pensieveDir, decision.kind, slug, dateIso, body);
	} catch (e: any) {
		logLine(stateRoot, `${tag} write-file:fail ${e?.message ?? String(e)}`);
		return { skipped: true, reason: `file write failed: ${e?.message ?? e}` };
	}

	logLine(stateRoot, `${tag} written:${path.relative(input.pensieveDir, filePath)}`);

	// 6. Refresh project state (mirror what /skill:pensieve self-improve does at the end)
	refreshState(input.skillRoot, input.projectRoot, `auto-sediment: ${decision.label}`);

	logLine(stateRoot, `${tag} sidecar:done`);
	return {
		skipped: false,
		reason: decision.reason,
		label: decision.label,
		kind: decision.kind,
		slug,
		filePath,
	};
}
