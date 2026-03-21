#!/bin/bash
# Initialize the current project's Pensieve user data directory.
#
# System files (SKILL.md, .src/, agents/) are at the user-level skill root.
# User data (maxims/decisions/knowledge/pipelines) lives at <project>/.pensieve/.
# Runtime state lives at <project>/.pensieve/.state/.
#
# Idempotent — safe to run repeatedly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

is_readme_file() {
  case "$(basename "$1")" in
    [Rr][Ee][Aa][Dd][Mm][Ee]|[Rr][Ee][Aa][Dd][Mm][Ee].md)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Guard against running from outside a real project directory.
_PROJECT_ROOT="$(project_root)"
validate_project_root "$_PROJECT_ROOT" || exit 1

DATA_ROOT="$(user_data_root)"
STATE_ROOT="$(ensure_state_dir "$(state_root)")"

SKILL_ROOT="$(skill_root_from_script "$SCRIPT_DIR")"
TEMPLATES_ROOT="$SKILL_ROOT/.src/templates"
SYSTEM_KNOWLEDGE_ROOT="$SKILL_ROOT/.src/templates/knowledge"
PROJECT_STATE_SCRIPT="$SKILL_ROOT/.src/scripts/maintain-project-state.sh"

mkdir -p "$DATA_ROOT"/{maxims,decisions,knowledge,pipelines}
mkdir -p "$DATA_ROOT"/short-term/{maxims,decisions,knowledge,pipelines}

# Create .pensieve/.gitignore (only ignore .state/)
PENSIEVE_GITIGNORE="$DATA_ROOT/.gitignore"
if [[ ! -f "$PENSIEVE_GITIGNORE" ]]; then
  cat > "$PENSIEVE_GITIGNORE" <<'EOF'
# Runtime state (reports, markers, caches, graph snapshots)
.state/
EOF
fi

TEMPLATE_MAXIMS_DIR="$TEMPLATES_ROOT/maxims"
if [[ -d "$TEMPLATE_MAXIMS_DIR" ]]; then
  for template_maxim in "$TEMPLATE_MAXIMS_DIR"/*.md; do
    [[ -f "$template_maxim" ]] || continue
    is_readme_file "$template_maxim" && continue
    target_maxim="$DATA_ROOT/maxims/$(basename "$template_maxim")"
    if [[ ! -f "$target_maxim" ]]; then
      cp "$template_maxim" "$target_maxim"
    fi
  done
fi

KNOWLEDGE_SEEDED_COUNT=0
if [[ -d "$SYSTEM_KNOWLEDGE_ROOT" ]]; then
  while IFS= read -r source_file; do
    [[ -f "$source_file" ]] || continue
    is_readme_file "$source_file" && continue
    rel_path="${source_file#$SYSTEM_KNOWLEDGE_ROOT/}"
    target_file="$DATA_ROOT/knowledge/$rel_path"
    mkdir -p "$(dirname "$target_file")"
    if [[ ! -f "$target_file" ]]; then
      cp "$source_file" "$target_file"
      ((KNOWLEDGE_SEEDED_COUNT++)) || true
    fi
  done < <(find "$SYSTEM_KNOWLEDGE_ROOT" -type f | LC_ALL=C sort)
fi

PIPELINE_SEEDED_COUNT=0
for template_pipeline in "$TEMPLATES_ROOT"/pipeline.run-when-*.md; do
  [[ -f "$template_pipeline" ]] || continue
  is_readme_file "$template_pipeline" && continue
  pipeline_name="$(basename "$template_pipeline" | sed 's/^pipeline\.//')"
  target_pipeline="$DATA_ROOT/pipelines/$pipeline_name"
  if [[ ! -f "$target_pipeline" ]]; then
    cp "$template_pipeline" "$target_pipeline"
    ((PIPELINE_SEEDED_COUNT++)) || true
  fi
done

# Seed custom agents for detected clients.
# Only seed when the client's config directory already exists in the project.
TEMPLATE_AGENTS_DIR="$TEMPLATES_ROOT/agents"
AGENT_SEEDED_COUNT=0
AGENT_SEEDED_TARGET=""
if [[ -d "$TEMPLATE_AGENTS_DIR" ]]; then
  for client_dir in .claude; do
    if [[ -d "$_PROJECT_ROOT/$client_dir" ]]; then
      AGENTS_DIR="$_PROJECT_ROOT/$client_dir/agents"
      mkdir -p "$AGENTS_DIR"
      for template_agent in "$TEMPLATE_AGENTS_DIR"/*.md; do
        [[ -f "$template_agent" ]] || continue
        is_readme_file "$template_agent" && continue
        target_agent="$AGENTS_DIR/$(basename "$template_agent")"
        if [[ ! -f "$target_agent" ]]; then
          cp "$template_agent" "$target_agent"
          ((AGENT_SEEDED_COUNT++)) || true
        fi
      done
      AGENT_SEEDED_TARGET="$client_dir/agents/"
      break
    fi
  done
fi

echo "✅ Initialization complete: $DATA_ROOT"
MAXIM_COUNT=0
if [[ -d "$DATA_ROOT/maxims" ]]; then
  MAXIM_COUNT="$(find "$DATA_ROOT/maxims" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
fi
echo "  - maxims/*.md: $MAXIM_COUNT files present"
echo "  - knowledge/*: seeded $KNOWLEDGE_SEEDED_COUNT new file(s)"
echo "  - pipelines/*: seeded $PIPELINE_SEEDED_COUNT new file(s)"
if [[ -n "$AGENT_SEEDED_TARGET" ]]; then
  echo "  - agents: seeded $AGENT_SEEDED_COUNT new file(s) → $AGENT_SEEDED_TARGET"
else
  echo "  - agents: skipped (no client config directory detected)"
fi
echo "  - runtime state: $STATE_ROOT"

if [[ -f "$PROJECT_STATE_SCRIPT" ]]; then
  if ! bash "$PROJECT_STATE_SCRIPT" --event install --note "seeded project data via init-project-data.sh"; then
    echo "⚠️  Generated state update skipped: failed to run maintain-project-state.sh" >&2
  fi
fi

MARKER_SCRIPT="$SKILL_ROOT/.src/scripts/pensieve-session-marker.sh"
if [[ -f "$MARKER_SCRIPT" ]]; then
  bash "$MARKER_SCRIPT" --mode record --event init || true
fi
