#!/usr/bin/env bash
# orphan_test_reap.sh — 親を失った(=/init直下)テスト実行系プロセス樹を列挙/停止する。
# 2026-08-27 02:35 発端: test_heavy_job_admission.bats のfixture run_tests.sh unit が孤児化し
# 全unit suiteを再帰起動して自己増殖(root 27・bats-exec-suite 32本・load 66)。
# pgid単位のkillでは heavy_job_admission.sh が新pgidを切るため子孫が残り再増殖した。
# ∴ 孤児root→子孫を再帰展開し、反復して静止まで回収する。ps 1回のスナップショットで木を組む(高負荷下でも数秒)。
# 使い方: bash scripts/orphan_test_reap.sh          # dry-run(列挙のみ)
#         bash scripts/orphan_test_reap.sh --kill   # 停止(将軍はD006により実行しない。殿が実行)
#         EXTRA_PATTERN='hanzo_e38d94bd2c010891' bash scripts/orphan_test_reap.sh --kill  # 追加pattern(祖先がtmuxでも対象)
set -u
MODE=list
[ "${1:-}" = "--kill" ] && MODE=kill
export EXTRA_PATTERN="${EXTRA_PATTERN:-}"
export REAP_MODE="$MODE"
python3 - <<'PY'
import os, re, signal, subprocess, sys, time
PAT = re.compile(r'bats-exec|bats-core/bats |run_tests\.sh|run_with_receipt\.sh|heavy_job_admission')
extra = os.environ.get('EXTRA_PATTERN') or None
EXTRA = re.compile(extra) if extra else None
mode = os.environ.get('REAP_MODE', 'list')
me = os.getpid(); mypp = os.getppid()

def snapshot():
    out = subprocess.run(['ps', '-eo', 'pid=,ppid=,pgid=,etimes=,args='], capture_output=True, text=True).stdout
    proc = {}
    for l in out.splitlines():
        f = l.split(None, 4)
        if len(f) < 5: continue
        proc[int(f[0])] = (int(f[1]), int(f[2]), int(f[3]), f[4])
    return proc

def init_pids(proc):
    s = {1}
    for p, v in proc.items():
        if v[3].strip() in ('/init', 'init') or v[3].startswith('/init '): s.add(p)
    return s

def collect(proc):
    inits = init_pids(proc)
    kids = {}
    for p, v in proc.items(): kids.setdefault(v[0], []).append(p)
    roots = set()
    for p, v in proc.items():
        a = v[3]
        if p in (me, mypp): continue
        if v[0] in inits and PAT.search(a): roots.add(p)
        if EXTRA and EXTRA.search(a): roots.add(p)
    def has_tmux_ancestor(p):
        seen = set()
        while p in proc and p not in seen:
            seen.add(p)
            if proc[p][3].startswith('tmux'): return True
            p = proc[p][0]
        return False
    targets = set()
    for r in roots:
        if not (EXTRA and EXTRA.search(proc[r][3])) and has_tmux_ancestor(r): continue
        stack = [r]
        while stack:
            x = stack.pop()
            if x in targets: continue
            targets.add(x); stack.extend(kids.get(x, []))
    targets.discard(me); targets.discard(mypp)
    return sorted(targets), sorted(roots)

proc = snapshot()
targets, roots = collect(proc)
if mode == 'list':
    print(f"orphan_test_procs={len(targets)} roots={len(roots)}")
    for r in sorted(roots):
        v = proc[r]; print(f"  root pid={r} ppid={v[0]} pgid={v[1]} etime={v[2]}s {v[3][:110]}")
    sys.exit(0)
for rnd in range(1, 9):
    proc = snapshot(); targets, roots = collect(proc)
    print(f"round={rnd} targets={len(targets)} roots={len(roots)}"); sys.stdout.flush()
    if not targets: break
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for p in targets:
            try: os.kill(p, sig)
            except ProcessLookupError: pass
            except PermissionError: print(f"  EPERM pid={p}")
        time.sleep(1.5)
proc = snapshot(); targets, _ = collect(proc)
print(f"remaining={len(targets)}")
PY
