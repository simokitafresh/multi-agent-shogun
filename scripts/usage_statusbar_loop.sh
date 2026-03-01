#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

INTERVAL_SEC="${INTERVAL_SEC:-300}"
MAX_LOOPS="${MAX_LOOPS:-0}" # 0 = run forever
DRY_RUN="${DRY_RUN:-0}"     # 1 = use mock payload

USAGE_API_URL="${USAGE_API_URL:-https://api.anthropic.com/api/oauth/usage}"
ANTHROPIC_BETA="${ANTHROPIC_BETA:-oauth-2025-04-20}"
CREDENTIALS_PATH="${CREDENTIALS_PATH:-$HOME/.claude/.credentials.json}"
API_TIMEOUT_SEC="${API_TIMEOUT_SEC:-15}"
CONNECT_TIMEOUT_SEC="${CONNECT_TIMEOUT_SEC:-10}"

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

get_oauth_token() {
  python3 - "$CREDENTIALS_PATH" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
if not path.exists():
    raise SystemExit(f"credentials not found: {path}")

with path.open("r", encoding="utf-8") as f:
    data = json.load(f)

candidates = [
    data.get("oauth_token"),
    (data.get("claudeAiOauth") or {}).get("accessToken"),
    (data.get("claudeAiOauth") or {}).get("access_token"),
    data.get("accessToken"),
]

token = next((x for x in candidates if isinstance(x, str) and x.strip()), None)
if not token:
    raise SystemExit("oauth token not found in credentials file")

print(token)
PY
}

fetch_usage_json() {
  if [[ "$DRY_RUN" == "1" ]]; then
    if [[ -n "${MOCK_RESPONSE_FILE:-}" ]]; then
      cat "$MOCK_RESPONSE_FILE"
      return 0
    fi
    if [[ -n "${MOCK_RESPONSE_JSON:-}" ]]; then
      printf '%s\n' "$MOCK_RESPONSE_JSON"
      return 0
    fi
    local mock_5h="${MOCK_5H_PCT:-42}"
    local mock_7d="${MOCK_7D_PCT:-18}"
    printf '{"five_hour":{"utilization":%s},"seven_day":{"utilization":%s}}\n' "$mock_5h" "$mock_7d"
    return 0
  fi

  local token
  token="$(get_oauth_token)"

  curl -fsS \
    --max-time "$API_TIMEOUT_SEC" \
    --connect-timeout "$CONNECT_TIMEOUT_SEC" \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: $ANTHROPIC_BETA" \
    -H "Accept: application/json" \
    "$USAGE_API_URL"
}

extract_usage_pair() {
  local payload="$1"
  PAYLOAD_JSON="$payload" python3 - <<'PY'
import json
import os

raw = os.environ.get("PAYLOAD_JSON", "").strip()
if not raw:
    raise SystemExit("empty API response")

data = json.loads(raw)

def extract_pct(container, key):
    value = None
    node = container.get(key)
    if isinstance(node, dict):
        value = node.get("utilization")
    if value is None:
        value = container.get(key)
    if value is None:
        raise SystemExit(f"{key}.utilization not found")
    pct = float(value)
    if 0.0 <= pct <= 1.0:
        pct *= 100.0
    return int(round(pct))

five_hour = extract_pct(data, "five_hour")
seven_day = extract_pct(data, "seven_day")
print(f"{five_hour} {seven_day}")
PY
}

update_tmux_status_right() {
  local five_hour_pct="$1"
  local seven_day_pct="$2"
  local status_right

  status_right="5h:${five_hour_pct}% 7d:${seven_day_pct}% #[fg=#cdd6f4]%Y-%m-%d %H:%M"

  tmux set-option -t "$TMUX_TARGET" status-right-length 200 >/dev/null 2>&1 || true
  tmux set-option -t "$TMUX_TARGET" status-right "$status_right" >/dev/null
}

run_once() {
  local payload usage_pair five_hour_pct seven_day_pct

  if ! payload="$(fetch_usage_json)"; then
    log "WARN: Usage API request failed; skipping this cycle"
    return 1
  fi

  if ! usage_pair="$(extract_usage_pair "$payload")"; then
    log "WARN: failed to parse Usage API payload; skipping this cycle"
    return 1
  fi

  five_hour_pct="${usage_pair%% *}"
  seven_day_pct="${usage_pair##* }"

  if ! tmux has-session -t "$TMUX_TARGET" 2>/dev/null; then
    log "WARN: tmux target session not found (${TMUX_TARGET}); skipping this cycle"
    return 1
  fi

  update_tmux_status_right "$five_hour_pct" "$seven_day_pct"
  log "updated status-right: 5h=${five_hour_pct}% 7d=${seven_day_pct}%"
}

main() {
  require_numeric "$INTERVAL_SEC" "INTERVAL_SEC"
  require_numeric "$MAX_LOOPS" "MAX_LOOPS"
  require_numeric "$API_TIMEOUT_SEC" "API_TIMEOUT_SEC"
  require_numeric "$CONNECT_TIMEOUT_SEC" "CONNECT_TIMEOUT_SEC"

  if awk -v t="$API_TIMEOUT_SEC" 'BEGIN { exit !(t >= 15) }'; then
    :
  else
    log "ERROR: API_TIMEOUT_SEC must be >= 15 (L040)"
    exit 1
  fi

  acquire_pidfile
  log "starting usage_statusbar_loop (dry_run=${DRY_RUN}, interval=${INTERVAL_SEC}s, timeout=${API_TIMEOUT_SEC}s)"

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
