#!/usr/bin/env bash
# tmux_live_send_guard.sh — attached production sessionへのsend-keys境界
#
# 実際のsocket/session/targetをtmux自身から解決し、attachedな本番
# shogun sessionだけを明示許可なしでfail-closedに遮断する。

tmux_live_send_guard() {
    local target="${1:-}"
    local target_info socket_path session_name session_attached window_name pane_id

    if [[ -z "$target" ]]; then
        echo "BLOCK: tmux send-keys target is empty" >&2
        return 2
    fi

    target_info="$(tmux display-message -t "$target" -p '#{socket_path}|#{session_name}|#{session_attached}|#{window_name}|#{pane_id}' 2>/dev/null)" || {
        echo "BLOCK: tmux target could not be resolved: ${target}" >&2
        return 2
    }
    IFS='|' read -r socket_path session_name session_attached window_name pane_id <<< "$target_info"

    if [[ -z "$socket_path" || -z "$session_name" || -z "$session_attached" || -z "$window_name" || -z "$pane_id" ]]; then
        echo "BLOCK: tmux target identity is incomplete: ${target}" >&2
        return 2
    fi

    if [[ "$session_name" == "shogun" && "$session_attached" =~ ^[1-9][0-9]*$ \
        && "${SHOGUN_ALLOW_LIVE_SENDKEYS:-}" != "1" ]]; then
        echo "BLOCK: attached production shogun send-keys requires SHOGUN_ALLOW_LIVE_SENDKEYS=1 (socket=${socket_path} session=${session_name} target=${target} pane=${pane_id})" >&2
        return 2
    fi

    return 0
}

tmux_live_send_keys() {
    local target="${1:-}"
    [[ -n "$target" ]] || {
        echo "BLOCK: tmux send-keys target is empty" >&2
        return 2
    }
    shift
    tmux_live_send_guard "$target" || return $?
    tmux send-keys -t "$target" "$@"
}
