#!/usr/bin/env bash

# Invalid or missing JSON must not fail the statusline.
pct="$(jq -r 'try (.context_window.used_percentage // 0) catch 0' 2>/dev/null || true)"

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
