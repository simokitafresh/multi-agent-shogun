#!/usr/bin/env bash

# Invalid or missing JSON must not fail the statusline.
# WSL2最適化: subshell(fork)を排除。IFS= read -r -d '' でcatサブシェル不要。
# pure bash regex で jq/python3 サブシェルも排除。
IFS= read -r -d '' _statusline_payload 2>/dev/null || true

# Pure bash regex: "used_percentage": N (floatのみ整数部を取得, 負数はclamp)
pct=0
if [[ "$_statusline_payload" =~ \"used_percentage\":[[:space:]]*(-?[0-9]+) ]]; then
  pct="${BASH_REMATCH[1]}"
fi

if (( pct < 0 )); then
  pct=0
fi

# tmuxペイン変数に使用率を書き込み（ninja_monitor.sh/ボーダー表示用）
printf -v _statusline_now '%(%s)T' -1
tmux set-option -p -t "$TMUX_PANE" @context_pct "${pct}%" \; \
     set-option -p -t "$TMUX_PANE" @last_active "$_statusline_now" 2>/dev/null

echo "CTX:${pct}%"
