#!/usr/bin/env bash

input="$(cat)"

# Invalid or missing JSON must not fail the statusline.
pct="$(printf '%s' "$input" | jq -r 'try (.context_window.used_percentage // 0) catch 0' 2>/dev/null)"

if ! [[ "$pct" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
  pct=0
fi

pct="${pct%%.*}"

if [ "$pct" -lt 0 ]; then
  pct=0
fi

# tmuxペイン変数に使用率を書き込み（ninja_monitor.sh/ボーダー表示用）
tmux set-option -p -t "$TMUX_PANE" @context_pct "${pct}%" \; \
     set-option -p -t "$TMUX_PANE" @last_active "$(date +%s)" 2>/dev/null

echo "CTX:${pct}%"
