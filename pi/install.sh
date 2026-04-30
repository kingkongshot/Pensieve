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
EXT_TARGET="$EXT_DIR/pensieve-context"
EXT_SOURCE="$SKILL_PATH/pi/extensions/pensieve-context"

if [[ ! -d "$EXT_SOURCE" ]]; then
	echo "❌ pensieve-context extension not found at $EXT_SOURCE" >&2
	echo "   Make sure your Pensieve checkout is on a branch that includes pi/extensions/." >&2
	exit 1
fi

mkdir -p "$EXT_DIR"
if [[ -L "$EXT_TARGET" ]]; then
	# Already a symlink — point it at the source unconditionally so updates
	# to the submodule take effect immediately.
	ln -sfn "$EXT_SOURCE" "$EXT_TARGET"
	echo "✅ pensieve-context symlinked at $EXT_TARGET"
elif [[ -e "$EXT_TARGET" ]]; then
	echo "ℹ️  $EXT_TARGET already exists as a non-symlink. Leaving it alone."
	echo "   Remove it manually and re-run if you want pi to track the submodule."
else
	ln -s "$EXT_SOURCE" "$EXT_TARGET"
	echo "✅ pensieve-context symlinked at $EXT_TARGET"
fi

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
	SEDIMENT_TARGET="$EXT_DIR/pensieve-auto-sediment"
	SEDIMENT_SOURCE="$SKILL_PATH/pi/extensions/pensieve-auto-sediment"

	if [[ ! -d "$SEDIMENT_SOURCE" ]]; then
		echo "❌ pensieve-auto-sediment extension not found at $SEDIMENT_SOURCE" >&2
	else
		mkdir -p "$EXT_DIR"
		if [[ -L "$SEDIMENT_TARGET" ]]; then
			ln -sfn "$SEDIMENT_SOURCE" "$SEDIMENT_TARGET"
		elif [[ -e "$SEDIMENT_TARGET" ]]; then
			echo "ℹ️  $SEDIMENT_TARGET already exists as non-symlink. Leaving alone."
		else
			ln -s "$SEDIMENT_SOURCE" "$SEDIMENT_TARGET"
		fi
		echo "✅ pensieve-auto-sediment symlinked at $SEDIMENT_TARGET"
	fi
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
