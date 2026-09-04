#!/usr/bin/env python3
"""slot_calendar の未来 slot に claim_bank の claim を割り当てて plan を作る(殿指示 2026-09-04 19:16『投稿ネタは全部新しく作り直して、カレンダー形式で 9 月末までの投稿を埋めて見せてくれ』)。
規則: Short は claim を 1 回だけ使う。Long/Thread/Series Entry は同じ claim を深掘り形式として 1 回だけ再利用可(Short と 5 日以上離す)。
      同じ belief の連続を避ける。external_topic は連続させない。claim を増やさない(claim 数は KPI にしない)。足りない slot は空のまま(fallback なし)。
Usage: python3 scripts/x_ops/x_plan_calendar.py --from 2026-09-05 --to 2026-09-30 --out skills/x-post-pipeline/plan_202609.yaml
"""
import sys, datetime as dt
from pathlib import Path
import yaml
ROOT = Path(__file__).resolve().parents[2]
BANK = yaml.safe_load((ROOT / "skills/x-post-pipeline/claim_bank.yaml").read_text(encoding="utf-8"))
CAL = yaml.safe_load((ROOT / "skills/x-post-pipeline/slot_calendar.yaml").read_text(encoding="utf-8"))["slots"]
SERIES = {  # 本人の題名の型に合わせた 2 系列。各回単独で成立、続きがあると分かる
    "break_point": {"title": "検証は最良探しじゃなく壊れる場所探し", "claims": ["C07", "C08", "C24", "C09", "C25", "C19", "C18", "C28"]},
    "invest_math": {"title": "投資の算数", "claims": ["C02", "C03", "C23", "C12", "C11", "C30", "C16", "C13"]},
}
LONG = ["C05", "C15", "C22", "C06", "C20", "C26", "C29"]
THREAD = ["C04", "C17", "C32"]


def main():
    a = sys.argv[1:]
    frm = a[a.index("--from") + 1] if "--from" in a else dt.date.today().isoformat()
    to = a[a.index("--to") + 1] if "--to" in a else "2026-09-30"
    out = Path(a[a.index("--out") + 1]) if "--out" in a else ROOT / "skills/x-post-pipeline/plan_202609.yaml"
    claims = {c["key"]: c for c in BANK["claims"]}
    slots = sorted([s for s in CAL if frm <= s["date"] <= to], key=lambda s: (s["date"], s["time"]))
    deep_use = {}  # claim -> date used in deep format
    plan = []; seq = {"short": 0, "long": 0, "thread": 0, "series_entry": 0}
    series_ptr = {k: 0 for k in SERIES}; series_turn = list(SERIES); long_i = thread_i = 0
    # 1) evening deep formats first (their dates constrain Short spacing)
    for s in slots:
        f = s["format"]
        if f == "series_entry":
            sid = series_turn[0]; series_turn.append(series_turn.pop(0))
            if series_ptr[sid] >= len(SERIES[sid]["claims"]): continue
            k = SERIES[sid]["claims"][series_ptr[sid]]; series_ptr[sid] += 1
            seq[f] += 1; deep_use[k] = s["date"]
            plan.append(dict(date=s["date"], time=s["time"], format=f, claim=k, draft_id=f"P9-SE-{seq[f]}", series_id=sid, series_title=SERIES[sid]["title"], series_order=series_ptr[sid], series_total=len(SERIES[sid]["claims"])))
        elif f == "long":
            if long_i >= len(LONG): continue
            k = LONG[long_i]; long_i += 1; seq[f] += 1; deep_use[k] = s["date"]
            plan.append(dict(date=s["date"], time=s["time"], format=f, claim=k, draft_id=f"P9-L-{seq[f]}"))
        elif f == "thread":
            if thread_i >= len(THREAD): continue
            k = THREAD[thread_i]; thread_i += 1; seq[f] += 1; deep_use[k] = s["date"]
            plan.append(dict(date=s["date"], time=s["time"], format=f, claim=k, draft_id=f"P9-T-{seq[f]}"))
    # 2) Short: 未使用 claim を優先、深掘りと 5 日以上離す、belief/origin 連続回避
    used_short = set(); prev = None
    def ok(k, date):
        c = claims[k]
        if k in used_short: return False
        if k in deep_use and abs((dt.date.fromisoformat(deep_use[k]) - dt.date.fromisoformat(date)).days) < 5: return False
        if prev and (claims[prev]["belief"] == c["belief"] or (c["origin"] == "external_topic" and claims[prev]["origin"] == "external_topic")): return False
        return True
    order = [k for k in claims if k not in deep_use] + [k for k in claims if k in deep_use]
    for s in slots:
        if s["format"] != "short": continue
        pick = next((k for k in order if ok(k, s["date"])), None)
        if not pick: plan.append(dict(date=s["date"], time=s["time"], format="short", claim=None, draft_id=None, note="適切な claim なし=SKIP(fallback なし)")); continue
        used_short.add(pick); prev = pick; seq["short"] += 1
        plan.append(dict(date=s["date"], time=s["time"], format="short", claim=pick, draft_id=f"P9-S-{seq['short']}"))
    plan.sort(key=lambda p: (p["date"], p["time"]))
    empty = [p for p in plan if not p["claim"]]
    out.write_text(yaml.safe_dump({"meta": {"generated": dt.datetime.now().isoformat(timespec="seconds"), "range": [frm, to], "rule": __doc__.strip().splitlines()[1], "series": SERIES, "empty_slots": len(empty)}, "plan": plan}, allow_unicode=True, sort_keys=False), encoding="utf-8")
    print(f"slots={len(slots)} planned={len(plan)-len(empty)} empty={len(empty)} seq={seq} out={out}")
    for p in plan: print(f"{p['date']} {p['time']} {p['format']:<12} {p['claim'] or '-':<4} {p['draft_id'] or ''} {p.get('series_id','')}{'#'+str(p['series_order']) if p.get('series_order') else ''}")


if __name__ == "__main__":
    main()
