#!/usr/bin/env python3
"""docs/research/x_post_drafts_round1_20260904.md → docs/dashboard/x-post-drafts-round1.html

殿指示 2026-09-04 11:40『x_post_drafts_round1 は artifact にしてくれ、そのほうがやり取りが早い』。
md が正本。本 script は表示専用(枠ごとに X 投稿風のカードで並べ、字数と URL を分けて見せる)。
Usage: python3 scripts/x_drafts_render.py [md] [html]
"""
import html
import re
import sys
import unicodedata
from datetime import datetime
from pathlib import Path

MD = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/research/x_post_drafts_round1_20260904.md")
OUT = Path(sys.argv[2] if len(sys.argv) > 2 else "docs/dashboard/x-post-drafts-round1.html")
TITLE = sys.argv[3] if len(sys.argv) > 3 else "バム X 下書き 第 1 巡"


def width(s: str) -> float:
    w = 0.0
    for ch in s:
        w += 1.0 if unicodedata.east_asian_width(ch) in ("W", "F", "A") else 0.5
    return w


text = MD.read_text(encoding="utf-8")
lines = [l for l in text.split("\n") if not l.startswith("<!--")]
head, sections, cur = [], [], None
post_re = re.compile(r"^(★?)((?:R\d+-)?[A-Z]{1,2})-(\d+(?:-[PR]\d?)?)\s*(.*)$")  # 2026-09-04 Round5: R5-S-1 / R5-T-1-P / R5-SE-2 も受ける
i = 0
while i < len(lines):
    l = lines[i]
    if l.startswith("## "):
        cur = {"title": l[3:].strip(), "posts": [], "notes": []}
        sections.append(cur)
    elif cur is None:
        if l.strip() and not l.startswith("# "):
            head.append(l.strip())
    else:
        m = post_re.match(l)
        if m:
            pid = f"{m.group(2)}-{m.group(3)}"; label = (("★ " if m.group(1) else "") + m.group(4)).strip()
            body, urls, figs = [], [], []
            i += 1
            while i < len(lines) and not post_re.match(lines[i]) and not lines[i].startswith("## ") and not lines[i].startswith("---"):
                s = lines[i].strip()
                if not s:
                    # 空行=段落区切り(投稿内の改行として保持)。次の非空行が post/section なら終了
                    j = i + 1
                    while j < len(lines) and not lines[j].strip():
                        j += 1
                    if j >= len(lines) or post_re.match(lines[j]) or lines[j].startswith("## ") or lines[j].startswith("---"):
                        break
                    body.append(""); i += 1; continue
                (urls if s.startswith("http") else (figs if s.startswith(("図:", "source_x:")) else body)).append(s)
                i += 1
            cur["posts"].append({"id": pid, "label": label, "body": "\n".join(body), "urls": urls, "figs": figs})
            continue
        elif l.strip() and l.strip() != "---":
            cur["notes"].append(l.strip())
    i += 1

now = datetime.now().strftime("%Y-%m-%d %H:%M")
h = html.escape
parts = []
parts.append(f"""<title>{h(TITLE)}</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Noto+Serif+JP:wght@600;700&family=BIZ+UDPGothic:wght@400;700&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
:root{{--ground:#f1f3f4;--panel:#ffffff;--ink:#181c20;--ink2:#495159;--ink3:#7a838c;--line:#d3d9de;--accent:#0f5f66;--accent-soft:#dfeeef;--warn:#9a5b12;--warn-soft:#f6ead6;--url:#2c5fa8}}
@media (prefers-color-scheme:dark){{:root:not([data-theme="light"]){{--ground:#121517;--panel:#1a1e22;--ink:#e8e6e1;--ink2:#b3b9c0;--ink3:#7f8790;--line:#2e353b;--accent:#6fc2c8;--accent-soft:#1d3235;--warn:#e0a24f;--warn-soft:#3a2c14;--url:#8db4ee}}}}
:root[data-theme="dark"]{{--ground:#121517;--panel:#1a1e22;--ink:#e8e6e1;--ink2:#b3b9c0;--ink3:#7f8790;--line:#2e353b;--accent:#6fc2c8;--accent-soft:#1d3235;--warn:#e0a24f;--warn-soft:#3a2c14;--url:#8db4ee}}
*{{box-sizing:border-box;min-width:0}}
html,body{{max-width:100%;overflow-x:hidden}}
body{{margin:0;padding:1.4rem 1rem 3rem;background:var(--ground);color:var(--ink);font-family:"BIZ UDPGothic","Hiragino Sans",system-ui,sans-serif;font-size:.97rem;line-height:1.75}}
.wrap{{max-width:44rem;margin:0 auto;display:flex;flex-direction:column;gap:1.4rem}}
h1{{font-family:"Noto Serif JP","Hiragino Mincho ProN",serif;font-weight:700;font-size:1.6rem;margin:0;letter-spacing:.02em;text-wrap:balance}}
.eyebrow{{font-family:"IBM Plex Mono",monospace;font-size:.7rem;letter-spacing:.12em;text-transform:uppercase;color:var(--ink3);margin:0 0 .3rem}}
.lead{{color:var(--ink2);font-size:.86rem;margin:.4rem 0 0;max-width:62ch}}
.lead p{{margin:.2rem 0}}
nav{{display:flex;flex-wrap:wrap;gap:.4rem}}
nav a{{font-family:"IBM Plex Mono",monospace;font-size:.78rem;color:var(--accent);background:var(--accent-soft);padding:.15rem .55rem;border-radius:.25rem;text-decoration:none}}
section{{display:flex;flex-direction:column;gap:.7rem}}
h2{{font-family:"Noto Serif JP",serif;font-weight:600;font-size:1.12rem;margin:.6rem 0 0;padding-bottom:.35rem;border-bottom:2px solid var(--accent);text-wrap:balance}}
.def{{color:var(--ink2);font-size:.84rem;margin:0;max-width:66ch}}
.post{{background:var(--panel);border:1px solid var(--line);border-radius:.5rem;padding:.8rem .95rem .7rem;display:flex;flex-direction:column;gap:.4rem}}
.post .head{{display:flex;align-items:baseline;gap:.6rem;flex-wrap:wrap}}
.pid{{font-family:"IBM Plex Mono",monospace;font-weight:500;font-size:.82rem;color:var(--accent);background:var(--accent-soft);padding:.05rem .45rem;border-radius:.25rem}}
.label{{font-size:.84rem;color:var(--ink2)}}
.count{{margin-left:auto;font-family:"IBM Plex Mono",monospace;font-size:.72rem;color:var(--ink3);font-variant-numeric:tabular-nums}}
.count.over{{color:var(--warn);background:var(--warn-soft);padding:0 .35rem;border-radius:.2rem}}
.body{{margin:0;white-space:pre-wrap;font-size:1rem;line-height:1.8}}
.url{{margin:0;font-family:"IBM Plex Mono",monospace;font-size:.76rem;color:var(--url);word-break:break-all}}
.note{{color:var(--ink3);font-size:.8rem;margin:0}}
footer{{color:var(--ink3);font-size:.74rem;font-family:"IBM Plex Mono",monospace}}
a:focus-visible{{outline:2px solid var(--accent);outline-offset:2px}}
@media (max-width:40rem){{body{{padding:.9rem .7rem 2.5rem}}.count{{margin-left:0;flex-basis:100%}}}}
</style>
<div class="wrap">
<header>
<p class="eyebrow">bam · x drafts · {h(now)}</p>
<h1>{h(TITLE)}</h1>
<div class="lead">{''.join(f'<p>{h(x)}</p>' for x in head)}
<p>字数は全角換算(URL を除く)。140 を超える行は色で示す。直しはこのページのコメントで。正本は docs/research/x_post_drafts_round1_20260904.md。</p></div>
<nav>{''.join(f'<a href="#s{n}">{h(s["title"].split("(")[0].strip())}</a>' for n,s in enumerate(sections))}</nav>
</header>""")
for n, s in enumerate(sections):
    parts.append(f'<section id="s{n}"><h2>{h(s["title"].split("(")[0].strip())}</h2>')
    rest = s["title"][len(s["title"].split("(")[0]):].strip()
    if rest:
        parts.append(f'<p class="def">{h(rest.strip("()"))}</p>')
    for p in s["posts"]:
        w = width(p["body"].replace("\n", ""))
        over = " over" if w > 140 else ""
        parts.append(f'<article class="post" id="{p["id"]}"><div class="head"><span class="pid">{p["id"]}</span><span class="label">{h(p["label"])}</span><span class="count{over}">{w:.0f} 字</span></div><p class="body">{h(p["body"])}</p>{"".join(f"<p class=url>{h(u)}</p>" for u in p["urls"])}{"".join(f"<p class=note>{h(f)}</p>" for f in p.get("figs",[]))}</article>')
    for nt in s["notes"]:
        parts.append(f'<p class="note">{h(nt)}</p>')
    parts.append("</section>")
parts.append(f'<footer>rendered {h(now)} · 正本 md → scripts/x_drafts_render.py · gist 196943087ca81493731a7eaf4e95b6b1</footer></div>')
OUT.write_text("\n".join(parts), encoding="utf-8")
print(f"sections={len(sections)} posts={sum(len(s['posts']) for s in sections)} bytes={OUT.stat().st_size}")
