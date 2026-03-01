#!/usr/bin/env bash
# =============================================================================
# usage_statusbar_loop.sh — Daemon loop for tmux status-right usage display
#
# Calls usage_status.sh periodically and updates tmux status-right.
# Display: "D:█▓░░░ 2% 12am W:█░░░░ 2% 3/4 2PM | YYYY-MM-DD HH:MM"
#
# Kept from hayate's original: pidfile, DRY_RUN, INTERVAL_SEC, MAX_LOOPS
# =============================================================================
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

INTERVAL_SEC="${INTERVAL_SEC:-300}"
MAX_LOOPS="${MAX_LOOPS:-0}" # 0 = run forever
DRY_RUN="${DRY_RUN:-0}"     # 1 = use mock payload

TMUX_TARGET="${TMUX_TARGET:-shogun}"
PIDFILE="${PIDFILE:-/tmp/usage_statusbar_loop.pid}"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >&2
}

require_numeric() {
  local value="$1"
  local name="$2"
  if ! awk -v v="$value" 'BEGIN { exit !(v ~ /^[0-9]+(\.[0-9]+)?$/) }'; then
    log "ERROR: ${name} must be numeric (got: ${value})"
    exit 1
  fi
}

cleanup() {
  if [[ -f "$PIDFILE" ]] && [[ "$(cat "$PIDFILE" 2>/dev/null || true)" == "$$" ]]; then
    rm -f "$PIDFILE"
  fi
}

acquire_pidfile() {
  if [[ -f "$PIDFILE" ]]; then
    local existing_pid
    existing_pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
      log "already running (pid=${existing_pid})"
      exit 0
    fi
    rm -f "$PIDFILE"
  fi

  printf '%s\n' "$$" > "$PIDFILE"
  trap cleanup EXIT INT TERM
}

generate_mock_output() {
  local mock_5h="${MOCK_5H_PCT:-42}"
  local mock_7d="${MOCK_7D_PCT:-18}"

  # Generate progress bars for mock data
  local d_bar="" w_bar="" i
  for i in 0 1 2 3 4; do
    local full=$(( (i + 1) * 20 ))
    local partial=$(( i * 20 + 5 ))
    if [[ "$mock_5h" -ge "$full" ]]; then d_bar+="█"
    elif [[ "$mock_5h" -ge "$partial" ]]; then d_bar+="▓"
    else d_bar+="░"; fi
    if [[ "$mock_7d" -ge "$full" ]]; then w_bar+="█"
    elif [[ "$mock_7d" -ge "$partial" ]]; then w_bar+="▓"
    else w_bar+="░"; fi
  done

  printf 'D:%s %s%% -- W:%s %s%% --' "$d_bar" "$mock_5h" "$w_bar" "$mock_7d"
}

update_tmux_status_right() {
  local usage_output="$1"
  local status_right

  status_right="${usage_output} #[fg=#cdd6f4]| %Y-%m-%d %H:%M"

  tmux set-option -t "$TMUX_TARGET" status-right-length 200 >/dev/null 2>&1 || true
  tmux set-option -t "$TMUX_TARGET" status-right "$status_right" >/dev/null
}

run_once() {
  local usage_output

  if [[ "$DRY_RUN" == "1" ]]; then
    usage_output="$(generate_mock_output)"
  else
    if ! usage_output="$("${SCRIPT_ROOT}/scripts/usage_status.sh" 2>/dev/null)"; then
      log "WARN: usage_status.sh failed; skipping this cycle"
      return 1
    fi
  fi

  if [[ -z "$usage_output" ]]; then
    log "WARN: empty output from usage_status.sh; skipping this cycle"
    return 1
  fi

  if ! tmux has-session -t "$TMUX_TARGET" 2>/dev/null; then
    log "WARN: tmux target session not found (${TMUX_TARGET}); skipping this cycle"
    return 1
  fi

  update_tmux_status_right "$usage_output"
  log "updated status-right: ${usage_output}"
}

main() {
  require_numeric "$INTERVAL_SEC" "INTERVAL_SEC"
  require_numeric "$MAX_LOOPS" "MAX_LOOPS"

  acquire_pidfile
  log "starting usage_statusbar_loop (dry_run=${DRY_RUN}, interval=${INTERVAL_SEC}s)"

  local loop_count=0
  while true; do
    run_once || true

    loop_count=$((loop_count + 1))
    if [[ "$MAX_LOOPS" != "0" ]] && (( loop_count >= MAX_LOOPS )); then
      log "exiting after ${loop_count} loops (MAX_LOOPS reached)"
      break
    fi

    sleep "$INTERVAL_SEC"
  done
}

main "$@"
