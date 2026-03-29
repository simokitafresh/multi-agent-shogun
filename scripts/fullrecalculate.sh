#!/usr/bin/env bash
# fullrecalculate.sh — fullrecalculate wrapper with baseline auto-save and diff comparison
# cmd_1540: 実行前にbaseline(現在値)を自動保存し、実行後に差分比較を出力
#
# Usage:
#   bash scripts/fullrecalculate.sh baseline         # baseline保存のみ（デフォルト）
#   bash scripts/fullrecalculate.sh full              # baseline保存→recalculate実行→差分比較
#   bash scripts/fullrecalculate.sh diff <file.json>  # 指定baselineと現在DBを差分比較
#
# 保存先: outputs/baselines/baseline_YYYYMMDD_HHMMSS.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHOGUN_DIR="$(dirname "$SCRIPT_DIR")"
DM_SIGNAL_PATH="/mnt/c/Python_app/DM-signal"
ENV_PATH="${DM_SIGNAL_PATH}/backend/.env"
BASELINE_DIR="${SHOGUN_DIR}/outputs/baselines"

MODE="${1:-baseline}"
DIFF_BASELINE="${2:-}"

mkdir -p "$BASELINE_DIR"

# Load DATABASE_URL
if [[ ! -f "$ENV_PATH" ]]; then
    echo "FAIL: backend/.env not found at ${ENV_PATH}"
    exit 1
fi

DATABASE_URL=$(grep '^DATABASE_URL=' "$ENV_PATH" | cut -d= -f2-)
if [[ -z "$DATABASE_URL" ]]; then
    echo "FAIL: DATABASE_URL not found in backend/.env"
    exit 1
fi

export DATABASE_URL
export BASELINE_DIR
export DM_SIGNAL_PATH

# ============================================================
# save_baseline: DB現在値をJSONに保存
# ============================================================
save_baseline() {
    local out_file="$1"
    echo "=== Phase 1: Saving baseline ==="
    python3 -u - "$out_file" <<'PYEOF'
import json, os, sys
from datetime import date, datetime
import psycopg2

baseline_file = sys.argv[1]
DATABASE_URL = os.environ["DATABASE_URL"]

def json_serial(obj):
    if isinstance(obj, (date, datetime)):
        return obj.isoformat()
    raise TypeError(f"Type {type(obj)} not serializable")

conn = psycopg2.connect(DATABASE_URL)
try:
    baseline = {"timestamp": datetime.now().isoformat(), "portfolios": {}}

    with conn.cursor() as cur:
        cur.execute("SELECT id, name, type, is_active FROM portfolios ORDER BY name")
        portfolios = cur.fetchall()

        for pf_id, pf_name, pf_type, is_active in portfolios:
            pf_data = {
                "name": pf_name,
                "type": pf_type,
                "is_active": is_active,
            }

            # Signal count + latest date
            cur.execute(
                "SELECT COUNT(*), MAX(date) FROM signals WHERE portfolio_id = %s",
                (pf_id,),
            )
            sig_count, sig_latest = cur.fetchone()
            pf_data["signal_count"] = sig_count
            pf_data["latest_signal_date"] = sig_latest.isoformat() if sig_latest else None

            # Latest holding_signal
            cur.execute(
                "SELECT holding_signal FROM signals WHERE portfolio_id = %s ORDER BY date DESC LIMIT 1",
                (pf_id,),
            )
            row = cur.fetchone()
            pf_data["latest_holding_signal"] = row[0] if row else None

            # Monthly returns count + latest year_month
            cur.execute(
                "SELECT COUNT(*), MAX(year_month) FROM monthly_returns WHERE portfolio_id = %s",
                (pf_id,),
            )
            mr_count, mr_latest = cur.fetchone()
            pf_data["monthly_return_count"] = mr_count
            pf_data["latest_year_month"] = mr_latest

            # Latest cumulative_return and monthly_return
            if mr_latest:
                cur.execute(
                    "SELECT cumulative_return, monthly_return FROM monthly_returns "
                    "WHERE portfolio_id = %s AND year_month = %s",
                    (pf_id, mr_latest),
                )
                row = cur.fetchone()
                if row:
                    pf_data["latest_cumulative_return"] = float(row[0]) if row[0] is not None else None
                    pf_data["latest_monthly_return"] = float(row[1]) if row[1] is not None else None
                else:
                    pf_data["latest_cumulative_return"] = None
                    pf_data["latest_monthly_return"] = None
            else:
                pf_data["latest_cumulative_return"] = None
                pf_data["latest_monthly_return"] = None

            # Portfolio metrics total_return
            cur.execute(
                "SELECT total_return FROM portfolio_metrics WHERE portfolio_id = %s",
                (pf_id,),
            )
            row = cur.fetchone()
            pf_data["metrics_total_return"] = float(row[0]) if row and row[0] is not None else None

            # Trade performance count
            cur.execute(
                "SELECT COUNT(*) FROM trade_performance WHERE portfolio_id = %s",
                (pf_id,),
            )
            pf_data["trade_performance_count"] = cur.fetchone()[0]

            baseline["portfolios"][pf_id] = pf_data

    # Global summary
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM signals")
        baseline["total_signals"] = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM monthly_returns")
        baseline["total_monthly_returns"] = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM portfolio_metrics")
        baseline["total_metrics"] = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM trade_performance")
        baseline["total_trade_performance"] = cur.fetchone()[0]

    with open(baseline_file, "w") as f:
        json.dump(baseline, f, indent=2, default=json_serial)

    pf_count = len(baseline["portfolios"])
    print(f"  Portfolios: {pf_count}")
    print(f"  Total signals: {baseline['total_signals']}")
    print(f"  Total monthly_returns: {baseline['total_monthly_returns']}")
    print(f"  Total metrics: {baseline['total_metrics']}")
    print(f"  Total trade_performance: {baseline['total_trade_performance']}")
    print(f"  Saved to: {baseline_file}")

finally:
    conn.close()
PYEOF
}

# ============================================================
# run_recalculate: fullrecalculate実行
# ============================================================
run_recalculate() {
    echo ""
    echo "=== Phase 2: Running fullrecalculate ==="
    cd "$DM_SIGNAL_PATH"
    python3 -c "
import logging, sys
logging.basicConfig(level=logging.INFO, stream=sys.stdout)
from backend.app.jobs.recalculator import run_recalculate_job
stats = run_recalculate_job()
print(f'Recalculate completed: {stats}')
"
    cd "$SHOGUN_DIR"
}

# ============================================================
# diff_baseline: baselineと現在DBを比較
# ============================================================
diff_baseline() {
    local baseline_file="$1"
    echo ""
    echo "=== Phase 3: Comparing baseline vs current DB ==="
    python3 -u - "$baseline_file" <<'PYEOF'
import json, os, sys
from datetime import date, datetime
import psycopg2

baseline_file = sys.argv[1]
DATABASE_URL = os.environ["DATABASE_URL"]

with open(baseline_file) as f:
    baseline = json.load(f)

conn = psycopg2.connect(DATABASE_URL)
try:
    changes = []
    numeric_deltas = []

    with conn.cursor() as cur:
        # Global counts
        for table, key in [
            ("signals", "total_signals"),
            ("monthly_returns", "total_monthly_returns"),
            ("portfolio_metrics", "total_metrics"),
            ("trade_performance", "total_trade_performance"),
        ]:
            cur.execute(f"SELECT COUNT(*) FROM {table}")
            current = cur.fetchone()[0]
            prev = baseline.get(key, 0)
            diff = current - prev
            if diff != 0:
                pct = (diff / prev * 100) if prev else float("inf")
                changes.append(f"  {key}: {prev} -> {current} ({diff:+d}, {pct:+.2f}%)")
                numeric_deltas.append(abs(diff))
            else:
                changes.append(f"  {key}: {current} (no change)")

        # Per-portfolio comparison
        pf_changes = 0
        pf_signal_changes = []
        cumret_deltas = []

        for pf_id, prev_data in baseline.get("portfolios", {}).items():
            pf_name = prev_data["name"]
            pf_diffs = []

            # Signal count
            cur.execute(
                "SELECT COUNT(*), MAX(date) FROM signals WHERE portfolio_id = %s",
                (pf_id,),
            )
            sig_count, sig_latest = cur.fetchone()
            prev_sig = prev_data.get("signal_count", 0)
            if sig_count != prev_sig:
                pf_diffs.append(f"signal_count: {prev_sig}->{sig_count} ({sig_count - prev_sig:+d})")

            # Holding signal
            cur.execute(
                "SELECT holding_signal FROM signals WHERE portfolio_id = %s ORDER BY date DESC LIMIT 1",
                (pf_id,),
            )
            row = cur.fetchone()
            cur_holding = row[0] if row else None
            prev_holding = prev_data.get("latest_holding_signal")
            if cur_holding != prev_holding:
                pf_diffs.append(f"holding_signal: {prev_holding}->{cur_holding}")
                pf_signal_changes.append(f"  {pf_name}: {prev_holding} -> {cur_holding}")

            # Monthly return count
            cur.execute(
                "SELECT COUNT(*), MAX(year_month) FROM monthly_returns WHERE portfolio_id = %s",
                (pf_id,),
            )
            mr_count, mr_latest = cur.fetchone()
            prev_mr = prev_data.get("monthly_return_count", 0)
            if mr_count != prev_mr:
                pf_diffs.append(f"monthly_return_count: {prev_mr}->{mr_count} ({mr_count - prev_mr:+d})")

            # Cumulative return
            if mr_latest:
                cur.execute(
                    "SELECT cumulative_return FROM monthly_returns WHERE portfolio_id = %s AND year_month = %s",
                    (pf_id, mr_latest),
                )
                row = cur.fetchone()
                cur_cumret = float(row[0]) if row and row[0] is not None else None
            else:
                cur_cumret = None
            prev_cumret = prev_data.get("latest_cumulative_return")
            if cur_cumret is not None and prev_cumret is not None:
                delta = cur_cumret - prev_cumret
                if abs(delta) > 1e-10:
                    pf_diffs.append(f"cumulative_return: {prev_cumret:.6f}->{cur_cumret:.6f} ({delta:+.6f})")
                    cumret_deltas.append((pf_name, abs(delta)))
            elif cur_cumret != prev_cumret:
                pf_diffs.append(f"cumulative_return: {prev_cumret}->{cur_cumret}")

            # Metrics total_return
            cur.execute(
                "SELECT total_return FROM portfolio_metrics WHERE portfolio_id = %s",
                (pf_id,),
            )
            row = cur.fetchone()
            cur_total_ret = float(row[0]) if row and row[0] is not None else None
            prev_total_ret = prev_data.get("metrics_total_return")
            if cur_total_ret is not None and prev_total_ret is not None:
                delta = cur_total_ret - prev_total_ret
                if abs(delta) > 1e-10:
                    pf_diffs.append(f"total_return: {prev_total_ret:.6f}->{cur_total_ret:.6f} ({delta:+.6f})")
            elif cur_total_ret != prev_total_ret:
                pf_diffs.append(f"total_return: {prev_total_ret}->{cur_total_ret}")

            # Trade performance count
            cur.execute(
                "SELECT COUNT(*) FROM trade_performance WHERE portfolio_id = %s",
                (pf_id,),
            )
            cur_tp = cur.fetchone()[0]
            prev_tp = prev_data.get("trade_performance_count", 0)
            if cur_tp != prev_tp:
                pf_diffs.append(f"trade_performance: {prev_tp}->{cur_tp} ({cur_tp - prev_tp:+d})")

            if pf_diffs:
                pf_changes += 1

    # Output summary
    print("=" * 60)
    print("DIFF SUMMARY")
    print("=" * 60)
    print(f"Baseline: {baseline.get('timestamp', 'unknown')}")
    print(f"Current:  {datetime.now().isoformat()}")
    print()

    print("--- Global Counts ---")
    for line in changes:
        print(line)
    print()

    total_pf = len(baseline.get("portfolios", {}))
    print(f"--- Portfolio Changes: {pf_changes}/{total_pf} portfolios changed ---")

    if pf_signal_changes:
        print()
        print("--- Holding Signal Changes ---")
        for line in pf_signal_changes:
            print(line)

    if cumret_deltas:
        cumret_deltas.sort(key=lambda x: x[1], reverse=True)
        max_name, max_delta = cumret_deltas[0]
        print()
        print(f"--- Cumulative Return: max change = {max_delta:.6f} ({max_name}) ---")
        print(f"  Changed portfolios: {len(cumret_deltas)}")
        if len(cumret_deltas) > 5:
            print("  Top 5:")
            for name, delta in cumret_deltas[:5]:
                print(f"    {name}: {delta:.6f}")

    change_rate = (pf_changes / total_pf * 100) if total_pf else 0
    max_numeric = max(numeric_deltas) if numeric_deltas else 0

    print()
    print("=" * 60)
    if pf_changes == 0 and max_numeric == 0:
        print("RESULT: NO CHANGES (baseline and current DB are identical)")
    else:
        print(f"RESULT: {pf_changes} portfolios changed ({change_rate:.1f}%), max global count delta = {max_numeric}")
    print("=" * 60)

finally:
    conn.close()
PYEOF
}

# ============================================================
# Main
# ============================================================
case "$MODE" in
    baseline)
        TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
        BASELINE_FILE="${BASELINE_DIR}/baseline_${TIMESTAMP}.json"
        save_baseline "$BASELINE_FILE"
        echo ""
        echo "Done. To compare later: bash scripts/fullrecalculate.sh diff ${BASELINE_FILE}"
        ;;
    full)
        TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
        BASELINE_FILE="${BASELINE_DIR}/baseline_${TIMESTAMP}.json"
        save_baseline "$BASELINE_FILE"
        run_recalculate
        diff_baseline "$BASELINE_FILE"
        # Post-recalculate checks
        echo ""
        echo "=== Phase 4: Post-recalculate health checks ==="
        bash "${SCRIPT_DIR}/post_recalculate_checks.sh"
        ;;
    diff)
        if [[ -z "$DIFF_BASELINE" ]]; then
            echo "Usage: bash scripts/fullrecalculate.sh diff <baseline_file.json>"
            exit 1
        fi
        if [[ ! -f "$DIFF_BASELINE" ]]; then
            echo "FAIL: Baseline file not found: ${DIFF_BASELINE}"
            exit 1
        fi
        diff_baseline "$DIFF_BASELINE"
        ;;
    *)
        echo "Usage: bash scripts/fullrecalculate.sh [baseline|full|diff <file>]"
        echo "  baseline  Save current DB state to outputs/baselines/ (default)"
        echo "  full      Save baseline -> run recalculate -> diff -> health check"
        echo "  diff      Compare given baseline file with current DB"
        exit 1
        ;;
esac
