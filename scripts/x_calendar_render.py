#!/usr/bin/env python3
"""plan_202609.yaml + queue/x_drafts/*P9-* → docs/dashboard/x-post-calendar-202609.html(月間カレンダー、各 slot に本文)。殿 2026-09-04 19:16"""
import datetime as dt, html, re, glob, os
from pathlib import Path
import yaml
ROOT = Path(__file__).resolve().parents[1]
PLAN = yaml.safe_load((ROOT / "skills/x-post-pipeline/plan_202609.yaml").read_text(encoding="utf-8"))
BANK = {c["key"]: c for c in yaml.safe_load((ROOT / "skills/x-post-pipeline/claim_bank.yaml").read_text(encoding="utf-8"))["claims"]}
OUT = ROOT / "docs/dashboard/x-post-calendar-202609.html"
FMT = {"short": ("Short", "s"), "long": ("Long", "l"), "thread": ("Thread", "t"), "series_entry": ("Series", "e")}


def body(did, fmt):
    fs = sorted(glob.glob(str(ROOT / f"queue/x_drafts/*_{did}.txt")))
    if fmt == "thread":
        fs = sorted(glob.glob(str(ROOT / f"queue/x_drafts/*_{did}-P.txt"))) + sorted(glob.glob(str(ROOT / f"queue/x_drafts/*_{did}-R*.txt")))
    if not fs: return None
    parts = [Path(f).read_text(encoding="utf-8").strip() for f in fs]
    approved = any(os.path.exists(f[:-4] + ".approved") for f in fs)
    return parts, approved


days = sorted({p["date"] for p in PLAN["plan"]})
first = dt.date.fromisoformat(days[0]); last = dt.date.fromisoformat(days[-1])
by = {}
for p in PLAN["plan"]: by.setdefault(p["date"], []).append(p)
cells = []; stats = {"gen": 0, "todo": 0, "approved": 0}
# 月グリッド(月曜始まり)
start = first - dt.timedelta(days=first.weekday())
d = start
while d <= last:
    if d < first:
        cells.append(f'<div class="day pad"></div>')
    else:
        items = ""
        for p in sorted(by.get(d.isoformat(), []), key=lambda x: x["time"]):
            name, cls = FMT[p["format"]]; c = BANK.get(p["claim"]) if p["claim"] else None
            b = body(p["draft_id"], p["format"]) if p["draft_id"] else None
            if b:
                parts, ap = b; stats["gen"] += 1; stats["approved"] += ap
                txt = "".join(f'<p class="post">{html.escape(x).replace(chr(10), "<br>")}</p>' + ('<p class="rep">↳ 自己リプ</p>' if i < len(parts) - 1 else "") for i, x in enumerate(parts))
                st = '<span class="st ok">承認済</span>' if ap else '<span class="st">未承認</span>'
            else:
                stats["todo"] += 1; txt = '<p class="post muted">生成中 / 未生成</p>'; st = '<span class="st">—</span>'
            ser = f' <span class="ser">{html.escape(p["series_title"])} {p["series_order"]}/{p["series_total"]}</span>' if p.get("series_id") else ""
            claim = f'<div class="claim"><b>{p["claim"]}</b> {html.escape(c["claim"])}<span class="origin">{c["origin"]}</span></div>' if c else '<div class="claim muted">適切な claim なし → SKIP</div>'
            items += f'<div class="slot {cls}"><div class="head"><span class="time">{p["time"]}</span><span class="fmt">{name}</span>{ser}{st}</div>{claim}{txt}</div>'
        wk = "土日"[d.weekday() - 5] if d.weekday() >= 5 else ""
        cells.append(f'<div class="day{" we" if wk else ""}"><div class="dnum">{d.day}<span class="wd">{"月火水木金土日"[d.weekday()]}</span></div>{items}</div>')
    d += dt.timedelta(days=1)
while len(cells) % 7: cells.append('<div class="day pad"></div>')
gen_at = dt.datetime.now().strftime("%Y-%m-%d %H:%M")
page = f"""<title>X 投稿カレンダー 2026 年 9 月</title>
<style>
:root{{--bg:#f7f6f2;--ink:#1f2328;--mute:#6b7280;--line:#dcd9d0;--card:#fff;--s:#2f6f9f;--l:#8a5a2b;--t:#5b6b2f;--e:#7a3e7a;--ok:#1f7a4d;--okbg:#e4f3ea}}
@media (prefers-color-scheme:dark){{:root:not([data-theme=light]){{--bg:#15171a;--ink:#e8e6e0;--mute:#9aa0a6;--line:#2c3138;--card:#1d2126;--s:#7fb3dc;--l:#d9a06b;--t:#a9c06a;--e:#c48ac4;--ok:#6fcf97;--okbg:#1d3a2b}}}}
:root[data-theme=dark]{{--bg:#15171a;--ink:#e8e6e0;--mute:#9aa0a6;--line:#2c3138;--card:#1d2126;--s:#7fb3dc;--l:#d9a06b;--t:#a9c06a;--e:#c48ac4;--ok:#6fcf97;--okbg:#1d3a2b}}
body{{background:var(--bg);color:var(--ink);font-family:"Hiragino Sans","Noto Sans JP",system-ui,sans-serif;padding:20px;line-height:1.55}}
h1{{font-size:20px;margin:0 0 4px;text-wrap:balance}} .sub{{color:var(--mute);font-size:13px;margin:0 0 14px}}
.legend{{display:flex;gap:14px;flex-wrap:wrap;font-size:12px;color:var(--mute);margin-bottom:14px}} .legend i{{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px;vertical-align:middle}}
.grid{{display:grid;grid-template-columns:repeat(7,minmax(150px,1fr));gap:8px;overflow-x:auto}}
.day{{background:var(--card);border:1px solid var(--line);border-radius:6px;padding:8px;min-height:80px}} .day.pad{{background:transparent;border-color:transparent}} .day.we{{background:color-mix(in srgb,var(--card) 92%,var(--line))}}
.dnum{{font-weight:600;font-size:14px;margin-bottom:6px}} .wd{{color:var(--mute);font-weight:400;font-size:11px;margin-left:4px}}
.slot{{border-left:3px solid var(--mute);padding:4px 0 4px 8px;margin:6px 0}} .slot.s{{border-color:var(--s)}} .slot.l{{border-color:var(--l)}} .slot.t{{border-color:var(--t)}} .slot.e{{border-color:var(--e)}}
.head{{display:flex;gap:6px;align-items:center;flex-wrap:wrap;font-size:11px}} .time{{font-variant-numeric:tabular-nums;color:var(--mute)}} .fmt{{font-weight:600;letter-spacing:.04em;text-transform:uppercase}}
.s .fmt{{color:var(--s)}} .l .fmt{{color:var(--l)}} .t .fmt{{color:var(--t)}} .e .fmt{{color:var(--e)}}
.ser{{color:var(--e)}} .st{{margin-left:auto;color:var(--mute)}} .st.ok{{color:var(--ok);background:var(--okbg);padding:0 6px;border-radius:8px}}
.claim{{font-size:11px;color:var(--mute);margin:3px 0}} .claim b{{color:var(--ink)}} .origin{{margin-left:6px;font-size:10px;border:1px solid var(--line);border-radius:8px;padding:0 5px}}
.post{{font-size:12.5px;margin:4px 0;white-space:normal}} .rep{{font-size:10px;color:var(--mute);margin:0}} .muted{{color:var(--mute)}}
</style>
<h1>X 投稿カレンダー 2026 年 9 月(9/5〜9/30)</h1>
<p class="sub">claim_bank 起点で全 unit を作り直した版。生成 {stats["gen"]}/{len(PLAN["plan"])}、承認済 {stats["approved"]}、未生成 {stats["todo"]}。承認するまで cron は投稿しません(fallback なし)。更新 {gen_at}</p>
<div class="legend"><span><i style="background:var(--s)"></i>Short 08:30</span><span><i style="background:var(--e)"></i>Series Entry 18:30</span><span><i style="background:var(--l)"></i>Long 18:30</span><span><i style="background:var(--t)"></i>Thread 18:30</span><span>origin: existing_user_thesis=本人の既存思想 / external_topic=外部で話題(ext_gate A-E 通過)</span></div>
<div class="grid">{"".join(cells)}</div>
"""
OUT.write_text(page, encoding="utf-8"); print(f"gen={stats['gen']} approved={stats['approved']} todo={stats['todo']} bytes={OUT.stat().st_size}")
