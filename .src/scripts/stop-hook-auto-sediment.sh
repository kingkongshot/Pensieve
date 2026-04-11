#!/bin/bash
# Stop hook — per-turn auto-sediment trigger.
#
# Two modes (selected by PENSIEVE_SEDIMENT_MODE env var):
#
#   inline (default):
#     On first hook fire, filters pass → decision:block + prompt asking
#     main Claude to run /pensieve self-improve directly. Current behavior.
#
#   dispatch:
#     On first hook fire, filters pass → decision:block + prompt asking
#     main Claude to only output a SEDIMENT_SCHEDULED:<label> marker.
#     On second hook fire (stop_hook_active=true), handle_post_dispatch
#     reads the marker from last_assistant_message and launches a background
#     sidecar (`claude -r <session> -p "..." --bare`) that runs self-improve
#     asynchronously. Main session incurs ~700 token overhead instead of
#     20-50k token inline execution. Sidecar uses post-compact active context
#     (see knowledge/claude-cli-sidecar-context-scope).
#
# First-fire filters (both modes):
# - Hook is not in a recursion (stop_hook_active != true)
# - Project has .pensieve/ initialized
# - Ralph-Loop is not active (don't interfere)
# - Last assistant message is substantial (default ≥ 200 chars)
#
# Recursion prevention:
# - After sediment fires, Claude continues → stop_hook_active=true.
# - In dispatch mode, second fire runs handle_post_dispatch THEN recursion guard.
# - In inline mode, second fire hits recursion_guard directly and exits.
#
# Design notes:
# - No git_clean filter: relying on "commit pipeline handles dirty trees" is a fiction —
#   commit pipeline has no automatic trigger, so uncommitted-change turns would simply lose
#   their insights if we skipped them here. Instead, trust Claude to evaluate each turn.
# - No cooldown: any turn could be the last, time throttling drops insights permanently.
# - No session counter: long sessions can legitimately have multiple distinct insights.
#
# Short-circuits on first filter failure.
# Logs are captured via run-hook.sh → hook-trace.log.
# Dispatch-mode sidecar output → .state/sidecar-sediment.log.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Tunable: minimum last_assistant_message length to consider "substantial"
MIN_MSG_LENGTH="${PENSIEVE_SEDIMENT_MIN_LENGTH:-200}"

# Mode selector: inline | dispatch. Default inline preserves existing behavior.
# Normalize + whitelist: typos or invalid values silently fall back to inline.
# This is intentional — the hook should never crash on bad env, and the user
# can verify the mode via hook-trace.log 'dispatch-*' lines (presence = dispatch
# active, absence = inline).
SEDIMENT_MODE="${PENSIEVE_SEDIMENT_MODE:-inline}"
SEDIMENT_MODE="${SEDIMENT_MODE,,}"
case "$SEDIMENT_MODE" in
  inline|dispatch) ;;
  *) SEDIMENT_MODE=inline ;;
esac

# --- Helper: handle_post_dispatch ---
# On second hook fire (stop_hook_active=true) in dispatch mode, parse
# last_assistant_message for a SEDIMENT_SCHEDULED marker and spawn a
# background sidecar to run self-improve. Never fails the hook.
handle_post_dispatch() {
  local last_msg="$1"
  local session_id="$2"

  # Fast path: bash pattern match enforces "starts exactly with marker".
  # `grep -qE '^SEDIMENT_SCHEDULED:'` would match any line, so a main-Claude
  # reply that leads with prose and has the marker on a later line would
  # trigger dispatch with an empty label. We want first-char-only.
  [[ "$last_msg" == SEDIMENT_SCHEDULED:* ]] || return 0

  # Resolve project (skip silently if non-pensieve)
  local pr
  pr="$(project_root 2>/dev/null)" || return 0
  [[ -d "$pr/.pensieve" ]] || return 0

  # Require claude CLI in PATH
  command -v claude >/dev/null 2>&1 || return 0

  local state_dir="$pr/.pensieve/.state"
  local lock_dir="$state_dir/sidecar-sediment.lock"
  local sidecar_log="$state_dir/sidecar-sediment.log"
  local trace_log="$state_dir/hook-trace.log"
  # Guarded mkdir: on full/permission-denied disks the hook must still return 0.
  mkdir -p "$state_dir" 2>/dev/null || return 0

  # Extract first line's label. IMPORTANT: do NOT pipe into `head -c 120`.
  # Under `set -o pipefail`, head closing stdin after N bytes causes SIGPIPE
  # on awk, awk exits non-zero, the $(...) assignment fails, and set -e kills
  # the hook. Instead, let awk emit the full first line and truncate with
  # bash parameter expansion — which is SIGPIPE-safe AND UTF-8 character-aware
  # (bash ${var:0:N} counts characters, head -c counts bytes and can split
  # multi-byte codepoints).
  local label
  label=$(printf '%s' "$last_msg" \
    | awk 'NR==1 && /^SEDIMENT_SCHEDULED:/ {sub(/^SEDIMENT_SCHEDULED:[[:space:]]*/, ""); print; exit}')
  label=${label:0:120}

  local sidecar_prompt
  sidecar_prompt="[pensieve auto-sediment executor]
You are a background sidecar spawned after the main session's last turn completed.
Label hint: ${label:-unknown}

Task:
1. Look at the most recent assistant turn in the conversation history (the turn immediately BEFORE your current instruction).
2. Evaluate whether it contains insights worth sedimenting, using the standard auto-sediment signals (bug root cause, architecture decision, new pattern, symptom-to-root mapping, boundary clarification, capability discovery, good failure).
3. If insights are present, call /pensieve self-improve to sediment them.
4. Exit immediately without further dialog.

Strict rules:
- Do not ask the user questions.
- Do not call any skill other than /pensieve.
- Do not edit files outside of the pensieve write path.
- Do not continue the main task."

  # Spawn sidecar with atomic-mkdir lock + nohup SIGHUP immunity.
  # Design rationale:
  # - mkdir is atomic on POSIX: only one process succeeds in creating a given
  #   directory. This fuses "check lock" and "acquire lock" into one step
  #   and eliminates the TOCTOU window that plain PID-file locks have.
  # - PID inside the lock dir is ONLY for stale-detection after crash
  #   (previous sidecar died without trap cleanup). Normal exclusion is
  #   handled by mkdir atomicity, not by the PID check.
  # - `$BASHPID` (bash 4+) returns the real subshell PID, unlike `$$` which
  #   keeps the parent hook's PID and would mark the lock as stale the
  #   moment the hook exits.
  # - `nohup` immunizes the sidecar from SIGHUP if the hook's ancestor
  #   process group is signaled. `disown` removes it from the shell's job
  #   table. Belt-and-suspenders for interactive + non-interactive envs.
  (
    # Atomic lock acquisition: only one mkdir can succeed.
    if ! mkdir "$lock_dir" 2>/dev/null; then
      # Lock held — check if holder is actually alive.
      other_pid=$(cat "$lock_dir/pid" 2>/dev/null || true)
      if [[ -n "$other_pid" ]] && kill -0 "$other_pid" 2>/dev/null; then
        # Previous sidecar still running — yield this dispatch.
        printf '[%s] dispatch-skip: prev sidecar alive pid=%s\n' \
          "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$other_pid" \
          >> "$trace_log" 2>/dev/null || true
        exit 0
      fi
      # Stale lock from crashed sidecar — clean and retry once.
      rm -rf "$lock_dir" 2>/dev/null || true
      mkdir "$lock_dir" 2>/dev/null || exit 0
    fi
    printf '%s' "$BASHPID" > "$lock_dir/pid"
    trap 'rm -rf "$lock_dir"' EXIT
    cd "$pr" || exit 1
    export PENSIEVE_PROJECT_ROOT="$pr"
    nohup timeout 300 claude -r "$session_id" -p "$sidecar_prompt" \
      --bare \
      --permission-mode bypassPermissions \
      >> "$sidecar_log" 2>&1
  ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true

  printf '[%s] dispatch-launch: sid=%s label=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$session_id" "${label:-unknown}" \
    >> "$trace_log" 2>/dev/null || true
  return 0
}

# --- Read payload ---
HOOK_INPUT=""
if [[ ! -t 0 ]]; then
  HOOK_INPUT=$(timeout 2 cat 2>/dev/null || true)
fi

# Extract critical fields
SESSION_ID=""
STOP_HOOK_ACTIVE="missing"
LAST_MSG=""
LAST_MSG_LEN=0
if [[ -n "$HOOK_INPUT" ]] && command -v jq &>/dev/null; then
  SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
  STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | jq -r 'if has("stop_hook_active") then .stop_hook_active | tostring else "missing" end' 2>/dev/null || echo "error")
  LAST_MSG=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || echo "")
  LAST_MSG_LEN=${#LAST_MSG}
fi

# --- Post-dispatch: handle SEDIMENT_SCHEDULED marker on second hook fire ---
# Only dispatch mode + stop_hook_active=true path. Falls through to recursion
# guard after dispatch attempt (which always returns 0).
if [[ "$SEDIMENT_MODE" == "dispatch" && "$STOP_HOOK_ACTIVE" == "true" ]]; then
  handle_post_dispatch "$LAST_MSG" "$SESSION_ID"
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

# --- Probe support: persist payload for manual sidecar probe ---
# Minimal side effect: overwrites .state/last-stop-payload.json each invocation.
# Used by stop-hook-sidecar-probe.sh to test transcript timing + sidecar recovery.
# No behavior change — filters and decision:block output are unaffected.
if [[ -n "$HOOK_INPUT" ]]; then
  printf '%s' "$HOOK_INPUT" > "$STATE_ROOT/last-stop-payload.json" 2>/dev/null || true
fi

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

# --- Filter 3: Message substantial ---
[[ "$LAST_MSG_LEN" -lt "$MIN_MSG_LENGTH" ]] && exit 0

# --- All filters passed: fire sediment evaluation ---
# Two prompt variants: dispatch mode asks main Claude for a marker only, inline
# mode asks for direct /pensieve self-improve execution.
if [[ "$SEDIMENT_MODE" == "dispatch" ]]; then
cat <<'JSON'
{
  "decision": "block",
  "reason": "[PENSIEVE AUTO-SEDIMENT CHECK — dispatch mode]\n主任务已完成。这是自动沉淀评估，不是继续任务的信号。\n\n回顾本轮对话，检查是否命中以下信号（任一即沉淀）：\n\n成功信号:\n- 识别了 bug 根因\n- 做了架构或设计决策（考虑了多个方案）\n- 发现了新模式或反模式\n- 探索产出了\"症状→根因→定位\"映射\n- 澄清了边界、所有权、约束\n- 发现了系统中不存在/已废弃的能力\n\n失败信号（好的失败同样值得沉淀）:\n- 尝试了某方案但失败，失败原因不直觉\n- 踩到了文档未记录的坑或隐式约束\n- 排除了看似合理但实际不可行的路径\n\n判断结果:\n- 命中 → 首行必须为 SEDIMENT_SCHEDULED: <关键词>，次行为 1 句理由\n- 未命中 → 仅输出单行: NO_SEDIMENT: <简短理由>\n\n严格遵守:\n- 不要调用任何 tool（包括 /pensieve）\n- 不要继续主任务\n- 不要问用户问题\n- 沉淀将由独立 sidecar 异步执行，你的职责仅是决策\n- SEDIMENT_SCHEDULED 必须顶格且首行，否则沉淀会被跳过"
}
JSON
else
cat <<'JSON'
{
  "decision": "block",
  "reason": "[PENSIEVE AUTO-SEDIMENT CHECK]\n主任务已完成。这是自动沉淀评估，不是继续任务的信号。\n\n回顾本轮对话，检查是否命中以下信号（任一即沉淀）：\n\n成功信号:\n- 识别了 bug 根因\n- 做了架构或设计决策（考虑了多个方案）\n- 发现了新模式或反模式\n- 探索产出了\"症状→根因→定位\"映射\n- 澄清了边界、所有权、约束\n- 发现了系统中不存在/已废弃的能力\n\n失败信号（好的失败同样值得沉淀）:\n- 尝试了某方案但失败，失败原因不直觉\n- 踩到了文档未记录的坑或隐式约束\n- 排除了看似合理但实际不可行的路径\n\n判断结果:\n- 命中 → 执行 /pensieve self-improve 沉淀（完成后直接停止）\n- 未命中 → 仅输出单行: NO_SEDIMENT: <简短理由>\n\n严格遵守:\n- 不要继续主任务\n- 不要问用户问题\n- 不要调用除 /pensieve 外的 skill\n- 不要做 self-improve 之外的任何文件编辑"
}
JSON
fi
