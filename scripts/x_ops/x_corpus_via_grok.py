#!/usr/bin/env python3
"""xAI Grok の x_search で @TokyoJibika 本人投稿を月次窓で収集し author corpus 化する(X API の user 認可を殿に毎回求めない経路)。

殿指摘 2026-09-04 13:15『X API の認可を俺が毎回とるのはおかしい。@tokyojibika の情報は x search でも出来るはず』。
出力: docs/research/x_corpus/x/tweets_grok.jsonl(1 行 1 post、dedupe)、x_stats_grok.json。
Usage: python3 scripts/x_ops/x_corpus_via_grok.py --from 2025-01 --to 2026-09 [--handle TokyoJibika]
"""
import json
import re
import statistics
import sys
import time
from collections import Counter
from datetime import date
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/research/x_corpus/x"
API = "https://api.x.ai/v1/responses"
MODEL = "grok-4-1-fast-reasoning"


def env(path):
    v = {}
    for l in Path(path).read_text(encoding="utf-8").splitlines():
        if "=" in l and not l.lstrip().startswith("#"):
            k, x = l.split("=", 1); v[k.strip()] = x.strip().strip('"').strip("'")
    return v


PROMPT = """あなたは収集係です。x_search を使い、X アカウント @{handle} が {frm} から {to} の期間に投稿した本人のポストを、できる限り多く(最大 60 件)取得してください。
本人の投稿だけを対象にし、他人の投稿・本人へのリプライは含めないでください。本人による他人への返信(reply)や引用(quote)は含めてください。
出力は JSON 配列のみ。前置き・説明・コードフェンスを書かないでください。各要素:
{{"date":"YYYY-MM-DD","kind":"single|reply|quote|thread","text":"本文をそのまま(改行は \\n)","url":"https://x.com/{handle}/status/...","has_url":true/false,"likes":数値または null,"reposts":数値または null,"replies":数値または null,"views":数値または null}}
本文は要約せず原文のまま。数値は表示されていたものだけを入れ、無ければ null。件数が 0 なら [] を返してください。"""


def extract_text(d):
    parts = []
    for item in d.get("output", []) or []:
        for c in item.get("content", []) or []:
            if isinstance(c, dict) and c.get("type") in ("output_text", "text") and c.get("text"):
                parts.append(c["text"])
    return "\n".join(parts) if parts else (d.get("output_text") or "")


def month_windows(frm, to):
    y, m = map(int, frm.split("-")); ye, me = map(int, to.split("-"))
    while (y, m) <= (ye, me):
        nm, ny = (m + 1, y) if m < 12 else (1, y + 1)
        start = date(y, m, 1).isoformat()
        end = (date(ny, nm, 1)).isoformat()
        yield start, end
        y, m = ny, nm


def main():
    a = sys.argv[1:]
    frm = a[a.index("--from") + 1] if "--from" in a else "2025-01"
    to = a[a.index("--to") + 1] if "--to" in a else date.today().strftime("%Y-%m")
    handle = a[a.index("--handle") + 1] if "--handle" in a else "TokyoJibika"
    key = env(ROOT / "config/xai_api.env").get("XAI_API_KEY")
    if not key:
        print("XAI_API_KEY missing", file=sys.stderr); return 2
    OUT.mkdir(parents=True, exist_ok=True)
    seen, rows, log = set(), [], []
    for start, end in month_windows(frm, to):
        payload = {"model": MODEL,
                   "input": PROMPT.format(handle=handle, frm=start, to=end),
                   "tools": [{"type": "x_search", "allowed_x_handles": [handle], "from_date": start, "to_date": end}]}
        try:
            r = requests.post(API, headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"}, json=payload, timeout=240)
            r.raise_for_status()
            txt = extract_text(r.json())
            m = re.search(r"\[.*\]", txt, re.S)
            items = json.loads(m.group(0)) if m else []
        except Exception as ex:  # noqa: BLE001
            items = []; log.append(f"{start}: {type(ex).__name__} {str(ex)[:120]}")
        n = 0
        for it in items:
            if not isinstance(it, dict) or not it.get("text"):
                continue
            k = it.get("url") or it["text"][:80]
            if k in seen:
                continue
            seen.add(k); it["window"] = start[:7]; rows.append(it); n += 1
        log.append(f"{start[:7]}: {n}")
        print(log[-1], flush=True)
        time.sleep(1.5)
    with (OUT / "tweets_grok.jsonl").open("w", encoding="utf-8") as f:
        for r_ in rows:
            f.write(json.dumps(r_, ensure_ascii=False) + "\n")
    singles = [r_["text"] for r_ in rows if r_.get("kind") in ("single", "thread")]
    lens = [len(s) for s in singles]
    st = {"count": len(rows), "kinds": dict(Counter(r_.get("kind") for r_ in rows)),
          "period": [min((r_.get("date") or "9") for r_ in rows) if rows else None, max((r_.get("date") or "0") for r_ in rows) if rows else None],
          "single_len_median": statistics.median(lens) if lens else 0,
          "single_len_p90": sorted(lens)[int(len(lens) * 0.9)] if lens else 0,
          "with_url": sum(1 for r_ in rows if r_.get("has_url")),
          "kuten_end_ratio": round(sum(1 for s in singles if s.rstrip().endswith("。")) / max(1, len(singles)), 2),
          "question_ratio": round(sum(1 for s in singles if "？" in s or "?" in s) / max(1, len(singles)), 2),
          "newline_median": statistics.median(s.count("\n") for s in singles) if singles else 0,
          "desu_masu_ratio": round(sum(1 for s in singles if re.search(r"(です|ます|でした|ました)[。」\n]?$", s.strip()) or re.search(r"(です|ます)[。」\n]", s)) / max(1, len(singles)), 2),
          "first_person": dict(Counter(w for s in singles for w in ("僕", "私", "俺", "自分") if w in s)),
          "with_metrics": sum(1 for r_ in rows if r_.get("likes") is not None),
          "log": log}
    (OUT / "x_stats_grok.json").write_text(json.dumps(st, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps({k: v for k, v in st.items() if k != "log"}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
