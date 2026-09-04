#!/usr/bin/env python3
"""殿本人の note 2 マガジン(mb4377418b422 How to / m6557263f0241 ショートコラム)を author corpus 化する。

殿指示 2026-09-04 13:08『本人 note から思考・説明・検証文体を抽出。2 マガジンを雑に混ぜない』。
note 公開 API /api/v3/notes/<key> の body(HTML)を段落テキストへ落とし、
docs/research/x_corpus/note/<magazine>/<key>.md に保存、表面統計を docs/research/x_corpus/note_stats.json へ。
Usage: python3 scripts/x_ops/note_corpus_fetch.py [--keys k1,k2] [--skip-fetch]
"""
import html
import json
import re
import statistics
import sys
import time
import urllib.request
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/research/x_corpus/note"
LEDGER = ROOT / "skills/x-post-pipeline/stock_ledger.yaml"
SHORT = "m6557263f0241"
HOWTO = "mb4377418b422"
SHORT_KEYS = {"nc41e1f481754","nb13c356f36ff","n8da2aaf6ff34","ned3f1dc3c266","nb44887f51c66","n759ada77c21d",
              "nb56839c60686","n6f64950c2d3b","nd4e1d1095d0a","nc28aeb0785bc","n5cafff4b0bf6","n7039f248bafa",
              "na29bcd07f6bc","nfbc064fa3ee9"}


def fetch(key):
    with urllib.request.urlopen(f"https://note.com/api/v3/notes/{key}", timeout=30) as r:
        return json.load(r)["data"]


def html_to_text(b):
    b = re.sub(r"<(script|style)[^>]*>.*?</\1>", "", b, flags=re.S)
    b = re.sub(r"</(p|h[1-6]|li|blockquote|figure|div)>", "\n", b)
    b = re.sub(r"<br\s*/?>", "\n", b)
    b = re.sub(r"<[^>]+>", "", b)
    t = html.unescape(b)
    lines = [re.sub(r"[ \t　]+", " ", l).strip() for l in t.split("\n")]
    return "\n".join(l for l in lines if l)


def stats(text):
    paras = [p for p in text.split("\n") if p]
    sents = [s for s in re.split(r"(?<=[。！？!?])", text.replace("\n", "")) if s.strip()]
    slen = [len(s) for s in sents]
    return {
        "chars": len(text.replace("\n", "")),
        "paragraphs": len(paras),
        "sentences": len(sents),
        "sent_len_median": statistics.median(slen) if slen else 0,
        "sent_len_p90": sorted(slen)[int(len(slen) * 0.9)] if slen else 0,
        "para_len_median": statistics.median(len(p) for p in paras) if paras else 0,
        "question_marks": text.count("？") + text.count("?"),
        "kuten_ratio": round(text.count("。") / max(1, len(sents)), 2),
        "first_person": {w: text.count(w) for w in ("僕", "私", "俺", "自分")},
        "desu_masu": len(re.findall(r"(です|ます|でした|ました)[。」）\n]", text)),
        "da_dearu": len(re.findall(r"(だ|である|だった)[。」）\n]", text)),
        "dots": text.count("…") + text.count("・・・"),
        "brackets": text.count("（") + text.count("("),
        "numbers": len(re.findall(r"\d+(?:\.\d+)?%?", text)),
    }


def main():
    args = sys.argv[1:]
    skip = "--skip-fetch" in args
    keys = None
    for a in args:
        if a.startswith("--keys"):
            keys = args[args.index(a) + 1].split(",")
    d = yaml.safe_load(open(LEDGER, encoding="utf-8"))
    entries = [e for e in d["entries"] if keys is None or e["key"] in keys]
    report = {}
    for e in entries:
        key = e["key"]
        mag = SHORT if key in SHORT_KEYS or "ショートコラム" in str(e.get("note", "")) else HOWTO
        out = OUT / mag / f"{key}.md"
        out.parent.mkdir(parents=True, exist_ok=True)
        if skip and out.exists():
            text = out.read_text(encoding="utf-8").split("\n---\n", 1)[-1]
        else:
            try:
                data = fetch(key)
            except Exception as ex:  # noqa: BLE001
                report[key] = {"error": type(ex).__name__}
                continue
            body = data.get("body") or ""
            text = html_to_text(body)
            paid = not data.get("can_read", True) or (data.get("price") or 0) > 0
            head = (f"---\nkey: {key}\nmagazine: {mag}\ntitle: {data.get('name','')}\npublished: {str(data.get('publish_at',''))[:10]}\n"
                    f"price: {data.get('price',0)}\ncan_read: {data.get('can_read')}\nlike_count: {data.get('like_count')}\n"
                    f"url: https://note.com/tokyojibika/n/{key}\nfetched: {time.strftime('%Y-%m-%dT%H:%M:%S%z')}\n---\n")
            out.write_text(head + text + "\n", encoding="utf-8")
            time.sleep(0.4)
        st = stats(text)
        st.update({"magazine": mag, "title": e.get("title", "")[:60], "category": e.get("category", "")})
        report[key] = st
    (OUT.parent / "note_stats.json").write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    ok = [k for k, v in report.items() if "error" not in v]
    print(f"fetched={len(ok)} errors={len(report)-len(ok)} short={sum(1 for k in ok if report[k]['magazine']==SHORT)} howto={sum(1 for k in ok if report[k]['magazine']==HOWTO)}")


if __name__ == "__main__":
    main()
