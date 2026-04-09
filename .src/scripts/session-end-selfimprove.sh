#!/bin/bash
# Stop hook — prompt self-improve before session exit.
# Coexists with Ralph-Loop: skips when loop is active.
# Uses a session-scoped marker to prevent infinite re-prompting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Detect project root and .pensieve/.
PROJECT_ROOT="$(project_root 2>/dev/null)" || exit 0
PENSIEVE_DIR="$PROJECT_ROOT/.pensieve"
[[ -d "$PENSIEVE_DIR" ]] || exit 0

# Check Ralph-Loop state: if active, let Ralph-Loop handle the session flow.
LOOP_STATE=""
for candidate in \
  "${CLAUDE_PROJECT_DIR:-.}/.claude/loop-state.local.md" \
  "$HOME/.claude/loop-state.local.md"; do
  if [[ -f "$candidate" ]]; then
    LOOP_STATE="$candidate"
    break
  fi
done

if [[ -n "$LOOP_STATE" ]]; then
  active=$(grep -m1 '^active:' "$LOOP_STATE" 2>/dev/null | sed 's/^active:[[:space:]]*//' | tr -d '"' || true)
  if [[ "$active" == "true" ]]; then
    # Ralph-Loop is running — do not interfere.
    exit 0
  fi
fi

# Check session marker: if self-improve was already done, allow exit.
STATE_ROOT="$(state_root 2>/dev/null)" || exit 0
MARKER="$STATE_ROOT/session-selfimprove-done"
if [[ -f "$MARKER" ]]; then
  exit 0
fi

# Create marker and prompt self-improve.
mkdir -p "$STATE_ROOT"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$MARKER"

cat <<'PROMPT'
会话即将结束。回顾本次会话，检查是否存在以下信号（任一命中则执行 /pensieve 沉淀一下）：

成功信号：
- 识别了 bug 根因
- 做了架构或设计决策（考虑了多个方案）
- 发现了新模式或反模式
- 探索产出了"症状→根因→定位"映射
- 澄清了边界、所有权、约束
- 发现了系统中不存在/已废弃的能力

失败信号（好的失败同样值得沉淀）：
- 尝试了某方案但失败，失败原因不直觉
- 踩到了文档未记录的坑或隐式约束
- 排除了看似合理但实际不可行的路径
- 调试耗时长，最终定位到非预期的根因

全不命中（纯问答、简单查询、机械操作）→ 直接退出，不沉淀。
PROMPT
