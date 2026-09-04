#!/usr/bin/env python3
"""live OOS 台帳の投稿済み entry に 24h/7d の KPI snapshot を書き、アカウント日次(followers と当日の投稿構成)を記録する。

殿指示 2026-09-04 14:51 §17/§20、殿裁定 16:07『取得可能な情報だけ。0 と null を混ぜない。投稿別 follow を作らない』。
可否の正本: skills/x-post-pipeline/kpi_availability.yaml。
- observable_post_level: public_metrics 6 + non_public_metrics(profile_clicks/link_clicks/engagements。自投稿・30 日以内のみ)
- 取れなかった項目は null(キー自体を `null` で書く)。0 は計測してゼロの時だけ
- account_daily: followers/following/tweet_count と followers_delta_day/week(前日・7 日前の行が無ければ null)、当日の投稿構成(formats/funnel/physical_posts。台帳の事前登録から集計)
- 投稿別 follow・非フォロワー imp・dwell・note PV は書かない(unavailable)
token は読むだけ(refresh は keeper)。cron 毎時 15 分。
Usage: python3 scripts/x_ops/x_kpi_snapshot.py [--force] [--summary]
"""
import datetime as dt
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LEDGER = ROOT / "queue/x_live_oos/ledger.yaml"
ACCOUNT = ROOT / "queue/x_live_oos/account_daily.jsonl"
ENV = ROOT / "config/x_api.env"
WINDOWS = {"t24h": 24, "t7d": 24 * 7}
JST = dt.timezone(dt.timedelta(hours=9))
PUBLIC = ["impression_count", "like_count", "reply_count", "retweet_count", "quote_count", "bookmark_count"]
NONPUB = ["user_profile_clicks", "url_link_clicks", "engagements", "impression_count"]


def env():
    v = {}
    for l in ENV.read_text(encoding="utf-8").splitlines():
        if "=" in l and not l.lstrip().startswith("#"):
            k, x = l.split("=", 1); v[k.strip()] = x.strip().strip('"')
    return v


def api(path, params, token):
    req = urllib.request.Request("https://api.x.com/2" + path + "?" + urllib.parse.urlencode(params),
                                 headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def yv(x):
    return "null" if x is None else x


def load_ledger():
    import yaml
    return yaml.safe_load(LEDGER.read_text(encoding="utf-8")) if LEDGER.exists() else {"entries": []}


def summary():
    """format×funnel_stage×lane×window の中央値。null は集計から除外し n_null を併記(N/A を 0 にしない)。"""
    import statistics as st
    d = load_ledger()
    groups = {}
    for e in d.get("entries", []):
        g = e.get("growth", {}); snaps = e.get("snapshots") or {}
        for w, m in snaps.items():
            key = (g.get("format", "?"), g.get("funnel_stage", "?"), g.get("content_lane", "?"), w)
            groups.setdefault(key, []).append(m)
    cols = ["np_impression_count", "np_user_profile_clicks", "bookmark_count", "reply_count", "np_url_link_clicks"]
    print("format\tstage\tlane\twindow\tn\t" + "\t".join(c + "(med,n_null)" for c in cols))
    for k in sorted(groups):
        ms = groups[k]
        cells = []
        for c in cols:
            vals = [x.get(c) for x in ms if x.get(c) is not None]
            cells.append(f"{st.median(vals) if vals else 'N/A'},{len(ms) - len(vals)}")
        print("\t".join(map(str, [*k, len(ms), *cells])))
    return 0


def day_composition(entries, day):
    comp = {"organic_posts": 0, "physical_posts": 0, "conversation_entries": 0,
            "formats": {"short": 0, "long": 0, "thread": 0, "series_entry": 0},
            "funnel": {"reach": 0, "follow": 0, "trust": 0, "convert": 0}}
    for e in entries:
        pat = e.get("posted_at") or ""
        if not pat:
            continue
        posted = dt.datetime.fromisoformat(str(pat).replace("Z", "+00:00")).astimezone(JST)
        if posted.strftime("%Y-%m-%d") != day:
            continue
        g = e.get("growth", {})
        if g.get("external_context", "standalone") in ("reply", "quote"):
            comp["conversation_entries"] += 1
        else:
            comp["organic_posts"] += 1
        comp["physical_posts"] += int(g.get("physical_posts") or e.get("physical_posts") or 1)
        f = g.get("format", "short"); comp["formats"][f] = comp["formats"].get(f, 0) + 1
        s = g.get("funnel_stage", "?"); comp["funnel"][s] = comp["funnel"].get(s, 0) + 1
    return comp


def write_account_daily(me, now, entries):
    ACCOUNT.parent.mkdir(parents=True, exist_ok=True)
    rows = [json.loads(l) for l in ACCOUNT.read_text(encoding="utf-8").splitlines() if l.strip()] if ACCOUNT.exists() else []
    today = now.strftime("%Y-%m-%d")
    by_day = {r["date"]: r for r in rows}
    prev = by_day.get((now - dt.timedelta(days=1)).strftime("%Y-%m-%d"))
    week = by_day.get((now - dt.timedelta(days=7)).strftime("%Y-%m-%d"))
    fc = me["followers_count"]
    row = {"date": today, "ts": now.isoformat(timespec="seconds"),
           "followers_count": fc, "following_count": me.get("following_count"), "tweet_count": me.get("tweet_count"),
           "followers_delta_day": (fc - prev["followers_count"]) if prev and prev.get("followers_count") is not None else None,
           "followers_delta_week": (fc - week["followers_count"]) if week and week.get("followers_count") is not None else None,
           "status": {"followers": "observable_account_level",
                      "followers_delta_day": "observable_account_level" if prev else "null_no_prev_day",
                      "followers_delta_week": "observable_account_level" if week else "null_no_prev_week"},
           **day_composition(entries, today)}
    # 当日行は最新値で置換(日次=その日の最終観測)。過去日は不変(歴史修正禁止)
    rows = [r for r in rows if r["date"] != today] + [row]
    ACCOUNT.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    return row


def main():
    if "--summary" in sys.argv:
        return summary()
    force = "--force" in sys.argv
    token = env().get("X_ACCESS_TOKEN", "")
    if not token:
        print("x_kpi_snapshot: token empty", file=sys.stderr); return 2
    now = dt.datetime.now(JST)
    me = api("/users/me", {"user.fields": "public_metrics"}, token)["data"]["public_metrics"]
    ledger = load_ledger()
    write_account_daily(me, now, ledger.get("entries", []))
    if not LEDGER.exists():
        print("x_kpi_snapshot: ledger missing"); return 0
    text = LEDGER.read_text(encoding="utf-8")
    parts = re.split(r"(?m)^(?=- draft_id: )", text)
    head, entries = parts[0], parts[1:]
    due = []
    for i, e in enumerate(entries):
        pid = re.search(r"^  post_id: '?([0-9]*)'?\s*$", e, re.M)
        pat = re.search(r"^  posted_at: '?([^'\n]*)'?\s*$", e, re.M)
        if not pid or not pid.group(1) or not pat or not pat.group(1):
            continue
        posted = dt.datetime.fromisoformat(pat.group(1).replace("Z", "+00:00"))
        age_h = (now - posted.astimezone(JST)).total_seconds() / 3600
        for w, hours in WINDOWS.items():
            if (age_h >= hours or force) and not re.search(rf"^    {w}:", e, re.M):
                due.append((i, pid.group(1), w, age_h))
    if not due:
        print("x_kpi_snapshot: nothing due"); return 0
    ids = sorted({p for _, p, _, _ in due})
    data, errors = {}, {}
    for k in range(0, len(ids), 100):
        r = api("/tweets", {"ids": ",".join(ids[k:k + 100]), "tweet.fields": "public_metrics,non_public_metrics"}, token)
        for t in r.get("data", []):
            pm = t.get("public_metrics") or {}; npm = t.get("non_public_metrics")
            m = {f: pm.get(f) for f in PUBLIC}
            # non_public が返らない(30 日超/権限)時は null。0 にしない
            m.update({f"np_{f}": (npm.get(f) if npm else None) for f in NONPUB})
            data[t["id"]] = m
        for er in r.get("errors", []):
            errors.setdefault(er.get("resource_id"), []).append(er.get("detail", "")[:80])
    written = 0
    for i, pid, w, age_h in due:
        m = data.get(pid)
        if not m:
            continue
        reason = ""
        if m.get("np_user_profile_clicks") is None:
            reason = "older_than_30d" if age_h > 24 * 30 else "api_unavailable"
        snap = f"    {w}:\n      ts: {now.isoformat(timespec='seconds')}\n" + "".join(f"      {a}: {yv(b)}\n" for a, b in m.items())
        if reason:
            snap += f"      np_null_reason: {reason}\n"
        if errors.get(pid):
            snap += f"      api_errors: {json.dumps(errors[pid], ensure_ascii=False)}\n"
        e = entries[i]
        if re.search(r"^  snapshots: \{\}\s*$", e, re.M):
            e = re.sub(r"^  snapshots: \{\}\s*$", "  snapshots:\n" + snap.rstrip("\n"), e, count=1, flags=re.M)
        else:
            e = re.sub(r"^  snapshots:\n", "  snapshots:\n" + snap, e, count=1, flags=re.M)
        entries[i] = e
        written += 1
    LEDGER.write_text(head + "".join(entries), encoding="utf-8")
    print(f"x_kpi_snapshot: wrote {written} snapshots ({', '.join(w for _, _, w, _ in due)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
