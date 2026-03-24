#!/bin/bash
# gate_loop_health.sh — 第三層学習ループ健全性分析
# 目的: gate発火ログから成熟パターンを検出し、auto-fix追加候補を提案
# 三層学習ループの第三層を自己進化させる: 発火→分析→成熟提案→新gate/auto-fix
# Usage: bash scripts/gates/gate_loop_health.sh
# Exit: 0=OK, 1=要対応(繰返しFAILパターンあり)

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/gate_fire_log.yaml"
WORKAROUND_FILE="$REPO_ROOT/logs/karo_workarounds.yaml"

if [ ! -f "$LOG_FILE" ]; then
    echo "SKIP: gate_fire_log.yaml not found"
    exit 0
fi

python3 -c "
import yaml, sys, re, os
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

log_path = '$LOG_FILE'
wa_path = '$WORKAROUND_FILE'

# --- Load gate fire log (flow-style format, parsed via regex) ---
entries = []
with open(log_path) as f:
    for line in f:
        line = line.strip()
        if not line or not line.startswith('- '):
            continue
        entry = {}
        ts_m = re.search(r'ts:\s*\"([^\"]*)\"', line)
        file_m = re.search(r'file:\s*\"([^\"]*)\"', line)
        result_m = re.search(r'result:\s*(\w[\w-]*)', line)
        reasons_m = re.search(r'reasons:\s*\"(.*)\"$', line)
        fixes_m = re.search(r'fixes:\s*\"(.*)\"$', line)
        if ts_m:
            entry['ts'] = ts_m.group(1)
        if file_m:
            entry['file'] = file_m.group(1)
        if result_m:
            entry['result'] = result_m.group(1)
        if reasons_m:
            entry['reasons'] = reasons_m.group(1)
        if fixes_m:
            entry['fixes'] = fixes_m.group(1)
        if entry:
            entries.append(entry)

if not entries:
    print('NO DATA')
    sys.exit(0)

# --- Filter out /tmp test entries ---
tmp_entries = [e for e in entries if e.get('file', '').startswith('/tmp/')]
entries = [e for e in entries if not e.get('file', '').startswith('/tmp/')]

# --- Aggregate ---
total = len(entries)
pass_count = sum(1 for e in entries if e.get('result') == 'PASS')
fail_count = sum(1 for e in entries if e.get('result') == 'FAIL')
autofix_count = sum(1 for e in entries if e.get('result') == 'AUTO-FIXED')

print('=== 第三層 Gate Health Report ===')
print(f'Total fires: {total} (除外: テスト{len(tmp_entries)}件)')
print(f'  PASS: {pass_count} ({pass_count*100//total}%)')
print(f'  FAIL: {fail_count} ({fail_count*100//total}%)')
print(f'  AUTO-FIXED: {autofix_count}')
print()

# --- Extract individual error reasons from FAIL entries ---
reason_counter = Counter()
reason_files = defaultdict(list)

for e in entries:
    if e.get('result') != 'FAIL':
        continue
    reasons_str = e.get('reasons', '')
    # Split by '; ' to get individual reasons
    for reason in reasons_str.split('; '):
        reason = reason.strip()
        if not reason:
            continue
        # Normalize: remove specific values, keep pattern
        # e.g., 'verdict: \"CONDITIONAL_PASS\"' → 'verdict: invalid'
        pattern = reason
        pattern = re.sub(r'lessons_useful\[\d+\]', 'lessons_useful[N]', pattern)
        pattern = re.sub(r'binary_checks\.\w+', 'binary_checks.ACx', pattern)
        reason_counter[pattern] += 1
        fname = e.get('file', '')
        reason_files[pattern].append(fname)

if reason_counter:
    print('=== Recurring FAIL Patterns (成熟候補) ===')
    for pattern, count in reason_counter.most_common(10):
        # Determine if auto-fixable
        auto_fixable = False
        if 'is dict (must be list)' in pattern:
            auto_fixable = True  # dict→list conversion
        elif 'is string' in pattern and 'lesson_candidate' not in pattern:
            auto_fixable = True  # format conversion

        status = 'AUTO-FIX候補' if auto_fixable else '要品質判断'
        print(f'  [{count}回] {pattern}')
        print(f'    → {status}')
    print()

# --- Maturation recommendations ---
print('=== 成熟提案 ===')
recommendations = []

# Check for patterns that fire > 5 times and are auto-fixable
for pattern, count in reason_counter.most_common():
    if count >= 5:
        if 'is dict (must be list)' in pattern:
            recommendations.append(f'UPGRADE: \"{pattern}\" ({count}回) → gate_report_autofix.shにdict→list変換追加')
        elif 'MISSING' in pattern and count >= 10:
            recommendations.append(f'INVESTIGATE: \"{pattern}\" ({count}回) → テンプレートにデフォルト値追加を検討')

if recommendations:
    for r in recommendations:
        print(f'  {r}')
else:
    print('  現時点で成熟提案なし')

# === Auto-insight generation: recurring patterns → queue/insights.yaml ===
# Phase 4原則: 理解だけでは行動は変わらない → 自動化×強制
# 成熟候補を自動でinsight起票し、アクション強制
import subprocess, json

insights_file = os.path.join('$REPO_ROOT', 'queue', 'insights.yaml')
existing_insights = set()
try:
    with open(insights_file) as f:
        idata = yaml.safe_load(f) or {}
    for ins in idata.get('insights', []):
        existing_insights.add(ins.get('insight', ''))
except Exception:
    pass

new_insights = []
for pattern, count in reason_counter.most_common():
    if count < 5:
        continue
    # Build insight message
    if 'is dict (must be list)' in pattern:
        msg = f'GATE成熟: {pattern} ({count}回発火) → gate_report_autofix.shにdict-list変換追加せよ'
    elif 'MISSING' in pattern and count >= 10:
        msg = f'テンプレート強化: {pattern} ({count}回発火) → report templateにデフォルト値追加せよ'
    elif count >= 10:
        msg = f'高頻度FAIL: {pattern} ({count}回発火) → auto-fix化 or gate強化を検討せよ'
    else:
        continue
    # Deduplicate: normalize quotes then check substring match
    DQ = chr(34)
    SQ = chr(39)
    norm_pattern = pattern.replace(chr(92)+DQ, DQ).replace(SQ, DQ)
    if any(norm_pattern in ex.replace(chr(92)+DQ, DQ).replace(SQ, DQ) for ex in existing_insights):
        continue
    new_insights.append(msg)

if new_insights:
    print(f'\\n=== Auto-Insight Generation ===')
    insight_script = os.path.join('$REPO_ROOT', 'scripts', 'insight_write.sh')
    for msg in new_insights:
        try:
            result = subprocess.run(
                ['bash', insight_script, msg, 'high', 'gate_loop_health'],
                capture_output=True, text=True, timeout=10
            )
            ins_id = result.stdout.strip()
            if ins_id:
                print(f'  CREATED: {ins_id} — {msg[:60]}...')
        except Exception as e:
            print(f'  ERROR: {e}')
    print(f'  計{len(new_insights)}件のinsightを自動起票')

# --- Workaround trend (if available) ---
print()
try:
    with open(wa_path) as f:
        wa_data = yaml.safe_load(f) or {}
    wa_list = wa_data if isinstance(wa_data, list) else wa_data.get('workarounds', [])
    if wa_list:
        wa_true = sum(1 for w in wa_list if isinstance(w, dict) and w.get('workaround') is True)
        wa_false = sum(1 for w in wa_list if isinstance(w, dict) and w.get('workaround') is False)
        wa_total = wa_true + wa_false
        if wa_total > 0:
            print(f'=== 第二層 Workaround Rate ===')
            print(f'  workaround: {wa_true}/{wa_total} ({wa_true*100//wa_total}%)')
            # Category breakdown
            cat_counter = Counter()
            for w in wa_list:
                if isinstance(w, dict) and w.get('workaround') is True:
                    cat = w.get('category', 'uncategorized')
                    if cat:
                        cat_counter[cat] += 1
            if cat_counter:
                print(f'  Categories:')
                for cat, cnt in cat_counter.most_common(5):
                    print(f'    {cat}: {cnt}')
except Exception:
    pass

print()
print('=== Loop Status ===')
if fail_count > 0 and autofix_count == 0:
    print('  WARNING: FAIL発生中だがAUTO-FIX未稼働。auto-fix対象拡大を検討せよ')
    sys.exit(1)
elif fail_count > pass_count * 0.2:
    print('  WARNING: FAIL率20%超。gate強化または新auto-fixパターン追加を検討せよ')
    sys.exit(1)
else:
    print('  OK: 第三層は健全')
    sys.exit(0)
"
