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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${DAEMON_SUPERVISOR_LOG:-$SCRIPT_DIR/logs/daemon_supervisor.log}"
STATE_DIR="${SHOGUN_STATE_DIR:-${IDLE_FLAG_DIR:-/tmp}}"

mkdir -p "$SCRIPT_DIR/logs"

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

    keep="$(ds_oldest_pid "${pids[@]}")"
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
        &>> "$SCRIPT_DIR/logs/inbox_watcher_${agent}.log" &
    disown
    ds_log "START: inbox_watcher(${agent}) pane=${pane} cli=${cli} pid=$!"
    return 0
}

ds_start_ninja_monitor() {
    nohup bash "$SCRIPT_DIR/scripts/ninja_monitor.sh" >> "$SCRIPT_DIR/logs/ninja_monitor.log" 2>&1 &
    local new_pid=$!
    disown
    printf '%s\n' "$new_pid" > "${STATE_DIR}/ninja_monitor.pid" 2>/dev/null || true
    ds_log "START: ninja_monitor.sh pid=${new_pid}"
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
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
    printf '%s\n' "shogun"
    get_all_agents | tr ' ' '\n' | sed '/^$/d'
}

ds_main() {
    local failed=0
    local agent

    while IFS= read -r agent; do
        [[ -n "$agent" ]] || continue
        ds_supervise_inbox_watcher "$agent" || failed=$((failed + 1))
    done < <(ds_agent_list)

    ds_supervise_singleton "ninja_monitor.sh" "[n]inja_monitor\.sh" "/scripts/ninja_monitor.sh" ds_start_ninja_monitor || failed=$((failed + 1))
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
