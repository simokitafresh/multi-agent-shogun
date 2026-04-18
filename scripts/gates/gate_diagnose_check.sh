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
TASK_DIR="${GATE_SESSION_STATE_TASK_DIR:-$REPO_ROOT/queue/tasks}"

# --- 1+2. YAML fields を一括取得 (awk, python3廃止) ---
DIAGNOSE_REASON=""
APPROACH_SUMMARY=""
NINJA_NAME="unknown"
_cmd_id="unknown"
while IFS=$'\001' read -r _k _v; do
    case "$_k" in
        diagnose_reason) DIAGNOSE_REASON="$_v" ;;
        approach_summary) APPROACH_SUMMARY="$_v" ;;
        worker_id)       NINJA_NAME="${_v:-unknown}" ;;
        parent_cmd)      _cmd_id="${_v:-unknown}" ;;
    esac
done < <(awk '
/^(diagnose_reason|worker_id|parent_cmd):/ {
    key = $1; sub(/:$/, "", key)
    val = substr($0, index($0, ":") + 1)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
    gsub(/^["\x27]|["\x27]$/, "", val)
    printf "%s\001%s\n", key, val
}
/^result:[[:space:]]*$/ { in_result=1; next }
in_result && /^[[:space:]]{2}summary:/ {
    key = "approach_summary"
    val = substr($0, index($0, ":") + 1)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
    gsub(/^["\x27]|["\x27]$/, "", val)
    printf "%s\001%s\n", key, val
    next
}
in_result && /^[[:space:]]{2}[a-zA-Z_][a-zA-Z0-9_]*:/ { next }
in_result && /^[^[:space:]]/ { in_result=0 }
' "$REPORT_PATH" 2>/dev/null)

# --- 3. DIVERGENT: 同一忍者×同一理由の連続回数を計数 (GP-197) ---
CONSECUTIVE=0
if [ -f "$LOG_FILE" ] && [ -n "$BLOCK_REASONS" ] && [ "$NINJA_NAME" != "unknown" ]; then
    CONSECUTIVE=$(awk -v ninja="$NINJA_NAME" -v current="$BLOCK_REASONS" '
    { lines[NR] = $0 }
    END {
        # main reason: before first ";"
        n = split(current, cp, ";")
        main_current = (n > 0 ? cp[1] : current)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", main_current)
        count = 0
        for (i = NR; i >= 1; i--) {
            line = lines[i]
            if (line !~ /result: FAIL/) continue
            if (line !~ (ninja "_report")) continue
            if (match(line, /reasons:[[:space:]]*/)) {
                reasons_str = substr(line, RSTART + RLENGTH)
                gsub(/^["\x27][[:space:]]*|[[:space:]]*["\x27]$/, "", reasons_str)
                n2 = split(reasons_str, rp, ";")
                main_reason = (n2 > 0 ? rp[1] : reasons_str)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", main_reason)
                if (main_reason == main_current) { count++ } else { break }
            } else { break }
        }
        print count
    }
    ' "$LOG_FILE" 2>/dev/null)
fi

# --- 3.5 prior_attempts similarity (GP-2070 DIVERGENT v2) ---
SIM_LEVEL="none"
SIM_MESSAGE=""
if [ "$NINJA_NAME" != "unknown" ] && [ -f "$TASK_DIR/${NINJA_NAME}.yaml" ] && [ -n "$DIAGNOSE_REASON$APPROACH_SUMMARY" ]; then
    while IFS=$'\001' read -r _sim_level _sim_message; do
        SIM_LEVEL="${_sim_level:-none}"
        SIM_MESSAGE="${_sim_message:-}"
    done < <(python3 - "$TASK_DIR/${NINJA_NAME}.yaml" "$DIAGNOSE_REASON" "$APPROACH_SUMMARY" <<'PY'
import re
import sys
import yaml

task_yaml = sys.argv[1]
current_diag = sys.argv[2].strip()
current_approach = sys.argv[3].strip()

def tokenize(text: str):
    text = text.lower()
    tokens = set(re.findall(r"[a-z0-9_]{2,}", text))
    jp = re.sub(r"[\x00-\x7f\s]", "", text)
    for i in range(len(jp) - 1):
        tokens.add(jp[i:i+2])
    return tokens

def similarity(a: str, b: str) -> float:
    if not a or not b:
        return 0.0
    ta = tokenize(a)
    tb = tokenize(b)
    if not ta or not tb:
        return 0.0
    union = ta | tb
    return len(ta & tb) / len(union) if union else 0.0

def collect_attempts(node):
    attempts = []
    for key in ("session_state", "previous_failures"):
        ss = node.get(key) if isinstance(node, dict) else None
        if not isinstance(ss, dict):
            continue
        pa = ss.get("prior_attempts")
        if isinstance(pa, list):
            for item in pa:
                if isinstance(item, dict):
                    attempts.append(item)
        elif ss.get("attempt") or ss.get("last_block_reason"):
            attempts.append({
                "attempt": ss.get("attempt", 0),
                "block_reason": ss.get("last_block_reason", ""),
                "diagnose_reason": ss.get("diagnose_reason", ""),
                "approach_summary": ss.get("approach_summary", ""),
            })
    return attempts

try:
    with open(task_yaml, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    print("none\001")
    raise SystemExit(0)

task_node = data.get("task") or data
attempts = collect_attempts(task_node)
if not attempts:
    print("none\001")
    raise SystemExit(0)

best = None
for item in attempts:
    prev_diag = str(item.get("diagnose_reason", "") or item.get("block_reason", "")).strip()
    prev_app = str(item.get("approach_summary", "") or "").strip()
    diag_sim = similarity(current_diag, prev_diag)
    app_sim = similarity(current_approach, prev_app)
    if best is None or (diag_sim + app_sim) > (best[0] + best[1]):
        best = (diag_sim, app_sim, item)

if best is None:
    print("none\001")
    raise SystemExit(0)

diag_sim, app_sim, item = best
attempt_no = item.get("attempt", "?")
msg = f"prior_attempts[{attempt_no}] diag={diag_sim:.2f} approach={app_sim:.2f}"

if current_diag and current_approach and diag_sim >= 0.70 and app_sim >= 0.70:
    print(f"block\001{msg}")
elif diag_sim >= 0.80 or app_sim >= 0.80:
    print(f"warn\001{msg}")
else:
    print(f"none\001{msg}")
PY
)
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
    if [ "$SIM_LEVEL" = "block" ]; then
        echo ""
        echo "━━━ DIVERGENT v2: 類似診断/類似アプローチ再提出 ━━━"
        echo "★ prior_attempts と今回の diagnose_reason / approach_summary が近すぎる。"
        echo "  $SIM_MESSAGE"
        echo "  前回と同じ仮説・同じ直し方を繰り返すな。仮説を転換せよ。"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        exit 1
    fi
    if [ "$SIM_LEVEL" = "warn" ]; then
        echo "[DIAGNOSE] WARN: prior_attempts と類似した診断/アプローチの再提出を検出 ($SIM_MESSAGE)" >&2
    fi
    echo "[DIAGNOSE] OK: diagnose_reason記入確認 (${#DIAGNOSE_REASON}文字)" >&2
    exit 0
fi

exit 0
