#!/usr/bin/env bash
# =============================================================================
# usage_monitor.sh — Claude Max Plan Usage Monitor
# Ported from MCAS. Sonnet bucket removed. No mcas repo dependency.
#
# Usage:
#   ./usage_monitor.sh --once    # Single fetch, 5h only: x% (legacy)
#   ./usage_monitor.sh --status  # Structured Day+Week output (4 fields, tab-separated)
#   ./usage_monitor.sh --watch   # Continuous polling loop
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/mcas_common.sh"

# Defaults (env var > hardcoded)
MCAS_PRIMARY_DIR="${MCAS_PRIMARY_DIR:-${HOME}/.claude}"
MCAS_POLL_INTERVAL="${MCAS_POLL_INTERVAL:-60}"
MCAS_ALERT_THRESHOLD="${MCAS_ALERT_THRESHOLD:-80}"
MCAS_ALERT_COOLDOWN="${MCAS_ALERT_COOLDOWN:-300}"
MCAS_NTFY_TOPIC="${MCAS_NTFY_TOPIC:-}"
MCAS_API_TIMEOUT="${MCAS_API_TIMEOUT:-15}"

# Expand ~ in directory paths
MCAS_PRIMARY_DIR="${MCAS_PRIMARY_DIR/#\~/$HOME}"

API_URL="https://api.anthropic.com/api/oauth/usage"
ALERT_STATE_DIR="/tmp/mcas_alert_state"

# =============================================================================
# Functions
# =============================================================================

fetch_usage() {
    local token="$1"
    local response
    response=$(curl -s --max-time "$MCAS_API_TIMEOUT" \
        -H "Authorization: Bearer ${token}" \
        -H "anthropic-beta: oauth-2025-04-20" \
        "$API_URL" 2>/dev/null) || { echo ""; return 1; }

    # Validate JSON response
    if ! echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
        echo >&2 "[usage] unexpected API response"
        echo ""
        return 1
    fi

    echo "$response"
}

calc_usage_pct() {
    local json="$1"
    local bucket="$2"  # five_hour, seven_day

    if [[ -z "$json" ]]; then
        echo "ERR"
        return
    fi

    local utilization
    utilization=$(echo "$json" | jq -r ".${bucket}.utilization // empty" 2>/dev/null)

    if [[ -z "$utilization" ]]; then
        echo "ERR"
        return
    fi

    # Round to integer
    awk "BEGIN { printf \"%.0f\", ${utilization} }"
}

format_reset_time() {
    local iso_time="$1"
    if [[ -z "$iso_time" || "$iso_time" == "null" ]]; then
        echo "--"
        return
    fi
    local epoch
    epoch=$(date -d "$iso_time" +%s 2>/dev/null) || { echo "--"; return; }
    local today
    today=$(date +%Y-%m-%d)
    local reset_date
    reset_date=$(date -d "@$epoch" +%Y-%m-%d 2>/dev/null) || { echo "--"; return; }

    local hour minute ampm
    hour=$(date -d "@$epoch" +%-I)
    minute=$(date -d "@$epoch" +%M)
    ampm=$(date -d "@$epoch" +%P)  # lowercase am/pm

    local time_str
    if [[ "$minute" == "00" ]]; then
        time_str="${hour}${ampm}"
    else
        time_str="${hour}:${minute}${ampm}"
    fi

    if [[ "$today" == "$reset_date" ]]; then
        echo "$time_str"
    else
        local month day
        month=$(date -d "@$epoch" +%-m)
        day=$(date -d "@$epoch" +%-d)
        echo "${month}/${day} ${time_str}"
    fi
}

get_resets_at() {
    local json="$1"
    local bucket="$2"
    if [[ -z "$json" ]]; then
        echo "--"
        return
    fi
    local raw
    raw=$(echo "$json" | jq -r ".${bucket}.resets_at // empty" 2>/dev/null)
    if [[ -z "$raw" ]]; then
        echo "--"
        return
    fi
    format_reset_time "$raw"
}

format_account() {
    local label="$1"
    local pct="$2"
    local threshold="$3"

    if [[ "$pct" == "ERR" ]]; then
        echo "${label}:--"
        return
    fi

    if [[ "$pct" -ge "$threshold" ]]; then
        printf '%s:%s%%⚠' "$label" "$pct"
    else
        printf '%s:%s%%' "$label" "$pct"
    fi
}

should_alert() {
    local account_key="$1"
    local state_file="${ALERT_STATE_DIR}/${account_key}"

    mkdir -p "$ALERT_STATE_DIR" 2>/dev/null || true

    if [[ -f "$state_file" ]]; then
        local last_alert
        last_alert=$(cat "$state_file" 2>/dev/null || echo "0")
        local now
        now=$(date +%s)
        if (( now - last_alert < MCAS_ALERT_COOLDOWN )); then
            return 1  # cooldown active
        fi
    fi

    return 0  # should alert
}

send_alert() {
    local name="$1"
    local pct="$2"
    local account_key="$3"

    [[ "$pct" == "ERR" ]] && return
    [[ -z "$MCAS_NTFY_TOPIC" ]] && return
    [[ "$pct" -lt "$MCAS_ALERT_THRESHOLD" ]] && return

    if ! should_alert "$account_key"; then
        return
    fi

    curl -s -d "【Usage】${name} usage ${pct}% (threshold: ${MCAS_ALERT_THRESHOLD}%)" \
        "https://ntfy.sh/${MCAS_NTFY_TOPIC}" >/dev/null 2>&1 || true

    mkdir -p "$ALERT_STATE_DIR" 2>/dev/null || true
    date +%s > "${ALERT_STATE_DIR}/${account_key}"
}

monitor_once() {
    local token="" json="" pct

    token=$(mcas_get_token "$MCAS_PRIMARY_DIR" 2>/dev/null) || true

    if [[ -n "$token" ]]; then
        json=$(fetch_usage "$token") || true
    fi

    pct=$(calc_usage_pct "$json" "five_hour")

    local fmt
    fmt=$(format_account "" "$pct" "$MCAS_ALERT_THRESHOLD")
    echo "[${fmt}]"

    send_alert "5h" "$pct" "primary_5h"
}

monitor_status() {
    local token="" json=""

    token=$(mcas_get_token "$MCAS_PRIMARY_DIR" 2>/dev/null) || true

    if [[ -n "$token" ]]; then
        json=$(fetch_usage "$token") || true
    fi

    # Day (five_hour) + Week (seven_day) — Sonnet removed
    local d_pct w_pct
    d_pct=$(calc_usage_pct "$json" "five_hour")
    w_pct=$(calc_usage_pct "$json" "seven_day")

    # Resets_at (ISO 8601 → short format)
    local d_reset w_reset
    d_reset=$(get_resets_at "$json" "five_hour")
    w_reset=$(get_resets_at "$json" "seven_day")

    # Tab-separated structured output (4 fields)
    printf '%s\t%s\t%s\t%s\n' "$d_pct" "$d_reset" "$w_pct" "$w_reset"

    # Alerts (Day bucket)
    send_alert "5h" "$d_pct" "primary_5h"
}

monitor_watch() {
    echo "[usage] Starting watch mode (interval: ${MCAS_POLL_INTERVAL}s, threshold: ${MCAS_ALERT_THRESHOLD}%)"
    while true; do
        local output
        output=$(monitor_once)
        echo "$(date '+%H:%M:%S') ${output}"
        sleep "$MCAS_POLL_INTERVAL"
    done
}

show_help() {
    cat <<'HELP'
usage_monitor.sh — Claude Max Plan Usage Monitor

Usage:
  ./usage_monitor.sh [--once]    Single fetch (default). Outputs: [72%]
  ./usage_monitor.sh --status    Structured Day+Week output (tab-separated 4 fields)
  ./usage_monitor.sh --watch     Continuous polling with timestamps
  ./usage_monitor.sh --help      Show this help

Output format:
  --once:   [72%]                       (5h only)
  --status: D%\tD_reset\tW%\tW_reset
HELP
    exit 0
}

# =============================================================================
# Main
# =============================================================================
case "${1:---once}" in
    --once)   monitor_once ;;
    --status) monitor_status ;;
    --watch)  monitor_watch ;;
    --help|-h) show_help ;;
    *) echo "Unknown option: $1" >&2; show_help ;;
esac
