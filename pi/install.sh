#!/usr/bin/env bash
# Install Pensieve for the pi coding agent.
#
# Layers (smallest install first):
#   1. Skill (always)         — `~/.pi/agent/skills/pensieve` provides the
#                                six tools and the SKILL.md router.
#   2. pensieve-context       — knowledge-graph navigation card injected
#                                into the system prompt + auto-graph-sync
#                                when files inside .pensieve/ are edited.
#   3. pensieve-wand          — pre-change context retrieval skill.
#
# This script adds pensieve paths to ~/.pi/agent/settings.json instead of
# creating symlinks (pi-native method, unified with pi-gstack approach).
#
# Idempotent and safe to re-run.

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
SKILL_PATH="${PENSIEVE_SKILL_PATH:-$HOME/.pi/agent/skills/pensieve}"
BRANCH="${PENSIEVE_BRANCH:-pi}"
REPO_URL="${PENSIEVE_REPO_URL:-https://github.com/kingkongshot/Pensieve.git}"
SETTINGS_FILE="$HOME/.pi/agent/settings.json"
INIT_PROJECT=1

usage() {
	cat <<USAGE
Usage: install.sh [options]

Options:
  --no-init-project   Skip running init-project-data.sh on the current cwd.
  --skill-path PATH   Where the pensieve skill should live
                      (default: \$HOME/.pi/agent/skills/pensieve)
  --branch NAME       Branch to clone if installing from scratch
                      (default: pi)
  -h, --help          Show this help.

The script prefers a Pensieve checkout that already exists at SKILL_PATH (e.g.
git submodule, manual clone, or an earlier run). If it isn't there, it clones
the requested branch.
USAGE
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--no-init-project) INIT_PROJECT=0; shift ;;
		--skill-path) SKILL_PATH="$2"; shift 2 ;;
		--branch) BRANCH="$2"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
	esac
done

# ─── 1. Skill ────────────────────────────────────────────────────────────────
if [[ -f "$SKILL_PATH/.src/manifest.json" ]]; then
	echo "✅ Pensieve skill present at $SKILL_PATH"
else
	echo "→ Cloning Pensieve ($BRANCH) into $SKILL_PATH"
	mkdir -p "$(dirname "$SKILL_PATH")"
	git clone -b "$BRANCH" --single-branch "$REPO_URL" "$SKILL_PATH"
fi

# ─── 2. Update settings.json ─────────────────────────────────────────────────
if [[ ! -f "$SETTINGS_FILE" ]]; then
	echo "{}" > "$SETTINGS_FILE"
fi

SKILLS_PATH="$SKILL_PATH/pi/skills"
EXTS_PATH="$SKILL_PATH/pi/extensions"

# Add skills path
if command -v jq &>/dev/null; then
	# Add pi/skills if not present
	HAS_SKILLS=$(jq --arg p "$SKILLS_PATH" '.skills // [] | index($p)' "$SETTINGS_FILE")
	if [[ "$HAS_SKILLS" == "null" ]]; then
		jq --arg p "$SKILLS_PATH" '.skills = ([$p] + (.skills // []))' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
		mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
		echo "✅ Added $SKILLS_PATH to settings.json skills"
	else
		echo "ℹ️  $SKILLS_PATH already in settings.json skills"
	fi

	# Add pi/extensions if not present
	HAS_EXTS=$(jq --arg p "$EXTS_PATH" '.extensions // [] | index($p)' "$SETTINGS_FILE")
	if [[ "$HAS_EXTS" == "null" ]]; then
		jq --arg p "$EXTS_PATH" '.extensions = ([$p] + (.extensions // []))' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
		mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
		echo "✅ Added $EXTS_PATH to settings.json extensions"
	else
		echo "ℹ️  $EXTS_PATH already in settings.json extensions"
	fi
else
	echo "⚠️  jq not available — add these paths manually to $SETTINGS_FILE:"
	echo "   \"skills\": [\"$SKILLS_PATH\"]"
	echo "   \"extensions\": [\"$EXTS_PATH\"]"
fi

# ─── 3. Clean up old symlinks (migration from pre-package.json era) ───────────
for old_link in "$HOME/.pi/agent/extensions/pensieve-context" \
                "$HOME/.pi/agent/skills/pensieve-wand"; do
	if [[ -L "$old_link" ]]; then
		rm "$old_link"
		echo "🧹 Removed legacy symlink: $old_link"
	fi
done

# ─── 4. Project init ─────────────────────────────────────────────────────────
if [[ "$INIT_PROJECT" == "1" ]]; then
	if [[ -d ".pensieve" ]]; then
		echo "✅ Current project already initialized: $(pwd)/.pensieve"
	else
		echo "→ Initializing Pensieve in current project: $(pwd)"
		PENSIEVE_HARNESS=pi bash "$SKILL_PATH/.src/scripts/init-project-data.sh"
	fi
fi

cat <<DONE

Done.

Next steps:
  • Restart pi (or run \`/reload\` in an interactive session).
  • Pensieve extensions and skills are now managed via settings.json paths
    (same method as pi-gstack). No symlinks needed.
  • To add Pensieve to another project later:
      cd <other-project>
      PENSIEVE_HARNESS=pi bash "$SKILL_PATH/.src/scripts/init-project-data.sh"
DONE
