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


def main():
    a = sys.argv[1:]; dry = "--dry-run" in a
    date = a[a.index("--date") + 1] if "--date" in a else dt.date.today().isoformat()
    import yfinance as yf
    px = yf.download(["SPY", "^VIX", "^N225"], period="1y", progress=False, auto_adjust=True)["Close"].dropna(how="all")
    spy = px["SPY"].dropna(); n225 = px["^N225"].dropna(); vixs = px["^VIX"].dropna()  # 市場ごとに最終有効日が違う(日本が先に閉まる)
    asof = spy.index[-1].date().isoformat()
    spy_r = float(spy.iloc[-1] / spy.iloc[-2] - 1); n_r = float(n225.iloc[-1] / n225.iloc[-2] - 1)
    spy_dd = float(spy.iloc[-1] / spy.max() - 1); spy_dd_prev = float(spy.iloc[-2] / spy.iloc[:-1].max() - 1)
    vix, vix_prev = float(vixs.iloc[-1]), float(vixs.iloc[-2])
    obs = dict(asof=asof, spy_ret=round(spy_r, 4), n225_ret=round(n_r, 4), spy_dd_52w=round(spy_dd, 4), vix=round(vix, 2))
    fired = []
    if spy_r <= -0.03: fired.append("spy_drop_3")
    if spy_r >= 0.03: fired.append("spy_up_3")
    if spy_dd <= -0.10 and spy_dd_prev > -0.10: fired.append("spy_dd_10")
    if vix >= 30 and vix_prev < 30: fired.append("vix_30")
    if n_r <= -0.03: fired.append("n225_drop_3")
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
