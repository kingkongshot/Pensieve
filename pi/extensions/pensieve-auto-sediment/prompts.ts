/**
 * Sidecar prompts.
 *
 * Two stages, two prompts:
 *
 *   DECISION_PROMPT  → strict JSON output, "should we sediment?"
 *   WRITER_PROMPT    → markdown body, follows .src/references/{kind}.md format
 *
 * Design notes:
 *   - Both prompts deliberately stay simple and self-contained. CC's archived
 *     dispatch design (`~/.claude/.pensieve/decisions/2026-04-11-sidecar-...`)
 *     showed complex multi-section sidecar prompts cause Anthropic CLI to
 *     silently block. We don't go through `claude -r` here, but keeping
 *     prompts simple is still good defense.
 *   - Decision JSON schema is parseable without tool-use; we just ask for
 *     a fenced JSON block and parse it permissively.
 */

export interface DecisionInput {
	lastAssistantMessage: string;
	/** Optional: list of recent short-term entries (slugs) so the model can
	 *  avoid creating obvious duplicates. We don't read full content — keeping
	 *  the decision call cheap. */
	recentShortTermSlugs: string[];
}

export const DECISION_SYSTEM_PROMPT = `You are the Pensieve auto-sediment classifier.

You read the FINAL assistant message of a coding-agent turn and decide whether
that turn produced a durable engineering insight worth saving to the project's
long-term memory ("Pensieve").

Output ONLY a single fenced JSON block, nothing else.

JSON schema:
{
  "sediment": boolean,           // true = save it; false = skip
  "kind": "maxim" | "decision" | "knowledge" | null,
  "slug": string | null,         // 2-6 lowercase words separated by hyphens (no leading date)
  "label": string | null,        // <= 60 char human-readable headline
  "reason": string               // 1 sentence, why this decision
}

Sediment rules:

- "decision": an explicit architectural choice between alternatives, with
  context and consequences. Title pattern: "<X> 改为 <Y>", "采用 <Z>".
- "knowledge": a stable cached fact, call chain, anti-pattern, or
  symptom→root-cause map. Reusable beyond the current task.
- "maxim": a hard cross-project rule ("must / must not"). Rare. Default to
  decision/knowledge unless the insight is clearly universal.
- false ("skip"): the turn is execution of a previously-decided plan,
  routine implementation, status update, asking the user a question, or
  pure exploration without a settled conclusion.

Be conservative. False positives pollute the memory store. When in doubt, skip.

Slug rules (only when sediment=true):
- 2-6 lowercase words, hyphen-separated, ASCII only
- describe the insight, not the project (e.g. "in-process-llm-sidecar", not "pi-thing")
- avoid generic words like "design", "issue", "fix" alone
`;

export function buildDecisionPrompt(input: DecisionInput): string {
	const recentList = input.recentShortTermSlugs.length
		? `\n\nRecent short-term slugs (avoid obvious duplicates):\n${input.recentShortTermSlugs
				.slice(0, 30)
				.map((s) => `- ${s}`)
				.join("\n")}`
		: "";

	return `Evaluate the following final assistant message and emit the JSON decision.${recentList}

<final-assistant-message>
${input.lastAssistantMessage}
</final-assistant-message>`;
}

export interface WriterInput {
	kind: "maxim" | "decision" | "knowledge";
	slug: string;
	label: string;
	lastAssistantMessage: string;
	dateIso: string; // YYYY-MM-DD
	skillReferenceSnippet: string; // content of .src/references/{kind}.md (or summary)
}

export const WRITER_SYSTEM_PROMPT = `You are the Pensieve sediment writer.

You produce ONE markdown file capturing a durable insight, formatted to match
the project's reference template for the given kind (maxim / decision / knowledge).

Output ONLY the file content (with frontmatter), no surrounding prose, no fences.

Frontmatter MUST include: id, type, title, status: active, created (ISO date), tags.

Body MUST follow the reference template structure. Be precise and concise. Cite
file paths and exact symbols when relevant. Do NOT invent facts — only restate
and structure what's in the source assistant message.`;

export function buildWriterPrompt(input: WriterInput): string {
	return `Reference template for kind="${input.kind}":

${input.skillReferenceSnippet}

---

Produce a ${input.kind} markdown file.

- id: ${input.kind === "decision" ? `${input.dateIso}-${input.slug}` : input.slug}
- title: ${input.label}
- created: ${input.dateIso}
- The frontmatter \`type\` field MUST be exactly "${input.kind}".

Source material (final assistant message of the turn):

<source>
${input.lastAssistantMessage}
</source>

Write the file now.`;
}
