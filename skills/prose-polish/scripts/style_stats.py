#!/usr/bin/env python3
"""style_stats.py — 殿の完成稿と新稿の「形」を同じ計器で測る(prose-polish Step 2.5)。
Usage: python3 style_stats.py <md> [<md> ...]
計るもの: 段落数 / 段落あたり文数 / 1 文段落の比率 / 最大文数 / 横線(---)数 / 空白行(全角スペース)数 /
          文頭「でも」数 / 「」の直後に。がある比率 / 文字数。natural-japanese が見ない「段落の呼吸」を数値にする。
"""
import re, sys

def stats(path):
    s = open(path, encoding="utf-8").read()
    if s.startswith("<!--"):
        s = s.split("\n", 1)[1]
    s = re.sub(r"^#+ .*$", "", s, flags=re.M)
    paras = [x for x in re.split(r"\n\s*\n", s) if x.strip() and x.strip() not in ("---", "　")]
    lens = [len(re.findall(r"[。！？]", x)) or 1 for x in paras]
    quotes_close = len(re.findall(r"」", s))
    quotes_close_maru = len(re.findall(r"」。", s))
    return {
        "file": path.split("/")[-1],
        "chars": len(re.sub(r"\s", "", s)),
        "paras": len(paras),
        "sent_per_para": round(sum(lens) / max(1, len(paras)), 2),
        "single_ratio": round(sum(1 for l in lens if l == 1) / max(1, len(paras)), 2),
        "max_sent": max(lens) if lens else 0,
        "hr": len(re.findall(r"^---$", s, flags=re.M)),
        "spacer": len(re.findall(r"^　$", s, flags=re.M)),
        "demo_lead": len(re.findall(r"(?:^|。)\s*でも", s)),
        "quote_maru_ratio": round(quotes_close_maru / quotes_close, 2) if quotes_close else None,
    }

if __name__ == "__main__":
    rows = [stats(p) for p in sys.argv[1:]]
    keys = list(rows[0].keys())
    print("| " + " | ".join(keys) + " |")
    print("|" + "---|" * len(keys))
    for r in rows:
        print("| " + " | ".join(str(r[k]) for k in keys) + " |")
