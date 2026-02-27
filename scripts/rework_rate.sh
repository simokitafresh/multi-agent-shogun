#!/bin/bash
# rework_rate.sh - 手戻り率集計スクリプト
# Usage: rework_rate.sh [--since YYYY-MM-DD] [--json]
# STK(active+archive)を走査し手戻り率・手戻りリスト・期間別推移を集計する

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACTIVE_STK="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
ARCHIVE_STK="$SCRIPT_DIR/queue/archive/shogun_to_karo_done.yaml"

SINCE=""
OUTPUT_JSON=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --since) SINCE="$2"; shift 2 ;;
        --json)  OUTPUT_JSON=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# L047: Python heredocへの変数渡しは環境変数経由
export REWORK_ACTIVE="$ACTIVE_STK"
export REWORK_ARCHIVE="$ARCHIVE_STK"
export REWORK_SINCE="$SINCE"
export REWORK_JSON="$OUTPUT_JSON"

python3 << 'PYEOF'
import os
import sys
import json
import yaml
from collections import defaultdict
from datetime import datetime


def load_cmds(path):
    """
    アーカイブYAMLは混在形式(commands:ブロック + ルートレベルリスト)。
    分割して両方を取得する。
    """
    if not os.path.exists(path):
        return []
    with open(path, encoding='utf-8') as f:
        content = f.read()

    # まず素直に試みる
    try:
        data = yaml.safe_load(content)
        if data and isinstance(data, dict):
            return data.get('commands', []) or []
        if data and isinstance(data, list):
            return data
        return []
    except yaml.YAMLError:
        pass

    # 失敗時: commands:ブロック部分とベアリスト部分を分割してパース
    import re
    lines = content.splitlines(keepends=True)
    # ルートレベルの "- id:" 行のインデックスを探す
    bare_start = None
    for i, line in enumerate(lines):
        if re.match(r'^- ', line) and not line.startswith('commands:'):
            bare_start = i
            break

    cmds = []
    if bare_start is not None:
        # commands:ブロック部分
        commands_block = ''.join(lines[:bare_start])
        try:
            d = yaml.safe_load(commands_block)
            if d and isinstance(d, dict):
                cmds.extend(d.get('commands', []) or [])
        except yaml.YAMLError:
            pass
        # ベアリスト部分: "commands:\n" をプレフィックスとして付けてパース
        bare_block = 'commands:\n' + ''.join(
            '  ' + l for l in lines[bare_start:]
        )
        try:
            d = yaml.safe_load(bare_block)
            if d and isinstance(d, dict):
                cmds.extend(d.get('commands', []) or [])
        except yaml.YAMLError:
            pass
    else:
        # ベアリストのみ
        try:
            data = yaml.safe_load('commands:\n' + ''.join('  ' + l for l in lines))
            if data and isinstance(data, dict):
                cmds.extend(data.get('commands', []) or [])
        except yaml.YAMLError:
            pass

    return cmds


def parse_ts(ts_str):
    if not ts_str:
        return None
    try:
        s = str(ts_str).replace('Z', '+00:00')
        # isoformat with timezone offset
        return datetime.fromisoformat(s)
    except Exception:
        return None


active_path  = os.environ.get('REWORK_ACTIVE', '')
archive_path = os.environ.get('REWORK_ARCHIVE', '')
since_str    = os.environ.get('REWORK_SINCE', '')
output_json  = os.environ.get('REWORK_JSON', 'false').lower() == 'true'

# 全cmd読み込み
all_cmds = load_cmds(active_path) + load_cmds(archive_path)

# --since フィルタ
if since_str:
    try:
        since_dt = datetime.fromisoformat(since_str)
    except ValueError:
        print(f"ERROR: Invalid date format: {since_str}", file=sys.stderr)
        sys.exit(1)
    filtered = []
    for cmd in all_cmds:
        ts = parse_ts(cmd.get('timestamp', ''))
        # timezone-naive比較のため変換
        if ts is None:
            filtered.append(cmd)
        else:
            ts_naive = ts.replace(tzinfo=None)
            if ts_naive >= since_dt:
                filtered.append(cmd)
    all_cmds = filtered

total = len(all_cmds)
rework_cmds = [c for c in all_cmds if c.get('fixes')]

# 手戻りリスト
rework_list = []
for cmd in rework_cmds:
    rework_list.append({
        'id':        cmd.get('id', ''),
        'fixes':     cmd.get('fixes', ''),
        'title':     cmd.get('title', '')[:60],
        'timestamp': str(cmd.get('timestamp', '')),
    })

# 月別推移
monthly = defaultdict(lambda: {'total': 0, 'rework': 0})
for cmd in all_cmds:
    ts = parse_ts(cmd.get('timestamp', ''))
    key = ts.strftime('%Y-%m') if ts else 'unknown'
    monthly[key]['total'] = monthly[key]['total'] + 1
    if cmd.get('fixes'):
        monthly[key]['rework'] = monthly[key]['rework'] + 1

# 50cmd窓別推移
WINDOW = 50
sorted_cmds = sorted(all_cmds, key=lambda c: str(c.get('timestamp', '')))
window_trends = []
for i in range(0, len(sorted_cmds), WINDOW):
    win = sorted_cmds[i:i + WINDOW]
    w_total  = len(win)
    w_rework = sum(1 for c in win if c.get('fixes'))
    first_id = win[0].get('id', '')  if win else ''
    last_id  = win[-1].get('id', '') if win else ''
    window_trends.append({
        'range':  f"{first_id}-{last_id}",
        'total':  w_total,
        'rework': w_rework,
        'rate':   round(w_rework / w_total * 100, 1) if w_total > 0 else 0.0,
    })

# 手戻り連鎖検出 (A fixes B, C fixes A のような連鎖が3件以上)
fixes_map = {}
for cmd in rework_cmds:
    fixes_map[str(cmd.get('id', ''))] = str(cmd.get('fixes', ''))

chains = []
visited = set()
for start_id in fixes_map:
    if start_id in visited:
        continue
    chain = [start_id]
    cur = start_id
    while fixes_map.get(cur) and fixes_map[cur] in fixes_map:
        nxt = fixes_map[cur]
        if nxt in chain:
            break
        chain.append(nxt)
        visited.add(nxt)
        cur = nxt
    visited.add(start_id)
    if len(chain) >= 3:
        chains.append(chain)

rework_rate = round(len(rework_cmds) / total * 100, 1) if total > 0 else 0.0

result = {
    'summary': {
        'total_cmds':      total,
        'rework_cmds':     len(rework_cmds),
        'rework_rate_pct': rework_rate,
    },
    'rework_list':    rework_list,
    'monthly_trend':  {k: v for k, v in sorted(monthly.items())},
    'window_trends':  window_trends,
    'rework_chains':  chains,
}

if output_json:
    print(json.dumps(result, ensure_ascii=False, indent=2))
else:
    s = result['summary']
    print("=== 手戻り率レポート ===")
    print(f"総cmd数      : {s['total_cmds']}")
    print(f"手戻りcmd数  : {s['rework_cmds']}")
    print(f"手戻り率     : {s['rework_rate_pct']}%")
    print()

    if rework_list:
        print("=== 手戻りリスト ===")
        for r in rework_list:
            print(f"  {r['id']} → fixes: {r['fixes']}  ({r['title']})")
        print()

    print("=== 月別推移 ===")
    for month, counts in sorted(result['monthly_trend'].items()):
        rate = round(counts['rework'] / counts['total'] * 100, 1) if counts['total'] > 0 else 0.0
        print(f"  {month}: {counts['rework']}/{counts['total']} ({rate}%)")
    print()

    if window_trends:
        print("=== 50cmd窓別推移 ===")
        for w in window_trends:
            print(f"  [{w['range']}]: {w['rework']}/{w['total']} ({w['rate']}%)")
        print()

    if chains:
        print("=== 手戻り連鎖(3件以上) ===")
        for chain in chains:
            print(f"  {' → '.join(chain)}")
    else:
        print("=== 手戻り連鎖: なし ===")
PYEOF
