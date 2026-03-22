#!/usr/bin/env bash
# parity_check.sh — PF登録後のパリティ検証スクリプト
# cmd_1103 AC2: 本番DB vs experiments.db突合
#
# 使い方:
#   bash scripts/parity_check.sh <PF名 or UUID> [<PF名 or UUID> ...]
#   bash scripts/parity_check.sh --all   # 全PF一括チェック
#
# 出力: PASS(完全一致) / FAIL(不一致月あり+詳細)
# 戻り値: 0=全PASS, 1=FAIL有り

set -euo pipefail

DM_SIGNAL_PATH="/mnt/c/Python_app/DM-signal"
ENV_PATH="${DM_SIGNAL_PATH}/backend/.env"
EXPERIMENTS_DB="${DM_SIGNAL_PATH}/analysis_runs/experiments.db"

if [[ $# -eq 0 ]]; then
    echo "Usage: bash scripts/parity_check.sh <PF名 or UUID> [...]"
    echo "       bash scripts/parity_check.sh --all"
    exit 1
fi

if [[ ! -f "$ENV_PATH" ]]; then
    echo "FAIL: backend/.env not found at ${ENV_PATH}"
    exit 1
fi

if [[ ! -f "$EXPERIMENTS_DB" ]]; then
    echo "FAIL: experiments.db not found at ${EXPERIMENTS_DB}"
    exit 1
fi

DATABASE_URL=$(grep '^DATABASE_URL=' "$ENV_PATH" | cut -d= -f2-)
if [[ -z "$DATABASE_URL" ]]; then
    echo "FAIL: DATABASE_URL not found in backend/.env"
    exit 1
fi

export DATABASE_URL
export DM_SIGNAL_PATH
export EXPERIMENTS_DB

# Pass all arguments to Python
ARGS=("$@")
export PARITY_ARGS="${ARGS[*]}"

python3 -u - <<'PYTHON_EOF'
import json
import os
import sqlite3
import sys

import psycopg2

DATABASE_URL = os.environ["DATABASE_URL"]
EXPERIMENTS_DB = os.environ["EXPERIMENTS_DB"]
PARITY_ARGS = os.environ["PARITY_ARGS"].split()

TOLERANCE = 1e-10  # 浮動小数点許容誤差


def get_prod_connection():
    return psycopg2.connect(DATABASE_URL)


def get_experiments_connection():
    return sqlite3.connect(EXPERIMENTS_DB)


def resolve_portfolios(pg_conn, args):
    """引数からPF一覧を解決。名前 or UUID or --all"""
    with pg_conn.cursor() as cur:
        if "--all" in args:
            cur.execute("SELECT id, name, type FROM portfolios WHERE is_active = true ORDER BY name")
            return [(row[0], row[1], row[2]) for row in cur.fetchall()]

        results = []
        for arg in args:
            # UUID形式かチェック
            if len(arg) == 36 and arg.count("-") == 4:
                cur.execute("SELECT id, name, type FROM portfolios WHERE id = %s", (arg,))
            else:
                cur.execute("SELECT id, name, type FROM portfolios WHERE name = %s", (arg,))
            rows = cur.fetchall()
            if not rows:
                # 部分一致で検索
                cur.execute("SELECT id, name, type FROM portfolios WHERE name ILIKE %s", (f"%{arg}%",))
                rows = cur.fetchall()
            if not rows:
                print(f"  WARN: '{arg}' に一致するPFなし — スキップ")
                continue
            if len(rows) > 1:
                print(f"  WARN: '{arg}' に複数一致 — 全て検証:")
                for r in rows:
                    print(f"    {r[1]} ({r[0][:8]}...)")
            for row in rows:
                results.append((row[0], row[1], row[2]))
        return results


def check_return_parity(pg_conn, sqlite_conn, pf_id, pf_name):
    """月次リターンのパリティ検証"""
    # Production data
    with pg_conn.cursor() as cur:
        cur.execute(
            """SELECT year_month, return_open, return_close
               FROM monthly_returns
               WHERE portfolio_id = %s
               ORDER BY year_month""",
            (pf_id,),
        )
        prod_returns = {row[0]: (row[1], row[2]) for row in cur.fetchall()}

    # experiments.db data
    sqlite_cur = sqlite_conn.cursor()
    sqlite_cur.execute(
        """SELECT year_month, return_open, return_close
           FROM monthly_returns
           WHERE portfolio_id = ?
           ORDER BY year_month""",
        (pf_id,),
    )
    gs_returns = {row[0]: (row[1], row[2]) for row in sqlite_cur.fetchall()}

    if not gs_returns:
        return "SKIP", 0, 0, "experiments.dbにデータなし"

    # Compare common months
    common_months = sorted(set(prod_returns.keys()) & set(gs_returns.keys()))
    if not common_months:
        return "SKIP", 0, 0, "共通月なし"

    mismatches = []
    for ym in common_months:
        prod_open, prod_close = prod_returns[ym]
        gs_open, gs_close = gs_returns[ym]

        open_diff = abs((prod_open or 0) - (gs_open or 0))
        close_diff = abs((prod_close or 0) - (gs_close or 0))

        if open_diff > TOLERANCE or close_diff > TOLERANCE:
            mismatches.append({
                "ym": ym,
                "prod_open": prod_open,
                "gs_open": gs_open,
                "diff_open": open_diff,
                "prod_close": prod_close,
                "gs_close": gs_close,
                "diff_close": close_diff,
            })

    total = len(common_months)
    matched = total - len(mismatches)

    if mismatches:
        detail_lines = []
        for m in mismatches[:5]:  # 最初の5件のみ表示
            detail_lines.append(
                f"    {m['ym']}: open diff={m['diff_open']:.10f}, close diff={m['diff_close']:.10f}"
            )
        if len(mismatches) > 5:
            detail_lines.append(f"    ... (+{len(mismatches) - 5} more)")
        detail = "\n".join(detail_lines)
        return "FAIL", matched, total, detail
    else:
        return "PASS", matched, total, ""


def check_signal_parity(pg_conn, sqlite_conn, pf_id, pf_name):
    """シグナルのパリティ検証 (experiments.db monthly_returns.signal vs prod signals.holding_signal)"""
    # Production holding_signals
    with pg_conn.cursor() as cur:
        cur.execute(
            """SELECT TO_CHAR(date, 'YYYY-MM') as ym, holding_signal
               FROM signals
               WHERE portfolio_id = %s AND holding_signal IS NOT NULL
               ORDER BY date""",
            (pf_id,),
        )
        prod_signals = {}
        for row in cur.fetchall():
            prod_signals[row[0]] = row[1]

    # experiments.db: extract main ticker from signal JSON weights
    sqlite_cur = sqlite_conn.cursor()
    sqlite_cur.execute(
        """SELECT year_month, signal
           FROM monthly_returns
           WHERE portfolio_id = ?
           ORDER BY year_month""",
        (pf_id,),
    )

    gs_signals = {}
    for row in sqlite_cur.fetchall():
        ym = row[0]
        sig_raw = row[1]
        if sig_raw:
            try:
                weights = json.loads(sig_raw)
                if isinstance(weights, dict) and weights:
                    # 最大ウェイトのティッカーをシグナルとみなす
                    main_ticker = max(weights, key=weights.get)
                    gs_signals[ym] = main_ticker
            except (json.JSONDecodeError, TypeError):
                pass

    if not gs_signals:
        return "SKIP", 0, 0, "experiments.dbにシグナルデータなし"

    common_months = sorted(set(prod_signals.keys()) & set(gs_signals.keys()))
    if not common_months:
        return "SKIP", 0, 0, "共通月なし"

    mismatches = []
    for ym in common_months:
        if prod_signals[ym] != gs_signals[ym]:
            mismatches.append(f"    {ym}: prod={prod_signals[ym]}, gs={gs_signals[ym]}")

    total = len(common_months)
    matched = total - len(mismatches)

    if mismatches:
        detail = "\n".join(mismatches[:5])
        if len(mismatches) > 5:
            detail += f"\n    ... (+{len(mismatches) - 5} more)"
        return "FAIL", matched, total, detail
    else:
        return "PASS", matched, total, ""


def main():
    pg_conn = get_prod_connection()
    sqlite_conn = get_experiments_connection()

    try:
        portfolios = resolve_portfolios(pg_conn, PARITY_ARGS)
        if not portfolios:
            print("FAIL: チェック対象PFなし")
            sys.exit(1)

        print(f"Parity check: {len(portfolios)} PF(s)")
        print("=" * 60)

        overall_fail = False

        for pf_id, pf_name, pf_type in portfolios:
            print(f"\n--- {pf_name} [{pf_type}] ({pf_id[:8]}...) ---")

            # Return parity
            ret_status, ret_match, ret_total, ret_detail = check_return_parity(
                pg_conn, sqlite_conn, pf_id, pf_name
            )
            if ret_status == "SKIP":
                print(f"  Returns: SKIP — {ret_detail}")
            elif ret_status == "PASS":
                print(f"  Returns: PASS ({ret_match}/{ret_total} months match)")
            else:
                print(f"  Returns: FAIL ({ret_match}/{ret_total} months match)")
                print(ret_detail)
                overall_fail = True

            # Signal parity (standard PFs only)
            if pf_type != "fof":
                sig_status, sig_match, sig_total, sig_detail = check_signal_parity(
                    pg_conn, sqlite_conn, pf_id, pf_name
                )
                if sig_status == "SKIP":
                    print(f"  Signals: SKIP — {sig_detail}")
                elif sig_status == "PASS":
                    print(f"  Signals: PASS ({sig_match}/{sig_total} months match)")
                else:
                    print(f"  Signals: FAIL ({sig_match}/{sig_total} months match)")
                    print(sig_detail)
                    overall_fail = True
            else:
                print("  Signals: N/A (FoF)")

        print()
        print("=" * 60)
        if overall_fail:
            print("OVERALL: FAIL")
            sys.exit(1)
        else:
            print("OVERALL: PASS")
            sys.exit(0)

    finally:
        pg_conn.close()
        sqlite_conn.close()


if __name__ == "__main__":
    main()
PYTHON_EOF
