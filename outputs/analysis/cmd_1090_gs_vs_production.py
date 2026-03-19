#!/usr/bin/env python3
"""cmd_1090: シン忍法v2(21体)+シン四神v2(10体) GS vs 本番乖離分析"""

import csv
import json
import psycopg2


def get_db_connection():
    conn = psycopg2.connect(
        dbname="dm_signal",
        user="dm_signal_user",
        password="dWrxHnOl78RmGpuK9Y5r8gXIaRo4L9qS",
        host="dpg-d542chchg0os73979vg0-a.singapore-postgres.render.com",
        port=5432,
        connect_timeout=30,
    )
    return conn


# --- シン四神v2 10体 (projects/dm-signal.yaml L700-715) ---
# DB name = 日本語名。PID = GS識別子
SHIN_SHIJIN_V2 = {
    "シン青龍-激攻": {"pid": "DM2_SXLU_T1_M_L2502", "gs_cagr": 0.537, "gs_maxdd": -0.610},
    "シン青龍-常勝": {"pid": "DM2_SXLU_T2_M_L2502", "gs_cagr": 0.528, "gs_maxdd": -0.576},
    "シン青龍-鉄壁": {"pid": "DM2_SXLU_T2_M_L2754", "gs_cagr": 0.446, "gs_maxdd": -0.576},
    "シン朱雀-激攻": {"pid": "DM3_STMV_T2_Be_L0003", "gs_cagr": 0.356, "gs_maxdd": -0.652},
    "シン朱雀-鉄壁": {"pid": "DM3_STMV_T2_Be_L0005", "gs_cagr": 0.353, "gs_maxdd": -0.576},
    "シン白虎-激攻": {"pid": "DM6_SGLD_T1_Qj_L0247", "gs_cagr": 0.466, "gs_maxdd": -0.294},
    "シン白虎-常勝": {"pid": "DM6_SGLD_T2_Qj_L0247", "gs_cagr": 0.447, "gs_maxdd": -0.336},
    "シン白虎-鉄壁": {"pid": "DM6_SGLD_T1_Qj_L0713", "gs_cagr": 0.432, "gs_maxdd": -0.277},
    "シン玄武-激攻": {"pid": "DM7P_RXLU_T1_M_L0001", "gs_cagr": 0.379, "gs_maxdd": -0.456},
    "シン玄武-鉄壁": {"pid": "DM7P_RXLU_T1_M_L0003", "gs_cagr": 0.309, "gs_maxdd": -0.261},
}


def load_ninpo_champions():
    """シン忍法v2チャンピオンCSVから日本語名・GS CAGR/MaxDDを読み込む"""
    csv_path = "/mnt/c/Python_app/DM-signal/outputs/analysis/shin_ninpo_v2_champions.csv"
    ninpo_names = {
        "bunshin": "分身", "yotsume": "四つ目", "oikaze": "追い風",
        "kawarimi": "変わり身", "nukimi": "抜き身",
        "kasoku_ratio": "加速R", "kasoku_diff": "加速D",
    }
    champions = {}
    with open(csv_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            jp_name = f"シン{ninpo_names.get(row['ninpo'], row['ninpo'])}-{row['mode']}"
            subset_str = row["subset"]
            pids = [s.strip().strip("'\"") for s in subset_str.strip("()").split(",")]
            pids = [p.strip() for p in pids if p.strip()]
            champions[jp_name] = {
                "component_pids": pids,
                "gs_cagr": float(row["CAGR"]),
                "gs_maxdd": float(row["MaxDD"]),
                "ninpo_params": row["ninpo_params"],
            }
    return champions


def calc_cagr(returns):
    if not returns:
        return None
    cumulative = 1.0
    for r in returns:
        cumulative *= (1 + r)
    n_years = len(returns) / 12.0
    if n_years <= 0 or cumulative <= 0:
        return None
    return cumulative ** (1.0 / n_years) - 1.0


def calc_maxdd(returns):
    if not returns:
        return None
    cumulative = 1.0
    peak = 1.0
    max_dd = 0.0
    for r in returns:
        cumulative *= (1 + r)
        if cumulative > peak:
            peak = cumulative
        dd = (cumulative - peak) / peak
        if dd < max_dd:
            max_dd = dd
    return max_dd


def analyze_pf(cur, db_name, gs_cagr, gs_maxdd, is_fof=False):
    """PFの本番データを取得し、GS結果と比較"""
    cur.execute("SELECT id, config FROM portfolios WHERE name = %s", (db_name,))
    row = cur.fetchone()
    if not row:
        return {
            "prod_cagr": None, "prod_maxdd": None, "gap_pct": None, "gap_maxdd": None,
            "n_months": 0, "first_month": None, "last_month": None,
            "has_pipeline_config": None, "weight_count": None,
            "causes": ["PF not found in DB"],
        }

    portfolio_id, config_json = row[0], row[1]

    # pipeline_config確認
    has_pc = False
    if config_json:
        cfg = config_json if isinstance(config_json, dict) else json.loads(config_json)
        has_pc = cfg.get("pipeline_config") is not None

    # monthly_returns取得 (カラム: year_month, monthly_return)
    cur.execute("""
        SELECT year_month, monthly_return
        FROM monthly_returns
        WHERE portfolio_id = %s AND monthly_return IS NOT NULL
        ORDER BY year_month ASC
    """, (portfolio_id,))
    monthly_data = cur.fetchall()

    if not monthly_data:
        causes = ["No monthly_returns"]
        if not is_fof and not has_pc:
            causes.append("pipeline_config MISSING(PI-003)")
        return {
            "prod_cagr": None, "prod_maxdd": None, "gap_pct": None, "gap_maxdd": None,
            "n_months": 0, "first_month": None, "last_month": None,
            "has_pipeline_config": has_pc, "weight_count": None, "causes": causes,
        }

    returns = [r[1] for r in monthly_data]
    first_month = monthly_data[0][0]
    last_month = monthly_data[-1][0]
    n_months = len(returns)

    prod_cagr = calc_cagr(returns)
    prod_maxdd = calc_maxdd(returns)

    gap_pct = ((prod_cagr - gs_cagr) / abs(gs_cagr) * 100) if prod_cagr is not None and gs_cagr else None
    gap_maxdd = ((prod_maxdd - gs_maxdd) / abs(gs_maxdd) * 100) if prod_maxdd is not None and gs_maxdd else None

    # FoF weights確認
    weight_count = None
    if is_fof:
        cur.execute("""
            SELECT COUNT(*) FROM fof_component_weights
            WHERE portfolio_id = %s
        """, (portfolio_id,))
        weight_count = cur.fetchone()[0]

    # 原因判定
    causes = []
    if not is_fof and not has_pc:
        causes.append("pipeline_config MISSING(PI-003)")
    if gap_pct is not None:
        if abs(gap_pct) < 5:
            causes.append("within_tolerance(<5%)")
        elif abs(gap_pct) < 20:
            causes.append("resolution_diff(PI-001)")
        else:
            causes.append("large_divergence")
    if is_fof and weight_count == 0:
        causes.append("NO_FoF_WEIGHTS")
    if n_months < 60:
        causes.append(f"short_period({n_months}M)")

    return {
        "prod_cagr": prod_cagr, "prod_maxdd": prod_maxdd,
        "gap_pct": gap_pct, "gap_maxdd": gap_maxdd,
        "n_months": n_months, "first_month": first_month, "last_month": last_month,
        "has_pipeline_config": has_pc, "weight_count": weight_count, "causes": causes,
    }


def main():
    conn = get_db_connection()
    cur = conn.cursor()
    results = []

    # === Step 1: シン四神v2 (10体, standard) ===
    print("=== シン四神v2 (10体) ===")
    for name, info in SHIN_SHIJIN_V2.items():
        a = analyze_pf(cur, name, info["gs_cagr"], info["gs_maxdd"], is_fof=False)
        if a["prod_cagr"] is not None:
            print(f"  {name}: prod_cagr={a['prod_cagr']:.4f} gs_cagr={info['gs_cagr']:.3f} gap={a['gap_pct']:+.1f}% | "
                  f"prod_maxdd={a['prod_maxdd']:.4f} gs_maxdd={info['gs_maxdd']:.3f} gap={a['gap_maxdd']:+.1f}% | "
                  f"period={a['first_month']}~{a['last_month']} ({a['n_months']}M) | "
                  f"pipeline_config={'YES' if a['has_pipeline_config'] else 'MISSING'}")
        else:
            print(f"  {name}: {'; '.join(a['causes'])}")
        results.append({
            "pf_name": name,
            "gs_cagr": round(info["gs_cagr"], 4),
            "prod_cagr": round(a["prod_cagr"], 4) if a["prod_cagr"] is not None else "",
            "gap_pct": round(a["gap_pct"], 1) if a["gap_pct"] is not None else "",
            "gs_maxdd": round(info["gs_maxdd"], 4),
            "prod_maxdd": round(a["prod_maxdd"], 4) if a["prod_maxdd"] is not None else "",
            "gap_maxdd": round(a["gap_maxdd"], 1) if a["gap_maxdd"] is not None else "",
            "suspected_cause": "; ".join(a["causes"]),
        })

    # === Step 2: シン忍法v2 (21体, FoF) ===
    print("\n=== シン忍法v2 (21体) ===")
    ninpo_champions = load_ninpo_champions()
    for name, info in ninpo_champions.items():
        a = analyze_pf(cur, name, info["gs_cagr"], info["gs_maxdd"], is_fof=True)
        if a["prod_cagr"] is not None:
            print(f"  {name}: prod_cagr={a['prod_cagr']:.4f} gs_cagr={info['gs_cagr']:.4f} gap={a['gap_pct']:+.1f}% | "
                  f"prod_maxdd={a['prod_maxdd']:.4f} gs_maxdd={info['gs_maxdd']:.4f} gap={a['gap_maxdd']:+.1f}% | "
                  f"period={a['first_month']}~{a['last_month']} ({a['n_months']}M) | weights={a['weight_count']}")
        else:
            print(f"  {name}: {'; '.join(a['causes'])}")
        results.append({
            "pf_name": name,
            "gs_cagr": round(info["gs_cagr"], 4),
            "prod_cagr": round(a["prod_cagr"], 4) if a["prod_cagr"] is not None else "",
            "gap_pct": round(a["gap_pct"], 1) if a["gap_pct"] is not None else "",
            "gs_maxdd": round(info["gs_maxdd"], 4),
            "prod_maxdd": round(a["prod_maxdd"], 4) if a["prod_maxdd"] is not None else "",
            "gap_maxdd": round(a["gap_maxdd"], 1) if a["gap_maxdd"] is not None else "",
            "suspected_cause": "; ".join(a["causes"]),
        })

    # === Step 3: 仮説検証 ===
    print("\n=== 仮説検証 ===")

    # (1) pipeline_config
    print("\n--- 仮説(1): pipeline_config ---")
    for name in SHIN_SHIJIN_V2:
        cur.execute("SELECT config FROM portfolios WHERE name = %s", (name,))
        row = cur.fetchone()
        if row and row[0]:
            cfg = row[0] if isinstance(row[0], dict) else json.loads(row[0])
            pc = cfg.get("pipeline_config")
            print(f"  {name}: pipeline_config={'PRESENT' if pc else 'MISSING'}")
            if pc:
                blocks = pc.get("blocks", [])
                print(f"    blocks: {len(blocks)}")
                for b in blocks[:3]:
                    print(f"      type={b.get('type')}, params={list(b.get('params', {}).keys())[:5]}")
        else:
            print(f"  {name}: config NOT FOUND")

    # (2) 期間一致
    print("\n--- 仮説(2): 期間一致 ---")
    for name in SHIN_SHIJIN_V2:
        cur.execute("""
            SELECT MIN(year_month), MAX(year_month), COUNT(*)
            FROM monthly_returns mr
            JOIN portfolios p ON p.id = mr.portfolio_id
            WHERE p.name = %s AND mr.monthly_return IS NOT NULL
        """, (name,))
        row = cur.fetchone()
        if row and row[0]:
            print(f"  {name}: {row[0]}~{row[1]} ({row[2]}M)")
        else:
            print(f"  {name}: no data")

    # (3) FoF weights
    print("\n--- 仮説(3): FoF weights ---")
    for name in ninpo_champions:
        cur.execute("""
            SELECT fw.date, COUNT(*)
            FROM fof_component_weights fw
            JOIN portfolios p ON p.id = fw.portfolio_id
            WHERE p.name = %s
            GROUP BY fw.date
            ORDER BY fw.date DESC
            LIMIT 3
        """, (name,))
        rows = cur.fetchall()
        if rows:
            print(f"  {name}: latest date={rows[0][0]}, {rows[0][1]} components, {len(rows)} sample dates")
        else:
            print(f"  {name}: NO WEIGHTS")

    # (4) パラメータ一致 — standard PFのconfig内pidとGS pidの対応確認
    print("\n--- 仮説(4): パラメータ一致 ---")
    for name, info in SHIN_SHIJIN_V2.items():
        cur.execute("SELECT config FROM portfolios WHERE name = %s", (name,))
        row = cur.fetchone()
        if row and row[0]:
            cfg = row[0] if isinstance(row[0], dict) else json.loads(row[0])
            pc = cfg.get("pipeline_config", {})
            if pc:
                blocks = pc.get("blocks", [])
                for b in blocks:
                    params = b.get("params", {})
                    if "lookback_periods" in params:
                        print(f"  {name}: lookback={params.get('lookback_periods')}, top_n={params.get('top_n')}")
                        break
                else:
                    print(f"  {name}: no lookback block found")
            else:
                print(f"  {name}: no pipeline_config")

    # (5) 解像度差異(PI-001)定量評価
    print("\n--- 仮説(5): 解像度差異 PI-001 ---")
    shijin_with_gap = [r for r in results[:10] if r["gap_pct"] != ""]
    ninpo_with_gap = [r for r in results[10:] if r["gap_pct"] != ""]
    if shijin_with_gap:
        avg = sum(abs(r["gap_pct"]) for r in shijin_with_gap) / len(shijin_with_gap)
        print(f"  シン四神 平均|CAGR gap|: {avg:.1f}% ({len(shijin_with_gap)}体)")
    if ninpo_with_gap:
        avg = sum(abs(r["gap_pct"]) for r in ninpo_with_gap) / len(ninpo_with_gap)
        print(f"  シン忍法 平均|CAGR gap|: {avg:.1f}% ({len(ninpo_with_gap)}体)")
    print("  PI-001: 本番=日次解像度、GS=月次。10D/15D/20D/1Mの区別がGSでは消える構造的乖離")

    # --- CSV出力 ---
    output_path = "/mnt/c/tools/multi-agent-shogun/outputs/analysis/cmd_1090_gs_vs_production.csv"
    fieldnames = ["pf_name", "gs_cagr", "prod_cagr", "gap_pct", "gs_maxdd", "prod_maxdd", "gap_maxdd", "suspected_cause"]
    with open(output_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)
    print(f"\n=== CSV出力完了: {output_path} ({len(results)}行) ===")

    # サマリー
    print("\n=== サマリー ===")
    found = [r for r in results if r["prod_cagr"] != ""]
    not_found = [r for r in results if r["prod_cagr"] == ""]
    print(f"  取得成功: {len(found)}/{len(results)}")
    if not_found:
        print(f"  DB未登録/データなし: {len(not_found)}")
        for r in not_found:
            print(f"    - {r['pf_name']}: {r['suspected_cause']}")

    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
