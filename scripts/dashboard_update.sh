#!/usr/bin/env bash
# ============================================================
# dashboard_update.sh
# report YAMLからdashboard.mdの「最新更新」セクションを自動更新
# 家老の手動更新作業を排除する
#
# Usage: bash scripts/dashboard_update.sh <cmd_id> [--dry-run]
#   cmd_id (必須): cmd_XXX 形式
#   --dry-run: 差分のみ表示。dashboard.mdは変更しない
#
# Exit:
#   0: 成功（dashboard.md更新完了）
#   1: 失敗（解析エラー等。stderrにWARN出力）
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

CMD_ID="${1:-}"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true

# ─── Validation ───
if [[ -z "$CMD_ID" || "$CMD_ID" != cmd_* ]]; then
    echo "Usage: dashboard_update.sh <cmd_id> [--dry-run]" >&2
    echo "  cmd_id: cmd_XXX形式（必須）" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

DASHBOARD="$PROJECT_DIR/dashboard.md"
REPORTS_DIR="$PROJECT_DIR/queue/reports"
STK_FILE="$PROJECT_DIR/queue/shogun_to_karo.yaml"

if [[ ! -f "$DASHBOARD" ]]; then
    echo "ERROR: dashboard.md not found: $DASHBOARD" >&2
    exit 1
fi

# ─── Export for Python ───
export DASHBOARD REPORTS_DIR STK_FILE CMD_ID DRY_RUN

# ─── Main processing (flock for concurrency safety) ───
LOCK_FILE="${DASHBOARD}.lock"
(
    flock -w 10 200 || { echo "ERROR: flock取得失敗" >&2; exit 1; }

    python3 << 'PYEOF'
import yaml, glob, os, sys, re

DASHBOARD = os.environ['DASHBOARD']
REPORTS_DIR = os.environ['REPORTS_DIR']
STK_FILE = os.environ['STK_FILE']
CMD_ID = os.environ['CMD_ID']
DRY_RUN = os.environ['DRY_RUN'] == 'true'

NAME_MAP = {
    'sasuke': '佐助', 'kirimaru': '霧丸', 'hayate': '疾風',
    'kagemaru': '影丸', 'hanzo': '半蔵', 'saizo': '才蔵',
    'kotaro': '小太郎', 'tobisaru': '飛猿', 'karo': '家老',
}


def get_nested(data, path, default=None):
    """Dot-separated path accessor for nested dicts."""
    keys = path.split('.')
    val = data
    for k in keys:
        if isinstance(val, dict):
            val = val.get(k)
        else:
            return default
    return val if val is not None else default


def get_first(data, *paths, default=''):
    """Return first non-empty value from multiple dot-paths."""
    for path in paths:
        val = get_nested(data, path)
        if val is not None and val != '' and val != []:
            return val
    return default


def summarize_ac(ac_val):
    """AC情報を短縮文字列に変換。"""
    if isinstance(ac_val, dict):
        pass_n = sum(1 for v in ac_val.values()
                     if isinstance(v, str) and 'PASS' in v.upper())
        fail_n = sum(1 for v in ac_val.values()
                     if isinstance(v, str) and 'FAIL' in v.upper())
        total = len(ac_val)
        if fail_n == 0 and pass_n > 0:
            return f'AC1-{total}全PASS'
        elif fail_n > 0:
            return f'PASS:{pass_n} FAIL:{fail_n}/{total}'
    elif isinstance(ac_val, str):
        return ac_val[:80]
    elif isinstance(ac_val, list):
        pass_n = sum(1 for v in ac_val
                     if isinstance(v, str) and 'PASS' in str(v).upper())
        total = len(ac_val)
        if total > 0:
            return f'AC:{pass_n}/{total} PASS'
    return ''


# ─── Step 1: Find matching report YAMLs ───
matches = []
for fpath in sorted(glob.glob(os.path.join(REPORTS_DIR, '*.yaml'))):
    try:
        with open(fpath) as f:
            raw = yaml.safe_load(f)
        if not raw:
            continue
        pcmd = str(get_first(raw, 'parent_cmd', 'report.parent_cmd'))
        if pcmd != CMD_ID:
            continue
        status = str(get_first(raw, 'status', 'report.status', default=''))
        # Skip placeholder reports (empty status)
        if not status.strip() or status.strip() == 'None':
            continue
        ts = str(get_first(raw, 'timestamp', 'report.timestamp', default=''))
        matches.append({'ts': ts, 'path': fpath, 'data': raw})
    except Exception:
        continue

if not matches:
    print(f"WARN: {CMD_ID}に対応する完了済みreport YAMLが見つかりません", file=sys.stderr)
    sys.exit(1)

# Sort by timestamp (latest first; empty timestamps go last)
matches.sort(key=lambda x: x['ts'] if x['ts'] else '', reverse=True)
latest = matches[0]['data']

# ─── Step 2: Extract fields with fallback ───
status_raw = str(get_first(latest, 'status', 'report.status', default=''))
status_label = '完了' if status_raw.lower() in ('done', 'completed') else status_raw

summary = str(get_first(latest, 'result.summary', 'report.summary',
                        'report.result.summary', 'report.conclusion',
                        default=''))
summary = summary.strip().replace('\n', ' ')
if len(summary) > 120:
    summary = summary[:117] + '...'

# Collect workers from ALL matching reports
workers = set()
for m in matches:
    w = get_first(m['data'], 'worker_id', 'report.agent',
                  'report.assigned_to', 'assigned_to')
    if w and str(w) != 'None':
        workers.add(str(w))

worker_names = [NAME_MAP.get(w, w) for w in sorted(workers)]
worker_str = '+'.join(worker_names) + '完遂' if worker_names else ''

# AC: use first found from any matching report
ac_str = ''
for m in matches:
    ac = get_first(m['data'], 'result.ac_results', 'result.ac_status',
                   'report.ac_checklist', 'report.acceptance_criteria',
                   'report.acceptance_criteria_check')
    if ac:
        ac_str = summarize_ac(ac)
        if ac_str:
            break

# ─── Step 3: Get cmd title from shogun_to_karo.yaml ───
title = ''
try:
    with open(STK_FILE) as f:
        stk = yaml.safe_load(f)
    if stk and 'commands' in stk:
        for cmd in stk['commands']:
            if cmd.get('id') == CMD_ID:
                title = cmd.get('title', cmd.get('purpose', ''))
                break
except Exception:
    pass

# ─── Step 4: Generate dashboard line ───
parts = [f'- **{CMD_ID}**: ']
if status_label:
    parts.append(f'{status_label}。')
if title:
    parts.append(title)
if summary and summary != title:
    parts.append(f' — {summary}')
if worker_str:
    parts.append(f'。{worker_str}')
if ac_str:
    parts.append(f'。{ac_str}')

new_line = ''.join(parts)

if DRY_RUN:
    print(f'DRY-RUN: {new_line}')
    sys.exit(0)

# ─── Step 5: Update dashboard.md ───
with open(DASHBOARD) as f:
    lines = f.read().split('\n')

# Remove existing entry for this cmd_id (dedup) and track if it existed
cmd_pattern = re.compile(rf'^- \*\*{re.escape(CMD_ID)}\*\*:')
is_replacement = any(cmd_pattern.match(l) for l in lines)
lines = [l for l in lines if not cmd_pattern.match(l)]

# Insert after "## 最新更新" header
inserted = False
result = []
for line in lines:
    result.append(line)
    if line.startswith('## 最新更新') and not inserted:
        result.append(new_line)
        inserted = True

if not inserted:
    print("ERROR: '## 最新更新' section not found in dashboard.md", file=sys.stderr)
    sys.exit(1)

content = '\n'.join(result)

# ─── Step 6: Counter updates (完了 status + 新規エントリのみ) ───
if status_label == '完了' and not is_replacement:
    # 連勝街道: N連勝 (最長: M連勝) → (N+1)連勝, max(N+1,M)
    m = re.search(r'\| 連勝街道 \| (\d+)連勝 \(最長: (\d+)連勝\)\s*\|', content)
    if m:
        current = int(m.group(1)) + 1
        best = max(current, int(m.group(2)))
        content = content.replace(
            m.group(0),
            f'| 連勝街道 | {current}連勝 (最長: {best}連勝) |')

    # 今日の完了: C/T（cmd: X + VF: Y） → (C+1)/(T+1)（cmd: (X+1) + VF: Y）
    m = re.search(
        r'\| 今日の完了 \| (\d+)/(\d+)（cmd: (\d+) \+ VF: (\d+)）\s*\|',
        content)
    if m:
        c = int(m.group(1)) + 1
        t = int(m.group(2)) + 1
        cc = int(m.group(3)) + 1
        vf = int(m.group(4))
        content = content.replace(
            m.group(0),
            f'| 今日の完了 | {c}/{t}（cmd: {cc} + VF: {vf}）|')

with open(DASHBOARD, 'w') as f:
    f.write(content)

if is_replacement:
    print(f'UPDATED: {CMD_ID} line replaced in 最新更新')
else:
    print(f'UPDATED: {CMD_ID} line appended to 最新更新')
if status_label == '完了' and not is_replacement:
    print('UPDATED: 連勝街道/今日の完了 counters')
PYEOF
) 200>"$LOCK_FILE"
