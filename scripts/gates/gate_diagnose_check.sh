#!/bin/bash
# gate_diagnose_check.sh — 診断推論ステップ: BLOCK時に根本原因の言語化を強制
# おしお殿CoDD #5「Diagnose MANDATORY — まず根本原因を書いてから直せ」の環境埋込み
# 情報注入(答えを教える)ではなく思考構造の強制(考え方を教える) = 退化しない
#
# Usage: bash scripts/gates/gate_diagnose_check.sh <report_yaml_path> [block_reasons]
# Exit: 0=diagnose済み or 初回BLOCK(警告のみ), 1=未診断の再BLOCK(強制)
# 呼出元: gate_report_format.sh FAIL後 or cmd_complete_gate.sh内
#
# GP-195: 原理1行「根本原因を書いてから直せ」の環境埋込み
# GP-197: DIVERGENT — 同一理由2回連続→仮説転換強制

set -euo pipefail

REPORT_PATH="${1:-}"
BLOCK_REASONS="${2:-}"

if [ -z "$REPORT_PATH" ] || [ ! -f "$REPORT_PATH" ]; then
    echo "[DIAGNOSE] SKIP: report not found" >&2
    exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_FILE="${GATE_FIRE_LOG_FILE:-$REPO_ROOT/logs/gate_fire_log.yaml}"

# --- 1. diagnose_reason 確認 ---
DIAGNOSE_REASON=$(python3 -c "
import yaml, sys
try:
    with open('$REPORT_PATH') as f:
        data = yaml.safe_load(f)
    dr = data.get('diagnose_reason', '') if data else ''
    print(dr.strip() if isinstance(dr, str) else '')
except:
    print('')
" 2>/dev/null)

# --- 2. 忍者名とcmd_id取得 ---
read -r NINJA_NAME _cmd_id < <(python3 -c "
import yaml, sys
try:
    with open('$REPORT_PATH') as f:
        data = yaml.safe_load(f)
    print(data.get('worker_id','unknown'), data.get('parent_cmd','unknown'))
except:
    print('unknown unknown')
" 2>/dev/null)

# --- 3. DIVERGENT: 同一忍者×同一理由の連続回数を計数 (GP-197) ---
CONSECUTIVE=0
if [ -f "$LOG_FILE" ] && [ -n "$BLOCK_REASONS" ] && [ "$NINJA_NAME" != "unknown" ]; then
    # gate_fire_logから同一忍者の直近FAILを逆順で取得
    # 最新の連続同一理由をカウント
    CONSECUTIVE=$(python3 -c "
import sys

ninja = '$NINJA_NAME'
current_reasons = '$BLOCK_REASONS'
log_path = '$LOG_FILE'
count = 0

try:
    with open(log_path) as f:
        lines = f.readlines()

    # 逆順で同一忍者のFAILを走査
    for line in reversed(lines):
        if 'result: FAIL' not in line:
            continue
        if ninja + '_report' not in line:
            continue
        # reasons抽出
        if 'reasons:' in line:
            idx = line.index('reasons:')
            reasons_part = line[idx+9:].strip().strip('\"')
            # 主要理由（最初のセミコロン前）を比較
            main_reason = reasons_part.split(';')[0].strip()
            current_main = current_reasons.split(';')[0].strip()
            if main_reason == current_main:
                count += 1
            else:
                break  # 異なる理由に到達→連続終了
        else:
            break
except:
    pass

print(count)
" 2>/dev/null)
fi

# --- 4. 診断メッセージ出力 ---

# 初回BLOCK（diagnose_reason空 + 連続0-1回）: 警告+FIX hintのまま通す
if [ -z "$DIAGNOSE_REASON" ] && [ "${CONSECUTIVE:-0}" -le 1 ]; then
    echo ""
    echo "━━━ 診断推論 (Diagnose MANDATORY) ━━━"
    echo "★ BLOCKされた。修正する前に、まず報告YAMLに以下を追記せよ:"
    echo "  diagnose_reason: \"なぜこのBLOCKが発生したか。自分の何が間違っていたか\""
    echo "  ※ FIX hintのコピペ禁止。自分の言葉で原因を書け"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    exit 0  # 初回は警告のみ（段階的導入）
fi

# 再BLOCK（diagnose_reason空 + 連続2回以上）: DIVERGENT発動
if [ -z "$DIAGNOSE_REASON" ] && [ "${CONSECUTIVE:-0}" -ge 2 ]; then
    echo ""
    echo "━━━ DIVERGENT: 同じ理由で${CONSECUTIVE}回BLOCK ━━━"
    echo "★ 修正方法が間違っている可能性が高い。"
    echo "  1. diagnose_reason を必ず書け（空のまま再提出禁止）"
    echo "  2. 前回の修正方法を疑え。前提ごと見直せ"
    echo "  3. FIX hintの「答え」を鵜呑みにするな。なぜそのhintが出たかを考えよ"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    exit 1  # DIVERGENT時は強制BLOCK
fi

# diagnose_reason記入済み: 思考した証拠あり。通常フローへ
if [ -n "$DIAGNOSE_REASON" ]; then
    # FIX hintのコピペ検出（簡易）
    if echo "$DIAGNOSE_REASON" | grep -qi "report_field_set\|FIX\|bash scripts/" ; then
        echo ""
        echo "━━━ 診断推論: コピペ検出 ━━━"
        echo "★ diagnose_reasonにFIX hintをコピペしている。"
        echo "  修正手順ではなく「なぜ間違えたか」を書け。"
        echo "  例: 「report_field_set.shの存在を知らず手動編集した」"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        exit 1  # コピペは思考していない証拠→再BLOCK
    fi
    echo "[DIAGNOSE] OK: diagnose_reason記入確認 (${#DIAGNOSE_REASON}文字)" >&2
    exit 0
fi

exit 0
