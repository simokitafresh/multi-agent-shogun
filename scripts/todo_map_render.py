#!/usr/bin/env python3
"""queue/shogun_todo_map.md(正本) から docs/dashboard/shogun-todo-map.html の行セクション/タイル/更新時刻を機械生成する。
usage: python3 scripts/todo_map_render.py "<更新ラベル>"  → 生成後に md↔HTML の ID 集合一致を検証し不一致なら exit 2"""
import re,sys,html
MD='queue/shogun_todo_map.md'; H='docs/dashboard/shogun-todo-map.html'
label=sys.argv[1] if len(sys.argv)>1 else ''
s=open(MD).read(); t=open(H).read()
rows=[dict(st=m.group(1),id=m.group(2),ev=m.group(3),title=m.group(4),why=m.group(5))
      for m in re.finditer(r'^- \[(.)\] (T\d+[a-z]?|K\d+)\((.*?)\) (.*?) ★(.*)$',s,re.M)]
cnt={k:sum(1 for r in rows if r['st']==k) for k in 'x~ '}
def row(r,c): return f'    <div class="row {c}"><span class="id">{r["id"]}</span><span class="t">{html.escape(r["title"])}</span><span class="d">{html.escape(r["ev"])}</span><span class="w">{html.escape(r["why"])}</span></div>'
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
if label:
    t=re.sub(r'(shogun todo map · )[^·]*( · 正本)',lambda m:m.group(1)+label+m.group(2),t)
    t=re.sub(r'(各inbox処理後/30分毎に更新 · )[^<]*(</footer>)',lambda m:m.group(1)+label+m.group(2),t)
open(H,'w').write(t)
miss=[r['id'] for r in rows if f'<span class="id">{r["id"]}</span>' not in t]
print(f"rows={len(rows)} done={cnt['x']} run={cnt['~']} todo={cnt[' ']} html_missing={miss}")
sys.exit(2 if miss else 0)
