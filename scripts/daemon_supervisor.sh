#!/usr/bin/env bash
# semantic-links: [[インフラ運用基盤]], [[デーモン監視と復旧]]
# =============================================================================
# daemon_supervisor.sh — 統一デーモン管理層
#
# 監視対象:
#   - inbox_watcher.sh: shogun + get_all_agents() の各1本
#   - ninja_monitor.sh: 1本
#   - ntfy_listener.sh: 1本
#
# 挙動:
#   - 0本: 再起動
#   - 2本以上: 最新PIDだけ残して古いプロセスを停止
#   - 異常検知時: ntfy通知
#
# Usage:
#   bash scripts/daemon_supervisor.sh
#   DAEMON_SUPERVISOR_LIB_ONLY=1 source scripts/daemon_supervisor.sh
# =============================================================================
set -uo pipefail

_DS_SELF="${BASH_SOURCE[0]}"
[[ "$_DS_SELF" != /* ]] && _DS_SELF="$PWD/$_DS_SELF"
SCRIPT_DIR="${_DS_SELF%/scripts/daemon_supervisor.sh}"
LOG_FILE="${DAEMON_SUPERVISOR_LOG:-$SCRIPT_DIR/logs/daemon_supervisor.log}"
STATE_DIR="${SHOGUN_STATE_DIR:-${IDLE_FLAG_DIR:-/tmp}}"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/daemon_maintenance_lock.sh"

# A daemon may be launched from restart_watchers.sh or another shell that
# inherited its coordinator lock.  The lock belongs only to the restart
# transaction, never to a long-lived daemon.
close_inherited_restart_watchers_lock() {
    local lock_path="${RESTART_WATCHERS_LOCK_FILE:-/tmp/restart_watchers.lock}"
    local fd_path fd target
    for fd_path in /proc/$$/fd/*; do
        fd="${fd_path##*/}"
        [[ "$fd" =~ ^[0-9]+$ && "$fd" != 0 && "$fd" != 1 && "$fd" != 2 ]] || continue
        target="$(readlink "$fd_path" 2>/dev/null || true)"
        [[ "$target" == "$lock_path" ]] || continue
        eval "exec ${fd}>&-"
    done
}
close_inherited_restart_watchers_lock

[[ "${DAEMON_SUPERVISOR_LIB_ONLY:-0}" == "1" ]] || mkdir -p "$SCRIPT_DIR/logs"

ds_log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

ds_notify() {
    local message="$1"
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "$message" >/dev/null 2>&1 || true
}

ds_pid_live() {
    local pid="${1:-}"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null
}

ds_cmdline() {
    local pid="$1"
    tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true
}

ds_pattern_pids() {
    local pgrep_pattern="$1"
    local cmdline_needle="$2"
    local pid cmdline

    while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        [[ "$pid" == "$$" ]] && continue
        ds_pid_live "$pid" || continue
        cmdline="$(ds_cmdline "$pid")"
        [[ "$cmdline" == *"$cmdline_needle"* ]] || continue
        printf '%s\n' "$pid"
    done < <(pgrep -f "$pgrep_pattern" 2>/dev/null || true)
}

ds_inbox_watcher_pids() {
    local agent="$1"
    local pid ppid cmdline parent_cmdline

    while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        [[ "$pid" == "$$" ]] && continue
        ds_pid_live "$pid" || continue
        cmdline="$(ds_cmdline "$pid")"
        [[ "$cmdline" == *"inbox_watcher.sh ${agent} "* ]] || continue

        ppid="$(awk '/^PPid:/ {print $2}' "/proc/${pid}/status" 2>/dev/null || true)"
        if [[ -n "$ppid" ]] && ds_pid_live "$ppid"; then
            parent_cmdline="$(ds_cmdline "$ppid")"
            [[ "$parent_cmdline" == *"inbox_watcher.sh ${agent} "* ]] && continue
        fi

        printf '%s\n' "$pid"
    done < <(pgrep -f "[i]nbox_watcher\.sh" 2>/dev/null || true)
}

ds_newest_pid() {
    local newest="" pid
    for pid in "$@"; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        if [[ -z "$newest" ]] || (( pid > newest )); then
            newest="$pid"
        fi
    done
    [[ -n "$newest" ]] && printf '%s\n' "$newest"
}

ds_oldest_pid() {
    local oldest="" pid
    for pid in "$@"; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        if [[ -z "$oldest" ]] || (( pid < oldest )); then
            oldest="$pid"
        fi
    done
    [[ -n "$oldest" ]] && printf '%s\n' "$oldest"
}

ds_stop_pid() {
    local pid="$1"
    local label="$2"

    ds_pid_live "$pid" || return 0
    ds_log "STOP-DUPLICATE: ${label} PID ${pid} (TERM)"
    kill -TERM "$pid" 2>/dev/null || true

    local wait_count=0
    while (( wait_count < 10 )); do
        ds_pid_live "$pid" || return 0
        sleep 0.5
        wait_count=$((wait_count + 1))
    done

    if ds_pid_live "$pid"; then
        ds_log "STOP-DUPLICATE: ${label} PID ${pid} still alive; KILL"
        kill -KILL "$pid" 2>/dev/null || true
    fi
}

ds_stop_duplicates() {
    local label="$1"
    shift
    local pids=("$@")
    local keep pid

    keep="$(ds_newest_pid "${pids[@]}")"
    [[ -n "$keep" ]] || return 0

    for pid in "${pids[@]}"; do
        [[ "$pid" == "$keep" ]] && continue
        ds_stop_pid "$pid" "$label"
    done
}

ds_pane_for_agent() {
    local agent="$1"
    if [[ "$agent" == "shogun" ]]; then
        printf '%s\n' "shogun:main"
        return 0
    fi

    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/scripts/lib/pane_lookup.sh"
    pane_lookup "$agent"
}

ds_cli_for_pane() {
    local pane="$1"
    tmux show-options -p -t "$pane" -v @agent_cli 2>/dev/null || printf '%s\n' "claude"
}

ds_start_inbox_watcher() {
    local agent="$1"
    local pane cli

    pane="$(ds_pane_for_agent "$agent" 2>/dev/null || true)"
    if [[ -z "$pane" ]]; then
        ds_log "START-FAILED: inbox_watcher(${agent}) pane not found"
        ds_notify "【daemon_supervisor/WARN】inbox_watcher(${agent})のpaneが見つからず再起動不可"
        return 1
    fi

    cli="$(ds_cli_for_pane "$pane")"
    unset ASW_DISABLE_ESCALATION
    nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "$agent" "$pane" "$cli" \
        &>> "$SCRIPT_DIR/logs/inbox_watcher_${agent}.log" 200>&- &
    disown
    ds_log "START: inbox_watcher(${agent}) pane=${pane} cli=${cli} pid=$!"
    return 0
}

ds_start_ninja_monitor() {
    local replace_generation="${1:-}"
    if [ -n "$replace_generation" ]; then
        nohup env NINJA_MONITOR_REPLACE_GENERATION="$replace_generation" \
            bash "$SCRIPT_DIR/scripts/ninja_monitor.sh" >> "$SCRIPT_DIR/logs/ninja_monitor.log" 2>&1 &
    else
        nohup bash "$SCRIPT_DIR/scripts/ninja_monitor.sh" >> "$SCRIPT_DIR/logs/ninja_monitor.log" 2>&1 &
    fi
    local new_pid=$!
    DS_LAST_NINJA_MONITOR_PID="$new_pid"
    export DS_LAST_NINJA_MONITOR_PID
    disown
    printf '%s\n' "$new_pid" > "${STATE_DIR}/ninja_monitor.pid" 2>/dev/null || true
    ds_log "START: ninja_monitor.sh pid=${new_pid}"
}

ds_ninja_monitor_owner_healthy() {
    local owner_file="${NINJA_MONITOR_OWNER_FILE:-$STATE_DIR/ninja_monitor.owner}"
    local identity_file="${owner_file}.identity"
    local owner_pid="" generation="" heartbeat="" script_mtime="" fingerprint=""
    local current_fingerprint=""
    [ -f "$owner_file" ] || return 1
    read -r owner_pid generation heartbeat _legacy_mtime _legacy_fingerprint < "$owner_file" 2>/dev/null || return 1
    [[ "$owner_pid" =~ ^[0-9]+$ && -n "$generation" && "$heartbeat" =~ ^[0-9]+$ ]] || return 1
    ds_pid_live "$owner_pid" || return 1
    [[ "$(ds_cmdline "$owner_pid")" == *"/scripts/ninja_monitor.sh"* ]] || return 1
    read -r script_mtime fingerprint < "$identity_file" 2>/dev/null || return 1
    current_fingerprint="$(sha256sum "$SCRIPT_DIR/scripts/ninja_monitor.sh" 2>/dev/null | awk '{print $1}')"
    [ -n "$fingerprint" ] && [ "$fingerprint" = "$current_fingerprint" ]
}

ds_supervise_ninja_monitor() {
    local owner_file="${NINJA_MONITOR_OWNER_FILE:-$STATE_DIR/ninja_monitor.owner}"
    local start_lock="${STATE_DIR}/ninja_monitor.supervisor.start.lock"
    local starting_file="${STATE_DIR}/ninja_monitor.supervisor.starting"
    local starting_pid="" starting_epoch="" starting_age=0 lock_fd
    local observed_generation="" observed_pid="" observed_heartbeat="" replace_generation=""
    local launch_pid=""
    local -a legacy_pids=()
    if ds_ninja_monitor_owner_healthy; then
        [ -f "$starting_file" ] && unlink "$starting_file" 2>/dev/null || true
        ds_log "HEALTH-OK: ninja_monitor owner=healthy identity=current"
        return 0
    fi

    mapfile -t legacy_pids < <(ds_pattern_pids "[n]inja_monitor\\.sh" "/scripts/ninja_monitor.sh")
    mkdir -p "$STATE_DIR"
    exec {lock_fd}>"$start_lock"
    flock "$lock_fd"
    if ds_ninja_monitor_owner_healthy; then
        [ -f "$starting_file" ] && unlink "$starting_file" 2>/dev/null || true
        flock -u "$lock_fd"; eval "exec ${lock_fd}>&-"
        ds_log "HEALTH-OK: ninja_monitor owner=healthy after-lock identity=current"
        return 0
    fi
    IFS=' ' read -r observed_pid observed_generation observed_heartbeat _legacy_mtime _legacy_fingerprint \
        < "$owner_file" 2>/dev/null || true
    if [ -n "$observed_generation" ]; then
        replace_generation="$observed_generation"
    fi
    if [ -f "$starting_file" ]; then
        read -r starting_pid starting_epoch < "$starting_file" 2>/dev/null || true
        if [[ "$starting_epoch" =~ ^[0-9]+$ ]]; then
            starting_age=$((EPOCHSECONDS - starting_epoch))
        else
            starting_age=999999
        fi
        if [[ "$starting_pid" =~ ^[0-9]+$ ]] && ds_pid_live "$starting_pid" && (( starting_age < 60 )); then
            flock -u "$lock_fd"; eval "exec ${lock_fd}>&-"
            ds_log "HEALTH-WAIT: ninja_monitor startup_claim pid=${starting_pid} age=${starting_age}s legacy_pids=${#legacy_pids[@]}"
            return 0
        fi
    fi
    ds_log "OWNER-INVALID: ninja_monitor owner/identity mismatch; legacy_pids=${#legacy_pids[@]} start=1"
    ds_start_ninja_monitor "$replace_generation"
    launch_pid="${DS_LAST_NINJA_MONITOR_PID:-}"
    printf '%s %s\n' "$launch_pid" "$EPOCHSECONDS" > "$starting_file"
    flock -u "$lock_fd"
    eval "exec ${lock_fd}>&-"
}

ds_start_ntfy_listener() {
    nohup bash "$SCRIPT_DIR/scripts/ntfy_listener.sh" >> "$SCRIPT_DIR/logs/ntfy_listener.log" 2>&1 &
    disown
    ds_log "START: ntfy_listener.sh pid=$!"
}

ds_verify_count() {
    local label="$1"
    local expected="$2"
    shift 2
    local pids=("$@")
    local actual="${#pids[@]}"

    if (( actual == expected )); then
        ds_log "HEALTH-OK: ${label} count=${actual}/${expected}"
        return 0
    fi

    ds_log "HEALTH-WARN: ${label} count=${actual}/${expected}"
    return 1
}

ds_supervise_singleton() {
    local label="$1"
    local pgrep_pattern="$2"
    local cmdline_needle="$3"
    local start_func="$4"
    local pids=()
    local count

    mapfile -t pids < <(ds_pattern_pids "$pgrep_pattern" "$cmdline_needle")
    count="${#pids[@]}"

    if (( count == 0 )); then
        if is_maintenance_active; then
            ds_log "SKIP: daemon maintenance active; ${label} restart deferred"
            return 0
        elif [[ $? -eq 2 ]]; then
            ds_log "BLOCK: corrupt daemon maintenance marker; ${label} restart refused"
            return 1
        fi
        ds_log "MISSING: ${label}; restarting"
        ds_notify "【daemon_supervisor】${label}が0本のため再起動します"
        "$start_func"
    elif (( count > 1 )); then
        ds_log "DUPLICATE: ${label} count=${count} pids=${pids[*]}"
        ds_notify "【daemon_supervisor】${label}が${count}重起動。古いプロセスを停止します"
        ds_stop_duplicates "$label" "${pids[@]}"
    fi

    mapfile -t pids < <(ds_pattern_pids "$pgrep_pattern" "$cmdline_needle")
    ds_verify_count "$label" 1 "${pids[@]}"
}

ds_supervise_inbox_watcher() {
    local agent="$1"
    local pids=()
    local count

    mapfile -t pids < <(ds_inbox_watcher_pids "$agent")
    count="${#pids[@]}"

    if (( count == 0 )); then
        if is_maintenance_active; then
            ds_log "SKIP: daemon maintenance active; inbox_watcher(${agent}) restart deferred"
            return 0
        elif [[ $? -eq 2 ]]; then
            ds_log "BLOCK: corrupt daemon maintenance marker; inbox_watcher(${agent}) restart refused"
            return 1
        fi
        ds_log "MISSING: inbox_watcher(${agent}); restarting"
        ds_notify "【daemon_supervisor】inbox_watcher(${agent})が0本のため再起動します"
        ds_start_inbox_watcher "$agent"
    elif (( count > 1 )); then
        ds_log "DUPLICATE: inbox_watcher(${agent}) count=${count} pids=${pids[*]}"
        ds_notify "【daemon_supervisor】inbox_watcher(${agent})が${count}重起動。古いプロセスを停止します"
        ds_stop_duplicates "inbox_watcher(${agent})" "${pids[@]}"
    fi

    mapfile -t pids < <(ds_inbox_watcher_pids "$agent")
    ds_verify_count "inbox_watcher(${agent})" 1 "${pids[@]}"
}

ds_agent_list() {
    local settings cache_key cache_file line

    settings="$SCRIPT_DIR/config/settings.yaml"
    cache_key="${SCRIPT_DIR//[\/: .#*?!]/_}"
    if ((${#cache_key} > 48)); then
        cache_key="${cache_key: -48}"
    fi
    cache_file="/tmp/shogun_agent_config_${cache_key}.cache"

    if [[ -f "$cache_file" && "$cache_file" -nt "$settings" ]]; then
        while IFS= read -r line; do
            case "$line" in
                _AGENT_CONFIG_CACHE_VERSION=*) eval "$line" ;;
                _AGENT_CONFIG_ALL_NAMES=*) eval "$line" ;;
            esac
        done < "$cache_file"
        if [[ "${_AGENT_CONFIG_CACHE_VERSION:-}" == "3" && -n "${_AGENT_CONFIG_ALL_NAMES:-}" ]]; then
            printf '%s\n' "shogun"
            printf '%s\n' "karo"
            printf '%s\n' $_AGENT_CONFIG_ALL_NAMES
            return 0
        fi
    fi

    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
    {
        printf '%s\n' "shogun"
        get_all_agents | tr ' ' '\n' | sed '/^$/d'
    } | awk 'NF && !seen[$0]++'
}

ds_main() {
    local failed=0
    local agent

    while IFS= read -r agent; do
        [[ -n "$agent" ]] || continue
        ds_supervise_inbox_watcher "$agent" || failed=$((failed + 1))
    done < <(ds_agent_list)

    ds_supervise_ninja_monitor || failed=$((failed + 1))
    ds_supervise_singleton "ntfy_listener.sh" "[n]tfy_listener\.sh" "/scripts/ntfy_listener.sh" ds_start_ntfy_listener || failed=$((failed + 1))

    if (( failed > 0 )); then
        ds_log "SUMMARY: WARN failed_checks=${failed}"
        return 1
    fi

    ds_log "SUMMARY: OK"
    return 0
}

if [[ "${DAEMON_SUPERVISOR_LIB_ONLY:-0}" != "1" ]]; then
    ds_main "$@"
fi
