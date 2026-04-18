#!/usr/bin/env bash

# Invalid or missing JSON must not fail the statusline.
_statusline_payload="$(cat 2>/dev/null || true)"
_statusline_extract_pct() {
  local _statusline_raw="$1"
  local _statusline_pct

  if _statusline_pct="$(jq -r 'try (.context_window.used_percentage // 0) catch 0' 2>/dev/null <<<"$_statusline_raw")"; then
    printf '%s' "$_statusline_pct"
    return 0
  fi

  STATUSLINE_PAYLOAD="$_statusline_raw" python3 - <<'PY'
import json
import os

payload = os.environ.get("STATUSLINE_PAYLOAD", "")
try:
    obj = json.loads(payload)
except Exception:
    print("0", end="")
    raise SystemExit(0)

context_window = obj.get("context_window")
if not isinstance(context_window, dict):
    context_window = {}

print(context_window.get("used_percentage", 0), end="")
PY
}

pct="$(_statusline_extract_pct "$_statusline_payload" || printf '0')"

if ! [[ "$pct" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
  pct=0
fi

pct="${pct%%.*}"

if [ "$pct" -lt 0 ]; then
  pct=0
fi

# tmuxペイン変数に使用率を書き込み（ninja_monitor.sh/ボーダー表示用）
printf -v _statusline_now '%(%s)T' -1
tmux set-option -p -t "$TMUX_PANE" @context_pct "${pct}%" \; \
     set-option -p -t "$TMUX_PANE" @last_active "$_statusline_now" 2>/dev/null

echo "CTX:${pct}%"
