#!/usr/bin/env python3
"""月間 editorial plan を作る(殿指示 2026-09-04 19:28『カレンダーを埋めるな。編集計画を作れ』)。
- plan=editorial decision。各 slot に claim/format/funnel_stage/audience/hook_type/desired_action/content_category/context/reuse を事前登録する。生成後に本文を見て stage を決めない
- Format(どう書くか)/Funnel(何をさせたいか)/Category(何を話すか)を混ぜない。format から stage/audience/hook/category を推定しない
- 52 slot は capacity であって quota ではない。自然な claim が無い slot は status: empty(正常)。fill_slot 目的の再利用禁止
- 再利用は editorial purpose が要る(Short で問題提起→5 日以上後に Long/Series/Thread で検証まで掘る)。深掘りの後に同じ claim の Short は水増し=不可
Usage: python3 scripts/x_ops/x_plan_calendar.py --from 2026-09-05 --to 2026-09-30 [--out skills/x-post-pipeline/plan_202609.yaml]
"""
import sys, datetime as dt
from pathlib import Path
import yaml
ROOT = Path(__file__).resolve().parents[2]
BANK = yaml.safe_load((ROOT / "skills/x-post-pipeline/claim_bank.yaml").read_text(encoding="utf-8"))
EVENTS = {e["date"]: e for e in yaml.safe_load((ROOT / "skills/x-post-pipeline/event_rules.yaml").read_text(encoding="utf-8"))["scheduled_events"]}
CAL = yaml.safe_load((ROOT / "skills/x-post-pipeline/slot_calendar.yaml").read_text(encoding="utf-8"))["slots"]
# --- editorial decisions(claim 単位。format とは独立) ---
SERIES = {
    "break_point": {"title": "検証は最良探しじゃなく壊れる場所探し", "claims": ["C07", "C08", "C24", "C09", "C25", "C19", "C18", "C28"], "funnel_stage": "follow", "audience": "systematic", "desired_action": ["bookmark", "follow", "profile"]},
    "invest_math": {"title": "投資の算数", "claims": ["C02", "C03", "C23", "C12", "C11", "C30", "C16", "C13"], "funnel_stage": "follow", "audience": "investor", "desired_action": ["bookmark", "follow", "quote"]},
}
LONG = {"C05": ("trust", "investor", "story"), "C15": ("trust", "systematic", "result"), "C22": ("reach", "investor", "contradiction"), "C06": ("trust", "systematic", "result"), "C20": ("trust", "systematic", "story"), "C26": ("trust", "systematic", "math"), "C29": ("reach", "general", "contradiction")}
THREAD = {"C04": ("reach", "general", "math"), "C17": ("trust", "investor", "question"), "C32": ("reach", "investor", "question")}
SHORT_STAGE = {  # claim ごとの Short の仕事。無指定は reach/investor
    "C10": ("follow", "investor"), "C15": ("follow", "systematic"), "C20": ("trust", "systematic"), "C33": ("trust", "investor"), "C26": ("trust", "systematic"),
    "C08": ("trust", "systematic"), "C19": ("trust", "systematic"), "C07": ("follow", "systematic"), "C22": ("reach", "general"), "C29": ("reach", "general"), "C30": ("reach", "general"), "C34": ("reach", "investor"),
}
ACTION = {"reach": ["dwell", "reply", "quote", "profile"], "follow": ["profile", "follow", "bookmark"], "trust": ["bookmark", "profile", "note"], "convert": ["dm_signal", "note"]}
REUSE_REASON = "Short で問題提起した claim を {fmt} で検証まで掘る(5 日以上後)"


def main():
    a = sys.argv[1:]
    frm = a[a.index("--from") + 1] if "--from" in a else dt.date.today().isoformat()
    to = a[a.index("--to") + 1] if "--to" in a else "2026-09-30"
    out = Path(a[a.index("--out") + 1]) if "--out" in a else ROOT / "skills/x-post-pipeline/plan_202609.yaml"
    claims = {c["key"]: c for c in BANK["claims"]}
    slots = sorted([s for s in CAL if frm <= s["date"] <= to], key=lambda s: (s["date"], s["time"]))
    plan = []; seq = {"short": 0, "long": 0, "thread": 0, "series_entry": 0}
    deep = {}  # claim -> (date, fmt) 深掘りで使う日
    sp = {k: 0 for k in SERIES}; turn = list(SERIES); li = list(LONG); ti = list(THREAD)
    def base(s, k, fmt, stage, aud, hook, did, **kw):
        c = claims[k]
        d = dict(date=s["date"], time=s["time"], status="scheduled", draft_id=did, claim=k, claim_origin=c["origin"], content_category=c["category"], format=fmt,
                 funnel_stage=stage, audience=aud, hook_type=hook, desired_action=ACTION[stage], context=c.get("context", ""), why_this_day=kw.pop("why", ""))
        d.update(kw); return d
    # 1) 夜 slot=深掘り形式(Series 進行/Long 検証/Thread 段階説明)。理由が無ければ empty
    for s in slots:
        f = s["format"]
        if f == "series_entry":
            sid = turn[0]; turn.append(turn.pop(0))
            if sp[sid] >= len(SERIES[sid]["claims"]): plan.append(dict(date=s["date"], time=s["time"], status="empty", format=f, reason="シリーズは完結。続きを作らない")); continue
            S = SERIES[sid]; k = S["claims"][sp[sid]]; sp[sid] += 1; seq[f] += 1; deep[k] = (s["date"], f)
            plan.append(base(s, k, f, S["funnel_stage"], S["audience"], claims[k]["hook"], f"P9-SE-{seq[f]}", series_id=sid, series_title=S["title"], series_order=sp[sid], series_total=len(S["claims"]), why=f"シリーズ『{S['title']}』の進行 {sp[sid]}/{len(S['claims'])}"))
        elif f == "long":
            if not li: plan.append(dict(date=s["date"], time=s["time"], status="empty", format=f, reason="検証まで掘る価値のある claim が残っていない")); continue
            k = li.pop(0); st, au, hk = LONG[k]; seq[f] += 1; deep[k] = (s["date"], f)
            plan.append(base(s, k, f, st, au, hk, f"P9-L-{seq[f]}", why="claim を疑い→検証→数字→結論まで掘る"))
        elif f == "thread":
            if not ti: plan.append(dict(date=s["date"], time=s["time"], status="empty", format=f, reason="段階説明に意味がある claim が残っていない")); continue
            k = ti.pop(0); st, au, hk = THREAD[k]; seq[f] += 1; deep[k] = (s["date"], f)
            plan.append(base(s, k, f, st, au, hk, f"P9-T-{seq[f]}", why="親で核、リプで条件と数字を段階的に足す"))
    # 2) 朝 Short: 未使用 claim=問題提起。深掘り予定の claim は『5 日以上前の問題提起』としてのみ再利用可。深掘り後は水増し=empty
    used = set(); prev = None
    def cand(k, date):
        c = claims[k]
        if k in used: return None
        if prev and (claims[prev]["belief"] == c["belief"] or (c["origin"] == "external_topic" and claims[prev]["origin"] == "external_topic")): return None
        if k in deep:
            gap = (dt.date.fromisoformat(deep[k][0]) - dt.date.fromisoformat(date)).days
            if gap < 5: return None
            return dict(reuse_of=k, reuse_reason=REUSE_REASON.format(fmt=deep[k][1]))
        return {}
    fresh = [k for k in claims if k not in deep]; deep_first = [k for k in claims if k in deep]
    for s in slots:
        if s["format"] != "short": continue
        pick = None
        for k in fresh + deep_first:
            r = cand(k, s["date"])
            if r is not None: pick = (k, r); break
        if not pick: plan.append(dict(date=s["date"], time=s["time"], status="empty", format="short", reason="この日に自然に言える claim が無い(深掘り済み claim の再掲は水増し)")); continue
        k, r = pick; used.add(k); prev = k; seq["short"] += 1
        st, au = SHORT_STAGE.get(k, ("reach", "investor"))
        why = "深掘り予定の claim を先に広い層へ問題提起" if r else ("外部で今話題のテーマへ本人の違和感を置く" if claims[k]["origin"] == "external_topic" else "本人の既存思想。今週のテーマと自然に接続")
        plan.append(base(s, k, "short", st, au, claims[k]["hook"], f"P9-S-{seq['short']}", why=why, **r))
    # 3) 予定イベント(event_rules.scheduled_events)を event 欄へ。その日の Short はイベント対応 claim へ寄せる(claim は bank から。予測はしない)
    for p in plan:
        ev = EVENTS.get(p["date"])
        if not ev: continue
        p["event"] = ev["name"]
        if p["status"] == "scheduled" and p["format"] == "short":
            alt = next((k for k in ev["claims"] if k not in used and k not in deep), None)
            if alt:
                used.discard(p["claim"]); used.add(alt); c = claims[alt]
                p.update(claim=alt, claim_origin=c["origin"], content_category=c["category"], hook_type=c["hook"], context=c.get("context", ""), why_this_day=f"予定イベント『{ev['name']}』: {ev['note']}"); p.pop("reuse_of", None); p.pop("reuse_reason", None)
            else: p["why_this_day"] += f"(予定イベント『{ev['name']}』の日)"
    plan.sort(key=lambda p: (p["date"], p["time"]))
    sched = [p for p in plan if p["status"] == "scheduled"]; empty = [p for p in plan if p["status"] == "empty"]
    uniq = {p["claim"] for p in sched}; reused = [p for p in sched if p.get("reuse_of")]
    from collections import Counter
    stats = dict(capacity=len(slots), scheduled=len(sched), empty=len(empty), unique_claims=len(uniq), reused_claims=len(reused),
                 by_format=dict(Counter(p["format"] for p in sched)), by_stage=dict(Counter(p["funnel_stage"] for p in sched)), by_category=dict(Counter(p["content_category"] for p in sched)), by_origin=dict(Counter(p["claim_origin"] for p in sched)))
    meta = {"plan_id": f"plan_{frm.replace('-', '')[:6]}", "generated": dt.datetime.now().isoformat(timespec="seconds"), "range": [frm, to], "approval": {"stage1_editorial": "pending", "stage2_copy": "pending"},
            "rule": "capacity≠quota。empty は正常。format/funnel/category は別軸で事前登録。fill_slot 目的の再利用禁止", "series": {k: v["title"] for k, v in SERIES.items()}, "stats": stats}
    out.write_text(yaml.safe_dump({"meta": meta, "plan": plan}, allow_unicode=True, sort_keys=False, width=200), encoding="utf-8")
    print(yaml.safe_dump(stats, allow_unicode=True, sort_keys=False))
    for p in plan:
        if p["status"] == "empty": print(f"{p['date']} {p['time']} {p['format']:<12} EMPTY  {p['reason']}")
        else: print(f"{p['date']} {p['time']} {p['format']:<12} {p['claim']} {p['content_category']} {p['funnel_stage']:<6} {p['audience']:<10} {p['hook_type']:<13} {p['draft_id']}{' reuse' if p.get('reuse_of') else ''}")


if __name__ == "__main__":
    main()
