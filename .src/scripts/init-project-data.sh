#!/bin/bash
# 初始化当前 pensieve 用户数据根目录。
#
# `.src/`、`agents/`、`SKILL.md` 是 git tracked 的系统文件。
# `SKILL.md` 由 maintain-project-skill.sh 在本地覆盖更新。
# 用户数据（maxims/decisions/knowledge/pipelines）由 .gitignore 忽略，
# 不参与 git 更新。
#
# 可重复执行（幂等）。

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

DATA_ROOT="$(user_data_root "$SCRIPT_DIR")"
STATE_ROOT="$(ensure_state_dir "$(state_root "$SCRIPT_DIR")")"

SKILL_ROOT="$(skill_root_from_script "$SCRIPT_DIR")"
TEMPLATES_ROOT="$SKILL_ROOT/.src/templates"
SYSTEM_KNOWLEDGE_ROOT="$SKILL_ROOT/.src/templates/knowledge"
PROJECT_SKILL_SCRIPT="$SKILL_ROOT/.src/scripts/maintain-project-skill.sh"

mkdir -p "$DATA_ROOT"/{maxims,decisions,knowledge,pipelines}

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

echo "✅ Initialization complete: $DATA_ROOT"
MAXIM_COUNT=0
if [[ -d "$DATA_ROOT/maxims" ]]; then
  MAXIM_COUNT="$(find "$DATA_ROOT/maxims" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
fi
echo "  - maxims/*.md: $MAXIM_COUNT files present"
echo "  - knowledge/*: seeded $KNOWLEDGE_SEEDED_COUNT new file(s)"
echo "  - pipelines/*: seeded $PIPELINE_SEEDED_COUNT new file(s)"
echo "  - runtime state: $STATE_ROOT"

if [[ -x "$PROJECT_SKILL_SCRIPT" ]]; then
  if ! bash "$PROJECT_SKILL_SCRIPT" --event install --note "seeded project data via init-project-data.sh"; then
    echo "⚠️  Generated SKILL update skipped: failed to run maintain-project-skill.sh" >&2
  fi
fi

MARKER_SCRIPT="$SKILL_ROOT/.src/scripts/pensieve-session-marker.sh"
if [[ -f "$MARKER_SCRIPT" ]]; then
  bash "$MARKER_SCRIPT" --mode record --event init || true
fi
