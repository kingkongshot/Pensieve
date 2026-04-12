#!/bin/bash
# Stop hook — per-turn auto-sediment trigger (inline mode only).
#
# On first hook fire, filters pass → decision:block + prompt asking
# main Claude to run /pensieve self-improve directly.
#
# Filters (short-circuit on first failure):
# - Filter 0:    not in recursion (stop_hook_active != true)
# - Filter 1:    project has .pensieve/ initialized
# - Filter 0.5:  .pensieve/config.json auto_sediment.enabled != false
# - Filter 2:    Ralph-Loop is not active (don't interfere)
# - Filter 3:    last assistant message is substantial (default ≥ 200 chars)
# - Filter 4:    last message does NOT look like a pending question to the user
#                (Claude asking and waiting for input → this turn is not a
#                 sediment opportunity; skip evaluation. Heuristic based on
#                 trailing punctuation and common Chinese/English question
#                 patterns. See knowledge/auto-sediment-text-question-stop-waste
#                 for rationale and cost analysis.)
#
# Recursion prevention:
# - After sediment fires, Claude continues → stop_hook_active=true.
# - Second fire hits recursion_guard (Filter 0) and exits.
#
# Config on/off:
# - User can disable auto-sediment by editing .pensieve/config.json:
#     {"auto_sediment": {"enabled": false}}
# - Config file missing / malformed JSON → default enabled (backwards compat).
# - Change takes effect immediately; no Claude Code restart needed (hook reads
#   config on every fire).
#
# Design notes:
# - No git_clean filter: commit pipeline has no automatic trigger, so
#   uncommitted-change turns would simply lose their insights if we skipped
#   them here. Trust Claude to evaluate each turn.
# - No cooldown: any turn could be the last, time throttling drops insights
#   permanently.
# - No session counter: long sessions can legitimately have multiple distinct
#   insights.
#
# History:
# - 2026-04-11 sidecar dispatch mode was attempted and rolled back. See
#   decisions/2026-04-11-sidecar-sediment-dispatch-design.md (archived).
#
# Logs are captured via run-hook.sh → hook-trace.log.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Tunable: minimum last_assistant_message length to consider "substantial"
MIN_MSG_LENGTH="${PENSIEVE_SEDIMENT_MIN_LENGTH:-200}"

# --- Read payload ---
HOOK_INPUT=""
if [[ ! -t 0 ]]; then
  HOOK_INPUT=$(timeout 2 cat 2>/dev/null || true)
fi

# Extract critical fields
STOP_HOOK_ACTIVE="missing"
LAST_MSG=""
LAST_MSG_LEN=0
if [[ -n "$HOOK_INPUT" ]] && command -v jq &>/dev/null; then
  STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | jq -r 'if has("stop_hook_active") then .stop_hook_active | tostring else "missing" end' 2>/dev/null || echo "error")
  LAST_MSG=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || echo "")
  LAST_MSG_LEN=${#LAST_MSG}
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

# --- Filter 0.5: Config enabled check ---
# 读 .pensieve/config.json；auto_sediment.enabled=false 时静默 exit 0。
# 配置缺失、字段缺失、malformed → 默认 enabled（向后兼容其他 pensieve 项目）。
# 热加载：每次 hook fire 重新读文件，改 config 立即生效，无需重启 Claude Code。
#
# jq 陷阱：`.x.y // true` 当 .x.y 为 false 时会错误返回 true（因为 jq `//`
# 对 null/false/empty 三者都触发 default）。必须用 `== false` 显式比较。
CONFIG_FILE="$PENSIEVE_DIR/config.json"
if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
  AUTO_SEDIMENT_DISABLED=$(jq -r 'if .auto_sediment.enabled == false then "yes" else "no" end' "$CONFIG_FILE" 2>/dev/null || echo "no")
  [[ "$AUTO_SEDIMENT_DISABLED" == "yes" ]] && exit 0
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

# --- Filter 4: Pending question heuristic ---
# 如果本轮 Claude 在向用户提问并等待输入（而非用 AskUserQuestion 工具），
# 这个 turn 不是沉淀时机 —— 提问本身不是洞察，评估续轮大概率 NO_SEDIMENT
# 白白消耗 ~600-5000 token。参见 knowledge/auto-sediment-text-question-stop-waste。
#
# 启发式：取最后 ~300 字节，检测常见中英文提问结尾/句式。
# 精度目标 70-85%，误判为"问题"时代价仅为漏一次沉淀评估（可接受）。
# 不用 pipe，避免 pipefail 陷阱。
if [[ "$LAST_MSG_LEN" -gt 300 ]]; then
  TAIL_MSG="${LAST_MSG:$(( LAST_MSG_LEN - 300 ))}"
else
  TAIL_MSG="$LAST_MSG"
fi
if [[ "$TAIL_MSG" =~ [\?？][[:space:]]*$ ]] \
   || [[ "$TAIL_MSG" =~ 要不要[^。]*$ ]] \
   || [[ "$TAIL_MSG" =~ 需要[我你]?[^。]*吗 ]] \
   || [[ "$TAIL_MSG" =~ 是否[^。]*[\?？] ]] \
   || [[ "$TAIL_MSG" =~ 你(想|觉得|希望|打算)[^。]*[\?？] ]] \
   || [[ "$TAIL_MSG" =~ 哪[一个种][^。]*[\?？] ]] \
   || [[ "$TAIL_MSG" =~ 请[选确][^。]*$ ]] \
   || [[ "$TAIL_MSG" =~ [Ww]ould[[:space:]]+you ]] \
   || [[ "$TAIL_MSG" =~ [Ww]hich[[:space:]] ]] \
   || [[ "$TAIL_MSG" =~ [Ss]hould[[:space:]]+[IWwYy] ]]; then
  # Record for observability / heuristic iteration
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) filter4-question-detected" \
    >> "$STATE_ROOT/hook-trace.log" 2>/dev/null || true
  exit 0
fi

# --- All filters passed: fire inline sediment evaluation ---
cat <<'JSON'
{
  "decision": "block",
  "reason": "[PENSIEVE AUTO-SEDIMENT CHECK]\n主任务已完成。这是自动沉淀评估，不是继续任务的信号。\n\n回顾本轮对话，检查是否命中以下信号（任一即沉淀）：\n\n成功信号:\n- 识别了 bug 根因\n- 做了架构或设计决策（考虑了多个方案）\n- 发现了新模式或反模式\n- 探索产出了\"症状→根因→定位\"映射\n- 澄清了边界、所有权、约束\n- 发现了系统中不存在/已废弃的能力\n\n失败信号（好的失败同样值得沉淀）:\n- 尝试了某方案但失败，失败原因不直觉\n- 踩到了文档未记录的坑或隐式约束\n- 排除了看似合理但实际不可行的路径\n\n判断结果:\n- 命中 → 执行 /pensieve self-improve 沉淀（完成后直接停止）\n- 未命中 → 仅输出单行: NO_SEDIMENT: <简短理由>\n\n严格遵守:\n- 不要继续主任务\n- 不要问用户问题\n- 不要调用除 /pensieve 外的 skill\n- 不要做 self-improve 之外的任何文件编辑"
}
JSON
