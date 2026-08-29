#!/usr/bin/env python3
"""queue/shogun_todo_map.md(正本) から docs/dashboard/shogun-todo-map.html を全文生成する(パッチ型を廃止 2026-08-29 01:20 殿指示『レスポンシブ崩れ・冗長→再構築』)。
usage: python3 scripts/todo_map_render.py "<更新ラベル>" [現況ファイル(md 箇条書き、任意)]
  → 生成後に md↔HTML の ID 集合一致を検証し不一致なら exit 2
設計: 走行中/未着手=現在値 1 行(先頭セグメント)+終端条件+★1 行、全経緯は details。済=1 行(ID/件名/解決時刻)。
      grid 列指定なし(block/flex のみ)、表は自コンテナで横スクロール、文字単位折返しなし。40rem 幅で縦並び 0 が公開条件。"""
import re, sys, html, subprocess, statistics, datetime

MD = 'queue/shogun_todo_map.md'
H = 'docs/dashboard/shogun-todo-map.html'
label = sys.argv[1] if len(sys.argv) > 1 else ''
now_path = sys.argv[2] if len(sys.argv) > 2 else 'docs/dashboard/shogun-todo-map.now.md'
s = open(MD).read()

subprocess.run([sys.executable, 'scripts/todo_map_timestamps.py'], check=True, capture_output=True)
TS = {}
for ln in open('queue/shogun_todo_map_timestamps.tsv').read().splitlines():
    if ln.startswith('#') or ln.startswith('id\t'):
        continue
    c = ln.split('\t')
    TS[c[0]] = dict(st=c[1], reg=c[2], start=c[3], res=c[4], ls=c[5], lr=c[6], reopen=c[7])

NOW = datetime.datetime.now().astimezone()

def hm(iso):
    return iso[5:16].replace('T', ' ') if iso else '—'

def dur(m):
    if m == '':
        return '—'
    m = int(m)
    return f'{m // 60}h{m % 60:02d}m' if m >= 60 else f'{m}m'

def since(iso):
    return dur(str(int((NOW - datetime.datetime.fromisoformat(iso)).total_seconds() // 60)))

rows = [dict(st=m.group(1), id=m.group(2), ev=m.group(3), title=m.group(4), why=m.group(5))
        for m in re.finditer(r'^- \[(.)\] (T\d+[a-z]?|K\d+)\((.*?)\) (.*?) ★(.*)$', s, re.M)]
cnt = {k: sum(1 for r in rows if r['st'] == k) for k in 'x~ '}

def segs(ev):
    return [x.strip() for x in ev.split('; ') if x.strip()]

def terminal(ev):
    m = re.search(r'終端条件=([^;]{1,220})', ev)
    return m.group(1).strip() if m else ''

def clip(x, n):
    return x if len(x) <= n else x[:n].rstrip() + '…'

def e(x):
    return html.escape(x)

def ts_open(i):
    x = TS.get(i)
    if not x:
        return ''
    if x['start']:
        return f'着手 {hm(x["start"])} · 経過 {since(x["start"])}'
    return f'登録 {hm(x["reg"])} · 未着手 {since(x["reg"])}'

def row_open(r, cls):
    sg = segs(r['ev'])
    head = clip(sg[0], 260) if sg else ''
    term = terminal(r['ev'])
    rest = sg[1:]
    det = ''
    if rest:
        det = f'<details><summary>経緯 +{len(rest)}</summary><p>{e("; ".join(rest))}</p></details>'
    tline = f'<p class="term"><b>終端</b> {e(clip(term, 200))}</p>' if term else ''
    return (f'<article class="item {cls}">'
            f'<p class="head"><span class="id">{r["id"]}</span><span class="title">{e(clip(r["title"], 90))}</span></p>'
            f'<p class="now">{e(head)}</p>{tline}'
            f'<p class="why">★ {e(clip(r["why"], 120))}</p>'
            f'<p class="meta">{e(ts_open(r["id"]))}</p>{det}</article>')

def row_done(r):
    x = TS.get(r['id'], {})
    sg = segs(r['ev'])
    first = e(clip(sg[0], 200)) if sg else ''
    return (f'<li><span class="id">{r["id"]}</span><span class="title">{e(clip(r["title"], 70))}</span>'
            f'<span class="when">{hm(x.get("res", ""))}</span>'
            f'<details><summary>証跡</summary><p>{first}</p></details></li>')

run_rows = [r for r in rows if r['st'] == '~']
todo_rows = [r for r in rows if r['st'] == ' ']
done_rows = [r for r in rows if r['st'] == 'x'][::-1]

# 済は解決日で束ねる(1 行/件)
groups = {}
for r in done_rows:
    d = (TS.get(r['id'], {}).get('res') or '')[:10] or '日付なし'
    groups.setdefault(d, []).append(r)
done_html = ''.join(
    f'<details class="day" {"open" if i == 0 else ""}><summary>{e(d)} <span class="n">{len(v)}</span></summary><ul class="done">'
    + ''.join(row_done(r) for r in v) + '</ul></details>'
    for i, (d, v) in enumerate(sorted(groups.items(), reverse=True)))

# 回転 3TS
ls = [int(x['ls']) for x in TS.values() if x['ls'] != '']
lr = [int(x['lr']) for x in TS.values() if x['lr'] != '']
open_wait = [i for i, x in TS.items() if x['st'] == ' ' and (NOW - datetime.datetime.fromisoformat(x['reg'])).total_seconds() > 7200]

# 現況(任意: 将軍が loop 毎に 5 行以内で更新する md。無ければ節を出さない)
now_html = ''
try:
    lines = [l.strip()[2:] for l in open(now_path).read().splitlines() if l.strip().startswith('- ')]
    if lines:
        now_html = '<section class="now-box"><h2>現況 <span class="n">' + e(label) + '</span></h2><ul>' + ''.join(f'<li>{e(l)}</li>' for l in lines[:8]) + '</ul></section>'
except FileNotFoundError:
    pass

def tile(k, v, cls, sub):
    return f'<div class="tile"><span class="k">{k}</span><span class="v {cls}">{v}</span><span class="s">{e(sub)}</span></div>'

tiles = ''.join([
    tile('走行中', cnt['~'], 'run', ' / '.join(r['id'] for r in run_rows)),
    tile('未着手', cnt[' '], 'todo', ' / '.join(r['id'] for r in todo_rows) or 'なし'),
    tile('済', cnt['x'], 'done', 'md 正本の [x] 実数'),
    tile('着手→解決', dur(str(int(statistics.median(lr)))) if lr else '—', 'run', f'中央値 n={len(lr)} · 登録→着手 {dur(str(int(statistics.median(ls)))) if ls else "—"}'),
    tile('未着手 2h超', len(open_wait), 'bad' if open_wait else 'done', '/'.join(open_wait) or '0 件'),
])

page = f'''<title>将軍 全体状況マップ</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Zen+Kaku+Gothic+New:wght@500;700&family=IBM+Plex+Sans+JP:wght@400;500&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
:root{{--ground:#eef1f2;--panel:#ffffff;--ink:#1a1d21;--ink2:#4b535c;--ink3:#7b8590;--line:#d5dbe0;--accent:#2f4a7a;--accent-soft:#e4eaf4;
  --done:#2e7d5b;--done-soft:#e1f1ea;--run:#b7791f;--run-soft:#f7ecd7;--todo:#6b7280;--todo-soft:#e7e9ec;--bad:#b3352b;--bad-soft:#f6e1de}}
@media (prefers-color-scheme:dark){{:root:not([data-theme="light"]){{--ground:#14171b;--panel:#1c2025;--ink:#e9e8e3;--ink2:#b5bac1;--ink3:#848c96;--line:#30363d;--accent:#9db1e6;--accent-soft:#242c3d;
  --done:#6cc493;--done-soft:#1c3327;--run:#e0a94a;--run-soft:#3a2d14;--todo:#9aa2ad;--todo-soft:#282d34;--bad:#e5776a;--bad-soft:#3d2220}}}}
:root[data-theme="dark"]{{--ground:#14171b;--panel:#1c2025;--ink:#e9e8e3;--ink2:#b5bac1;--ink3:#848c96;--line:#30363d;--accent:#9db1e6;--accent-soft:#242c3d;
  --done:#6cc493;--done-soft:#1c3327;--run:#e0a94a;--run-soft:#3a2d14;--todo:#9aa2ad;--todo-soft:#282d34;--bad:#e5776a;--bad-soft:#3d2220}}
*{{box-sizing:border-box;min-width:0}}
html,body{{max-width:100%;overflow-x:hidden}}
body{{margin:0;padding:1.25rem 1rem 3rem;background:var(--ground);color:var(--ink);font-family:"IBM Plex Sans JP",system-ui,sans-serif;font-size:.95rem;line-height:1.6;overflow-wrap:break-word;word-break:normal}}
.wrap{{max-width:60rem;margin:0 auto;display:flex;flex-direction:column;gap:1.1rem}}
h1{{font-family:"Zen Kaku Gothic New","IBM Plex Sans JP",sans-serif;font-weight:700;font-size:1.55rem;margin:0;letter-spacing:.01em;text-wrap:balance}}
.eyebrow{{font-family:"IBM Plex Mono",monospace;font-size:.7rem;letter-spacing:.1em;text-transform:uppercase;color:var(--ink3);margin:0 0 .2rem}}
.rule{{color:var(--ink2);font-size:.85rem;margin:.2rem 0 0;max-width:65ch}}
.tiles{{display:flex;flex-wrap:wrap;gap:.6rem}}
.tile{{flex:1 1 9rem;background:var(--panel);border:1px solid var(--line);border-radius:.35rem;padding:.65rem .8rem;display:flex;flex-direction:column;gap:.1rem}}
.tile .k{{font-family:"IBM Plex Mono",monospace;font-size:.66rem;letter-spacing:.1em;text-transform:uppercase;color:var(--ink3)}}
.tile .v{{font-family:"IBM Plex Mono",monospace;font-size:1.45rem;font-weight:500;font-variant-numeric:tabular-nums;line-height:1.1}}
.tile .s{{font-size:.76rem;color:var(--ink2)}}
.v.done{{color:var(--done)}}.v.run{{color:var(--run)}}.v.todo{{color:var(--todo)}}.v.bad{{color:var(--bad)}}
h2{{font-family:"Zen Kaku Gothic New","IBM Plex Sans JP",sans-serif;font-weight:700;font-size:1.05rem;margin:0 0 .5rem;display:flex;align-items:baseline;gap:.5rem}}
h2 .n{{font-family:"IBM Plex Mono",monospace;font-size:.8rem;font-weight:400;color:var(--ink3)}}
.now-box{{background:var(--panel);border:1px solid var(--line);border-radius:.35rem;padding:.8rem .95rem}}
.now-box ul{{margin:0;padding-left:1.1rem;display:flex;flex-direction:column;gap:.25rem;font-size:.88rem}}
.items{{display:flex;flex-direction:column;gap:.55rem}}
.item{{background:var(--panel);border:1px solid var(--line);border-left:4px solid var(--edge);border-radius:.35rem;padding:.65rem .85rem}}
.item.run{{--edge:var(--run)}}.item.todo{{--edge:var(--todo)}}
.item p{{margin:0}}
.item .head{{display:flex;flex-wrap:wrap;align-items:baseline;gap:.5rem;margin-bottom:.2rem}}
.id{{font-family:"IBM Plex Mono",monospace;font-size:.78rem;color:var(--accent);background:var(--accent-soft);padding:.05rem .4rem;border-radius:.25rem;white-space:nowrap}}
.title{{font-weight:500}}
.item .now{{color:var(--ink);font-size:.9rem}}
.item .term{{color:var(--ink2);font-size:.84rem;margin-top:.2rem}}
.item .term b{{color:var(--run);font-weight:500;margin-right:.3rem}}
.item .why{{color:var(--accent);font-size:.82rem;margin-top:.2rem}}
.item .meta{{font-family:"IBM Plex Mono",monospace;font-size:.7rem;color:var(--ink3);margin-top:.25rem;font-variant-numeric:tabular-nums}}
details{{margin-top:.3rem}}summary{{cursor:pointer;color:var(--accent);font-size:.78rem}}
details p{{color:var(--ink2);font-size:.82rem;margin:.3rem 0 0}}
.day{{background:var(--panel);border:1px solid var(--line);border-radius:.35rem;padding:.5rem .85rem;margin:0}}
.day>summary{{font-family:"IBM Plex Mono",monospace;font-size:.85rem;color:var(--ink);font-variant-numeric:tabular-nums}}
.day>summary .n{{color:var(--ink3);margin-left:.4rem}}
ul.done{{list-style:none;margin:.4rem 0 0;padding:0;display:flex;flex-direction:column;gap:.15rem}}
ul.done li{{display:flex;flex-wrap:wrap;align-items:baseline;gap:.45rem;padding:.2rem 0;border-top:1px solid var(--line);font-size:.86rem}}
ul.done .when{{font-family:"IBM Plex Mono",monospace;font-size:.72rem;color:var(--ink3);font-variant-numeric:tabular-nums;margin-left:auto}}
ul.done details{{flex-basis:100%;margin:0}}
footer{{color:var(--ink3);font-size:.74rem;font-family:"IBM Plex Mono",monospace}}
a:focus-visible,summary:focus-visible{{outline:2px solid var(--accent);outline-offset:2px}}
@media (max-width:40rem){{body{{padding:.9rem .7rem 2.5rem}}.tile{{flex-basis:calc(50% - .3rem)}}.tile .v{{font-size:1.2rem}}ul.done .when{{margin-left:0;flex-basis:100%}}}}
@media (prefers-reduced-motion:reduce){{*{{transition:none!important}}}}
</style>
<div class="wrap">
<header>
  <p class="eyebrow">shogun todo map · {e(label)} · 正本 queue/shogun_todo_map.md</p>
  <h1>将軍 全体状況マップ</h1>
  <p class="rule">らせん: 計測器を律速の名指しから常設 → 1 unit だけ切る(1 unit/commit) → 計測を一段深く → 計測器は残す。切るのは機械的待ちのみ。行の [x]/[~] は<b>終端条件×本番の現在値</b>で決める(CLEAR は途中成果)。</p>
</header>
<div class="tiles">{tiles}</div>
{now_html}
<section><h2>走行中 <span class="n">{len(run_rows)}</span></h2><div class="items">{''.join(row_open(r, 'run') for r in run_rows)}</div></section>
<section><h2>未着手 <span class="n">{len(todo_rows)}</span></h2><div class="items">{''.join(row_open(r, 'todo') for r in todo_rows) or '<p class="rule">なし</p>'}</div></section>
<section><h2>済 <span class="n">{len(done_rows)}</span></h2><div class="items">{done_html}</div></section>
<footer>正本 queue/shogun_todo_map.md · HTML docs/dashboard/shogun-todo-map.html · 各 inbox 処理後/30 分毎に更新 · {e(label)}</footer>
</div>
'''
open(H, 'w').write(page)
miss = [r['id'] for r in rows if f'<span class="id">{r["id"]}</span>' not in page]
print(f"rows={len(rows)} done={cnt['x']} run={cnt['~']} todo={cnt[' ']} bytes={len(page.encode())} html_missing={miss}")
sys.exit(2 if miss else 0)
