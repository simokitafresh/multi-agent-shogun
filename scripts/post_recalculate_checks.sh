#!/usr/bin/env bash
# post_recalculate_checks.sh — recalculate完了後の自動健全性チェック
# cmd_1103 AC1: ワンショット検証のラルフループ化
#
# 実行: bash scripts/post_recalculate_checks.sh
# 出力: PASS/FAIL/WARN 形式 (stdout)
# 戻り値: 0=全PASS, 1=FAIL有り, 2=WARN有り(FAILなし)

set -euo pipefail

DM_SIGNAL_PATH="${DM_SIGNAL_PATH:-/mnt/c/Python_app/DM-signal}"
ENV_PATH="${ENV_PATH:-${DM_SIGNAL_PATH}/backend/.env}"

load_database_url() {
    local env_path="${1:?env path is required}"
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
    ' "$env_path"
}

resolve_database_url() {
    local database_url="${DATABASE_URL:-}"
    if [[ -n "$database_url" ]]; then
        printf '%s\n' "${database_url%$'\r'}"
        return 0
    fi

    if [[ ! -f "$ENV_PATH" ]]; then
        echo "FAIL: backend/.env not found at ${ENV_PATH}" >&2
        return 1
    fi

    database_url="$(load_database_url "$ENV_PATH")" || {
        echo "FAIL: DATABASE_URL not found in backend/.env" >&2
        return 1
    }

    if [[ -z "$database_url" ]]; then
        echo "FAIL: DATABASE_URL not found in backend/.env" >&2
        return 1
    fi

    printf '%s\n' "$database_url"
}

run_post_recalculate_checks() {
    local database_url
    database_url="$(resolve_database_url)" || return 1

    export DATABASE_URL="$database_url"
    export DM_SIGNAL_PATH

    python3 -u - <<'PYTHON_EOF'
import json
import os
import socket
import sys
from datetime import date
from urllib.parse import urlparse

import psycopg2

DATABASE_URL = os.environ["DATABASE_URL"]
DM_SIGNAL_PATH = os.environ["DM_SIGNAL_PATH"]

CASH_RATIO_THRESHOLD = 0.5  # 50%超のPFがCashならWARN

def connect():
    parsed = urlparse(DATABASE_URL)
    host = parsed.hostname
    if host:
        try:
            return psycopg2.connect(DATABASE_URL, hostaddr=socket.gethostbyname(host))
        except Exception:
            pass
    return psycopg2.connect(DATABASE_URL)


def load_portfolios(conn):
    with conn.cursor() as cur:
        cur.execute(
            """
            WITH monthly_stats AS (
                SELECT
                    portfolio_id,
                    COUNT(*)::int AS month_count,
                    COALESCE(
                        SUM(
                            CASE
                                WHEN prev_month IS NOT NULL
                                 AND month_start <> (prev_month + INTERVAL '1 month')::date
                                THEN 1
                                ELSE 0
                            END
                        ),
                        0
                    )::int AS gap_count
                FROM (
                    SELECT
                        portfolio_id,
                        to_date(year_month || '-01', 'YYYY-MM-DD') AS month_start,
                        LAG(to_date(year_month || '-01', 'YYYY-MM-DD'))
                            OVER (PARTITION BY portfolio_id ORDER BY year_month) AS prev_month
                    FROM monthly_returns
                ) monthly_scan
                GROUP BY portfolio_id
            ),
            latest_signals AS (
                SELECT DISTINCT ON (portfolio_id)
                    portfolio_id,
                    date AS latest_signal_date,
                    holding_signal AS latest_holding_signal
                FROM signals
                ORDER BY portfolio_id, date DESC
            )
            SELECT
                p.id,
                p.name,
                p.type,
                p.config,
                p.is_active,
                COALESCE(ms.month_count, 0) AS month_count,
                COALESCE(ms.gap_count, 0) AS gap_count,
                ls.latest_signal_date,
                ls.latest_holding_signal
            FROM portfolios p
            LEFT JOIN monthly_stats ms ON ms.portfolio_id = p.id
            LEFT JOIN latest_signals ls ON ls.portfolio_id = p.id
            ORDER BY p.name
            """
        )
        cols = [d[0] for d in cur.description]
        portfolios = [dict(zip(cols, row)) for row in cur.fetchall()]

    all_pf_ids = {pf["id"] for pf in portfolios}
    return portfolios, all_pf_ids


def parse_config(raw_config):
    if isinstance(raw_config, dict):
        return raw_config
    if not raw_config:
        return {}
    return json.loads(raw_config)


def run_checks():
    conn = connect()
    fail_count = 0
    warn_count = 0

    try:
        # ====================================
        # CHECK 1: 全PF健全性チェック
        # ====================================
        print("=" * 60)
        print("CHECK 1: 全PF健全性チェック")
        print("=" * 60)

        portfolios, all_pf_ids = load_portfolios(conn)

        today = date.today()
        prev_month = today.month - 1
        prev_year = today.year
        if prev_month < 1:
            prev_month = 12
            prev_year -= 1
        prev_ym = f"{prev_year}-{prev_month:02d}"

        pf_failures = []
        pf_warnings = []

        for pf in portfolios:
            pf_id = pf["id"]
            pf_name = pf["name"]
            pf_type = pf["type"]
            config = parse_config(pf["config"])
            issues = []

            # (1a) pipeline_config存在 (standard PFのみ)
            if pf_type != "fof":
                pc = config.get("pipeline_config")
                if pc is None or pc == {}:
                    issues.append("FAIL:pipeline_config missing")

            # (1b) monthly_returns連続性
            if pf["month_count"] == 0:
                issues.append("FAIL:no monthly_returns")
            elif pf["gap_count"] > 0:
                issues.append(f"FAIL:return_gaps({pf['gap_count']})")

            # (1c) signals最新性
            latest_sig = pf["latest_signal_date"]

            if latest_sig is None:
                issues.append("FAIL:no signals")
            else:
                sig_ym = f"{latest_sig.year}-{latest_sig.month:02d}"
                if sig_ym < prev_ym:
                    issues.append(f"WARN:stale signal({latest_sig})")

            # (1d) FoF component整合
            if pf_type == "fof":
                components = config.get("component_portfolios", [])
                if not components:
                    issues.append("FAIL:FoF no components")
                else:
                    missing = [c for c in components if c not in all_pf_ids]
                    if missing:
                        issues.append(f"FAIL:FoF missing refs({len(missing)})")

            # Classify
            has_fail = any("FAIL:" in i for i in issues)
            has_warn = any("WARN:" in i for i in issues)
            if has_fail:
                pf_failures.append((pf_name, pf_type, issues))
            elif has_warn:
                pf_warnings.append((pf_name, pf_type, issues))

        if pf_failures:
            fail_count += len(pf_failures)
            for name, typ, issues in pf_failures:
                print(f"  FAIL: {name} [{typ}] — {'; '.join(issues)}")
        if pf_warnings:
            warn_count += len(pf_warnings)
            for name, typ, issues in pf_warnings:
                print(f"  WARN: {name} [{typ}] — {'; '.join(issues)}")

        ok_count = len(portfolios) - len(pf_failures) - len(pf_warnings)
        status1 = "FAIL" if pf_failures else ("WARN" if pf_warnings else "PASS")
        print(f"  → CHECK 1: {status1} ({ok_count}/{len(portfolios)} OK, {len(pf_failures)} FAIL, {len(pf_warnings)} WARN)")

        # ====================================
        # CHECK 2: FoF component weights存在確認
        # ====================================
        print()
        print("=" * 60)
        print("CHECK 2: FoF component weights存在確認")
        print("=" * 60)

        fof_portfolios = [p for p in portfolios if p["type"] == "fof"]
        fof_weight_failures = []

        for pf in fof_portfolios:
            pf_name = pf["name"]
            config = parse_config(pf["config"])
            components = config.get("component_portfolios", [])
            weights = config.get("component_weights", config.get("weights", []))

            if components and not weights:
                fof_weight_failures.append(pf_name)
                print(f"  FAIL: {pf_name} — component_weights/weights empty")

            if components and weights and len(components) != len(weights):
                fof_weight_failures.append(pf_name)
                print(f"  FAIL: {pf_name} — components({len(components)}) != weights({len(weights)}) count mismatch")

        if fof_weight_failures:
            fail_count += len(fof_weight_failures)
        status2 = "FAIL" if fof_weight_failures else "PASS"
        print(f"  → CHECK 2: {status2} ({len(fof_portfolios)} FoFs checked, {len(fof_weight_failures)} issues)")

        # ====================================
        # CHECK 3: 直近月シグナル異常検出(Cash比率閾値超過)
        # ====================================
        print()
        print("=" * 60)
        print("CHECK 3: 直近月シグナル異常検出(Cash比率)")
        print("=" * 60)

        # 直近月の全standard PFのholding_signalを取得
        standard_pfs = [p for p in portfolios if p["type"] != "fof" and p["is_active"]]
        cash_pfs = []
        checked_pfs = []

        for pf in standard_pfs:
            pf_name = pf["name"]
            holding_signal = pf["latest_holding_signal"]
            if holding_signal:
                checked_pfs.append(pf_name)
                if holding_signal == "Cash":
                    cash_pfs.append(pf_name)

        if checked_pfs:
            cash_ratio = len(cash_pfs) / len(checked_pfs)
            if cash_ratio > CASH_RATIO_THRESHOLD:
                warn_count += 1
                print(f"  WARN: Cash比率 {cash_ratio:.1%} ({len(cash_pfs)}/{len(checked_pfs)}) — 閾値{CASH_RATIO_THRESHOLD:.0%}超過")
                for name in cash_pfs:
                    print(f"    Cash: {name}")
                status3 = "WARN"
            else:
                print(f"  Cash比率 {cash_ratio:.1%} ({len(cash_pfs)}/{len(checked_pfs)}) — 閾値{CASH_RATIO_THRESHOLD:.0%}以内")
                status3 = "PASS"
        else:
            print("  WARN: チェック対象のactive standard PFなし")
            warn_count += 1
            status3 = "WARN"

        print(f"  → CHECK 3: {status3}")

        # ====================================
        # SUMMARY
        # ====================================
        print()
        print("=" * 60)
        if fail_count > 0:
            print(f"OVERALL: FAIL ({fail_count} failures, {warn_count} warnings)")
            sys.exit(1)
        elif warn_count > 0:
            print(f"OVERALL: WARN ({warn_count} warnings)")
            sys.exit(2)
        else:
            print("OVERALL: PASS (all checks passed)")
            sys.exit(0)

    finally:
        conn.close()


if __name__ == "__main__":
    run_checks()
PYTHON_EOF
}

if [[ "${POST_RECALCULATE_CHECKS_LIB_ONLY:-0}" != "1" ]]; then
    run_post_recalculate_checks "$@"
fi
