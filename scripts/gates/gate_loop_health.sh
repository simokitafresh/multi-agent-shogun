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

GATE_LOG_FILE="$LOG_FILE" \
GATE_WA_FILE="$WORKAROUND_FILE" \
GATE_REPO_ROOT="$REPO_ROOT" \
python3 << 'PYEOF'
import sys, re, os, json, glob, statistics
from collections import Counter, defaultdict
import yaml

# Pre-compile patterns (minor speedup)
RE_TS = re.compile(r'ts:\s*"([^"]*)"')
RE_FILE = re.compile(r'file:\s*"([^"]*)"')
RE_RESULT = re.compile(r'result:\s*(\w[\w-]*)')
RE_REASONS = re.compile(r'reasons:\s*"(.*)"$')
RE_FIXES = re.compile(r'fixes:\s*"(.*)"$')
RE_LU = re.compile(r'lessons_useful\[\d+\]')
RE_BC = re.compile(r'binary_checks\.\w+')

log_path = os.environ['GATE_LOG_FILE']
wa_path = os.environ['GATE_WA_FILE']
repo_root = os.environ['GATE_REPO_ROOT']
gate_metrics_path = os.path.join(repo_root, 'logs', 'gate_metrics.log')

# --- Load gate fire log (flow-style format, parsed via regex) ---
entries = []
with open(log_path) as f:
    for line in f:
        line = line.strip()
        if not line or not line.startswith('- '):
            continue
        entry = {}
        ts_m = RE_TS.search(line)
        file_m = RE_FILE.search(line)
        result_m = RE_RESULT.search(line)
        reasons_m = RE_REASONS.search(line)
        fixes_m = RE_FIXES.search(line)
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

# --- 時系列原則: 直近エントリのみでinsight生成 ---
# 累積カウントは解決済みパターンのノイズを生む(殿指摘2026-03-23)
# 全体統計は全entries、insight生成用は直近WINDOW件のみ
INSIGHT_WINDOW = 20  # 直近20エントリ
recent_entries = entries[-INSIGHT_WINDOW:] if len(entries) > INSIGHT_WINDOW else entries

# --- Aggregate ---
total = len(entries)
pass_count = sum(1 for e in entries if e.get('result') == 'PASS')
fail_count = sum(1 for e in entries if e.get('result') == 'FAIL')
autofix_count = sum(1 for e in entries if e.get('result') == 'AUTO-FIXED')
recent_pass_count = sum(1 for e in recent_entries if e.get('result') == 'PASS')
recent_fail_count = sum(1 for e in recent_entries if e.get('result') == 'FAIL')

print('=== 第三層 Gate Health Report ===')
print(f'Total fires: {total} (除外: テスト{len(tmp_entries)}件)')
print(f'  PASS: {pass_count} ({pass_count*100//total}%)')
print(f'  FAIL: {fail_count} ({fail_count*100//total}%)')
print(f'  AUTO-FIXED: {autofix_count}')
print()

# --- Extract individual error reasons from FAIL entries ---
# 全体統計用(reason_counter_all)とinsight生成用(reason_counter)を分離
reason_counter_all = Counter()
reason_counter = Counter()
reason_files = defaultdict(list)
recent_set = set(id(e) for e in recent_entries)

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
        # e.g., 'verdict: "CONDITIONAL_PASS"' → 'verdict: invalid'
        pattern = reason
        pattern = RE_LU.sub('lessons_useful[N]', pattern)
        pattern = RE_BC.sub('binary_checks.ACx', pattern)
        reason_counter_all[pattern] += 1
        # insight生成用カウンタは直近エントリのみ(時系列原則)
        if id(e) in recent_set:
            reason_counter[pattern] += 1
        fname = e.get('file', '')
        reason_files[pattern].append(fname)

if reason_counter_all:
    print('=== Recurring FAIL Patterns (成熟候補・全期間) ===')
    for pattern, count in reason_counter_all.most_common(10):
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

# Check for patterns that fire > 5 times and are auto-fixable (直近INSIGHT_WINDOW)
for pattern, count in reason_counter.most_common():
    if count >= 5:
        if 'is dict (must be list)' in pattern:
            recommendations.append(f'UPGRADE: "{pattern}" ({count}回) → gate_report_autofix.shにdict→list変換追加')
        elif 'MISSING' in pattern and count >= 10:
            recommendations.append(f'INVESTIGATE: "{pattern}" ({count}回) → テンプレートにデフォルト値追加を検討')

if recommendations:
    for r in recommendations:
        print(f'  {r}')
else:
    print('  現時点で成熟提案なし')

# --- task duration anomaly detection from recent CLEAR cmds ---
duration_rows = []
if os.path.isfile(gate_metrics_path):
    with open(gate_metrics_path, encoding='utf-8', errors='replace') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) < 10 or parts[2] != 'CLEAR':
                continue
            m = re.search(r'duration_sec=(\d+)', parts[9])
            if not m:
                continue
            duration_rows.append({
                'ts': parts[0],
                'cmd_id': parts[1],
                'duration_sec': int(m.group(1)),
            })

recent_duration_rows = duration_rows[-20:] if len(duration_rows) > 20 else duration_rows
if len(recent_duration_rows) >= 5:
    median_duration = statistics.median(row['duration_sec'] for row in recent_duration_rows)
    anomalies = []
    for row in recent_duration_rows:
        duration_sec = row['duration_sec']
        delta = duration_sec - median_duration
        ratio = (duration_sec / median_duration) if median_duration > 0 else float('inf')
        if delta >= 900 and ratio >= 1.5:
            anomalies.append((ratio, row, delta))

    if anomalies:
        print()
        print('=== Task Duration Outlier Check ===')
        for ratio, row, delta in sorted(anomalies, key=lambda item: (-item[0], -item[2], item[1]['cmd_id']))[:3]:
            print(
                f'WARNING: task duration異常値 {row["cmd_id"]} '
                f'(duration={row["duration_sec"]}s, median={median_duration:.1f}s, ratio={ratio:.2f}x, delta=+{delta:.1f}s)'
            )

# --- CTX% anomaly detection from recent CLEAR cmds (cmd_2129) ---
ctx_rows = []
if os.path.isfile(gate_metrics_path):
    with open(gate_metrics_path, encoding='utf-8', errors='replace') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) < 3 or parts[2] != 'CLEAR':
                continue
            m = re.search(r'ctx_pct=(\d+)', line)
            if not m:
                continue
            ctx_rows.append({
                'ts': parts[0],
                'cmd_id': parts[1],
                'ctx_pct': int(m.group(1)),
            })

recent_ctx_rows = ctx_rows[-20:] if len(ctx_rows) > 20 else ctx_rows
if len(recent_ctx_rows) >= 5:
    median_ctx = statistics.median(row['ctx_pct'] for row in recent_ctx_rows)
    ctx_anomalies = []
    for row in recent_ctx_rows:
        ctx_pct = row['ctx_pct']
        delta = ctx_pct - median_ctx
        ratio = (ctx_pct / median_ctx) if median_ctx > 0 else float('inf')
        if delta >= 20 and ratio >= 1.5:
            ctx_anomalies.append((ratio, row, delta))

    if ctx_anomalies:
        print()
        print('=== CTX% Outlier Check ===')
        for ratio, row, delta in sorted(ctx_anomalies, key=lambda item: (-item[0], -item[2], item[1]['cmd_id']))[:3]:
            print(
                f'WARNING: CTX%異常値 {row["cmd_id"]} '
                f'(ctx_pct={row["ctx_pct"]}%, median={median_ctx:.1f}%, ratio={ratio:.2f}x, delta=+{delta:.1f}pt)'
            )

# === Auto-insight generation: recurring patterns → queue/insights.yaml ===
# Phase 4原則: 理解だけでは行動は変わらない → 自動化×強制
# 成熟候補を自動でinsight起票し、アクション強制
insights_file = os.path.join(repo_root, 'queue', 'insights.yaml')
existing_insights = set()
try:
    with open(insights_file) as f:
        for line in f:
            s = line.strip()
            if s.startswith('insight:'):
                raw = s[len('insight:'):].strip()
                try:
                    # json.loads properly decodes JSON-encoded strings (handles \\\" etc.)
                    val = json.loads(raw) if raw.startswith('"') else raw.strip("'")
                except Exception:
                    val = raw.strip('"')
                existing_insights.add(val)
except Exception:
    pass

new_insights = []
# 時系列原則: insight生成は直近INSIGHT_WINDOWエントリのみ(解決済みパターンの再起票防止)
for pattern, count in reason_counter.most_common():
    if count < 5:
        continue
    # Build insight message
    if 'is dict (must be list)' in pattern:
        msg = f'GATE成熟: {pattern} ({count}回発火) → gate_report_autofix.shにdict-list変換追加せよ'
    elif 'MISSING' in pattern and count >= 10:
        msg = f'テンプレート強化: {pattern} ({count}回発火) → report templateにデフォルト値追加せよ'
    elif count >= 10:
        msg = f'高頻度FAIL: {pattern} ({count}回発火) → GP-107(消火4問)で判定後にgate強化を検討せよ。auto-fix化は消火構造の可能性あり'
    else:
        continue
    # Deduplicate: normalize pattern (unescape \" → ") and check if it's in any existing insight
    # Use pattern (not full msg with count) since count changes each run
    pattern_norm = pattern.replace('\\"', '"')
    if any(pattern_norm[:60] in ex.replace('\\"', '"') for ex in existing_insights):
        continue
    new_insights.append(msg)

if new_insights:
    import subprocess
    print(f'\n=== Auto-Insight Generation ===')
    insight_script = os.path.join(repo_root, 'scripts', 'insight_write.sh')
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
    wa_true = 0
    wa_false = 0
    cat_counter = Counter()
    cur_wa = None
    cur_cat = None
    with open(wa_path) as f:
        for line in f:
            s = line.strip()
            if s.startswith('- '):
                # new entry: flush previous
                if cur_wa is True and cur_cat:
                    cat_counter[cur_cat] += 1
                cur_wa = None
                cur_cat = None
                # inline single-line entry
                if 'workaround: true' in s:
                    cur_wa = True
                    wa_true += 1
                elif 'workaround: false' in s:
                    cur_wa = False
                    wa_false += 1
                m = re.search(r'category:\s*(\S+)', s)
                if m:
                    cur_cat = m.group(1)
            elif s.startswith('workaround:'):
                val = s.split(':', 1)[1].strip()
                if val == 'true':
                    cur_wa = True
                    wa_true += 1
                elif val == 'false':
                    cur_wa = False
                    wa_false += 1
            elif s.startswith('category:'):
                cur_cat = s.split(':', 1)[1].strip().strip("'\"")
        # flush last entry
        if cur_wa is True and cur_cat:
            cat_counter[cur_cat] += 1
    wa_total = wa_true + wa_false
    if wa_total > 0:
        wa_pct = wa_true * 100 // wa_total
        print(f'=== 第二層 Workaround Rate ===')
        print(f'  workaround: {wa_true}/{wa_total} ({wa_pct}%)')
        if cat_counter:
            print('  Categories:')
            for cat, cnt in cat_counter.most_common(5):
                print(f'    {cat}: {cnt}')
except Exception:
    pass

print()
# --- Self-correction rate: files that FAILed then later PASSed ---
file_events = defaultdict(list)
for e in entries:
    fname = e.get('file', '')
    if not fname:
        continue
    file_events[fname].append(e.get('result', ''))

# Count files that had at least one FAIL
files_with_fail = set()
files_self_corrected = set()
for fname, results in file_events.items():
    fail_seen = False
    for r in results:
        if r == 'FAIL':
            fail_seen = True
            files_with_fail.add(fname)
        elif r == 'PASS' and fail_seen:
            files_self_corrected.add(fname)
            break  # already counted

sc_total = len(files_with_fail)
sc_corrected = len(files_self_corrected)
sc_pct = (sc_corrected * 100 // sc_total) if sc_total > 0 else 0

print(f'=== Self-correction: {sc_corrected}/{sc_total} ({sc_pct}%) ===')
print()

# Classify recent FAIL patterns: format(auto-fixable) vs quality(品質判断)
quality_fail_recent = 0
format_fail_recent = 0
for pattern, count in reason_counter.items():
    af = False
    if 'is dict (must be list)' in pattern:
        af = True
    elif 'is string' in pattern and 'lesson_candidate' not in pattern:
        af = True
    if af:
        format_fail_recent += count
    else:
        quality_fail_recent += count

# === Hold-out vs Training gate FAIL分布比較 ===
# 修行(L1-L4)でカバーしたパターン(training)と未カバーのパターン(hold-out)のFAIL数を比較。
# 汎化成功: 両セットのFAIL数が同程度。過適合: hold-outが高止まり。
# context/training-cycle.md §27参照

TRAINING_KEYS = [
    'verdict', 'binary_checks', 'lessons_useful', 'lesson_candidate',
    'self_gate_check', 'files_modified', 'status', 'purpose_validation',
    'result.summary',
]
HOLDOUT_KEYS = [
    'assumption_check', 'simplicity_check', 'assumption_invalidation',
    'knowledge_candidate', 'skill_candidate', 'decision_candidate',
    'hook_failures', 'ac_version_read',
]

training_fails = 0
holdout_fails = 0
training_fail_files = set()
holdout_fail_files = set()

for e in entries:
    if e.get('result') != 'FAIL':
        continue
    reasons_str = e.get('reasons', '')
    fname = e.get('file', '')
    for reason in reasons_str.split('; '):
        r = reason.strip()
        if not r:
            continue
        if any(k in r for k in TRAINING_KEYS):
            training_fails += 1
            training_fail_files.add(fname)
        elif any(k in r for k in HOLDOUT_KEYS):
            holdout_fails += 1
            holdout_fail_files.add(fname)

t_files = len(training_fail_files)
h_files = len(holdout_fail_files)
# FAILファイル数ベースのパーセント(FAILエントリのreasonは複数あるため件数ベースは100%超になる)
fail_files_total = len(set(e.get('file', '') for e in entries if e.get('result') == 'FAIL' and e.get('file')))
t_pct = t_files * 100 // fail_files_total if fail_files_total > 0 else 0
h_pct = h_files * 100 // fail_files_total if fail_files_total > 0 else 0

print('=== Hold-out vs Training FAIL分布 ===')
print(f'  Training set FAIL: {training_fails}件 [{t_files}ファイル/{fail_files_total}FAILファイルの{t_pct}%]')
print(f'  Hold-out set FAIL: {holdout_fails}件 [{h_files}ファイル/{fail_files_total}FAILファイルの{h_pct}%]')
if fail_files_total > 0:
    if holdout_fails == 0 and training_fails == 0:
        print('  -> FAIL記録なし')
    elif holdout_fails == 0:
        print('  -> hold-outパターンのFAILなし: 汎化良好 or hold-out未計測')
    elif h_pct > t_pct + 20:
        print(f'  -> WARNING: hold-out FAILファイルがtraining FAILファイルより{h_pct - t_pct}pt高い。過適合の疑い。context/training-cycle.md §27 L5設計検討')
    elif t_pct > h_pct + 20:
        print(f'  -> training setにまだ未解決パターン多い。既存L修行継続')
    else:
        print(f'  -> 差{abs(h_pct - t_pct)}pt: 汎化概ね良好')
print()

# === task_clarity_score 平均 (cmd_2130) ===
_tc_scores = []
for _rdir in [os.path.join(repo_root, 'queue', 'reports'), os.path.join(repo_root, 'archive', 'reports')]:
    for _rp in glob.glob(os.path.join(_rdir, '*_report_*.yaml')):
        try:
            with open(_rp, encoding='utf-8') as _rf:
                _rd = yaml.safe_load(_rf) or {}
            _tc = _rd.get('task_clarity') or {}
            _score = _tc.get('score', '')
            if _score is not None and str(_score).strip() not in ('', 'null'):
                _tc_scores.append(float(str(_score).strip()))
        except Exception:
            pass
print('=== task_clarity_score 平均 ===')
if _tc_scores:
    _tc_avg = sum(_tc_scores) / len(_tc_scores)
    print(f'  対象: {len(_tc_scores)}件 / 平均: {_tc_avg:.1f} / 最小: {min(_tc_scores):.0f} / 最大: {max(_tc_scores):.0f}')
else:
    print('  データなし (task_clarity.score記入済み報告が0件)')
print()

print('=== Loop Status ===')
if fail_count > 0 and autofix_count == 0:
    if sc_total > 0 and sc_pct >= 80:
        print(f'  OK: 免疫系正常（自己修正率{sc_pct}%）')
        sys.exit(0)
    elif format_fail_recent > 0:
        print(f'  WARNING: フォーマット系FAIL {format_fail_recent}件が未auto-fix。新フォーマットパターンの成熟提案を確認せよ')
        sys.exit(1)
    elif quality_fail_recent > 0:
        print(f'  INFO: 品質系FAIL {quality_fail_recent}件は意図的BLOCK(GP-107撤去済み)。修行サイクルで対応')
        sys.exit(0)
    else:
        print('  OK: 直近のFAILパターンなし')
        sys.exit(0)
elif recent_fail_count > recent_pass_count * 0.3:
    print('  WARNING: FAIL率30%超。gate強化を検討せよ。新auto-fixパターン追加はGP-107(消火4問)で判定必須')
    sys.exit(1)
else:
    print('  OK: 第三層は健全')
    sys.exit(0)
PYEOF
