#!/bin/bash
# stop-hook-sidecar-probe.sh — manual probe for sidecar sediment dispatch.
#
# Validates the 4 unknowns blocking the dispatch-mode redesign:
#   P1: transcript.jsonl write timing vs Stop hook payload
#   P2a: sidecar `claude -r` basic session recovery
#   P3: nohup background launch is non-blocking
#   P2c / P4: deferred (manual + design tasks)
#
# Prerequisites:
#   - stop-hook-auto-sediment.sh has been patched to persist payload.
#   - At least one Stop hook has fired since the patch, creating the payload
#     file at .pensieve/.state/last-stop-payload.json.
#
# Usage:
#   bash .src/scripts/stop-hook-sidecar-probe.sh          # run all probes
#   bash .src/scripts/stop-hook-sidecar-probe.sh --p1     # only P1
#   bash .src/scripts/stop-hook-sidecar-probe.sh --p2a    # only P2a
#   bash .src/scripts/stop-hook-sidecar-probe.sh --p3     # only P3
#
# Outputs:
#   .pensieve/.state/sidecar-probe.log        — full trace (appended)
#   .pensieve/.state/sidecar-probe-summary.json — latest run machine-readable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

ensure_home

PROJECT_ROOT="$(project_root)" || {
  echo "ERROR: cannot resolve project root" >&2
  exit 1
}

STATE_ROOT="$PROJECT_ROOT/.pensieve/.state"
PAYLOAD_FILE="$STATE_ROOT/last-stop-payload.json"
LOG_FILE="$STATE_ROOT/sidecar-probe.log"
SUMMARY_FILE="$STATE_ROOT/sidecar-probe-summary.json"

mkdir -p "$STATE_ROOT"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG_FILE"
}

section() {
  printf '\n\n=== %s ===\n' "$1" | tee -a "$LOG_FILE"
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    log "ERROR: required tool '$1' not installed"
    exit 1
  }
}

require_tool jq

# --- Preflight ---
section "PROBE START"
log "project_root=$PROJECT_ROOT"
log "state_root=$STATE_ROOT"
log "payload_file=$PAYLOAD_FILE"

if [[ ! -s "$PAYLOAD_FILE" ]]; then
  log "ERROR: payload file missing or empty: $PAYLOAD_FILE"
  log "Reason: auto-sediment hook hasn't fired (with patched payload persist)"
  log "since the last Claude Code restart. Trigger at least one substantial"
  log "turn, then rerun this probe."
  exit 1
fi

SESSION_ID=$(jq -r '.session_id // empty' "$PAYLOAD_FILE")
TRANSCRIPT_PATH=$(jq -r '.transcript_path // empty' "$PAYLOAD_FILE")
PAYLOAD_LAST_MSG=$(jq -r '.last_assistant_message // empty' "$PAYLOAD_FILE")
PAYLOAD_LAST_MSG_LEN=${#PAYLOAD_LAST_MSG}

log "session_id=$SESSION_ID"
log "transcript_path=$TRANSCRIPT_PATH"
log "payload.last_assistant_message length=$PAYLOAD_LAST_MSG_LEN"

# --- P1: transcript write timing ---
# Correct test: payload.last_assistant_message is a SNAPSHOT at Stop hook fire.
# The probe runs later, so transcript tail is ahead. The real question is
# whether the payload content has been persisted to transcript at all.
# PASS condition: payload.last_assistant_message appears somewhere in the
# transcript's assistant text entries. If it does, sidecar launched at Stop
# hook time would have seen it.
probe_p1() {
  section "P1: transcript write timing (payload ⊆ transcript)"

  if [[ -z "$TRANSCRIPT_PATH" ]]; then
    log "P1 SKIP: payload has no transcript_path"
    P1_RESULT="skip"
    return
  fi

  if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    log "P1 FAIL: transcript file not found: $TRANSCRIPT_PATH"
    P1_RESULT="fail"
    return
  fi

  if [[ -z "$PAYLOAD_LAST_MSG" ]]; then
    log "P1 INCONCLUSIVE: payload last_assistant_message empty"
    P1_RESULT="inconclusive"
    return
  fi

  # Extract unique 60-char signature from payload head
  local payload_sig="${PAYLOAD_LAST_MSG:0:60}"
  log "payload signature (60 chars): $payload_sig"

  # Grep-based signature search across all assistant text content in transcript
  local found
  found=$(jq -sr --arg sig "$payload_sig" '
    [.[]
     | select(.type=="assistant")
     | .message.content
     | if type=="array" then (map(select(.type=="text") | .text) | join(""))
       elif type=="string" then .
       else "" end
     | select(length > 0)
     | select(contains($sig))]
    | length
  ' "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")

  log "matches in transcript: $found"

  if [[ "$found" -gt 0 ]]; then
    log "P1 PASS: payload content is persisted to transcript"
    log "(sidecar launched at Stop hook time would see the last assistant turn)"
    P1_RESULT="pass"
  else
    log "P1 FAIL: payload content NOT found in transcript"
    log "(sidecar would miss the target turn — transcript write delayed)"
    P1_RESULT="fail"
  fi
}

# --- P2c: sidecar can invoke /pensieve skill (slash command fingerprint) ---
probe_p2c() {
  section "P2c: sidecar /pensieve skill invocation"

  if [[ -z "$SESSION_ID" ]]; then
    log "P2c SKIP: no session_id"
    P2C_RESULT="skip"
    return
  fi

  if ! command -v claude >/dev/null 2>&1; then
    log "P2c SKIP: claude CLI not in PATH"
    P2C_RESULT="skip"
    return
  fi

  local doctor_file="$STATE_ROOT/pensieve-doctor-summary.json"
  local baseline_mtime=0
  if [[ -f "$doctor_file" ]]; then
    baseline_mtime=$(stat -c '%Y' "$doctor_file" 2>/dev/null || echo 0)
  fi
  log "baseline pensieve-doctor-summary.json mtime: $baseline_mtime"

  local prompt='Run /pensieve doctor now. Do not explain. After the skill completes, output one line: P2C_DONE and exit.'
  local sidecar_out=""
  local sidecar_rc=0

  (
    cd "$PROJECT_ROOT" || exit 1
    export PENSIEVE_PROJECT_ROOT="$PROJECT_ROOT"
    timeout 120 claude -r "$SESSION_ID" -p "$prompt" \
      --bare \
      --permission-mode bypassPermissions 2>&1
  ) > "$STATE_ROOT/p2c-sidecar.out" 2>&1 || sidecar_rc=$?

  sidecar_out=$(cat "$STATE_ROOT/p2c-sidecar.out" 2>/dev/null || echo "")
  log "sidecar exit code: $sidecar_rc"
  log "sidecar output (first 400 chars): ${sidecar_out:0:400}"

  local post_mtime=0
  if [[ -f "$doctor_file" ]]; then
    post_mtime=$(stat -c '%Y' "$doctor_file" 2>/dev/null || echo 0)
  fi
  log "post pensieve-doctor-summary.json mtime: $post_mtime"

  if [[ "$post_mtime" -gt "$baseline_mtime" ]]; then
    log "P2c PASS: doctor summary file was updated (skill was invoked)"
    P2C_RESULT="pass"
  else
    log "P2c FAIL: doctor summary file mtime unchanged (skill NOT invoked)"
    P2C_RESULT="fail"
  fi
}

# --- P2a: sidecar -r basic session recovery ---
probe_p2a() {
  section "P2a: sidecar -r basic session recovery"

  if [[ -z "$SESSION_ID" ]]; then
    log "P2a SKIP: payload has no session_id"
    P2A_RESULT="skip"
    return
  fi

  if ! command -v claude >/dev/null 2>&1; then
    log "P2a SKIP: claude CLI not in PATH"
    P2A_RESULT="skip"
    return
  fi

  # NOTE: --no-session-persistence is INTENTIONALLY omitted.
  # Empirical finding 2026-04-11: --no-session-persistence is incompatible with
  # -r/--resume. Despite docs saying "only works with --print", its semantics
  # ("sessions will not be saved to disk and cannot be resumed") conflict with
  # resume intent — claude silently ignores -r and spawns a new session.
  # Correction to knowledge/claude-cli-sidecar-pattern (pending sediment).
  local prompt="Output exactly one line: HISTORY_COUNT=<number of assistant turns existing in this conversation BEFORE this current instruction>. No explanation. No tool calls."
  local sidecar_out=""
  local sidecar_rc=0
  local start_ms end_ms elapsed_ms

  start_ms=$(date +%s%N)
  sidecar_out=$(timeout 120 claude -r "$SESSION_ID" -p "$prompt" \
    --bare \
    --permission-mode bypassPermissions 2>&1) || sidecar_rc=$?
  end_ms=$(date +%s%N)
  elapsed_ms=$(( (end_ms - start_ms) / 1000000 ))

  log "sidecar exit code: $sidecar_rc"
  log "sidecar duration: ${elapsed_ms}ms"
  log "sidecar output (first 400 chars): ${sidecar_out:0:400}"

  if [[ $sidecar_rc -ne 0 ]]; then
    log "P2a FAIL: sidecar exited non-zero"
    P2A_RESULT="fail"
    return
  fi

  if echo "$sidecar_out" | grep -qE "HISTORY_COUNT=[0-9]+"; then
    local count
    count=$(echo "$sidecar_out" | grep -oE "HISTORY_COUNT=[0-9]+" | head -1 | cut -d= -f2)
    log "P2a PASS: sidecar recovered session, sees $count historical assistant turns"
    if [[ $count -ge 2 ]]; then
      log "(post-compact active context; main-session Claude has same view)"
    else
      log "WARNING: HISTORY_COUNT=$count suspiciously low, may indicate empty context"
    fi
    P2A_RESULT="pass"
  else
    log "P2a FAIL: marker 'HISTORY_COUNT=<n>' not found in output"
    P2A_RESULT="fail"
  fi
}

# --- P3: sidecar detach is non-blocking ---
# IMPORTANT: this probe mirrors the PRODUCTION detach pattern exactly.
# Production uses: `( nohup ... ) </dev/null >/dev/null 2>&1 & disown`
# A simpler `nohup sleep &` would pass even if the production wrapper
# blocked — the probe must test the actual wrapper shape, not a proxy.
probe_p3() {
  section "P3: sidecar wrapper detach non-blocking"

  local start_ms end_ms elapsed_ms bg_pid
  start_ms=$(date +%s%N)
  (
    nohup sleep 8 >/dev/null 2>&1
  ) </dev/null >/dev/null 2>&1 &
  bg_pid=$!
  disown 2>/dev/null || true
  end_ms=$(date +%s%N)
  elapsed_ms=$(( (end_ms - start_ms) / 1000000 ))

  log "wrapper launch elapsed: ${elapsed_ms}ms"
  log "bg pid: $bg_pid"

  # Cleanup (kill both wrapper subshell and nohup child)
  pkill -P "$bg_pid" 2>/dev/null || true
  kill "$bg_pid" 2>/dev/null || true

  if [[ $elapsed_ms -lt 500 ]]; then
    log "P3 PASS: production-shape wrapper returned in ${elapsed_ms}ms (<500ms threshold)"
    P3_RESULT="pass"
  else
    log "P3 FAIL: wrapper blocked ${elapsed_ms}ms"
    P3_RESULT="fail"
  fi
}

# --- Entry ---
MODE="${1:-all}"
P1_RESULT="not-run"
P2A_RESULT="not-run"
P2C_RESULT="not-run"
P3_RESULT="not-run"

case "$MODE" in
  --p1)      probe_p1 ;;
  --p2|--p2a) probe_p2a ;;
  --p2c)     probe_p2c ;;
  --p3)      probe_p3 ;;
  all|"")
    probe_p1  || true
    probe_p3  || true
    probe_p2a || true
    probe_p2c || true
    ;;
  *)
    log "Unknown mode: $MODE (expected: --p1|--p2a|--p2c|--p3|all)"
    exit 1
    ;;
esac

# --- Summary ---
section "SUMMARY"
log "P1  (transcript timing)     : $P1_RESULT"
log "P2a (sidecar recovery)      : $P2A_RESULT"
log "P2c (skill invocation)      : $P2C_RESULT"
log "P3  (nohup non-blocking)    : $P3_RESULT"
log "P4  (concurrent sediment)   : TODO — design task after P1-P3"

cat > "$SUMMARY_FILE" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "session_id": "$SESSION_ID",
  "transcript_path": "$TRANSCRIPT_PATH",
  "results": {
    "P1_transcript_timing": "$P1_RESULT",
    "P2a_sidecar_recovery": "$P2A_RESULT",
    "P2c_skill_invocation": "$P2C_RESULT",
    "P3_nohup_nonblocking": "$P3_RESULT",
    "P4_concurrent_sediment": "todo"
  }
}
EOF

log "Summary written to: $SUMMARY_FILE"
section "PROBE END"
