#!/usr/bin/env python3
"""@TokyoJibika の本人 X 投稿を X API v2 で取得し author corpus 化する。

殿指示 2026-09-04 13:08『本人の既存 X 投稿を取得可能な範囲で取得し、最重要の author corpus とする。
単独/引用/リプ/スレッド、リンク有無、テーマで区別する』。
必要 scope: tweet.read users.read(config/x_api.env)。token 失効時は scripts/x_ops/x_token_refresh.py を先に通す。
出力: docs/research/x_corpus/x/tweets.jsonl(1 行 1 post、public_metrics 付き)、x_stats.json。
Usage: python3 scripts/x_ops/x_fetch_author_corpus.py [--max 3200] [--env config/x_api.env]
"""
import json
import re
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/research/x_corpus/x"
USER_ID = "1096450072768741376"  # @TokyoJibika(2026-09-03 users/me で確認)


def load_env(p):
    v = {}
    for l in Path(p).read_text(encoding="utf-8").splitlines():
        if "=" in l and not l.lstrip().startswith("#"):
            k, x = l.split("=", 1); v[k.strip()] = x.strip().strip('"').strip("'")
    return v


def api(path, params, token):
    url = f"https://api.x.com/2{path}?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def classify(t):
    refs = t.get("referenced_tweets") or []
    kinds = {r["type"] for r in refs}
    if "replied_to" in kinds:
        return "reply"
    if "quoted" in kinds:
        return "quote"
    if "retweeted" in kinds:
        return "retweet"
    return "single"


THEMES = [
    ("dm_signal", r"DM-?[Ss]ignal|シグナル|四神|忍法|バックテスト"),
    ("investing", r"投資|株|ETF|リターン|モメンタム|インデックス|S&P|SPY|TQQQ|ドローダウン|MaxDD|複利"),
    ("math_prob", r"確率|期待値|分布|平均|標準偏差|シャープ|ボラ|α|β|数学"),
    ("verification", r"検証|OOS|ウォーク|Walk|パラメータ|頑健|過剰最適化|再現"),
    ("medical", r"医療|医師|クリニック|診療|患者|耳鼻|保険診療"),
    ("economy", r"経済|金利|インフレ|為替|日銀|FRB|景気"),
]


def theme(text):
    hits = [name for name, pat in THEMES if re.search(pat, text)]
    return hits or ["other"]


def main():
    args = sys.argv[1:]
    env = args[args.index("--env") + 1] if "--env" in args else str(ROOT / "config/x_api.env")
    mx = int(args[args.index("--max") + 1]) if "--max" in args else 3200
    v = load_env(env)
    token = v.get("X_ACCESS_TOKEN", "")
    if not token:
        print("x_fetch_author_corpus: token empty", file=sys.stderr); return 2
    OUT.mkdir(parents=True, exist_ok=True)
    rows, token_next = [], None
    fields = "created_at,public_metrics,referenced_tweets,entities,conversation_id,in_reply_to_user_id,lang,note_tweet"
    while len(rows) < mx:
        params = {"max_results": 100, "tweet.fields": fields, "expansions": "referenced_tweets.id"}
        if token_next:
            params["pagination_token"] = token_next
        try:
            d = api(f"/users/{USER_ID}/tweets", params, token)
        except urllib.error.HTTPError as ex:
            print(f"x_fetch_author_corpus: http={ex.code} body={ex.read().decode()[:200]}", file=sys.stderr)
            break
        data = d.get("data") or []
        rows.extend(data)
        token_next = (d.get("meta") or {}).get("next_token")
        if not token_next or not data:
            break
        time.sleep(1.0)
    with (OUT / "tweets.jsonl").open("w", encoding="utf-8") as f:
        for t in rows:
            text = (t.get("note_tweet") or {}).get("text") or t.get("text", "")
            urls = [u.get("expanded_url", "") for u in (t.get("entities") or {}).get("urls", [])]
            rec = {"id": t["id"], "created_at": t.get("created_at"), "kind": classify(t), "text": text,
                   "has_url": bool(urls), "urls": urls, "themes": theme(text), "metrics": t.get("public_metrics", {}),
                   "conversation_id": t.get("conversation_id")}
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    kinds = Counter(classify(t) for t in rows)
    dates = sorted(t.get("created_at", "") for t in rows if t.get("created_at"))
    singles = [((t.get("note_tweet") or {}).get("text") or t.get("text", "")) for t in rows if classify(t) == "single"]
    lens = [len(s) for s in singles]
    st = {"count": len(rows), "kinds": dict(kinds), "period": [dates[0][:10] if dates else None, dates[-1][:10] if dates else None],
          "single_len_median": statistics.median(lens) if lens else 0,
          "single_len_p90": sorted(lens)[int(len(lens) * 0.9)] if lens else 0,
          "single_with_url": sum(1 for t in rows if classify(t) == "single" and (t.get("entities") or {}).get("urls")),
          "themes": dict(Counter(th for s in singles for th in theme(s))),
          "kuten_end_ratio": round(sum(1 for s in singles if s.rstrip().endswith("。")) / max(1, len(singles)), 2),
          "question_ratio": round(sum(1 for s in singles if "？" in s or "?" in s) / max(1, len(singles)), 2),
          "newline_median": statistics.median(s.count("\n") for s in singles) if singles else 0}
    (OUT / "x_stats.json").write_text(json.dumps(st, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps(st, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
