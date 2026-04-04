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

# ── compound_chain チェック (draft/reportレビュー) ──
# 2026-04-05追加: 「この選択が10回繰り返されたら何が起きるか」
# deepdive Phase 4: 理解では行動は変わらない→gateに埋め込む
COMPOUND_RESULT=$(python3 -c "
import re

with open('$LOG_FILE') as f:
    content = f.read()

# review_type: draft のエントリを抽出(直近10件)
blocks = re.split(r'\n- cmd_id:', content)
recent_drafts = []
for block in blocks[1:]:
    if 'review_type: draft' in block:
        cmd_match = re.search(r'^\s*(\S+)', block)
        cmd_id = cmd_match.group(1).strip() if cmd_match else '?'
        has_compound = 'compound_chain:' in block
        recent_drafts.append((cmd_id, has_compound))

missing = []
for cmd_id, has_compound in recent_drafts[-10:]:
    if not has_compound:
        missing.append(cmd_id)

if missing:
    print('COMPOUND_MISSING:' + ','.join(missing))
else:
    print('COMPOUND_PASS')
" 2>/dev/null)

compound_missing=$(echo "$COMPOUND_RESULT" | grep '^COMPOUND_MISSING:' | sed 's/^COMPOUND_MISSING://' | tr ',' '\n')
compound_pass=$(echo "$COMPOUND_RESULT" | grep -c '^COMPOUND_PASS' || true)

if (( compound_pass > 0 )); then
    echo "PASS: 直近draftレビュー全てにcompound_chain確認"
else
    if [ -n "$compound_missing" ]; then
        compound_count=$(echo "$compound_missing" | wc -l)
        echo "WARN: ${compound_count}件のdraftレビューにcompound_chainなし(「この選択が10回繰り返されたら?」):"
        echo "$compound_missing" | while read -r id; do echo "  - $id"; done
        warn=1
    fi
fi

if (( all_pass > 0 )) && (( compound_pass > 0 )); then
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
