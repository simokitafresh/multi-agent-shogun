#!/bin/bash
# gate_gunshi_cs_checklist.sh — consultation/self_studyエントリのCS観点チェックリスト強制
# @source: cmd_1494 (CoDD分析4サイクルで自己検出率0%→CS観点プロトコル定義)
# 知性の外部化: CS観点を軍師の意志に依存させず、自動検証で強制
# Usage: bash scripts/gates/gate_gunshi_cs_checklist.sh
# Exit: 0=PASS(全エントリにcs_checklist), 1=WARN(欠落あり)

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/gunshi_review_log.yaml"

if [ ! -f "$LOG_FILE" ]; then
    echo "SKIP: gunshi_review_log.yaml not found"
    exit 0
fi

# 直近N件のself_study/consultationエントリにcs_checklistがあるか確認
# 全件チェックは過去データに不公平(定義前)。直近10件のみ。
# cmd_1501: causal_chainフィールドも併せてチェック
RESULT=$(python3 -c "
import re, sys

with open('$LOG_FILE') as f:
    content = f.read()

blocks = content.split('\n- id: ')
recent_ss = []
for block in blocks[1:]:
    if 'type: self_study' in block or 'type: consultation' in block:
        id_match = re.match(r'(\S+)', block)
        entry_id = id_match.group(1) if id_match else '?'
        has_cs = 'cs_checklist:' in block
        has_causal = 'causal_chain:' in block
        recent_ss.append((entry_id, has_cs, has_causal))

cs_missing = []
causal_missing = []
for entry_id, has_cs, has_causal in recent_ss[-10:]:
    if not has_cs:
        cs_missing.append(entry_id)
    if not has_causal:
        causal_missing.append(entry_id)

if cs_missing:
    print('CS_MISSING:' + ','.join(cs_missing))
if causal_missing:
    print('CAUSAL_MISSING:' + ','.join(causal_missing))
if not cs_missing and not causal_missing:
    print('ALL_PASS')
" 2>/dev/null)

cs_missing=$(echo "$RESULT" | grep '^CS_MISSING:' | sed 's/^CS_MISSING://' | tr ',' '\n')
causal_missing=$(echo "$RESULT" | grep '^CAUSAL_MISSING:' | sed 's/^CAUSAL_MISSING://' | tr ',' '\n')
all_pass=$(echo "$RESULT" | grep -c '^ALL_PASS' || true)

if (( all_pass > 0 )); then
    echo "PASS: 直近self_study/consultationエントリ全てにcs_checklist+causal_chain確認"
fi

# --- Check 2: APPROVE+FM許容パターン検出 (GP-177: なぜなぜ7回の自動化ターゲット) ---
# 真因: FMを発見→mitigationが「許容/TBD/後追い」→APPROVEできてしまう=発見≠解決
# 「二度と起きない」レベルのmitigationでなければAPPROVEすべきでない
FM_TOLERANCE_RESULT=$(python3 -c "
import re

with open('$LOG_FILE') as f:
    content = f.read()

# cmd_id単位でブロック分割
entries = re.split(r'\n- cmd_id:', content)
fm_indicators = ['FM', 'failure', 'リスク', '穴', '通過する', '偽陽性', '偽陰性']
tolerance_indicators = ['許容', '後追い', 'v1で', 'TBD', 'shallow', '最小実装']
flagged = []
for entry in entries[-20:]:
    if 'review_type: draft' not in entry:
        continue
    if 'verdict: APPROVE' not in entry or 'verdict: REQUEST_CHANGES' in entry:
        continue
    obs_match = re.search(r'observations:(.*?)(?=\n  [a-z]|\n- cmd_id:|\Z)', entry, re.DOTALL)
    if not obs_match:
        continue
    obs_text = obs_match.group(1)
    has_fm = any(ind in obs_text for ind in fm_indicators)
    has_tolerance = any(ind in obs_text for ind in tolerance_indicators)
    if has_fm and has_tolerance:
        cmd_match = re.match(r'\s*(\S+)', entry)
        cmd_id = cmd_match.group(1) if cmd_match else '?'
        flagged.append(cmd_id)

if flagged:
    print('FM_TOLERANCE:' + ','.join(flagged))
else:
    print('FM_PASS')
" 2>/dev/null)

fm_flagged=$(echo "$FM_TOLERANCE_RESULT" | grep '^FM_TOLERANCE:' | sed 's/^FM_TOLERANCE://' | tr ',' '\n')
fm_pass=$(echo "$FM_TOLERANCE_RESULT" | grep -c '^FM_PASS' || true)

if [ -n "$fm_flagged" ]; then
    echo "WARN: APPROVE+FM許容パターン検出(発見≠解決):"
    echo "$fm_flagged" | while read -r id; do echo "  - $id: FMを発見しながらmitigationが許容/TBD。REQUEST_CHANGESの再検討を"; done
    warn=1
elif (( fm_pass > 0 )); then
    echo "PASS: APPROVE+FM許容パターンなし"
fi

if (( all_pass > 0 )) && (( fm_pass > 0 )); then
    exit 0
fi

warn=0
if [ -n "$cs_missing" ]; then
    cs_count=$(echo "$cs_missing" | wc -l)
    echo "WARN: ${cs_count}件のエントリにcs_checklistなし:"
    echo "$cs_missing" | while read -r id; do echo "  - $id"; done
    warn=1
fi
if [ -n "$causal_missing" ]; then
    causal_count=$(echo "$causal_missing" | wc -l)
    echo "WARN: ${causal_count}件のエントリにcausal_chainなし:"
    echo "$causal_missing" | while read -r id; do echo "  - $id"; done
    warn=1
fi

exit $warn
