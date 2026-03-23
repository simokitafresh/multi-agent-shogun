#!/usr/bin/env bash
# agent_state.sh - shared busy/idle detection for tmux agents
#
# API:
#   agent_is_busy_check <pane_target> <agent_id>   -> 0=busy, 1=idle, 2=unknown/absent
#   get_agent_state_label <pane_target> <agent_id> -> busy|idle|unknown
#   get_pane_state_label <pane_target> <agent_id>  -> alias of get_agent_state_label
#   check_agent_busy <pane_target> <agent_id>      -> 0=idle, 1=busy, 2=unknown

AGENT_STATE_DEFAULT_BUSY_PATTERN="background terminal running|Working|Thinking|Planning|Sending|task is in progress|Compacting conversation|thought for|thinking|思考中|考え中|計画中|送信中|処理中|実行中"
AGENT_STATE_DEFAULT_IDLE_PATTERN="❯|›|\\? for shortcuts|[0-9]+% (context )?left"

_agent_state_runtime_dir() {
    printf '%s\n' "${SHOGUN_STATE_DIR:-/tmp}"
}

_agent_state_idle_flag_path() {
    local agent_id="$1"
    printf '%s/shogun_idle_%s\n' "$(_agent_state_runtime_dir)" "$agent_id"
}

_agent_state_profile_get() {
    local agent_id="$1"
    local key="$2"

    if command -v cli_profile_get >/dev/null 2>&1; then
        cli_profile_get "$agent_id" "$key"
        return 0
    fi

    echo ""
}

_agent_state_capture_pane() {
    local pane_target="$1"
    local tmux_type
    tmux_type=$(type -t tmux 2>/dev/null || true)

    if [ "$tmux_type" = "function" ]; then
        tmux capture-pane -t "$pane_target" -p 2>/dev/null || return 1
    elif command -v timeout >/dev/null 2>&1; then
        timeout 2 tmux capture-pane -t "$pane_target" -p 2>/dev/null || return 1
    else
        tmux capture-pane -t "$pane_target" -p 2>/dev/null || return 1
    fi
}

_agent_state_get_tail() {
    local pane_target="$1"
    local full_capture
    full_capture=$(_agent_state_capture_pane "$pane_target") || return 1
    printf '%s\n' "$full_capture" | tail -5
}

_agent_state_last_non_empty_line() {
    local text="$1"
    printf '%s\n' "$text" | grep -v '^[[:space:]]*$' | tail -1
}

_agent_state_extract_cli_pids() {
    local tree="$1"
    local matches

    matches=$(printf '%s\n' "$tree" | grep -oE '(claude|codex)\([0-9]+\)' 2>/dev/null || true)
    if [ -z "$matches" ]; then
        matches=$(printf '%s\n' "$tree" | grep -oE 'node\([0-9]+\)' 2>/dev/null || true)
    fi

    [ -n "$matches" ] || return 1
    printf '%s\n' "$matches" | sed -E 's/.*\(([0-9]+)\)/\1/' | awk '!seen[$0]++'
}

_agent_state_descendant_has_process_name() {
    local parent_pid="$1"
    local target_name="$2"
    local children child child_name

    children=$(pgrep -P "$parent_pid" 2>/dev/null || true)
    [ -n "$children" ] || return 1

    for child in $children; do
        child_name=$(ps -p "$child" -o comm= 2>/dev/null | awk 'NR==1 {print $1}')
        if [ "$child_name" = "$target_name" ]; then
            return 0
        fi

        if _agent_state_descendant_has_process_name "$child" "$target_name"; then
            return 0
        fi
    done

    return 1
}

# pstree子プロセス検知: CLI直下にbash子プロセスがあればBash tool実行中
# 戻り値: 0=bash子プロセスあり(busy), 1=なし
# MCPサーバー(node/npm)はbashでないので自然に除外
_agent_state_has_busy_subprocess() {
    local pane_target="$1"
    local pane_pid
    pane_pid=$(tmux display-message -t "$pane_target" -p '#{pane_pid}' 2>/dev/null) || return 1
    [ -n "$pane_pid" ] || return 1

    # pstree -A -p でプロセスツリーを取得（ASCII出力）
    local tree
    tree=$(pstree -A -p "$pane_pid" 2>/dev/null) || return 1

    # codex/claudeを優先し、無い場合のみnodeへフォールバック
    local cli_pids cli_pid
    cli_pids=$(_agent_state_extract_cli_pids "$tree") || return 1

    for cli_pid in $cli_pids; do
        if _agent_state_descendant_has_process_name "$cli_pid" "bash"; then
            return 0
        fi
    done

    return 1
}

agent_is_busy_check() {
    local pane_target="$1"
    local agent_id="${2:-}"

    if [ -z "$pane_target" ]; then
        return 2
    fi

    if ! tmux display-message -t "$pane_target" -p '#{pane_id}' >/dev/null 2>&1; then
        return 2
    fi

    local pane_tail
    pane_tail=$(_agent_state_get_tail "$pane_target") || return 2

    if [ -z "$pane_tail" ]; then
        return 1
    fi

    local last_line
    last_line=$(_agent_state_last_non_empty_line "$pane_tail")
    if printf '%s\n' "$last_line" | grep -qiF 'esc to'; then
        return 0
    fi

    local idle_pat
    idle_pat=$(_agent_state_profile_get "$agent_id" "idle_pattern")
    if [ -z "$idle_pat" ]; then
        idle_pat="$AGENT_STATE_DEFAULT_IDLE_PATTERN"
    else
        idle_pat="${idle_pat}|\\? for shortcuts|[0-9]+% (context )?left"
    fi

    if printf '%s\n' "$pane_tail" | grep -qE "$idle_pat"; then
        return 1
    fi

    local busy_pat
    busy_pat=$(_agent_state_profile_get "$agent_id" "busy_patterns")
    if [ -z "$busy_pat" ]; then
        busy_pat="$AGENT_STATE_DEFAULT_BUSY_PATTERN"
    else
        busy_pat="${busy_pat}|${AGENT_STATE_DEFAULT_BUSY_PATTERN}"
    fi

    if printf '%s\n' "$pane_tail" | grep -qiE "$busy_pat"; then
        return 0
    fi

    return 2
}

get_agent_state_label() {
    local pane_target="$1"
    local agent_id="${2:-}"

    agent_is_busy_check "$pane_target" "$agent_id"
    case $? in
        0) echo "busy" ;;
        1) echo "idle" ;;
        *) echo "unknown" ;;
    esac
}

get_pane_state_label() {
    get_agent_state_label "$@"
}

check_agent_busy() {
    local pane_target="$1"
    local agent_id="$2"

    if [ -z "$pane_target" ] || [ -z "$agent_id" ]; then
        return 2
    fi

    # pstree子プロセス検知: CLI直下にbash子プロセスがあればBUSY
    if _agent_state_has_busy_subprocess "$pane_target"; then
        return 1
    fi

    local idle_flag
    idle_flag=$(_agent_state_idle_flag_path "$agent_id")
    local agent_state
    agent_state=$(tmux display-message -t "$pane_target" -p '#{@agent_state}' 2>/dev/null || true)

    if [ "$agent_state" = "idle" ]; then
        [ ! -f "$idle_flag" ] && touch "$idle_flag"
        return 0
    fi

    local state_rc
    if agent_is_busy_check "$pane_target" "$agent_id"; then
        state_rc=0
    else
        state_rc=$?
    fi

    case "$state_rc" in
        0)
            return 1
            ;;
        1)
            tmux set-option -p -t "$pane_target" @agent_state idle 2>/dev/null || true
            [ ! -f "$idle_flag" ] && touch "$idle_flag"
            return 0
            ;;
        *)
            return 2
            ;;
    esac
}
