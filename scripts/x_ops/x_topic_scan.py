#!/usr/bin/env python3
"""要人発言・話題の検知(殿 2026-09-04 19:48『要人発言なんかのトピックも欲しい』)。毎時 cron。
X API tweets/counts/recent(数値規則のみ): topic ごとに直近 1 時間の投稿数を 7 日の時間別中央値と比べ、3 倍以上かつ 200 以上で発火。
発火→Grok x_search で『この 3 時間に何が言われたか』を 2 行で要約(context にだけ使う。claim は bank から、要人発言を引用・要約して投稿しない)→提案+ntfy。
Usage: python3 scripts/x_ops/x_topic_scan.py [--dry-run]
"""
import sys, json, statistics, urllib.request, urllib.parse, datetime as dt
from pathlib import Path
import yaml
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/x_ops"))
from x_event_scan import propose, RULES


def env(p):
    v = {}
    for l in Path(p).read_text(encoding="utf-8").splitlines():
        if "=" in l and not l.lstrip().startswith("#"): k, x = l.split("=", 1); v[k.strip()] = x.strip().strip('"').strip("'")
    return v


def counts(tok, query):
    q = urllib.parse.quote(query)
    req = urllib.request.Request(f"https://api.x.com/2/tweets/counts/recent?query={q}&granularity=hour", headers={"Authorization": f"Bearer {tok}"})
    d = json.load(urllib.request.urlopen(req, timeout=30))["data"]
    full = [x for x in d if x["end"] <= dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:00:00.000Z")]
    return [x["tweet_count"] for x in full]


def grok_summary(key, topic_query):
    try:
        import requests
        prompt = f"x_search で直近 3 時間の日本語ポストから「{topic_query}」に関して何が起きたか(誰が何を言ったか・何が発表されたか)を事実だけ 2 行で。憶測・相場予想・煽りは書かない。日本語。"
        r = requests.post("https://api.x.ai/v1/responses", headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                          json={"model": "grok-4-1-fast-reasoning", "input": prompt, "tools": [{"type": "x_search"}]}, timeout=120)
        for o in r.json().get("output", []):
            for c in o.get("content", []) or []:
                if c.get("type") in ("output_text", "text") and c.get("text"): return c["text"].strip()[:300]
    except Exception as ex: return f"(要約取得失敗 {type(ex).__name__})"
    return ""


def main():
    dry = "--dry-run" in sys.argv; date = dt.date.today().isoformat()
    v = env(ROOT / "config/x_api.env"); tok = v.get("X_ACCESS_TOKEN") or json.loads(v.get("X_TOKEN_JSON", "{}")).get("access_token")
    xai = env(ROOT / "config/xai_api.env").get("XAI_API_KEY")
    fired = []; obs = {}
    for r in RULES["topic_triggers"]:
        try:
            c = counts(tok, r["query"]); last = c[-1]; base = statistics.median(c[:-1]) if len(c) > 24 else None
            ratio = (last / base) if base else None
            obs[r["id"]] = dict(last_hour=last, median_7d=base, ratio=round(ratio, 2) if ratio else None)
            if ratio and ratio >= 3.0 and last >= 200: fired.append(r["id"])
        except Exception as ex: obs[r["id"]] = f"ERR {type(ex).__name__}"
    print(json.dumps(dict(mode="topic", date=date, obs=obs, fired=fired), ensure_ascii=False))
    if not fired or dry: return 0
    rule = next(r for r in RULES["topic_triggers"] if r["id"] == fired[0])
    summ = grok_summary(xai, rule["query"]) if xai else ""
    propose(date, rule, dict(asof=dt.datetime.now().strftime("%Y-%m-%d %H:%M"), **obs[fired[0]]), ctx_extra=f" / 話題の要約(context のみ): {summ}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
