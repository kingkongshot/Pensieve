#!/usr/bin/env bash
# Install Pensieve for the pi coding agent.
#
# Layers (smallest install first):
#   1. Skill (always)         — `~/.pi/agent/skills/pensieve` provides the
#                                six tools and the SKILL.md router.
#   2. pensieve-context       — knowledge-graph navigation card injected
#                                into the system prompt + auto-graph-sync
#                                when files inside .pensieve/ are edited.
#   3. (future) pensieve-auto-sediment — per-prompt auto-sediment trigger.
#
# By default this script does (1) + (2). Layer 3 is opt-in (--with-auto-sediment)
# once the extension exists.
#
# This script is *idempotent* and safe to re-run.

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
SKILL_PATH="${PENSIEVE_SKILL_PATH:-$HOME/.pi/agent/skills/pensieve}"
SKILL_DIR="${PENSIEVE_SKILL_DIR:-$HOME/.pi/agent/skills}"
EXT_DIR="${PENSIEVE_PI_EXT_DIR:-$HOME/.pi/agent/extensions}"
BRANCH="${PENSIEVE_BRANCH:-feature/auto-sediment-hook}"
REPO_URL="${PENSIEVE_REPO_URL:-https://github.com/kingkongshot/Pensieve.git}"
INIT_PROJECT=1
AUTO_SEDIMENT=0

usage() {
	cat <<USAGE
Usage: install.sh [options]

Options:
  --no-init-project   Skip running init-project-data.sh on the current cwd.
  --with-auto-sediment Also install Layer 3: per-prompt auto-sediment trigger.
  --skill-path PATH   Where the pensieve skill should live
                      (default: \$HOME/.pi/agent/skills/pensieve)
  --ext-dir PATH      Where pi looks up extensions
                      (default: \$HOME/.pi/agent/extensions)
  --branch NAME       Branch to clone if installing from scratch
                      (default: feature/auto-sediment-hook)
  -h, --help          Show this help.

The script prefers a Pensieve checkout that already exists at SKILL_PATH (e.g.
git submodule, manual clone, or an earlier run). If it isn't there, it clones
the requested branch.
USAGE
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--no-init-project) INIT_PROJECT=0; shift ;;
		--with-auto-sediment) AUTO_SEDIMENT=1; shift ;;
		--skill-path) SKILL_PATH="$2"; shift 2 ;;
		--ext-dir) EXT_DIR="$2"; shift 2 ;;
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

# ─── 2. pensieve-context extension ───────────────────────────────────────────
install_extension() {
	local ext_name="$1"
	local ext_target="$EXT_DIR/$ext_name"
	local ext_source="$SKILL_PATH/pi/extensions/$ext_name"

	if [[ ! -d "$ext_source" ]]; then
		echo "❌ $ext_name extension not found at $ext_source" >&2
		return 1
	fi

	mkdir -p "$EXT_DIR"
	# Create relative symlink so the layout survives cloning to a different HOME
	local rel_source
	rel_source="$(realpath --relative-to="$EXT_DIR" "$ext_source" 2>/dev/null || echo "")"
	[[ -z "$rel_source" ]] && rel_source="$ext_source"

	if [[ -L "$ext_target" ]]; then
		ln -sfn "$rel_source" "$ext_target"
		echo "✅ $ext_name symlinked at $ext_target"
	elif [[ -e "$ext_target" ]]; then
		echo "ℹ️  $ext_target already exists as a non-symlink. Leaving it alone."
		echo "   Remove it manually and re-run if you want pi to track the submodule."
	else
		ln -s "$rel_source" "$ext_target"
		echo "✅ $ext_name symlinked at $ext_target"
	fi
}

install_extension "pensieve-context"
[[ $? -ne 0 ]] && exit 1

# ─── 2.5 pensieve-wand skill ─────────────────────────────────────────────────
WAND_TARGET="$SKILL_DIR/pensieve-wand"
WAND_SOURCE="$SKILL_PATH/pi/skills/pensieve-wand"

if [[ -d "$WAND_SOURCE" ]]; then
	mkdir -p "$SKILL_DIR"
	# Create relative symlink so the layout survives cloning to a different HOME
	REL_SOURCE="$(realpath --relative-to="$SKILL_DIR" "$WAND_SOURCE" 2>/dev/null)"
	if [[ -z "$REL_SOURCE" ]]; then
		REL_SOURCE="$WAND_SOURCE"  # fallback to absolute on systems without realpath --relative-to
	fi
	if [[ -L "$WAND_TARGET" ]]; then
		ln -sfn "$REL_SOURCE" "$WAND_TARGET"
		echo "✅ pensieve-wand skill symlinked at $WAND_TARGET"
	elif [[ -e "$WAND_TARGET" ]]; then
		echo "ℹ️  $WAND_TARGET already exists as a non-symlink. Leaving alone."
	else
		ln -s "$REL_SOURCE" "$WAND_TARGET"
		echo "✅ pensieve-wand skill symlinked at $WAND_TARGET"
	fi
fi

# ─── 3 (optional). pensieve-auto-sediment extension ────────────────────────
if [[ "$AUTO_SEDIMENT" == "1" ]]; then
	install_extension "pensieve-auto-sediment" || true
fi

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
  • Restart pi (or run \`/reload\` in an interactive session) so the extension
    is picked up.
  • In a fresh pi session inside this project, ask:
      "What do you know about Pensieve memory in this project?"
    The system prompt now carries the navigation card.
  • To add Pensieve to another project later:
      cd <other-project>
      PENSIEVE_HARNESS=pi bash "$SKILL_PATH/.src/scripts/init-project-data.sh"
DONE
