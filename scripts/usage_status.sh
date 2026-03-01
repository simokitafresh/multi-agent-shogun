#!/usr/bin/env bash
# =============================================================================
# usage_status.sh — tmux status-right integration for usage display
# Ported from MCAS. Sonnet (S:) bar removed.
#
# Wraps usage_monitor.sh --status with a file-based cache.
# Renders Day+Week usage with 5-char progress bars.
# Output: "5H:█▓░░░ 2% 12am 7D:█░░░░ 2% 3/4 2PM"
#
# Cache TTL: MCAS_STATUS_INTERVAL (default 300s / 5 min).
# Graceful degradation: fetch failure does NOT overwrite cache (L007).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cache TTL
CACHE_TTL="${MCAS_STATUS_INTERVAL:-${MCAS_POLL_INTERVAL:-300}}"

CACHE_FILE="/tmp/mcas_usage_status_cache"
CACHE_MAX_AGE=3600  # 1 hour: force delete stale cache regardless of TTL

# =============================================================================
# cache_valid: validate cache content format
# Returns 0 if valid ("5H:" prefix and contains "7D:"), 1 if corrupted
# =============================================================================
cache_valid() {
    local content="$1"
    [[ "$content" == 5H:*7D:* ]]
}

# =============================================================================
# Progress bar: percentage → 5-char bar (█▓░)
# =============================================================================
progress_bar() {
    local pct="$1"
    if [[ "$pct" == "ERR" || "$pct" == "--" ]]; then
        echo "-----"
        return
    fi
    local bar="" i
    for i in 0 1 2 3 4; do
        local full=$(( (i + 1) * 20 ))
        local partial=$(( i * 20 + 5 ))
        if [[ "$pct" -ge "$full" ]]; then
            bar+="█"
        elif [[ "$pct" -ge "$partial" ]]; then
            bar+="▓"
        else
            bar+="░"
        fi
    done
    echo "$bar"
}

# =============================================================================
# Format output: "5H:█▓░░░ 2% 12am 7D:█░░░░ 2% 3/4 2pm"
# =============================================================================
format_line() {
    local d_pct="$1" d_reset="$2" w_pct="$3" w_reset="$4"

    local d_bar w_bar
    d_bar=$(progress_bar "$d_pct")
    w_bar=$(progress_bar "$w_pct")

    local d_disp w_disp
    if [[ "$d_pct" == "ERR" ]]; then d_disp="--"; else d_disp="${d_pct}"; fi
    if [[ "$w_pct" == "ERR" ]]; then w_disp="--"; else w_disp="${w_pct}"; fi

    printf '5H:%s %s%% %s 7D:%s %s%% %s' \
        "$d_bar" "$d_disp" "$d_reset" \
        "$w_bar" "$w_disp" "$w_reset"
}

# =============================================================================
# Check cache freshness
# =============================================================================
if [[ -f "$CACHE_FILE" ]]; then
    cache_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo "0")
    now=$(date +%s)
    cache_age=$(( now - cache_mtime ))

    # Force delete if older than CACHE_MAX_AGE
    if [[ "$cache_age" -ge "$CACHE_MAX_AGE" ]]; then
        rm -f "$CACHE_FILE"
    elif [[ "$cache_age" -lt "$CACHE_TTL" ]]; then
        cached=$(cat "$CACHE_FILE")
        if cache_valid "$cached"; then
            echo "$cached"
            exit 0
        fi
        # Corrupted cache: fall through to refetch
    fi
fi

# =============================================================================
# Cache miss: fetch fresh data via --status
# =============================================================================
raw=$("${SCRIPT_DIR}/usage_monitor.sh" --status 2>/dev/null) || raw=""

# L007: fetch failure → don't overwrite cache
if [[ -z "$raw" ]]; then
    if [[ -f "$CACHE_FILE" ]]; then
        cached=$(cat "$CACHE_FILE")
        if cache_valid "$cached"; then
            echo "$cached"
        else
            echo "5H:----- --% -- 7D:----- --% --"
        fi
    else
        echo "5H:----- --% -- 7D:----- --% --"
    fi
    exit 0
fi

# Parse tab-separated 4 fields
IFS=$'\t' read -r d_pct d_reset w_pct w_reset <<< "$raw"

# Build formatted output
result=$(format_line "$d_pct" "$d_reset" "$w_pct" "$w_reset")

# Atomic write: tmp → mv (prevents partial write corruption)
echo "$result" > "${CACHE_FILE}.tmp.$$" && mv -f "${CACHE_FILE}.tmp.$$" "$CACHE_FILE"
echo "$result"
