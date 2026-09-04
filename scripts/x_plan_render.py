#!/usr/bin/env python3
"""Stage 1 編集計画 artifact(殿 19:28 §24/§25)。plan_202609.yaml → docs/dashboard/x-editorial-plan-202609.html。本文生成前に『なぜこの日にこれを言うか』を殿が見る"""
import html, datetime as dt
from pathlib import Path
import yaml
ROOT = Path(__file__).resolve().parents[1]
D = yaml.safe_load((ROOT / "skills/x-post-pipeline/plan_202609.yaml").read_text(encoding="utf-8")); M, P = D["meta"], D["plan"]
B = {c["key"]: c for c in yaml.safe_load((ROOT / "skills/x-post-pipeline/claim_bank.yaml").read_text(encoding="utf-8"))["claims"]}
EV = yaml.safe_load((ROOT / "skills/x-post-pipeline/event_rules.yaml").read_text(encoding="utf-8"))
CAT = {"A": "常識を壊す", "B": "DM 啓蒙", "C": "検証至上", "D": "数学小ネタ", "E": "そこまで疑うか", "F": "DM-Signal 実績", "G": "直接誘導"}
st = M["stats"]; rows = ""
for p in P:
    wd = "月火水木金土日"[dt.date.fromisoformat(p["date"]).weekday()]
    if p["status"] == "empty":
        rows += f'<tr class="empty"><td class="d">{p["date"][5:]} {wd}<br><span class="t">{p["time"]}</span></td><td><span class="fmt f-{p["format"]}">{p["format"]}</span></td><td colspan="7" class="mute">空き — {html.escape(p["reason"])}</td></tr>'; continue
    c = B[p["claim"]]
    ev = f'<div class="ev">📅 {html.escape(p["event"])}</div>' if p.get("event") else ""
    reuse = f'<div class="reuse">↺ {html.escape(p["reuse_reason"])}</div>' if p.get("reuse_of") else ""
    ser = f'<div class="ser">{html.escape(p["series_title"])} {p["series_order"]}/{p["series_total"]}</div>' if p.get("series_id") else ""
    rows += (f'<tr><td class="d">{p["date"][5:]} {wd}<br><span class="t">{p["time"]}</span>{ev}</td>'
             f'<td><span class="fmt f-{p["format"]}">{p["format"]}</span>{ser}</td>'
             f'<td><b>{p["claim"]}</b><div class="claim">{html.escape(c["claim"])}</div><div class="belief">壊す前提: {html.escape(c["belief"])}</div>{reuse}</td>'
             f'<td><span class="org o-{c["origin"]}">{c["origin"]}</span></td><td>{p["content_category"]} <span class="mute">{CAT[p["content_category"]]}</span></td>'
             f'<td class="stage s-{p["funnel_stage"]}">{p["funnel_stage"]}</td><td>{p["audience"]}</td><td>{p["hook_type"]}</td>'
             f'<td class="why">{html.escape(p.get("why_this_day", ""))}{("<div class=ctx>" + html.escape(p["context"]) + "</div>") if p.get("context") else ""}</td></tr>')
evrows = "".join(f'<li><b>{e["date"]}</b> {html.escape(e["name"])} → claim 候補 {", ".join(e["claims"])}<span class="mute"> {html.escape(e["note"])}</span></li>' for e in EV["scheduled_events"])
intra = "".join(f'<li><b>{t["id"]}</b> {html.escape(t["rule"])} → {", ".join(t["claims"])}</li>' for t in EV.get("intraday_triggers", []))
topics = "".join(f'<li><b>{t["id"]}</b> <code>{html.escape(t["query"])}</code> → {", ".join(t["claims"])}</li>' for t in EV.get("topic_triggers", []))
trig = "".join(f'<li><b>{t["id"]}</b> {html.escape(t["rule"])} → {", ".join(t["claims"])} ({t["format"]}×{t["funnel_stage"]}×{t["content_category"]})</li>' for t in EV["reactive_triggers"])
def kv(d): return " / ".join(f"{k} {v}" for k, v in d.items())
page = f"""<title>X 編集計画 2026 年 9 月</title>
<style>
:root{{--bg:#f7f6f2;--ink:#1f2328;--mute:#6b7280;--line:#dcd9d0;--card:#fff;--s:#2f6f9f;--l:#8a5a2b;--t:#5b6b2f;--e:#7a3e7a;--reach:#2f6f9f;--follow:#7a3e7a;--trust:#1f7a4d;--ext:#b45309}}
@media (prefers-color-scheme:dark){{:root:not([data-theme=light]){{--bg:#15171a;--ink:#e8e6e0;--mute:#9aa0a6;--line:#2c3138;--card:#1d2126;--s:#7fb3dc;--l:#d9a06b;--t:#a9c06a;--e:#c48ac4;--reach:#7fb3dc;--follow:#c48ac4;--trust:#6fcf97;--ext:#f0b060}}}}
:root[data-theme=dark]{{--bg:#15171a;--ink:#e8e6e0;--mute:#9aa0a6;--line:#2c3138;--card:#1d2126;--s:#7fb3dc;--l:#d9a06b;--t:#a9c06a;--e:#c48ac4;--reach:#7fb3dc;--follow:#c48ac4;--trust:#6fcf97;--ext:#f0b060}}
body{{background:var(--bg);color:var(--ink);font-family:"Hiragino Sans","Noto Sans JP",system-ui,sans-serif;padding:20px;line-height:1.5}}
h1{{font-size:20px;margin:0 0 4px;text-wrap:balance}} h2{{font-size:15px;margin:22px 0 8px}} .sub{{color:var(--mute);font-size:13px;margin:0 0 12px}}
.stats{{display:flex;gap:10px;flex-wrap:wrap;margin:10px 0 16px}} .stat{{background:var(--card);border:1px solid var(--line);border-radius:6px;padding:8px 12px;font-size:12px;color:var(--mute)}} .stat b{{display:block;font-size:20px;color:var(--ink);font-variant-numeric:tabular-nums}}
.wrap{{overflow-x:auto}} table{{border-collapse:collapse;width:100%;font-size:12.5px;background:var(--card)}} th,td{{border-bottom:1px solid var(--line);padding:7px 8px;vertical-align:top;text-align:left}} th{{font-size:11px;letter-spacing:.04em;color:var(--mute);text-transform:uppercase;position:sticky;top:0;background:var(--card)}}
td.d{{white-space:nowrap;font-variant-numeric:tabular-nums}} .t{{color:var(--mute);font-size:11px}} tr.empty td{{background:color-mix(in srgb,var(--card) 90%,var(--line))}} .mute{{color:var(--mute)}}
.fmt{{font-weight:600;font-size:11px;letter-spacing:.04em}} .f-short{{color:var(--s)}} .f-long{{color:var(--l)}} .f-thread{{color:var(--t)}} .f-series_entry{{color:var(--e)}}
.claim{{font-size:12.5px}} .belief{{font-size:11px;color:var(--mute)}} .reuse{{font-size:11px;color:var(--l)}} .ser{{font-size:11px;color:var(--e)}} .ev{{font-size:11px;color:var(--ext);white-space:normal}}
.org{{font-size:10px;border:1px solid var(--line);border-radius:8px;padding:0 6px}} .o-external_topic{{color:var(--ext);border-color:var(--ext)}}
.stage{{font-weight:600}} .s-reach{{color:var(--reach)}} .s-follow{{color:var(--follow)}} .s-trust{{color:var(--trust)}}
.why{{font-size:11.5px;min-width:200px}} .ctx{{color:var(--mute);font-size:11px;margin-top:2px}}
ul{{font-size:12.5px;padding-left:18px}} li{{margin:3px 0}}
</style>
<h1>X 編集計画 2026 年 9 月(Stage 1: 何を・いつ・誰に・何の目的で・どの形式で)</h1>
<p class="sub">本文はまだ作りません。この計画を殿が承認してから本文生成→Fact/Voice gate→本文承認(Stage 2)→scheduled のみ投稿。52 枠は capacity で quota ではありません。空きは正常。生成 {M["generated"]}・承認状態 Stage 1 = {M["approval"]["stage1_editorial"]}</p>
<div class="stats"><div class="stat">capacity<b>{st["capacity"]}</b></div><div class="stat">scheduled<b>{st["scheduled"]}</b></div><div class="stat">empty<b>{st["empty"]}</b></div><div class="stat">unique claims<b>{st["unique_claims"]}</b></div><div class="stat">reused<b>{st["reused_claims"]}</b></div>
<div class="stat">format<b style="font-size:12px">{kv(st["by_format"])}</b></div><div class="stat">funnel<b style="font-size:12px">{kv(st["by_stage"])}</b></div><div class="stat">category<b style="font-size:12px">{kv(st["by_category"])}</b></div><div class="stat">origin<b style="font-size:12px">{kv(st["by_origin"])}</b></div></div>
<div class="wrap"><table><thead><tr><th>日時</th><th>Format</th><th>Claim</th><th>Origin</th><th>Category</th><th>Funnel</th><th>Audience</th><th>Hook</th><th>なぜこの日に言うか</th></tr></thead><tbody>{rows}</tbody></table></div>
<h2>イベント lane(計画の上に重ねる。claim は増やさない)</h2>
<p class="sub">予定イベントは event 欄に事前登録。突発イベントは毎朝 07:05 に価格データ(yfinance)で数値規則だけで検知し、提案→本文生成→gate→殿承認→当日 12:30 の event slot か空き slot で投稿。1 日 1 unit、同一 claim は 7 日再発火しない。相場予測はしない。</p>
<ul>{evrows}</ul>
<p class="sub">日次(07:05、前日終値): </p><ul>{trig}</ul>
<p class="sub">日中(30 分ごと、yfinance 5 分足=ほぼ実時間。殿 19:48『為替はリアルタイムじゃないと変』): </p><ul>{intra}</ul>
<p class="sub">要人発言・話題(毎時、X API 投稿数が 7 日中央値の 3 倍かつ 200 以上で発火。発言は context にだけ使い引用・要約投稿はしない): </p><ul>{topics}</ul>
"""
out = ROOT / "docs/dashboard/x-editorial-plan-202609.html"; out.write_text(page, encoding="utf-8"); print("bytes", out.stat().st_size)
