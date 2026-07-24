#!/usr/bin/env bash
# CDP Chrome Cleanup — remove only the terminal task owner's isolated Chrome.
set -euo pipefail

PID_DIR="${CDP_PID_DIR:-/tmp}"
PID_PREFIX="cdp_chrome_"
LOG_PREFIX="[cdp_cleanup]"

timestamp() { printf '%(%Y-%m-%d %H:%M:%S)T' -1; }
log() { echo "${LOG_PREFIX} $(timestamp) $*"; }
log_err() { echo "${LOG_PREFIX} $(timestamp) ERROR: $*" >&2; }

usage() {
    echo "Usage: $0 --agent AGENT [--cmd CMD]" >&2
    echo "PID record: agent=... profile=... port=... cmd=... pid=... (pid may repeat)" >&2
    exit 2
}

agent=""
cmd=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --agent) [ "$#" -ge 2 ] || usage; agent="$2"; shift 2 ;;
        --cmd) [ "$#" -ge 2 ] || usage; cmd="$2"; shift 2 ;;
        *) usage ;;
    esac
done
[[ "$agent" =~ ^[a-z][a-z0-9_-]*$ ]] || usage

process_command_line() {
    local pid="$1"
    if [ -n "${CDP_PROCESS_TABLE_FILE:-}" ]; then
        awk -F '\t' -v pid="$pid" '$1 == pid { sub(/^[^\t]*\t/, ""); print; exit }' "$CDP_PROCESS_TABLE_FILE"
        return 0
    fi
    powershell.exe -NoProfile -Command \
        "(Get-CimInstance Win32_Process -Filter \"ProcessId=${pid}\").CommandLine" 2>/dev/null | tr -d '\r'
}

stop_process() {
    local pid="$1"
    if [ -n "${CDP_STOP_LOG:-}" ]; then
        printf '%s\n' "$pid" >> "$CDP_STOP_LOG"
        return 0
    fi
    powershell.exe -NoProfile -Command \
        "Stop-Process -Id ${pid} -Force -ErrorAction Stop" >/dev/null 2>&1
}

cleanup_owner() {
    local total=0 killed=0 stale=0 malformed=0 foreign=0
    local pid_file
    shopt -s nullglob
    local pid_files=("${PID_DIR}/${PID_PREFIX}"*.pid)
    shopt -u nullglob

    for pid_file in "${pid_files[@]}"; do
        local rec_agent="" profile="" port="" rec_cmd="" key value
        local -a pids=()
        while IFS='=' read -r key value; do
            value="${value%$'\r'}"
            case "$key" in
                agent) rec_agent="$value" ;;
                profile) profile="$value" ;;
                port) port="$value" ;;
                cmd) rec_cmd="$value" ;;
                pid) pids+=("$value") ;;
            esac
        done < "$pid_file"

        # Legacy numeric-only records have no ownership boundary. Never stop them.
        if [ -z "$rec_agent" ]; then
            foreign=$((foreign + 1))
            continue
        fi
        if [ "$rec_agent" != "$agent" ] || { [ -n "$cmd" ] && [ "$rec_cmd" != "$cmd" ]; }; then
            foreign=$((foreign + 1))
            continue
        fi

        total=$((total + 1))
        if [[ ! "$profile" =~ ^cdp-${agent}-[A-Za-z0-9._-]+$ ]] ||
           [[ ! "$port" =~ ^[0-9]+$ ]] || [ -z "$rec_cmd" ] || [ "${#pids[@]}" -eq 0 ]; then
            log_err "Malformed owned PID record removed: ${pid_file}"
            rm -f -- "$pid_file"
            malformed=$((malformed + 1))
            continue
        fi

        local pid line
        for pid in "${pids[@]}"; do
            if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
                malformed=$((malformed + 1))
                continue
            fi
            line="$(process_command_line "$pid" || true)"
            if [ -z "$line" ]; then
                stale=$((stale + 1))
                continue
            fi
            # Chrome children do not all repeat --remote-debugging-port.  The
            # unique isolated profile is therefore the per-process ownership
            # token; port remains mandatory in the record and binds the group.
            if [[ "$line" != *"$profile"* ]]; then
                stale=$((stale + 1))
                continue
            fi
            if stop_process "$pid"; then
                killed=$((killed + 1))
            else
                stale=$((stale + 1))
            fi
        done
        rm -f -- "$pid_file"
    done

    log "Summary: owner=${agent} cmd=${cmd:-any} records=${total} killed=${killed} stale=${stale} malformed=${malformed} foreign_kept=${foreign}"
}

cleanup_orphan_profiles() {
    local total=0 killed=0 pid cmdline
    if [ -n "${CDP_PROCESS_TABLE_FILE:-}" ]; then
        while IFS=$'\t' read -r pid cmdline; do
            cmdline="${cmdline%$'\r'}"
            [[ "$pid" =~ ^[0-9]+$ ]] || continue
            [[ "$cmdline" == *"cdp-"* && "$cmdline" == *"--remote-debugging-port"* ]] || continue
            total=$((total + 1))
            if stop_process "$pid"; then
                killed=$((killed + 1))
            fi
        done < "$CDP_PROCESS_TABLE_FILE"
    else
        local ps_out
        ps_out="$(powershell.exe -NoProfile -Command \
            "(Get-CimInstance Win32_Process -Filter \"Name='chrome.exe'\").ForEach({\$_.ProcessId.ToString() + [char]9 + [string]\$_.CommandLine})" \
            2>/dev/null | tr -d '\r')" || true
        while IFS=$'\t' read -r pid cmdline; do
            [[ "$pid" =~ ^[0-9]+$ ]] || continue
            [[ "$cmdline" == *"cdp-"* && "$cmdline" == *"--remote-debugging-port"* ]] || continue
            total=$((total + 1))
            if stop_process "$pid"; then
                killed=$((killed + 1))
            fi
        done <<< "$ps_out"
    fi
    log "Orphan profiles scan: found=${total} killed=${killed}"
}

log "Starting owner-scoped CDP cleanup..."
cleanup_owner
cleanup_orphan_profiles
log "Done."
