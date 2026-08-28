#!/usr/bin/env python3
"""queue/shogun_todo_map.md(正本) から docs/dashboard/shogun-todo-map.html の行セクション/タイル/更新時刻を機械生成する。
usage: python3 scripts/todo_map_render.py "<更新ラベル>"  → 生成後に md↔HTML の ID 集合一致を検証し不一致なら exit 2"""
import re,sys,html,subprocess,statistics,datetime
MD='queue/shogun_todo_map.md'; H='docs/dashboard/shogun-todo-map.html'
label=sys.argv[1] if len(sys.argv)>1 else ''
s=open(MD).read(); t=open(H).read()
# 3 タイムスタンプ(登録/着手/解決)= git 履歴から機械抽出(殿指示 2026-08-28 09:06)。正本 tsv を毎回再生成
subprocess.run([sys.executable,'scripts/todo_map_timestamps.py'],check=True,capture_output=True)
TS={}
for ln in open('queue/shogun_todo_map_timestamps.tsv').read().splitlines():
    if ln.startswith('#') or ln.startswith('id\t'): continue
    c=ln.split('\t'); TS[c[0]]=dict(st=c[1],reg=c[2],start=c[3],res=c[4],ls=c[5],lr=c[6],reopen=c[7])
def hm(iso): return iso[5:16].replace('T',' ') if iso else '—'
def dur(m):
    if m=='': return '—'
    m=int(m); return f'{m//60}h{m%60:02d}m' if m>=60 else f'{m}m'
def tsline(i):
    x=TS.get(i)
    if not x: return ''
    wait=dur(x['ls']) if x['start'] else dur(str(int((datetime.datetime.now().astimezone()-datetime.datetime.fromisoformat(x['reg'])).total_seconds()//60)))+'(未着手経過)'
    work=dur(x['lr']) if x['res'] else ('' if not x['start'] else dur(str(int((datetime.datetime.now().astimezone()-datetime.datetime.fromisoformat(x['start'])).total_seconds()//60)))+'(走行中)')
    return f'<span class="ts">登録 <b>{hm(x["reg"])}</b> → 着手 <b>{hm(x["start"])}</b> → 解決 <b>{hm(x["res"])}</b> · 待機 {wait} · 所要 {work}'+(' · 再開あり' if x['reopen']=='yes' else '')+'</span>'
rows=[dict(st=m.group(1),id=m.group(2),ev=m.group(3),title=m.group(4),why=m.group(5))
      for m in re.finditer(r'^- \[(.)\] (T\d+[a-z]?|K\d+)\((.*?)\) (.*?) ★(.*)$',s,re.M)]
cnt={k:sum(1 for r in rows if r['st']==k) for k in 'x~ '}
def row(r,c): return f'    <div class="row {c}"><span class="id">{r["id"]}</span><span class="t">{html.escape(r["title"])}</span><span class="d">{html.escape(r["ev"])}</span><span class="w">{html.escape(r["why"])}</span>{tsline(r["id"])}</div>'
def sec(name,c,st,rev=False):
    rs=[r for r in rows if r['st']==st]; rs=rs[::-1] if rev else rs
    body='\n'.join(row(r,c) for r in rs)
    return f'<section class="group">\n  <h2>{name} <span class="n">{len(rs)}</span></h2>\n  <div class="rows">\n{body}\n  </div>\n</section>'
t=re.sub(r'<section class="group">\s*<h2>走行中.*?</section>',sec('走行中','run','~'),t,count=1,flags=re.S)
t=re.sub(r'<section class="group">\s*<h2>未着手.*?</section>',sec('未着手','todo',' '),t,count=1,flags=re.S)
t=re.sub(r'<section class="group">\s*<h2>済.*?</section>',sec('済','done','x',True),t,count=1,flags=re.S)
t=re.sub(r'(<span class="k">済</span><span class="v done">)\d+(</span><span class="s">)[^<]*',lambda m:m.group(1)+str(cnt['x'])+m.group(2)+'md正本の [x] 実数',t)
t=re.sub(r'(<span class="k">走行中</span><span class="v run">)\d+(</span><span class="s">)[^<]*',lambda m:m.group(1)+str(cnt['~'])+m.group(2)+' / '.join(r['id'] for r in rows if r['st']=='~'),t)
t=re.sub(r'(<span class="k">未着手</span><span class="v todo">)\d+(</span><span class="s">)[^<]*',lambda m:m.group(1)+str(cnt[' '])+m.group(2)+' / '.join(r['id'] for r in rows if r['st']==' '),t)
ls=[int(x['ls']) for x in TS.values() if x['ls']!='']; lr=[int(x['lr']) for x in TS.values() if x['lr']!='']
open_wait=[i for i,x in TS.items() if x['st']==' ' and (datetime.datetime.now().astimezone()-datetime.datetime.fromisoformat(x['reg'])).total_seconds()>7200]
tile=f'<div class="tile"><span class="k">回転(3TS)</span><span class="v run">{dur(str(int(statistics.median(lr)))) if lr else "—"}</span><span class="s">着手→解決 中央値(n={len(lr)}) · 登録→着手 中央値 {dur(str(int(statistics.median(ls)))) if ls else "—"}(n={len(ls)}) · 未着手2h超 {len(open_wait)}件{("="+"/".join(open_wait)) if open_wait else ""} · 正本 queue/shogun_todo_map_timestamps.tsv</span></div>'
if '<span class="k">回転(3TS)</span>' in t:
    t=re.sub(r'<div class="tile"><span class="k">回転\(3TS\)</span>.*?</div>',lambda m:tile,t,count=1,flags=re.S)
else:
    t=t.replace('</div>\n\n<div class="live">',tile+'\n</div>\n\n<div class="live">',1)
if label:
    t=re.sub(r'(shogun todo map · )[^·]*( · 正本)',lambda m:m.group(1)+label+m.group(2),t)
    t=re.sub(r'(各inbox処理後/30分毎に更新 · )[^<]*(</footer>)',lambda m:m.group(1)+label+m.group(2),t)
open(H,'w').write(t)
miss=[r['id'] for r in rows if f'<span class="id">{r["id"]}</span>' not in t]
print(f"rows={len(rows)} done={cnt['x']} run={cnt['~']} todo={cnt[' ']} html_missing={miss}")
sys.exit(2 if miss else 0)
