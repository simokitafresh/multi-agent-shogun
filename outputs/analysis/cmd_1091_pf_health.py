"""cmd_1091: 本番DB全PF健全性スイープ.

全ポートフォリオに対し5項目チェックを実行し、結果をCSV出力する。
(1) pipeline_config存在 (standard PFのみ)
(2) monthly_returns連続性
(3) signals最新性
(4) FoF component整合
(5) config pydanticバリデーション
"""

import csv
import json
import os
import sys
from datetime import date, datetime

import psycopg2

# --- Pydantic validation ---
# Add DM-signal backend to path for schema import
DM_SIGNAL_PATH = "/mnt/c/Python_app/DM-signal"
sys.path.insert(0, DM_SIGNAL_PATH)
from backend.app.schemas.models import Portfolio as PortfolioSchema

# --- DB connection ---
ENV_PATH = os.path.join(DM_SIGNAL_PATH, "backend/.env")


def load_database_url() -> str:
    """backend/.envからDATABASE_URLを取得."""
    with open(ENV_PATH) as f:
        for line in f:
            line = line.strip()
            if line.startswith("DATABASE_URL="):
                return line.split("=", 1)[1]
    raise RuntimeError("DATABASE_URL not found in backend/.env")


def fetch_all_portfolios(conn) -> list[dict]:
    """全PFを取得."""
    with conn.cursor() as cur:
        cur.execute("SELECT id, name, type, config, is_active FROM portfolios ORDER BY name")
        cols = [d[0] for d in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]


def fetch_monthly_returns(conn, pf_id: str) -> list[str]:
    """PFのmonthly_returnsのyear_monthリストを取得."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT year_month FROM monthly_returns WHERE portfolio_id = %s ORDER BY year_month",
            (pf_id,),
        )
        return [row[0] for row in cur.fetchall()]


def fetch_latest_signal_date(conn, pf_id: str) -> date | None:
    """PFの最新signal日を取得."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT MAX(date) FROM signals WHERE portfolio_id = %s",
            (pf_id,),
        )
        row = cur.fetchone()
        return row[0] if row else None


def fetch_all_portfolio_ids(conn) -> set[str]:
    """全PF IDのセットを取得."""
    with conn.cursor() as cur:
        cur.execute("SELECT id FROM portfolios")
        return {row[0] for row in cur.fetchall()}


def check_pipeline_config(config: dict, pf_type: str) -> str:
    """(1) pipeline_config存在チェック (standard PFのみ)."""
    if pf_type == "fof":
        return "N/A(FoF)"
    pipeline_config = config.get("pipeline_config")
    if pipeline_config is None or pipeline_config == {}:
        return "FAIL:missing"
    return "OK"


def check_monthly_returns_continuity(year_months: list[str]) -> str:
    """(2) monthly_returns連続性チェック."""
    if not year_months:
        return "FAIL:no_data"

    # Parse year-months and check continuity
    parsed = []
    for ym in year_months:
        parts = ym.split("-")
        parsed.append((int(parts[0]), int(parts[1])))

    parsed.sort()
    gaps = []
    for i in range(1, len(parsed)):
        prev_y, prev_m = parsed[i - 1]
        curr_y, curr_m = parsed[i]
        # Expected next month
        exp_m = prev_m + 1
        exp_y = prev_y
        if exp_m > 12:
            exp_m = 1
            exp_y += 1
        if (curr_y, curr_m) != (exp_y, exp_m):
            gaps.append(f"{prev_y}-{prev_m:02d}→{curr_y}-{curr_m:02d}")

    if gaps:
        return f"FAIL:gaps({len(gaps)}):{';'.join(gaps[:3])}"
    return f"OK({len(parsed)}m:{parsed[0][0]}-{parsed[0][1]:02d}~{parsed[-1][0]}-{parsed[-1][1]:02d})"


def check_signals_freshness(latest_signal_date: date | None) -> str:
    """(3) signals最新性チェック."""
    if latest_signal_date is None:
        return "FAIL:no_signals"

    today = date.today()
    # Current year-month
    current_ym = f"{today.year}-{today.month:02d}"
    # Previous month
    prev_month = today.month - 1
    prev_year = today.year
    if prev_month < 1:
        prev_month = 12
        prev_year -= 1
    prev_ym = f"{prev_year}-{prev_month:02d}"

    signal_ym = f"{latest_signal_date.year}-{latest_signal_date.month:02d}"

    if signal_ym >= prev_ym:
        return f"OK({latest_signal_date})"
    else:
        return f"WARN:stale({latest_signal_date})"


def check_fof_components(config: dict, pf_type: str, all_pf_ids: set[str]) -> str:
    """(4) FoF component整合チェック."""
    if pf_type != "fof":
        return "N/A(standard)"

    components = config.get("component_portfolios", [])
    if not components:
        return "FAIL:no_components"

    missing = [c for c in components if c not in all_pf_ids]
    if missing:
        return f"FAIL:missing_refs({len(missing)}):{','.join(missing[:3])}"
    return f"OK({len(components)}components)"


def check_pydantic_validation(config: dict, pf_id: str) -> str:
    """(5) config pydanticバリデーションチェック."""
    try:
        # configにidが含まれていない場合は補完
        config_with_id = {**config, "id": pf_id}
        PortfolioSchema(**config_with_id)
        return "OK"
    except Exception as e:
        err_msg = str(e).replace("\n", " ")[:100]
        return f"FAIL:{err_msg}"


def main():
    db_url = load_database_url()
    conn = psycopg2.connect(db_url)

    try:
        portfolios = fetch_all_portfolios(conn)
        all_pf_ids = fetch_all_portfolio_ids(conn)

        print(f"Total portfolios: {len(portfolios)}")

        results = []
        anomalies = []

        for pf in portfolios:
            pf_id = pf["id"]
            pf_name = pf["name"]
            pf_type = pf["type"]
            config = pf["config"] if isinstance(pf["config"], dict) else json.loads(pf["config"])

            # (1) pipeline_config
            pc_result = check_pipeline_config(config, pf_type)

            # (2) monthly_returns continuity
            year_months = fetch_monthly_returns(conn, pf_id)
            mr_result = check_monthly_returns_continuity(year_months)

            # (3) signals freshness
            latest_sig = fetch_latest_signal_date(conn, pf_id)
            sig_result = check_signals_freshness(latest_sig)

            # (4) FoF components
            fof_result = check_fof_components(config, pf_type, all_pf_ids)

            # (5) pydantic validation
            pydantic_result = check_pydantic_validation(config, pf_id)

            # Overall status
            checks = [pc_result, mr_result, sig_result, fof_result, pydantic_result]
            has_fail = any(c.startswith("FAIL") for c in checks)
            has_warn = any(c.startswith("WARN") for c in checks)
            if has_fail:
                overall = "FAIL"
            elif has_warn:
                overall = "WARN"
            else:
                overall = "OK"

            row = {
                "pf_id": pf_id,
                "pf_name": pf_name,
                "type": pf_type,
                "pipeline_config_exists": pc_result,
                "monthly_returns_months": mr_result,
                "latest_signal": sig_result,
                "fof_components_valid": fof_result,
                "config_pydantic_valid": pydantic_result,
                "overall_status": overall,
            }
            results.append(row)

            if overall != "OK":
                anomalies.append(row)

            status_mark = "✗" if has_fail else ("⚠" if has_warn else "✓")
            print(f"  {status_mark} {pf_name} [{pf_type}] → {overall}")

        # Write CSV
        output_path = "/mnt/c/tools/multi-agent-shogun/outputs/analysis/cmd_1091_pf_health.csv"
        fieldnames = [
            "pf_id", "pf_name", "type",
            "pipeline_config_exists", "monthly_returns_months",
            "latest_signal", "fof_components_valid",
            "config_pydantic_valid", "overall_status",
        ]
        with open(output_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(results)

        print(f"\nCSV written: {output_path}")
        print(f"Total: {len(results)} PFs, Anomalies: {len(anomalies)}")

        if anomalies:
            print("\n=== ANOMALIES ===")
            for a in anomalies:
                print(f"\n[{a['overall_status']}] {a['pf_name']} ({a['type']}, {a['pf_id'][:8]}...)")
                for key in fieldnames[3:-1]:
                    val = a[key]
                    if val.startswith("FAIL") or val.startswith("WARN"):
                        print(f"  → {key}: {val}")
        else:
            print("\n異常なし: 全PFが5項目チェックをパス")

    finally:
        conn.close()


if __name__ == "__main__":
    main()
