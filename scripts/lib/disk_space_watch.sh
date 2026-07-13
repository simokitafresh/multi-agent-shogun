#!/usr/bin/env bash
# Shared /mnt/c free-space detector for startup gates and ninja_monitor.

disk_space_watch_measure() {
    local mount_path="${DISK_WATCH_MOUNT_PATH:-/mnt/c}"
    local warn_gb="${DISK_WATCH_WARN_GB:-50}"
    local danger_gb="${DISK_WATCH_DANGER_GB:-20}"
    local available_kb

    [[ "$warn_gb" =~ ^[0-9]+$ && "$danger_gb" =~ ^[0-9]+$ ]] || return 2
    (( danger_gb <= warn_gb )) || return 2
    if [[ -n "${DISK_WATCH_AVAILABLE_KB:-}" ]]; then
        available_kb="$DISK_WATCH_AVAILABLE_KB"
    else
        available_kb="$(df -Pk "$mount_path" 2>/dev/null | awk 'NR==2 {print $4}')"
    fi
    [[ "$available_kb" =~ ^[0-9]+$ ]] || return 2

    local warn_kb=$((warn_gb * 1024 * 1024))
    local danger_kb=$((danger_gb * 1024 * 1024))
    local status="OK"
    if (( available_kb < danger_kb )); then
        status="BLOCK"
    elif (( available_kb < warn_kb )); then
        status="WARN"
    fi
    printf '%s|%s|%s|%s|%s\n' "$status" "$available_kb" "$warn_gb" "$danger_gb" "$mount_path"
}

disk_space_watch_human_gb() {
    awk -v kb="${1:-0}" 'BEGIN { printf "%.1f", kb / 1024 / 1024 }'
}

disk_space_watch_log_fire() {
    local root="$1" result="$2" reason="$3"
    local file="${DISK_WATCH_GATE_FIRE_LOG:-$root/logs/gate_fire_log.yaml}"
    mkdir -p "$(dirname "$file")"
    reason="${reason//\"/\\\"}"
    printf -- '- ts: "%s", file: "disk_space_watch:/mnt/c", gate: "disk_space_watch", result: %s, checks: "df_available_kb", reasons: "%s"\n' \
        "$(date -Iseconds)" "$result" "$reason" >> "$file"
}
