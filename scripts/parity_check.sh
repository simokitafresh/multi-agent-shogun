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

DM_SIGNAL_PATH="${DM_SIGNAL_PATH:-/mnt/c/Python_app/DM-signal}"
ENV_PATH="${ENV_PATH:-${DM_SIGNAL_PATH}/backend/.env}"
EXPERIMENTS_DB="${EXPERIMENTS_DB:-${DM_SIGNAL_PATH}/analysis_runs/experiments.db}"

print_usage() {
    echo "Usage: bash scripts/parity_check.sh <PF名 or UUID> [...]"
    echo "       bash scripts/parity_check.sh --all"
}

is_help_request() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                return 0
                ;;
        esac
    done
    return 1
}

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

# GP-XXX4: 早期終了ガード — Python heredoc定義(~300行)前に共通fast-pathを処理
# PARITY_CHECK_LIB_ONLY=1時はソース経由のため$# > 0 (テストがargs付きでsource)→pass-through
if [[ "${PARITY_CHECK_LIB_ONLY:-0}" != "1" ]]; then
    if [[ $# -eq 0 ]]; then
        print_usage; exit 1
    elif [[ "$1" == "-h" || "$1" == "--help" ]]; then
        print_usage; exit 0
    fi
fi

run_parity_check() {
    if [[ $# -eq 0 ]]; then
        print_usage
        return 1
    fi

    if is_help_request "$@"; then
        print_usage
        return 0
    fi

    if [[ ! -f "$ENV_PATH" ]]; then
        echo "FAIL: backend/.env not found at ${ENV_PATH}"
        return 1
    fi

    if [[ ! -f "$EXPERIMENTS_DB" ]]; then
        echo "FAIL: experiments.db not found at ${EXPERIMENTS_DB}"
        return 1
    fi

    local database_url
    database_url="$(load_database_url "$ENV_PATH")" || {
        echo "FAIL: DATABASE_URL not found in backend/.env"
        return 1
    }

    if [[ -z "$database_url" ]]; then
        echo "FAIL: DATABASE_URL not found in backend/.env"
        return 1
    fi

    export DATABASE_URL="$database_url"
    export DM_SIGNAL_PATH
    export EXPERIMENTS_DB

    python3 -u - "$@" <<'PYTHON_EOF'
import json
import os
import sqlite3
import sys

import psycopg2

DATABASE_URL = os.environ["DATABASE_URL"]
EXPERIMENTS_DB = os.environ["EXPERIMENTS_DB"]
PARITY_ARGS = sys.argv[1:]

TOLERANCE = 1e-10  # 浮動小数点許容誤差


def get_prod_connection():
    try:
        return psycopg2.connect(DATABASE_URL)
    except psycopg2.OperationalError as e:
        print(f"FAIL: 本番DB接続失敗 — {e}")
        sys.exit(1)
    except Exception as e:
        print(f"FAIL: DB接続エラー(本番) — {e}")
        sys.exit(1)


def get_experiments_connection():
    try:
        return sqlite3.connect(EXPERIMENTS_DB)
    except sqlite3.OperationalError as e:
        print(f"FAIL: experiments.db接続失敗 — {e}")
        sys.exit(1)
    except Exception as e:
        print(f"FAIL: DB接続エラー(experiments) — {e}")
        sys.exit(1)


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


def fetch_batch_prod_returns(pg_conn, pf_ids):
    """PostgreSQL: N PFの月次リターンを1クエリで一括取得 (N→1クエリ削減)"""
    if not pf_ids:
        return {}
    with pg_conn.cursor() as cur:
        cur.execute(
            "SELECT portfolio_id, year_month, return_open, return_close "
            "FROM monthly_returns WHERE portfolio_id = ANY(%s) "
            "ORDER BY portfolio_id, year_month",
            (list(pf_ids),),
        )
        result = {}
        for row in cur.fetchall():
            pf_id = row[0]
            if pf_id not in result:
                result[pf_id] = {}
            result[pf_id][row[1]] = (row[2], row[3])
    return result


def fetch_batch_sqlite_data(sqlite_conn, pf_ids):
    """SQLite: N PFのmonthly_returns+signalを1クエリで一括取得 (N→1クエリ削減)"""
    if not pf_ids:
        return {}, {}
    placeholders = ",".join("?" * len(pf_ids))
    sqlite_cur = sqlite_conn.cursor()
    sqlite_cur.execute(
        f"SELECT portfolio_id, year_month, return_open, return_close, signal "
        f"FROM monthly_returns WHERE portfolio_id IN ({placeholders}) "
        f"ORDER BY portfolio_id, year_month",
        list(pf_ids),
    )
    returns_data = {}
    signals_data = {}
    for row in sqlite_cur.fetchall():
        pf_id, ym, ret_open, ret_close, sig_raw = row
        if pf_id not in returns_data:
            returns_data[pf_id] = {}
            signals_data[pf_id] = {}
        returns_data[pf_id][ym] = (ret_open, ret_close)
        if sig_raw:
            try:
                weights = json.loads(sig_raw)
                if isinstance(weights, dict) and weights:
                    main_ticker = max(weights, key=weights.get)
                    signals_data[pf_id][ym] = main_ticker
            except (json.JSONDecodeError, TypeError):
                pass
    return returns_data, signals_data


def fetch_batch_prod_signals(pg_conn, pf_ids):
    """PostgreSQL: N PFのsignalsを1クエリで一括取得 (N→1クエリ削減)"""
    if not pf_ids:
        return {}
    with pg_conn.cursor() as cur:
        cur.execute(
            "SELECT portfolio_id, TO_CHAR(date, 'YYYY-MM') AS ym, holding_signal "
            "FROM signals WHERE portfolio_id = ANY(%s) AND holding_signal IS NOT NULL "
            "ORDER BY portfolio_id, date",
            (list(pf_ids),),
        )
        result = {}
        for row in cur.fetchall():
            pf_id = row[0]
            if pf_id not in result:
                result[pf_id] = {}
            result[pf_id][row[1]] = row[2]
    return result


def check_return_parity(prod_returns, gs_returns, pf_id, pf_name):
    """月次リターンのパリティ検証 (pre-fetched data)"""
    pf_prod = prod_returns.get(pf_id, {})
    pf_gs = gs_returns.get(pf_id, {})

    if not pf_gs:
        return "SKIP", 0, 0, "experiments.dbにデータなし"

    # Compare common months
    common_months = sorted(set(pf_prod.keys()) & set(pf_gs.keys()))
    if not common_months:
        return "SKIP", 0, 0, "共通月なし"

    mismatches = []
    for ym in common_months:
        prod_open, prod_close = pf_prod[ym]
        gs_open, gs_close = pf_gs[ym]

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


def check_signal_parity(prod_signals, gs_signals, pf_id, pf_name):
    """シグナルのパリティ検証 (pre-fetched data)"""
    pf_prod = prod_signals.get(pf_id, {})
    pf_gs = gs_signals.get(pf_id, {})

    if not pf_gs:
        return "SKIP", 0, 0, "experiments.dbにシグナルデータなし"

    common_months = sorted(set(pf_prod.keys()) & set(pf_gs.keys()))
    if not common_months:
        return "SKIP", 0, 0, "共通月なし"

    mismatches = []
    for ym in common_months:
        if pf_prod.get(ym) != pf_gs[ym]:
            mismatches.append(f"    {ym}: prod={pf_prod.get(ym)}, gs={pf_gs[ym]}")

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

        # Batch fetch: N PFのデータを各3クエリ(prod returns/signals + sqlite)で一括取得
        # 旧: N PFごとに4クエリ = 4N+1クエリ → 新: 4クエリ固定 (--allで20PF時: 81→4クエリ)
        pf_ids = [pf[0] for pf in portfolios]
        all_prod_returns = fetch_batch_prod_returns(pg_conn, pf_ids)
        all_sqlite_returns, all_sqlite_signals = fetch_batch_sqlite_data(sqlite_conn, pf_ids)
        all_prod_signals = fetch_batch_prod_signals(pg_conn, pf_ids)

        overall_fail = False
        check_count = 0
        skip_count = 0

        for pf_id, pf_name, pf_type in portfolios:
            print(f"\n--- {pf_name} [{pf_type}] ({pf_id[:8]}...) ---")

            # Return parity
            ret_status, ret_match, ret_total, ret_detail = check_return_parity(
                all_prod_returns, all_sqlite_returns, pf_id, pf_name
            )
            if ret_status == "SKIP":
                print(f"  Returns: SKIP — {ret_detail}")
                skip_count += 1
            elif ret_status == "PASS":
                print(f"  Returns: PASS ({ret_match}/{ret_total} months match)")
                check_count += 1
            else:
                print(f"  Returns: FAIL ({ret_match}/{ret_total} months match)")
                print(ret_detail)
                overall_fail = True
                check_count += 1

            # Signal parity (standard PFs only)
            if pf_type != "fof":
                sig_status, sig_match, sig_total, sig_detail = check_signal_parity(
                    all_prod_signals, all_sqlite_signals, pf_id, pf_name
                )
                if sig_status == "SKIP":
                    print(f"  Signals: SKIP — {sig_detail}")
                    skip_count += 1
                elif sig_status == "PASS":
                    print(f"  Signals: PASS ({sig_match}/{sig_total} months match)")
                    check_count += 1
                else:
                    print(f"  Signals: FAIL ({sig_match}/{sig_total} months match)")
                    print(sig_detail)
                    overall_fail = True
                    check_count += 1
            else:
                print("  Signals: N/A (FoF)")

        print()
        print("=" * 60)
        if overall_fail:
            print(f"OVERALL: FAIL (checked={check_count}, skipped={skip_count})")
            sys.exit(1)
        elif check_count == 0:
            print(f"OVERALL: WARN — no checks performed (all {skip_count} skipped)")
            sys.exit(1)
        else:
            print(f"OVERALL: PASS (checked={check_count}, skipped={skip_count})")
            sys.exit(0)

    finally:
        pg_conn.close()
        sqlite_conn.close()


if __name__ == "__main__":
    main()
PYTHON_EOF
}

if [[ "${BASH_SOURCE[0]}" == "$0" && "${PARITY_CHECK_LIB_ONLY:-0}" != "1" ]]; then
    run_parity_check "$@"
fi
