#!/usr/bin/env bash
# post_recalculate_checks.sh — recalculate完了後の自動健全性チェック
# cmd_1103 AC1: ワンショット検証のラルフループ化
#
# 実行: bash scripts/post_recalculate_checks.sh
# 出力: PASS/FAIL/WARN 形式 (stdout)
# 戻り値: 0=全PASS, 1=FAIL有り, 2=WARN有り(FAILなし)

set -euo pipefail

DM_SIGNAL_PATH="/mnt/c/Python_app/DM-signal"
ENV_PATH="${DM_SIGNAL_PATH}/backend/.env"

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
export DM_SIGNAL_PATH

python3 -u - <<'PYTHON_EOF'
import json
import os
import sys
from datetime import date

import psycopg2

DATABASE_URL = os.environ["DATABASE_URL"]
DM_SIGNAL_PATH = os.environ["DM_SIGNAL_PATH"]

CASH_RATIO_THRESHOLD = 0.5  # 50%超のPFがCashならWARN

def connect():
    return psycopg2.connect(DATABASE_URL)

def run_checks():
    conn = connect()
    fail_count = 0
    warn_count = 0
    details = []

    try:
        # ====================================
        # CHECK 1: 全PF健全性チェック
        # ====================================
        print("=" * 60)
        print("CHECK 1: 全PF健全性チェック")
        print("=" * 60)

        with conn.cursor() as cur:
            cur.execute("SELECT id, name, type, config, is_active FROM portfolios ORDER BY name")
            cols = [d[0] for d in cur.description]
            portfolios = [dict(zip(cols, row)) for row in cur.fetchall()]

            cur.execute("SELECT id FROM portfolios")
            all_pf_ids = {row[0] for row in cur.fetchall()}

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
            config = pf["config"] if isinstance(pf["config"], dict) else json.loads(pf["config"])
            issues = []

            # (1a) pipeline_config存在 (standard PFのみ)
            if pf_type != "fof":
                pc = config.get("pipeline_config")
                if pc is None or pc == {}:
                    issues.append("FAIL:pipeline_config missing")

            # (1b) monthly_returns連続性
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT year_month FROM monthly_returns WHERE portfolio_id = %s ORDER BY year_month",
                    (pf_id,),
                )
                year_months = [row[0] for row in cur.fetchall()]

            if not year_months:
                issues.append("FAIL:no monthly_returns")
            else:
                parsed = []
                for ym in year_months:
                    parts = ym.split("-")
                    parsed.append((int(parts[0]), int(parts[1])))
                parsed.sort()
                gaps = []
                for i in range(1, len(parsed)):
                    py, pm = parsed[i - 1]
                    cy, cm = parsed[i]
                    ey, em = (py, pm + 1) if pm < 12 else (py + 1, 1)
                    if (cy, cm) != (ey, em):
                        gaps.append(f"{py}-{pm:02d}>{cy}-{cm:02d}")
                if gaps:
                    issues.append(f"FAIL:return_gaps({len(gaps)})")

            # (1c) signals最新性
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT MAX(date) FROM signals WHERE portfolio_id = %s",
                    (pf_id,),
                )
                row = cur.fetchone()
                latest_sig = row[0] if row else None

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
            pf_id = pf["id"]
            pf_name = pf["name"]
            config = pf["config"] if isinstance(pf["config"], dict) else json.loads(pf["config"])
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
            pf_id = pf["id"]
            pf_name = pf["name"]
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT holding_signal FROM signals WHERE portfolio_id = %s ORDER BY date DESC LIMIT 1",
                    (pf_id,),
                )
                row = cur.fetchone()
            if row and row[0]:
                checked_pfs.append(pf_name)
                if row[0] == "Cash":
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
