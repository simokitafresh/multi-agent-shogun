#!/usr/bin/env python3
"""live OOS 台帳の投稿済み entry に 24h/7d の KPI snapshot を書く。アカウント日次(followers)も記録する。

殿指示 2026-09-04 14:51 §17(KPI 体系)/§20(24h/7d snapshot)。取得できない指標は書かない(推測値禁止)。
取得: public_metrics + non_public_metrics(user_profile_clicks/url_link_clicks/engagements。自分の投稿のみ、OAuth user context)。
取得不能: 投稿別 follow、note PV、DM-Signal 訪問(UTM 未設定)。
token は読むだけ(refresh は keeper)。cron 毎時。
Usage: python3 scripts/x_ops/x_kpi_snapshot.py [--force]
"""
import datetime as dt
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LEDGER = ROOT / "queue/x_live_oos/ledger.yaml"
ACCOUNT = ROOT / "queue/x_live_oos/account_daily.jsonl"
ENV = ROOT / "config/x_api.env"
WINDOWS = {"t24h": 24, "t7d": 24 * 7}
JST = dt.timezone(dt.timedelta(hours=9))


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


def main():
    force = "--force" in sys.argv
    token = env().get("X_ACCESS_TOKEN", "")
    if not token:
        print("x_kpi_snapshot: token empty", file=sys.stderr); return 2
    now = dt.datetime.now(JST)
    # account daily
    me = api("/users/me", {"user.fields": "public_metrics"}, token)["data"]["public_metrics"]
    today = now.strftime("%Y-%m-%d")
    lines = ACCOUNT.read_text(encoding="utf-8").splitlines() if ACCOUNT.exists() else []
    if not any(l.startswith('{"date": "%s"' % today) for l in lines):
        with ACCOUNT.open("a", encoding="utf-8") as f:
            f.write(json.dumps({"date": today, "ts": now.isoformat(timespec="seconds"), **me}, ensure_ascii=False) + "\n")
    if not LEDGER.exists():
        print("x_kpi_snapshot: ledger missing"); return 0
    text = LEDGER.read_text(encoding="utf-8")
    # entry 分割(テキスト操作のみ。yaml.dump 禁止)
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
                due.append((i, pid.group(1), w))
    if not due:
        print("x_kpi_snapshot: nothing due"); return 0
    ids = sorted({p for _, p, _ in due})
    data = {}
    for k in range(0, len(ids), 100):
        r = api("/tweets", {"ids": ",".join(ids[k:k + 100]),
                            "tweet.fields": "public_metrics,non_public_metrics"}, token)
        for t in r.get("data", []):
            data[t["id"]] = {**t.get("public_metrics", {}), **{f"np_{a}": b for a, b in (t.get("non_public_metrics") or {}).items()}}
    written = 0
    for i, pid, w in due:
        m = data.get(pid)
        if not m:
            continue
        snap = f"    {w}:\n      ts: {now.isoformat(timespec='seconds')}\n" + "".join(f"      {a}: {b}\n" for a, b in m.items())
        e = entries[i]
        if re.search(r"^  snapshots: \{\}\s*$", e, re.M):
            e = re.sub(r"^  snapshots: \{\}\s*$", "  snapshots:\n" + snap.rstrip("\n"), e, count=1, flags=re.M)
        else:
            e = re.sub(r"^  snapshots:\n", "  snapshots:\n" + snap, e, count=1, flags=re.M)
        entries[i] = e
        written += 1
    LEDGER.write_text(head + "".join(entries), encoding="utf-8")
    print(f"x_kpi_snapshot: wrote {written} snapshots ({', '.join(w for _, _, w in due)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
