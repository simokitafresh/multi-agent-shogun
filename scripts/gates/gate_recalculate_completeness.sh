#!/usr/bin/env bash
# gate_recalculate_completeness.sh — GP-124: fullrecalculate後データ完全性チェック
# 用途: fullrecalculate後に全active portfolioがsignals+monthly_returns(+FoFはcomponent_weights)を持つことを検証
# 使い方: bash scripts/gates/gate_recalculate_completeness.sh
# 前提: backend/.envにDATABASE_URLが設定されていること
set -euo pipefail

DM_SIGNAL_DIR="${DM_SIGNAL_DIR:-/mnt/c/Python_app/DM-signal}"
ENV_FILE="${ENV_FILE:-$DM_SIGNAL_DIR/backend/.env}"
HOSTADDR_CACHE_FILE="${GATE_RECALCULATE_HOSTADDR_CACHE:-/tmp/gate_recalculate_completeness_hostaddr.cache}"
HOSTADDR_CACHE_TTL_SEC="${GATE_RECALCULATE_HOSTADDR_TTL_SEC:-86400}"

load_database_url() {
    local env_file="${1:?env file is required}"
    awk '
        /^DATABASE_URL=/ {
            sub(/\r$/, "", $0)
            print substr($0, index($0, "=") + 1)
            found = 1
            exit
        }
        END {
            if (!found) {
                exit 1
            }
        }
    ' "$env_file"
}

extract_db_host() {
    local database_url="${1:?database url is required}"
    DATABASE_URL_INPUT="$database_url" python3 - <<'PY'
import os
from urllib.parse import urlparse

url = os.environ["DATABASE_URL_INPUT"]
parsed = urlparse(url)
if parsed.hostname:
    print(parsed.hostname)
PY
}

read_cached_hostaddr() {
    local cache_file="${1:?cache file is required}"
    local expected_host="${2:?expected host is required}"
    local ttl_sec="${3:?ttl is required}"

    [[ -f "$cache_file" ]] || return 1

    local now epoch_age cache_host cache_ip cache_epoch
    now=$(date +%s)
    IFS='|' read -r cache_host cache_ip cache_epoch < "$cache_file" || return 1
    [[ "$cache_host" == "$expected_host" ]] || return 1
    [[ "$cache_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    [[ "$cache_epoch" =~ ^[0-9]+$ ]] || return 1

    epoch_age=$((now - cache_epoch))
    (( epoch_age <= ttl_sec )) || return 1

    printf '%s\n' "$cache_ip"
}

write_cached_hostaddr() {
    local cache_file="${1:?cache file is required}"
    local host="${2:?host is required}"
    local ip="${3:?ip is required}"
    mkdir -p "$(dirname "$cache_file")"
    printf '%s|%s|%s\n' "$host" "$ip" "$(date +%s)" > "$cache_file"
}

resolve_hostaddr() {
    local database_url="${1:?database url is required}"
    local cache_file="${2:?cache file is required}"
    local ttl_sec="${3:?ttl is required}"
    local host cached_ip resolved_ip

    host="$(extract_db_host "$database_url")" || return 0
    [[ -n "$host" ]] || return 0

    if cached_ip="$(read_cached_hostaddr "$cache_file" "$host" "$ttl_sec" 2>/dev/null)"; then
        printf '%s\n' "$cached_ip"
        return 0
    fi

    if command -v getent >/dev/null 2>&1; then
        resolved_ip="$(getent ahostsv4 "$host" | awk '$2 == "STREAM" { print $1; exit }')"
    else
        resolved_ip=""
    fi

    if [[ -n "$resolved_ip" ]]; then
        write_cached_hostaddr "$cache_file" "$host" "$resolved_ip"
        printf '%s\n' "$resolved_ip"
    fi
}

run_gate_recalculate_completeness() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "FAIL: $ENV_FILE が見つかりません"
        return 1
    fi

    local database_url
    database_url="$(load_database_url "$ENV_FILE")" || {
        echo "FAIL: DATABASE_URLが空です"
        return 1
    }

    if [[ -z "$database_url" ]]; then
        echo "FAIL: DATABASE_URLが空です"
        return 1
    fi

    local hostaddr=""
    hostaddr="$(resolve_hostaddr "$database_url" "$HOSTADDR_CACHE_FILE" "$HOSTADDR_CACHE_TTL_SEC" || true)"

    export DATABASE_URL="$database_url"
    export GATE_RECALCULATE_HOSTADDR="$hostaddr"

    echo "=== GP-124: Recalculate Data Completeness Check ==="
    echo ""

    python3 <<'PYEOF'
import os
import sys

import psycopg2

DATABASE_URL = os.environ["DATABASE_URL"]
HOSTADDR = os.environ.get("GATE_RECALCULATE_HOSTADDR", "").strip()

QUERY = """
WITH active_portfolios AS (
    SELECT id, name, type
    FROM portfolios
    WHERE is_active = true
),
signal_counts AS (
    SELECT portfolio_id, COUNT(*)::bigint AS signal_count
    FROM signals
    WHERE portfolio_id IN (SELECT id FROM active_portfolios)
    GROUP BY portfolio_id
),
monthly_return_counts AS (
    SELECT portfolio_id, COUNT(*)::bigint AS monthly_return_count
    FROM monthly_returns
    WHERE portfolio_id IN (SELECT id FROM active_portfolios)
    GROUP BY portfolio_id
),
fof_component_weight_counts AS (
    SELECT portfolio_id, COUNT(*)::bigint AS component_weight_count
    FROM fof_component_weights
    WHERE portfolio_id IN (
        SELECT id FROM active_portfolios WHERE type = 'fof'
    )
    GROUP BY portfolio_id
)
SELECT
    p.id,
    p.name,
    p.type,
    COALESCE(s.signal_count, 0) AS signal_count,
    COALESCE(m.monthly_return_count, 0) AS monthly_return_count,
    CASE
        WHEN p.type = 'fof' THEN COALESCE(c.component_weight_count, 0)
        ELSE NULL
    END AS component_weight_count
FROM active_portfolios p
LEFT JOIN signal_counts s ON s.portfolio_id = p.id
LEFT JOIN monthly_return_counts m ON m.portfolio_id = p.id
LEFT JOIN fof_component_weight_counts c ON c.portfolio_id = p.id
ORDER BY p.type, p.name
"""

try:
    connect_kwargs = {
        "connect_timeout": 5,
        "application_name": "gate_recalculate_completeness",
    }
    if HOSTADDR:
        connect_kwargs["hostaddr"] = HOSTADDR

    with psycopg2.connect(DATABASE_URL, **connect_kwargs) as conn:
        with conn.cursor() as cur:
            cur.execute(QUERY)
            rows = cur.fetchall()

    total = len(rows)
    standard = sum(1 for row in rows if row[2] == "standard")
    fofs = sum(1 for row in rows if row[2] == "fof")

    print(f"Active portfolios: {total} (standard={standard}, fof={fofs})")
    print()

    missing_signals = [row for row in rows if row[3] == 0]
    if missing_signals:
        print(f"FAIL: {len(missing_signals)} portfolios with 0 signals:")
        for row in missing_signals:
            print(f"  - {row[1]} ({row[2]}, id={row[0][:8]}...)")
    else:
        print(f"PASS: All {total} portfolios have signals")

    print()

    missing_monthly_returns = [row for row in rows if row[4] == 0]
    if missing_monthly_returns:
        print(f"FAIL: {len(missing_monthly_returns)} portfolios with 0 monthly_returns:")
        for row in missing_monthly_returns:
            print(f"  - {row[1]} ({row[2]}, id={row[0][:8]}...)")
    else:
        print(f"PASS: All {total} portfolios have monthly_returns")

    print()

    missing_component_weights = [row[1] for row in rows if row[2] == "fof" and row[5] == 0]
    if fofs == 0:
        print("INFO: No FoF portfolios found")
    elif missing_component_weights:
        print(f"FAIL: {len(missing_component_weights)} FoFs with 0 component_weights:")
        for name in missing_component_weights:
            print(f"  - {name}")
    else:
        print(f"PASS: All {fofs} FoFs have component_weights")

    print()

    fail_count = (
        len(missing_signals)
        + len(missing_monthly_returns)
        + len(missing_component_weights)
    )
    if fail_count == 0:
        print("=== VERDICT: PASS — All data complete ===")
    else:
        print(f"=== VERDICT: FAIL — {fail_count} gaps detected ===")
        sys.exit(1)
except Exception as exc:
    print(f"ERROR: {exc}")
    sys.exit(1)
PYEOF
}

if [[ "${BASH_SOURCE[0]}" == "$0" && "${GATE_RECALCULATE_LIB_ONLY:-0}" != "1" ]]; then
    run_gate_recalculate_completeness "$@"
fi
