#!/usr/bin/env bash
# Persist exactly one recovery nudge for an active task after verified respawn.
respawn_recovery_launch_command() {
    local root="$1" launch="$2" executable node_path
    [ -n "$launch" ] || return 1
    read -r executable _ <<< "$launch"
    [[ "$executable" = /* ]] || return 1
    node_path="${RESPAWN_RECOVERY_NODE_PATH:-${executable%/*}}"
    [ -d "$node_path" ] || return 1
    printf 'export PATH="%s:$PATH"; cd "%s" && exec %s\n' "$node_path" "$root" "$launch"
}

respawn_recovery_ready() {
    local pane="$1" capture ctx tmux_bin="${RESPAWN_RECOVERY_TMUX_BIN:-tmux}"
    [ "$($tmux_bin display-message -t "$pane" -p '#{pane_dead}' 2>/dev/null || echo 1)" = 0 ] || return 1
    capture=$($tmux_bin capture-pane -t "$pane" -p -J -S -100 2>/dev/null || true)
    printf '%s\n' "$capture" | grep -qE 'Claude Code|OpenAI Codex|Codex CLI|❯|›' || return 1
    respawn_recovery_generation "$pane" >/dev/null || return 1
    ctx=$(printf '%s\n' "$capture" | grep -oE '(CTX:[[:space:]]*|Context[[:space:]]+)[0-9]+%( used)?' | tail -1 | grep -oE '[0-9]+' || true)
    [ "$ctx" = 0 ] || return 1
}

# respawn-paneの成功直後はCLIバナー/CTX表示がまだ描画されていないことがある。
# 単発判定でその正常な起動窓をrespawn失敗へ誤変換せず、期限内だけ再確認する。
respawn_recovery_wait_ready() {
    local pane="$1"
    local attempts="${RESPAWN_RECOVERY_READY_ATTEMPTS:-10}"
    local delay="${RESPAWN_RECOVERY_READY_DELAY_SECONDS:-1}"
    local attempt

    [[ "$attempts" =~ ^[1-9][0-9]*$ ]] || attempts=10
    for ((attempt = 1; attempt <= attempts; attempt++)); do
        respawn_recovery_ready "$pane" && return 0
        [ "$attempt" -lt "$attempts" ] && sleep "$delay"
    done
    return 1
}

respawn_recovery_generation() {
    local pane="$1" pid stat starttime
    local tmux_bin="${RESPAWN_RECOVERY_TMUX_BIN:-tmux}" proc_root="${RESPAWN_RECOVERY_PROC_ROOT:-/proc}"
    pid=$($tmux_bin display-message -t "$pane" -p '#{pane_pid}' 2>/dev/null || true)
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    [ -r "$proc_root/$pid/stat" ] || return 1
    stat=$(<"$proc_root/$pid/stat")
    # comm (field 2) may contain spaces and parentheses; strip through its final ') '.
    stat=${stat##*) }
    starttime=$(printf '%s\n' "$stat" | awk '{print $20}')
    [[ "$starttime" =~ ^[0-9]+$ ]] || return 1
    printf '%s:%s\n' "$pid" "$starttime"
}

respawn_recovery_state_dir() {
    local root="$1" root_key
    if [ -n "${RESPAWN_RECOVERY_STATE_DIR:-}" ]; then
        printf '%s\n' "$RESPAWN_RECOVERY_STATE_DIR"
        return 0
    fi
    root_key=$(printf '%s' "$root" | sha256sum | cut -d' ' -f1)
    printf '%s/%s\n' "${RESPAWN_RECOVERY_EXT4_ROOT:-/tmp/shogun-respawn-recovery}" "$root_key"
}

respawn_recovery_notify_impl() {
    local root="$1" agent="$2" generation="$3" source="${4:-respawn}" content="${5:-}"
    local task_file="$root/queue/tasks/${agent}.yaml"
    local state_dir generation_dir timeout_seconds
    local values status parent task_id marker
    [ -n "$generation" ] && [ "$generation" != "unknown" ] || return 1
    if [ -n "$content" ] && [[ "$content" =~ [\`\$\|\;\&\<\>] ]]; then content=""; fi
    if [ -f "$task_file" ]; then
      values=$(python3 - "$task_file" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
t = d.get("task", d) if isinstance(d, dict) else {}
print(t.get("status") or "")
print(t.get("parent_cmd") or "")
print(t.get("task_id") or "")
PY
      ) || return 1
    else
      values=$'\n\n'
    fi
    status=$(printf '%s\n' "$values" | sed -n '1p')
    parent=$(printf '%s\n' "$values" | sed -n '2p')
    task_id=$(printf '%s\n' "$values" | sed -n '3p')
    case "$status" in
      assigned|acknowledged|in_progress) [ -n "$parent" ] && [ -n "$task_id" ] || return 1 ;;
      *) [ -n "$content" ] || return 0; parent=""; task_id="" ;;
    esac
    state_dir=$(respawn_recovery_state_dir "$root") || return 0
    generation_dir="$state_dir/$agent/$(printf '%s' "$generation" | sha256sum | cut -d' ' -f1)"
    mkdir -p "$generation_dir" || return 0
    marker="$generation_dir/sent"
    exec 219>"${marker}.lock"
    flock -w 5 219 || return 1
    [ ! -e "$marker" ] || return 0
    if [ -n "$parent" ]; then
      message="respawn復帰。既存taskを継続せよ。parent_cmd=${parent} task_id=${task_id} source=${source}"
      [ -z "$content" ] || message="${message} 補足: ${content}"
      sender=karo
    else
      message="$content"
      sender=ninja_monitor
    fi
    timeout_seconds="${RESPAWN_RECOVERY_NOTIFY_TIMEOUT_SECONDS:-2}"
    [[ "$timeout_seconds" =~ ^[1-9][0-9]*([.][0-9]+)?$ ]] || timeout_seconds=2
    if ! timeout --signal=TERM --kill-after=1 "$timeout_seconds" \
        bash "$root/scripts/inbox_write.sh" "$agent" "$message" \
        recovery "$sender" continue_same_task; then
      # Recovery notification is advisory. A blocked /mnt/c transport must not
      # stop the monitor; leave the marker absent so a later generation/retry
      # can deliver instead of recording a false success.
      return 0
    fi
    : > "$marker"
}

respawn_recovery_notify() {
    local root="$1" agent="$2" generation="$3" source="${4:-respawn}" content="${5:-}"
    local timeout_seconds="${RESPAWN_RECOVERY_NOTIFY_TIMEOUT_SECONDS:-2}"
    local library="${BASH_SOURCE[0]}" rc
    [ -n "$generation" ] && [ "$generation" != "unknown" ] || return 1
    [[ "$timeout_seconds" =~ ^[1-9][0-9]*([.][0-9]+)?$ ]] || timeout_seconds=2
    if timeout --signal=TERM --kill-after=1 "$timeout_seconds" \
        bash -c 'source "$1"; shift; respawn_recovery_notify_impl "$@"' \
        _ "$library" "$root" "$agent" "$generation" "$source" "$content"; then
        return 0
    else
        rc=$?
    fi
    case "$rc" in
      124|137) return 0 ;; # advisory recovery must never stall the monitor
      *) return "$rc" ;;
    esac
}
