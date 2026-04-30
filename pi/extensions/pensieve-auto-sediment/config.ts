/**
 * Auto-sediment configuration resolution.
 *
 * Four-tier override (highest precedence first):
 *   1. env vars (PENSIEVE_SEDIMENT_MODEL, PENSIEVE_SEDIMENT_DECISION_MODEL,
 *                PENSIEVE_SEDIMENT_WRITER_MODEL, PENSIEVE_SEDIMENT_MIN_LENGTH)
 *   2. project: .pensieve/config.json -> auto_sediment.{...}
 *   3. global:  ~/.pi/.pensieve-auto-sediment.json -> auto_sediment.{...}
 *   4. fallback: null model → caller falls back to ctx.model (main session model)
 *
 * Why a *pi-only* global file (not ~/.config/pensieve/config.json):
 *   The Pensieve project-level `.pensieve/config.json` is shared across
 *   harnesses (CC + pi). CC's auto-sediment runs inline (no sidecar — see
 *   ~/.claude/.pensieve/decisions/2026-04-11-sidecar-sediment-dispatch-design.md
 *   archived) and never reads `decision_model` / `writer_model`. Putting
 *   sidecar model defaults under a "global pensieve" path would mislead
 *   users into thinking CC honors them. Hence: pi-only file, pi-only fields.
 *
 *   Project-level fields that ARE harness-shared (`enabled`,
 *   `min_message_length`) are intentionally NOT readable from the global
 *   file — keep them in `.pensieve/config.json` where bash can also see them.
 *
 * Model strings: "<provider>/<modelId>", e.g. "anthropic/claude-haiku-4-5".
 *
 * Hot-reloaded: read on every agent_end fire so users can edit config
 * without restarting pi.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

export interface ModelRef {
	provider: string;
	modelId: string;
}

export interface SedimentConfig {
	/** Whether auto-sediment is enabled. Mirrors the upstream .sh Filter 0.5
	 *  check; kept here so the TS layer can short-circuit before spawning. */
	enabled: boolean;
	/** Model used to evaluate "should we sediment this turn?". */
	decisionModel: ModelRef | null;
	/** Model used to generate the markdown body when sedimenting. */
	writerModel: ModelRef | null;
	/** Minimum last_assistant_message length (also enforced by .sh Filter 3). */
	minLength: number;
	/** Decision-model timeout in ms. */
	decisionTimeoutMs: number;
	/** Writer-model timeout in ms. */
	writerTimeoutMs: number;
}

export function parseModelRef(s: string | undefined | null): ModelRef | null {
	if (!s || typeof s !== "string") return null;
	const trimmed = s.trim();
	if (!trimmed) return null;
	const slash = trimmed.indexOf("/");
	if (slash <= 0 || slash === trimmed.length - 1) return null;
	return {
		provider: trimmed.slice(0, slash),
		modelId: trimmed.slice(slash + 1),
	};
}

export function formatModelRef(ref: ModelRef): string {
	return `${ref.provider}/${ref.modelId}`;
}

/** Path to the pi-only global sidecar config. Override with env for tests. */
export function globalSidecarConfigPath(): string {
	return (
		process.env.PENSIEVE_AUTO_SEDIMENT_GLOBAL_CONFIG ||
		path.join(os.homedir(), ".pi", ".pensieve-auto-sediment.json")
	);
}

function readJsonSafe(p: string): any {
	try {
		return JSON.parse(fs.readFileSync(p, "utf8"));
	} catch {
		return {};
	}
}

/**
 * Resolve the {decision, writer} model pair from a single auto_sediment
 * sub-object. Specific (`decision_model`/`writer_model`) wins over common
 * (`model`) within the same layer.
 */
function layerModels(auto: any): {
	decision: ModelRef | null;
	writer: ModelRef | null;
} {
	const common = parseModelRef(auto?.model);
	return {
		decision: parseModelRef(auto?.decision_model) ?? common,
		writer: parseModelRef(auto?.writer_model) ?? common,
	};
}

export function loadConfig(pensieveDir: string): SedimentConfig {
	const projectAuto =
		readJsonSafe(path.join(pensieveDir, "config.json")).auto_sediment || {};
	const globalAuto = readJsonSafe(globalSidecarConfigPath()).auto_sediment || {};

	// env > project > global; specific > common within each layer
	const envCommon = parseModelRef(process.env.PENSIEVE_SEDIMENT_MODEL);
	const envDecision = parseModelRef(process.env.PENSIEVE_SEDIMENT_DECISION_MODEL) ?? envCommon;
	const envWriter = parseModelRef(process.env.PENSIEVE_SEDIMENT_WRITER_MODEL) ?? envCommon;

	const proj = layerModels(projectAuto);
	const glob = layerModels(globalAuto);

	// `enabled` and `min_message_length` are intentionally NOT read from the
	// global file — they belong to the harness-shared project-level pensieve
	// config so bash (CC) and TS (pi) agree.
	//
	// minLength priority (matches model/timeout: env > project > default):
	const envMinLen = Number.parseInt(process.env.PENSIEVE_SEDIMENT_MIN_LENGTH ?? "", 10);
	const minLength =
		Number.isFinite(envMinLen) && envMinLen > 0
			? envMinLen
			: typeof projectAuto.min_message_length === "number" && projectAuto.min_message_length > 0
				? projectAuto.min_message_length
				: 200;

	// Timeouts: project > global > default. Read both layers, project wins.
	const pickPositiveNum = (...vals: unknown[]): number | undefined => {
		for (const v of vals) if (typeof v === "number" && v > 0) return v;
		return undefined;
	};
	const decisionTimeoutMs =
		pickPositiveNum(projectAuto.decision_timeout_ms, globalAuto.decision_timeout_ms) ?? 30_000;
	const writerTimeoutMs =
		pickPositiveNum(projectAuto.writer_timeout_ms, globalAuto.writer_timeout_ms) ?? 90_000;

	return {
		enabled: projectAuto.enabled !== false,
		decisionModel: envDecision ?? proj.decision ?? glob.decision,
		writerModel: envWriter ?? proj.writer ?? glob.writer,
		minLength,
		decisionTimeoutMs,
		writerTimeoutMs,
	};
}
