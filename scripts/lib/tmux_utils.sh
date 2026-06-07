#!/bin/bash
# tmux send-keys排他制御ライブラリ。

# safe_send_keys — flock排他制御付きtmux send-keys
# 引数: $1=pane_target, $2以降=send-keysの引数
# 戻り値: 0=成功, 1=flock取得失敗
safe_send_keys() {
    local pane="$1"; shift
    local lock="/tmp/tmux_sendkeys_$(echo "$pane" | tr ':.' '_').lock"
    (
        flock -w 5 200 || { echo "[$(date)] LOCK TIMEOUT: safe_send_keys $pane" >&2; return 1; }
        # copy mode中はsend-keysが無視されるため、送信前に解除する
        if [ "$(tmux display-message -t "$pane" -p '#{pane_in_mode}')" = "1" ]; then
            tmux send-keys -t "$pane" -X cancel 2>/dev/null
            sleep 0.1
        fi
        tmux send-keys -t "$pane" "$@"
    ) 200>"$lock"
}

safe_send_keys_atomic() {
    local pane="$1"
    local cmd="$2"
    local wait="${3:-0.3}"
    local lock="/tmp/tmux_sendkeys_$(echo "$pane" | tr ':.' '_').lock"
    (
        flock -w 5 200 || { echo "[$(date)] LOCK TIMEOUT: safe_send_keys_atomic $pane" >&2; return 1; }
        # copy mode中はsend-keysが無視されるため、送信前に解除する
        if [ "$(tmux display-message -t "$pane" -p '#{pane_in_mode}')" = "1" ]; then
            tmux send-keys -t "$pane" -X cancel 2>/dev/null
            sleep 0.1
        fi
        tmux send-keys -t "$pane" "$cmd"
        sleep "$wait"
        tmux send-keys -t "$pane" Enter
    ) 200>"$lock"
}
