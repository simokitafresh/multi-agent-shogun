#!/usr/bin/env python3
"""イベント lane の検知(殿 2026-09-04 19:33)。毎朝 07:05 cron。yfinance で SPY/^VIX/^N225 を取り、event_rules.yaml の reactive_triggers を数値規則だけで判定する。
発火→queue/x_events/<date>_<id>.yaml(提案)+ntfy。生成は x_claim_gen.py --event <file>(gate 通過後 .approved を殿が置くまで投稿されない)。
イベントが無ければ何もしない(空 slot を埋める目的で発火しない)。
Usage: python3 scripts/x_ops/x_event_scan.py [--dry-run] [--date YYYY-MM-DD]
"""
import sys, datetime as dt, subprocess, json
from pathlib import Path
import yaml
ROOT = Path(__file__).resolve().parents[2]
RULES = yaml.safe_load((ROOT / "skills/x-post-pipeline/event_rules.yaml").read_text(encoding="utf-8"))
EV = ROOT / "queue/x_events"; EV.mkdir(exist_ok=True)


def recent_claims(days=7):
    used = set(); today = dt.date.today()
    for f in EV.glob("*.yaml"):
        d = yaml.safe_load(f.read_text(encoding="utf-8"))
        if (today - dt.date.fromisoformat(d["date"])).days <= days: used.add(d.get("claim"))
    L = yaml.safe_load((ROOT / "queue/x_live_oos/ledger.yaml").read_text(encoding="utf-8"))["entries"]
    for e in L:
        if e.get("posted_at") and (today - dt.date.fromisoformat(str(e["posted_at"])[:10])).days <= days: used.add((e.get("growth") or {}).get("claim_key"))
    return used


def propose(date, rule, obs, ctx_extra=""):
    """提案ファイル+ntfy(reactive/intraday/topic 共通。1 日 1 unit、同 claim 7 日再発火なし)"""
    if any(f.name.startswith(date) for f in EV.glob("*.yaml")): print("already proposed today (1 event unit/day)"); return None
    used = recent_claims(); claim = next((c for c in rule["claims"] if c not in used), None)
    if not claim: print("no unused claim for", rule["id"]); return None
    prop = dict(date=date, event_id=rule["id"], rule=rule["rule"] if "rule" in rule else rule.get("query", ""), observation=obs, claim=claim, format=rule["format"], funnel_stage=rule["funnel_stage"], audience=rule["audience"], hook_type=rule["hook_type"],
                content_category=rule["content_category"], desired_action=["dwell", "reply", "quote", "profile"], context=f"{obs.get('asof', date)} {rule.get('rule', rule['id'])} 実測 {obs}{ctx_extra} / {context_line()}", status="proposed", draft_id=f"EV-{date.replace('-', '')[4:]}-{rule['id']}")
    f = EV / f"{date}_{rule['id']}.yaml"; f.write_text(yaml.safe_dump(prop, allow_unicode=True, sort_keys=False), encoding="utf-8")
    subprocess.run(["bash", str(ROOT / "scripts/ntfy.sh"), f"【X イベント lane】{rule['id']} 発火。claim {claim} で Short を提案 → {f.name}。生成: python3 scripts/x_ops/x_claim_gen.py --event {f}"], cwd=ROOT)
    print("proposed", f); return f


def context_line():
    """直近の市場環境 1 行(event 提案の context に添える)。予測語は使わない"""
    try:
        rows = [json.loads(l) for l in (ROOT / "queue/x_market_context/daily.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
        a, b = rows[-1], (rows[-21] if len(rows) >= 21 else rows[0])
        fx = f"USD/JPY {a.get('usdjpy')}({(a.get('usdjpy', 0) / b.get('usdjpy', 1) - 1) * 100:+.1f}% / 4w)" if isinstance(a.get("usdjpy"), (int, float)) and isinstance(b.get("usdjpy"), (int, float)) else ""
        return f"市場環境 {a['date']}: {fx} 米2y {a.get('us2y')} 米10y {a.get('us10y')} 10-2y {a.get('curve_10_2')} JGB10 {a.get('jgb10')} BEI {a.get('bei10')} VIX {a.get('vix')} SPY 52w DD {a.get('spy_dd_52w')}"
    except Exception: return ""


def weekly_context():
    """日曜 09:00: 4 週表を docs/research/x_market_context_weekly/ へ、ntfy で 1 行。編集計画見直しの材料(自動補充はしない)"""
    rows = [json.loads(l) for l in (ROOT / "queue/x_market_context/daily.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()][-28:]
    out = ROOT / "docs/research/x_market_context_weekly"; out.mkdir(parents=True, exist_ok=True)
    cols = ["date", "usdjpy", "us2y", "us10y", "curve_10_2", "jgb10", "bei10", "spy_ret", "spy_dd_52w", "vix", "n225_ret"]
    md = "# Market Context 4 週(殿 2026-09-05 01:35: 観測対象。予測しない。本人思想=分解/観測と予測の分離/見ると売買の分離/検証)\n\n| " + " | ".join(cols) + " |\n|" + "---|" * len(cols) + "\n"
    for r in rows: md += "| " + " | ".join(str(r.get(c, "")) for c in cols) + " |\n"
    md += "\n適用候補 claim: C35 円建てリターン分解 / C36 FOMC 連鎖は観測 / C37 見ると売買は別 / C38 金利差は材料の 1 つ。plan へ入れる時は candidate→gate→editorial review(自動補充しない)。\n"
    f = out / f"market_context_{dt.date.today():%Y%m%d}.md"; f.write_text(md, encoding="utf-8")
    subprocess.run(["bash", str(ROOT / "scripts/ntfy.sh"), f"【Market Context 週次】{context_line()} → {f.name}"], cwd=ROOT); print("written", f)


def intraday(dry):
    """殿 19:48『為替はリアルタイムじゃないと変』。yfinance 5 分足(ほぼ実時間)。cron 30 分ごと"""
    import yfinance as yf, pandas as pd
    date = dt.date.today().isoformat(); fired = []; obs = {}
    rules = {r["id"]: r for r in RULES["intraday_triggers"]}
    try:
        fx = yf.download("JPY=X", period="2d", interval="5m", progress=False)["Close"].dropna(); fx = fx.iloc[:, 0] if hasattr(fx, "columns") else fx
        fx = fx.tz_convert("Asia/Tokyo"); today_fx = fx[fx.index.date == dt.date.today()]
        last = float(fx.iloc[-1]); two_h = fx[fx.index >= fx.index[-1] - pd.Timedelta(hours=2)]; r2h = last / float(two_h.iloc[0]) - 1
        r_open = (last / float(today_fx.iloc[0]) - 1) if len(today_fx) else 0.0
        obs.update(asof=str(fx.index[-1])[:16], usdjpy=round(last, 3), usdjpy_2h=round(r2h, 4), usdjpy_open=round(r_open, 4))
        if abs(r2h) >= 0.010 or abs(r_open) >= 0.015: fired.append("usdjpy_intraday")
    except Exception as ex: obs["usdjpy"] = f"ERR {type(ex).__name__}"
    try:
        spy = yf.download("SPY", period="2d", interval="5m", progress=False)["Close"].dropna(); spy = spy.iloc[:, 0] if hasattr(spy, "columns") else spy
        spy = spy.tz_convert("America/New_York"); sess = spy[spy.index.date == spy.index[-1].date()]
        if len(sess) >= 2 and (dt.datetime.now(dt.timezone.utc) - spy.index[-1].tz_convert("UTC").to_pydatetime()).total_seconds() < 3600:
            ro = float(sess.iloc[-1]) / float(sess.iloc[0]) - 1; obs.update(spy_session_open_ret=round(ro, 4), spy_asof=str(spy.index[-1])[:16])
            if abs(ro) >= 0.02: fired.append("spy_intraday")
        else: obs["spy_session"] = "closed"
    except Exception as ex: obs["spy"] = f"ERR {type(ex).__name__}"
    print(json.dumps(dict(mode="intraday", date=date, obs=obs, fired=fired), ensure_ascii=False))
    if fired and not dry: propose(date, rules[fired[0]], obs)
    return 0


def main():
    a = sys.argv[1:]; dry = "--dry-run" in a
    if "--intraday" in a: return intraday(dry)
    if "--context-weekly" in a: return weekly_context()
    date = a[a.index("--date") + 1] if "--date" in a else dt.date.today().isoformat()
    import yfinance as yf
    px = yf.download(["SPY", "^VIX", "^N225", "JPY=X"], period="1y", progress=False, auto_adjust=True)["Close"].dropna(how="all")
    spy = px["SPY"].dropna(); n225 = px["^N225"].dropna(); vixs = px["^VIX"].dropna()  # 市場ごとに最終有効日が違う(日本が先に閉まる)
    asof = spy.index[-1].date().isoformat()
    spy_r = float(spy.iloc[-1] / spy.iloc[-2] - 1); n_r = float(n225.iloc[-1] / n225.iloc[-2] - 1)
    spy_dd = float(spy.iloc[-1] / spy.max() - 1); spy_dd_prev = float(spy.iloc[-2] / spy.iloc[:-1].max() - 1)
    vix, vix_prev = float(vixs.iloc[-1]), float(vixs.iloc[-2])
    obs = dict(asof=asof, spy_ret=round(spy_r, 4), n225_ret=round(n_r, 4), spy_dd_52w=round(spy_dd, 4), vix=round(vix, 2))
    fired = []
    # --- 殿 19:45 追加: 為替・金利・カーブ・インフレ。取得失敗はその trigger をスキップ(落とさない) ---
    import urllib.request, io, csv
    def fred(sid):
        rows = [r for r in csv.reader(io.StringIO(urllib.request.urlopen(f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={sid}", timeout=20).read().decode())) if len(r) == 2 and r[1] not in (".", "")]
        return [(r[0], float(r[1])) for r in rows[-3:]]
    try:
        fx = px["JPY=X"].dropna(); fx_r = float(fx.iloc[-1] / fx.iloc[-2] - 1); obs["usdjpy"] = round(float(fx.iloc[-1]), 2); obs["usdjpy_ret"] = round(fx_r, 4)
        if abs(fx_r) >= 0.02: fired.append("usdjpy_2")
    except Exception as ex: obs["usdjpy"] = f"ERR {type(ex).__name__}"
    try:
        d2, d10, bei = fred("DGS2"), fred("DGS10"), fred("T10YIE")
        dd2 = d2[-1][1] - d2[-2][1]; dd10 = d10[-1][1] - d10[-2][1]; sp, sp_prev = d10[-1][1] - d2[-1][1], d10[-2][1] - d2[-2][1]; dbei = bei[-1][1] - bei[-2][1]
        obs.update(us2y=d2[-1][1], us2y_chg_bp=round(dd2 * 100, 1), us10y=d10[-1][1], us10y_chg_bp=round(dd10 * 100, 1), curve_10_2=round(sp, 2), curve_chg_bp=round((sp - sp_prev) * 100, 1), bei10=bei[-1][1], bei_chg_bp=round(dbei * 100, 1), fred_asof=d10[-1][0])
        if abs(dd2) >= 0.15: fired.append("us2y_15bp")
        if abs(dd10) >= 0.15: fired.append("us10y_15bp")
        if abs(sp - sp_prev) >= 0.15 or (sp * sp_prev < 0): fired.append("curve_15bp")
        if abs(dbei) >= 0.10: fired.append("breakeven_10bp")
    except Exception as ex: obs["fred"] = f"ERR {type(ex).__name__}"
    try:
        raw = urllib.request.urlopen("https://www.mof.go.jp/jgbs/reference/interest_rate/jgbcm.csv", timeout=20).read().decode("shift_jis", "ignore")
        rows = [r for r in csv.reader(io.StringIO(raw)) if r and r[0].startswith("R") and len(r) > 10 and r[10] not in ("", "-")]
        j10 = [(r[0], float(r[10])) for r in rows[-2:]]; dj = j10[-1][1] - j10[-2][1]
        obs.update(jgb10=j10[-1][1], jgb10_chg_bp=round(dj * 100, 1), jgb_asof=j10[-1][0])
        if abs(dj) >= 0.10: fired.append("jgb10_10bp")
    except Exception as ex: obs["jgb"] = f"ERR {type(ex).__name__}"
    if spy_r <= -0.03: fired.append("spy_drop_3")
    if spy_r >= 0.03: fired.append("spy_up_3")
    if spy_dd <= -0.10 and spy_dd_prev > -0.10: fired.append("spy_dd_10")
    if vix >= 30 and vix_prev < 30: fired.append("vix_30")
    if n_r <= -0.03: fired.append("n225_drop_3")
    # Market Context(殿 01:35): 発火の有無に関係なく観測値を残す
    MC = ROOT / "queue/x_market_context"; MC.mkdir(exist_ok=True)
    with (MC / "daily.jsonl").open("a", encoding="utf-8") as fh: fh.write(json.dumps(dict(date=date, **obs), ensure_ascii=False) + "\n")
    sched = [e for e in RULES["scheduled_events"] if e["date"] == date]
    print(json.dumps(dict(date=date, obs=obs, fired=fired, scheduled=[e["name"] for e in sched]), ensure_ascii=False))
    if not fired or dry: return 0
    if any(f.name.startswith(date) for f in EV.glob("*.yaml")): print("already proposed today (1 event unit/day)"); return 0
    used = recent_claims(); rule = next(r for r in RULES["reactive_triggers"] if r["id"] == fired[0])
    claim = next((c for c in rule["claims"] if c not in used), None)
    if not claim: print("no unused claim for", fired[0]); return 0
    ctx = f"{asof} {rule['rule']} 実測 {obs}"
    prop = dict(date=date, event_id=fired[0], rule=rule["rule"], observation=obs, claim=claim, format=rule["format"], funnel_stage=rule["funnel_stage"], audience=rule["audience"], hook_type=rule["hook_type"],
                content_category=rule["content_category"], desired_action=["dwell", "reply", "quote", "profile"], context=ctx, status="proposed", draft_id=f"EV-{date.replace('-', '')[4:]}-{fired[0]}")
    f = EV / f"{date}_{fired[0]}.yaml"; f.write_text(yaml.safe_dump(prop, allow_unicode=True, sort_keys=False), encoding="utf-8")
    subprocess.run(["bash", str(ROOT / "scripts/ntfy.sh"), f"【X イベント lane】{fired[0]} 発火({asof} SPY {spy_r:+.1%} / VIX {vix:.0f})。claim {claim} で Short を提案 → {f.name}。生成: python3 scripts/x_ops/x_claim_gen.py --event {f}"], cwd=ROOT)
    print("proposed", f)


if __name__ == "__main__":
    sys.exit(main())
