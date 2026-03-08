#!/usr/bin/env bash
# =============================================================================
# usage_status.sh — tmux status-right integration for usage display
# Ported from MCAS. Legacy secondary-model bar removed.
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

CACHE_MAX_AGE=3600  # 1 hour: force delete stale cache regardless of TTL

# =============================================================================
# detect_shogun_provider: auto-detect provider for shogun pane
# Returns: claude | codex (fallback: claude)
# =============================================================================
detect_shogun_provider() {
    local pane_cli
    pane_cli=$(tmux show-options -p -t shogun:main -v @agent_cli 2>/dev/null | tr -d '\r[:space:]' || true)
    case "$pane_cli" in
        codex|claude)
            echo "$pane_cli"
            return 0
            ;;
    esac

    # Fallback to settings.yaml if pane variable is absent.
    if [[ -f "${SCRIPT_DIR}/../config/settings.yaml" ]]; then
        python3 - "${SCRIPT_DIR}/../config/settings.yaml" <<'PY'
import yaml
from pathlib import Path
import sys
cfg_path = Path(sys.argv[1]).resolve()
try:
    cfg = yaml.safe_load(cfg_path.read_text(encoding="utf-8")) or {}
    cli = (cfg.get("cli") or {})
    agents = (cli.get("agents") or {})
    shogun = (agents.get("shogun") or {})
    t = (shogun.get("type") or cli.get("default") or "claude").strip()
    if t not in {"claude", "codex"}:
        t = "claude"
    print(t)
except Exception:
    print("claude")
PY
        return 0
    fi

    echo "claude"
}

# =============================================================================
# cache_valid: validate cache content format
# Returns 0 if valid ("5H:" prefix and contains "7D:"), 1 if corrupted
# =============================================================================
cache_valid() {
    local content="$1"
    local provider="${2:-claude}"
    if [[ "$content" != 5H:*7D:* ]]; then
        return 1
    fi
    # Codex format v2 includes explicit "left" labels.
    if [[ "$provider" == "codex" ]] && [[ "$content" != *" left "* ]]; then
        return 1
    fi
    return 0
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
# Format output:
# - Claude: "5H:█▓░░░ 2% 12am 7D:█░░░░ 2% 3/4 2pm" (used%)
# - Codex:  "5H:████▓ 94% left 18:58 7D:████▓ 98% left 13:58 on 10 Mar"
# =============================================================================
format_line() {
    local d_pct="$1" d_reset="$2" w_pct="$3" w_reset="$4" provider="${5:-claude}"

    local d_bar w_bar
    d_bar=$(progress_bar "$d_pct")
    w_bar=$(progress_bar "$w_pct")

    local d_disp w_disp
    if [[ "$d_pct" == "ERR" ]]; then d_disp="--"; else d_disp="${d_pct}"; fi
    if [[ "$w_pct" == "ERR" ]]; then w_disp="--"; else w_disp="${w_pct}"; fi

    if [[ "$provider" == "codex" ]]; then
        printf '5H:%s %s%% left %s 7D:%s %s%% left %s' \
            "$d_bar" "$d_disp" "$d_reset" \
            "$w_bar" "$w_disp" "$w_reset"
    else
        printf '5H:%s %s%% %s 7D:%s %s%% %s' \
            "$d_bar" "$d_disp" "$d_reset" \
            "$w_bar" "$w_disp" "$w_reset"
    fi
}

# =============================================================================
# Check cache freshness
# =============================================================================
PROVIDER="$(detect_shogun_provider)"
CACHE_FILE="/tmp/mcas_usage_status_cache_${PROVIDER}"

if [[ -f "$CACHE_FILE" ]]; then
    cache_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo "0")
    now=$(date +%s)
    cache_age=$(( now - cache_mtime ))

    # Force delete if older than CACHE_MAX_AGE
    if [[ "$cache_age" -ge "$CACHE_MAX_AGE" ]]; then
        rm -f "$CACHE_FILE"
    elif [[ "$cache_age" -lt "$CACHE_TTL" ]]; then
        cached=$(cat "$CACHE_FILE")
        if cache_valid "$cached" "$PROVIDER"; then
            echo "$cached"
            exit 0
        fi
        # Corrupted cache: fall through to refetch
    fi
fi

# =============================================================================
# Cache miss: fetch fresh data via --status
# =============================================================================
if [[ "$PROVIDER" == "codex" ]]; then
    raw=$("${SCRIPT_DIR}/usage_monitor_codex.sh" --status 2>/dev/null) || raw=""
else
    raw=$("${SCRIPT_DIR}/usage_monitor.sh" --status 2>/dev/null) || raw=""
fi

# L007: fetch failure → don't overwrite cache
if [[ -z "$raw" ]]; then
    if [[ -f "$CACHE_FILE" ]]; then
        cached=$(cat "$CACHE_FILE")
        if cache_valid "$cached" "$PROVIDER"; then
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
result=$(format_line "$d_pct" "$d_reset" "$w_pct" "$w_reset" "$PROVIDER")

# Atomic write: tmp → mv (prevents partial write corruption)
echo "$result" > "${CACHE_FILE}.tmp.$$" && mv -f "${CACHE_FILE}.tmp.$$" "$CACHE_FILE"
echo "$result"
