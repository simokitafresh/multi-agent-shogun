#!/usr/bin/env python3
"""queue/shogun_todo_map.md の git 履歴から各 T 行の 3 タイムスタンプ(登録/着手/解決)を機械抽出し
queue/shogun_todo_map_timestamps.tsv を生成する(殿指示 2026-08-28 09:06『登録・着手・解決の三点をデータとして』)。

定義(SSOT=git commit 時刻、歴史修正禁止ゆえ一度確定した値は後の commit で変わらない):
  registered_at = その ID の行が初めて map に現れた commit の時刻(状態は問わない)
  started_at    = その ID が初めて [~] または [x] になった commit の時刻
  resolved_at   = その ID が初めて [x] になった commit の時刻
  state         = 現在の working tree の状態(' ', '~', 'x')。reopen([x]→[~])しても first 値は保持し、
                  reopened=yes を立てる
  lead_start_min/lead_resolve_min = 登録→着手 / 着手→解決 の分(未到達は空)
working tree にあって未 commit の新規行は now(実行時刻)で仮登録する(次 commit で確定)。

usage: python3 scripts/todo_map_timestamps.py [--repo <root>] [--md queue/shogun_todo_map.md] [--out <tsv>] [--now <ISO>]
"""
import re, subprocess, sys, os, datetime

ROW = re.compile(r'^- \[(.)\] (T\d+[a-z]?|K\d+)\(', re.M)

def parse(text):
    return {m.group(2): m.group(1) for m in ROW.finditer(text)}

def git(repo, *args):
    return subprocess.run(['git', '-C', repo, *args], capture_output=True, text=True, check=False).stdout

def build(repo, md, now=None):
    log = git(repo, 'log', '--reverse', '--format=%H\t%cI', '--', md).strip().splitlines()
    rec = {}
    def touch(i, st, ts):
        r = rec.setdefault(i, dict(registered_at=ts, started_at='', resolved_at='', state=st, reopened='no'))
        if st in '~x' and not r['started_at']:
            r['started_at'] = ts
        if st == 'x' and not r['resolved_at']:
            r['resolved_at'] = ts
        if r['resolved_at'] and st == '~' and r['state'] == 'x':
            r['reopened'] = 'yes'
        r['state'] = st
    for line in log:
        h, ts = line.split('\t')
        for i, st in parse(git(repo, 'show', f'{h}:{md}')).items():
            touch(i, st, ts)
    wt = os.path.join(repo, md)
    if os.path.exists(wt):
        now = now or datetime.datetime.now().astimezone().isoformat(timespec='seconds')
        for i, st in parse(open(wt, encoding='utf-8').read()).items():
            touch(i, st, now)
    return rec

def minutes(a, b):
    if not a or not b:
        return ''
    fa = datetime.datetime.fromisoformat(a); fb = datetime.datetime.fromisoformat(b)
    return str(int((fb - fa).total_seconds() // 60))

def write(rec, out):
    cols = ['id', 'state', 'registered_at', 'started_at', 'resolved_at', 'lead_start_min', 'lead_resolve_min', 'reopened']
    lines = ['# precision: git commit 時刻が SSOT(状態遷移ごとの commit 以降は事象時刻≈commit 時刻。08-28 09:15 以前は 30 分束 commit ゆえ 0m が多い)', '\t'.join(cols)]
    for i, r in rec.items():
        lines.append('\t'.join([i, r['state'], r['registered_at'], r['started_at'], r['resolved_at'],
                                minutes(r['registered_at'], r['started_at']),
                                minutes(r['started_at'], r['resolved_at']), r['reopened']]))
    with open(out, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')

def main(argv):
    repo = os.getcwd(); md = 'queue/shogun_todo_map.md'; out = None; now = None
    a = argv[:]
    while a:
        k = a.pop(0)
        if k == '--repo': repo = a.pop(0)
        elif k == '--md': md = a.pop(0)
        elif k == '--out': out = a.pop(0)
        elif k == '--now': now = a.pop(0)
        else: print(f'unknown arg {k}', file=sys.stderr); return 2
    out = out or os.path.join(repo, 'queue/shogun_todo_map_timestamps.tsv')
    rec = build(repo, md, now)
    write(rec, out)
    n = len(rec); st = sum(1 for r in rec.values() if r['started_at']); rs = sum(1 for r in rec.values() if r['resolved_at'])
    print(f'rows={n} started={st} resolved={rs} out={out}')
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
