#!/usr/bin/env python3
"""xAI Grok x_search で「バズった投資ネタ」(日本語、高 like)を収集する(殿 2026-09-04 18:38『x search でバズった投資ネタを探し、特徴を分析して俺のスタイルと融合』)。
出力: docs/research/x_corpus/viral/viral_invest.jsonl(dedupe)、収集ログ。分析は x_viral_analyze.py。
役割(殿指示 2026-09-04 19:14 §4): 投稿本文を作らない。『今どんな投資テーマ・言説・疑問が注目されているか』を検出するセンサー。
経路は viral search→topic detection→本人思想との交点→claim candidate(skills/x-post-pipeline/claim_candidates.yaml)→ext_gate A-E→claim_bank。
viral post→rewrite→投稿は禁止。学ぶのは話題・Hook 構造・対比・数字の具体化・常識→違和感・読者への関係付け・問いの置き方まで。Voice・語尾・キャラ・スラング・煽り・www・独自フレーズ・結論は学ばない。
Usage: python3 scripts/x_ops/x_viral_search.py [--from 2026-03] [--to 2026-09] [--min-likes 1000]
"""
import json, re, sys, time
from datetime import date
from pathlib import Path
import requests

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/research/x_corpus/viral"; OUT.mkdir(parents=True, exist_ok=True)
API = "https://api.x.ai/v1/responses"; MODEL = "grok-4-1-fast-reasoning"
TOPICS = ["インデックス投資 オルカン S&P500", "新NISA 積立 暴落", "複利 資産形成 格差", "高配当 投資 落とし穴", "バックテスト 投資 検証",
          "FIRE 資産 年収", "暴落 狼狽売り 長期投資", "レバレッジ 投資 リスク", "期待値 勝率 投資", "モメンタム 投資 戦略"]


def env(p):
    v = {}
    for l in Path(p).read_text(encoding="utf-8").splitlines():
        if "=" in l and not l.lstrip().startswith("#"):
            k, x = l.split("=", 1); v[k.strip()] = x.strip().strip('"').strip("'")
    return v


PROMPT = """あなたは収集係です。x_search を使い、{frm} から {to} の期間に日本語で投稿された「{topic}」に関する X のポストを、いいね数が多い順に最大 40 件取得してください(いいね {minl} 未満は除外)。
企業・メディア公式ではなく個人アカウントの投稿を優先。広告・スパム・プレゼント企画は除外。
出力は JSON 配列のみ。前置き・説明・コードフェンスを書かないでください。各要素:
{{"date":"YYYY-MM-DD","handle":"@...","text":"本文をそのまま(改行は \\n)","url":"https://x.com/.../status/...","has_url":true/false,"has_image":true/false,"likes":数値,"reposts":数値または null,"replies":数値または null,"views":数値または null,"bookmarks":数値または null}}
本文は要約せず原文のまま。数値は表示されていたものだけ。0 件なら []。"""


def extract_text(d):
    for o in d.get("output", []):
        for c in o.get("content", []) or []:
            if c.get("type") in ("output_text", "text") and c.get("text"):
                return c["text"]
    return d.get("output_text", "")


def month_windows(frm, to):
    y, m = map(int, frm.split("-")); ey, em = map(int, to.split("-")); out = []
    while (y, m) <= (ey, em):
        ny, nm = (y + 1, 1) if m == 12 else (y, m + 1)
        out.append((f"{y}-{m:02d}-01", f"{ny}-{nm:02d}-01" if (y, m) < (ey, em) else date.today().isoformat())); y, m = ny, nm
    return out


def main():
    a = sys.argv[1:]
    frm = a[a.index("--from") + 1] if "--from" in a else "2026-03"; to = a[a.index("--to") + 1] if "--to" in a else "2026-09"
    minl = int(a[a.index("--min-likes") + 1]) if "--min-likes" in a else 1000
    key = env(ROOT / "config/xai_api.env").get("XAI_API_KEY")
    if not key:
        print("XAI_API_KEY missing", file=sys.stderr); return 2
    path = OUT / "viral_invest.jsonl"
    seen = set(); rows = []
    if path.exists():
        for l in path.read_text(encoding="utf-8").splitlines():
            r = json.loads(l); seen.add(r.get("url") or r["text"][:40]); rows.append(r)
    for start, end in month_windows(frm, to):
        for topic in TOPICS:
            payload = {"model": MODEL, "input": PROMPT.format(frm=start, to=end, topic=topic, minl=minl),
                       "tools": [{"type": "x_search", "from_date": start, "to_date": end}]}
            try:
                r = requests.post(API, headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"}, json=payload, timeout=180)
                txt = extract_text(r.json()) if r.ok else ""
            except Exception as ex:
                print(f"{start} {topic}: ERR {type(ex).__name__}", file=sys.stderr); continue
            m = re.search(r"\[.*\]", txt, re.S)
            try:
                items = json.loads(m.group(0)) if m else []
            except Exception:
                items = []
            n = 0
            for it in items:
                k = it.get("url") or it.get("text", "")[:40]
                if not it.get("text") or k in seen or (it.get("likes") or 0) < minl: continue
                it["topic"] = topic; it["window"] = start; seen.add(k); rows.append(it); n += 1
            print(f"{start} {topic}: +{n} (total {len(rows)})", flush=True)
            time.sleep(1)
    with path.open("w", encoding="utf-8") as f:
        for r in rows: f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print("saved", len(rows))


if __name__ == "__main__":
    sys.exit(main())
