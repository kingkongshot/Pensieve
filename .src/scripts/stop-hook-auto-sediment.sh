#!/bin/bash
# Stop hook — per-turn auto-sediment trigger.
#
# Triggers /pensieve self-improve on every turn that passes all 6 filters:
# - Hook is not in a recursion (stop_hook_active != true)
# - Project has .pensieve/ initialized
# - Ralph-Loop is not active (don't interfere)
# - Working tree is clean (commit pipeline handles dirty trees)
# - Cooldown has elapsed (default 600s since last sediment)
# - Last assistant message is substantial (default ≥ 200 chars)
#
# Rate limiting is provided by cooldown + git_clean + recursion_guard naturally:
# - After sediment fires, Claude continues → stop_hook_active=true → recursion_guard SKIP
# - After continuation, new short-term files → git_clean FAIL → SKIP
# - Within 10min of last sediment → cooldown FAIL → SKIP
# Long sessions can legitimately sediment multiple distinct insights as long as
# 10min+ and commit boundaries separate them.
#
# On all-pass: outputs decision:block + signal evaluation prompt.
# Claude continues one turn to evaluate signals and run /pensieve self-improve,
# or output NO_SEDIMENT if no signals match.
#
# Short-circuits on first filter failure.
# Logs are captured via run-hook.sh → hook-trace.log.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Tunables (override via environment)
COOLDOWN_SECONDS="${PENSIEVE_SEDIMENT_COOLDOWN:-600}"
MIN_MSG_LENGTH="${PENSIEVE_SEDIMENT_MIN_LENGTH:-200}"

# --- Read payload ---
HOOK_INPUT=""
if [[ ! -t 0 ]]; then
  HOOK_INPUT=$(timeout 2 cat 2>/dev/null || true)
fi

# Extract critical fields
SESSION_ID=""
STOP_HOOK_ACTIVE="missing"
LAST_MSG_LEN=0
if [[ -n "$HOOK_INPUT" ]] && command -v jq &>/dev/null; then
  SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
  STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | jq -r 'if has("stop_hook_active") then .stop_hook_active | tostring else "missing" end' 2>/dev/null || echo "error")
  LAST_MSG_LEN=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // "" | length' 2>/dev/null || echo 0)
fi

# --- Filter 0: Recursion guard ---
# Hook-triggered continuation has stop_hook_active=true. Skip to prevent infinite loop.
[[ "$STOP_HOOK_ACTIVE" == "true" ]] && exit 0

# --- Filter 1: Pensieve project ---
PROJECT_ROOT="$(project_root 2>/dev/null)" || exit 0
PENSIEVE_DIR="$PROJECT_ROOT/.pensieve"
[[ -d "$PENSIEVE_DIR" ]] || exit 0

STATE_ROOT="$PENSIEVE_DIR/.state"
mkdir -p "$STATE_ROOT"

# --- Filter 2: Ralph-Loop not active ---
for candidate in \
  "${CLAUDE_PROJECT_DIR:-.}/.claude/loop-state.local.md" \
  "$HOME/.claude/loop-state.local.md"; do
  if [[ -f "$candidate" ]]; then
    loop_active=$(grep -m1 '^active:' "$candidate" 2>/dev/null | sed 's/^active:[[:space:]]*//' | tr -d '"' || true)
    [[ "$loop_active" == "true" ]] && exit 0
    break
  fi
done

# --- Filter 3: Working tree clean (commit pipeline handles dirty trees) ---
if cd "$PROJECT_ROOT" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
  # grep -cv returns exit 1 on no matches; fallback to 0 via || echo 0
  UNCOMMITTED=$(git status --porcelain 2>/dev/null | { grep -cv '^?? \.pensieve/\.state/' || echo 0; })
  [[ "$UNCOMMITTED" -gt 0 ]] && exit 0
fi

# --- Filter 4: Cooldown ---
LAST_SEDIMENT_FILE="$STATE_ROOT/last-sediment-time"
if [[ -f "$LAST_SEDIMENT_FILE" ]]; then
  LAST_EPOCH=$(cat "$LAST_SEDIMENT_FILE" 2>/dev/null || echo 0)
  if [[ "$LAST_EPOCH" -gt 0 ]]; then
    NOW_EPOCH=$(date -u +%s)
    ELAPSED=$((NOW_EPOCH - LAST_EPOCH))
    [[ "$ELAPSED" -lt "$COOLDOWN_SECONDS" ]] && exit 0
  fi
fi

# --- Filter 5: Message substantial ---
[[ "$LAST_MSG_LEN" -lt "$MIN_MSG_LENGTH" ]] && exit 0

# --- All filters passed: fire sediment evaluation ---
# Record timestamp before outputting JSON (drives cooldown on next turn).
date -u +%s > "$LAST_SEDIMENT_FILE" 2>/dev/null

cat <<'JSON'
{
  "decision": "block",
  "reason": "[PENSIEVE AUTO-SEDIMENT CHECK]\n主任务已完成。这是自动沉淀评估，不是继续任务的信号。\n\n回顾本轮对话，检查是否命中以下信号（任一即沉淀）：\n\n成功信号:\n- 识别了 bug 根因\n- 做了架构或设计决策（考虑了多个方案）\n- 发现了新模式或反模式\n- 探索产出了\"症状→根因→定位\"映射\n- 澄清了边界、所有权、约束\n- 发现了系统中不存在/已废弃的能力\n\n失败信号（好的失败同样值得沉淀）:\n- 尝试了某方案但失败，失败原因不直觉\n- 踩到了文档未记录的坑或隐式约束\n- 排除了看似合理但实际不可行的路径\n\n判断结果:\n- 命中 → 执行 /pensieve self-improve 沉淀（完成后直接停止）\n- 未命中 → 仅输出单行: NO_SEDIMENT: <简短理由>\n\n严格遵守:\n- 不要继续主任务\n- 不要问用户问题\n- 不要调用除 /pensieve 外的 skill\n- 不要做 self-improve 之外的任何文件编辑"
}
JSON
