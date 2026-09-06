#!/usr/bin/env python3
"""Render layer_holdings_monthly.csv into the Layer Holdings Monthly artifact HTML.

Same layout as docs/dashboard/layer-holdings-wireframe.html (cmd_4481 wireframe,
artifact 27c1995d) but with the real CSV embedded. Usage:

  python3 scripts/layer_holdings_render.py <layer_holdings_monthly.csv> <out.html> \
      --source "<DM-Signal commit / cmd>" --universe "75 PF(L0 12/L1 21/L2 21/L3 21)"

Rows with is_suspect=true (v1.6 CSV) are dropped; the 75 PF CSV has no such column.
"""
import argparse
import csv
import json
import sys
from collections import defaultdict

PALETTE = {
    "XLU": "#5b7fa6", "TQQQ": "#c8553d", "GLD": "#d9a441", "TMV": "#6f8f72",
    "TECL": "#8b5e83", "Cash": "#b9b6ad", "CASH": "#b9b6ad", "DTB3": "#b9b6ad",
    "SPXL": "#3d7a6a", "UPRO": "#a35c8f", "TLT": "#7a8f3d", "TMF": "#4f6d9e",
    "IEF": "#9e7d4f", "SOXL": "#c07a3d", "SPY": "#3d5aa0", "QQQ": "#5f9ea0",
}
EXTRA = ["#8c6d31", "#5254a3", "#ad494a", "#637939", "#7b4173", "#a55194", "#6b6ecf", "#bd9e39"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("out")
    ap.add_argument("--source", default="")
    ap.add_argument("--universe", default="")
    ap.add_argument("--updated", default="")
    a = ap.parse_args()

    rows = []
    with open(a.csv, newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if r.get("is_suspect", "false").lower() == "true":
                continue
            rows.append(r)
    if not rows:
        print("no rows", file=sys.stderr)
        return 1

    layers = ["L0", "L1", "L2", "L3", "ALL"]
    months = sorted({r["year_month"] for r in rows})
    data = {L: {} for L in layers}
    pfc = {L: {} for L in layers}
    tickers = defaultdict(float)
    for r in rows:
        L, m, t = r["layer"], r["year_month"], r["ticker"]
        w = float(r["weight"])
        data.setdefault(L, {}).setdefault(m, {})[t] = round(w, 6)
        pfc.setdefault(L, {})[m] = int(r["pf_count"])
        tickers[t] += w
    order = [t for t, _ in sorted(tickers.items(), key=lambda kv: -kv[1])]
    colors = {}
    k = 0
    for t in order:
        if t in PALETTE:
            colors[t] = PALETTE[t]
        else:
            colors[t] = EXTRA[k % len(EXTRA)]
            k += 1
    mtd = sorted({r["year_month"] for r in rows if r["is_mtd"].lower() == "true"})
    payload = {"layers": layers, "months": months, "data": data, "pf": pfc,
               "tickers": order, "colors": colors, "mtd": mtd,
               "rows": len(rows), "source": a.source, "universe": a.universe, "updated": a.updated}
    legend = "".join(f'<span style="--c:{colors[t]}">{t}</span>' for t in order)

    html = f"""<title>Layer Holdings Monthly</title>
<style>
:root{{--bg:#f6f5f2;--ink:#1f2328;--mute:#6b7076;--line:#d9d6cf;--card:#ffffff;--acc:#2f5d8a;}}
@media (prefers-color-scheme: dark){{:root:not([data-theme="light"]){{--bg:#15181c;--ink:#e8e6e1;--mute:#9aa0a6;--line:#343a40;--card:#1e2227;--acc:#7fa7d1;}}}}
:root[data-theme="dark"]{{--bg:#15181c;--ink:#e8e6e1;--mute:#9aa0a6;--line:#343a40;--card:#1e2227;--acc:#7fa7d1;}}
body{{background:var(--bg);color:var(--ink);font:14px/1.5 -apple-system,"Segoe UI",Roboto,"Noto Sans JP",sans-serif;margin:0;padding:28px 20px 48px}}
main{{max-width:980px;margin:0 auto;display:grid;gap:20px}}
h1{{font-size:20px;margin:0;letter-spacing:.01em}}
.sub{{color:var(--mute);margin:4px 0 0;font-size:13px}}
.badge{{display:inline-block;border:1px solid var(--acc);color:var(--acc);border-radius:4px;padding:1px 8px;font-size:12px;margin-left:8px;vertical-align:middle}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:6px;padding:16px 18px}}
.tabs{{display:flex;gap:6px;flex-wrap:wrap;align-items:center}}
.tab{{border:1px solid var(--line);background:transparent;color:var(--ink);border-radius:4px;padding:5px 12px;cursor:pointer;font:inherit}}
.tab[aria-selected="true"]{{background:var(--acc);border-color:var(--acc);color:#fff}}
.tab:focus-visible{{outline:2px solid var(--acc);outline-offset:2px}}
.range{{margin-left:auto;display:flex;gap:6px}}
.legend{{display:flex;gap:14px;flex-wrap:wrap;color:var(--mute);font-size:12px;margin-top:10px}}
.legend span::before{{content:"";display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:5px;vertical-align:-1px;background:var(--c)}}
.rows{{display:grid;gap:6px;margin-top:14px}}
.row{{display:grid;grid-template-columns:72px 1fr 36px;align-items:center;gap:10px;font-variant-numeric:tabular-nums}}
.row .ym{{color:var(--mute);font-size:12px}}
.row .n{{color:var(--mute);font-size:12px;text-align:right}}
.bar{{display:flex;height:22px;border-radius:3px;overflow:hidden;border:1px solid var(--line)}}
.seg{{display:flex;align-items:center;justify-content:center;font-size:11px;color:#fff;min-width:0;overflow:hidden;white-space:nowrap}}
.mtd{{opacity:.65}}
.mtd .ym::after{{content:" MTD";font-size:10px;color:var(--acc)}}
table{{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums;font-size:13px}}
th,td{{padding:6px 8px;border-bottom:1px solid var(--line);text-align:left}}
th{{color:var(--mute);font-weight:600;font-size:12px;letter-spacing:.04em;text-transform:uppercase}}
td.num,th.num{{text-align:right}}
.tbl{{overflow-x:auto}}
.foot{{color:var(--mute);font-size:12px}}
code{{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px;background:var(--bg);padding:1px 5px;border-radius:3px}}
</style>
<main>
 <header>
  <h1>Layer Holdings Monthly <span class="badge">実値 {a.universe}</span></h1>
  <p class="sub">出力 CSV は 1 本: <code>layer_holdings_monthly.csv</code>(year_month, is_mtd, layer, ticker, weight, pf_count)。下の 2 面はその CSV を pivot しただけの見え方。出所: {a.source}{(' / 更新 ' + a.updated) if a.updated else ''}。行数 {len(rows)}。</p>
 </header>
 <section class="card">
  <div class="tabs" role="tablist" id="tabs"></div>
  <div class="legend">{legend}<span style="margin-left:auto">右端の数字 = pf_count(その月に展開できた PF 数)</span></div>
  <div class="rows" id="rows"></div>
 </section>
 <section class="card">
  <p class="sub" style="margin:0 0 10px">面 2: CSV そのまま(選択中の layer、直近 3 ヶ月)</p>
  <div class="tbl"><table>
   <thead><tr><th>year_month</th><th>is_mtd</th><th>layer</th><th>ticker</th><th class="num">weight</th><th class="num">pf_count</th></tr></thead>
   <tbody id="tbody"></tbody>
  </table></div>
 </section>
 <p class="foot">各 (year_month, layer) で weight 合計 = 1.0。ALL は {a.universe} の単純平均(1 PF = 1 票)。is_mtd=true の月は薄く表示。入力は基盤 F1 <code>holdings_monthly.csv</code> のみで、DB 接続・展開・パラメータは持たない。</p>
</main>
<script>
(function(){{
 const D={json.dumps(payload, ensure_ascii=False)};
 const tabs=document.getElementById("tabs"),rows=document.getElementById("rows"),tbody=document.getElementById("tbody");
 let cur="ALL",span=12;
 function render(){{
  tabs.innerHTML="";
  for(const L of D.layers){{
   const b=document.createElement("button");b.className="tab";b.setAttribute("role","tab");b.textContent=L+(L==="ALL"?" (全体)":"");
   b.setAttribute("aria-selected",L===cur);b.onclick=()=>{{cur=L;render();}};tabs.appendChild(b);
  }}
  const rg=document.createElement("div");rg.className="range";
  for(const s of [12,36,0]){{
   const b=document.createElement("button");b.className="tab";b.textContent=s===0?"全期間":s+"ヶ月";
   b.setAttribute("aria-selected",s===span);b.onclick=()=>{{span=s;render();}};rg.appendChild(b);
  }}
  tabs.appendChild(rg);
  const ms=D.months.filter(m=>D.data[cur]&&D.data[cur][m]);
  const shown=span?ms.slice(-span):ms;
  rows.innerHTML="";
  shown.forEach(m=>{{
   const w=D.data[cur][m],isM=D.mtd.includes(m);
   const r=document.createElement("div");r.className="row"+(isM?" mtd":"");
   const bar=D.tickers.filter(t=>w[t]>0).map(t=>`<div class="seg" style="width:${{(w[t]*100).toFixed(2)}}%;background:${{D.colors[t]}}" title="${{t}} ${{(w[t]*100).toFixed(1)}}%">${{w[t]>=0.12?t+" "+Math.round(w[t]*100)+"%":""}}</div>`).join("");
   r.innerHTML=`<div class="ym">${{m}}</div><div class="bar">${{bar}}</div><div class="n">${{D.pf[cur][m]}}</div>`;
   rows.appendChild(r);
  }});
  tbody.innerHTML="";
  ms.slice(-3).forEach(m=>{{
   const w=D.data[cur][m];
   D.tickers.filter(t=>w[t]>0).forEach(t=>{{
    const tr=document.createElement("tr");
    tr.innerHTML=`<td>${{m}}</td><td>${{D.mtd.includes(m)}}</td><td>${{cur}}</td><td>${{t}}</td><td class="num">${{w[t].toFixed(4)}}</td><td class="num">${{D.pf[cur][m]}}</td>`;
    tbody.appendChild(tr);
   }});
  }});
 }}
 render();
}})();
</script>
"""
    with open(a.out, "w", encoding="utf-8") as fh:
        fh.write(html)
    print(f"rows={len(rows)} months={len(months)} tickers={len(order)} out={a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
