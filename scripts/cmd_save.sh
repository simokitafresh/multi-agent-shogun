#!/usr/bin/env bash
# ============================================================
# cmd_save.sh
# 将軍がEdit toolでshogun_to_karo.yamlに書いたcmdブロックの保存前安全チェック
#
# Usage: bash scripts/cmd_save.sh <cmd_id>
#   cmd_id: 数字のみ（例: 1148）またはcmd_付き（例: cmd_1148）
#
# チェック内容:
#   1. cmdブロックがshogun_to_karo.yamlに存在するか
#   2. archive/cmds/配下の完了済みcmd_idとの重複チェック
#   3. quality_gateフィールド検査（q1_firefighting, q2_learning, q3_next_quality, q4_depth[WARNING]）
#   4. flock競合検出（家老との同時書き込み防止）
#   12. 内容重複チェック（キュー直近20件+archive直近20ファイルのtitle+purposeとの類似度比較）
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

QUEUE_FILE="${CMD_SAVE_QUEUE_FILE:-$PROJECT_DIR/queue/shogun_to_karo.yaml}"
ARCHIVE_CMD_DIR="${CMD_SAVE_ARCHIVE_CMD_DIR:-$PROJECT_DIR/queue/archive/cmds}"
QUALITY_LOG_FILE="${CMD_QUALITY_LOG_FILE:-$PROJECT_DIR/logs/cmd_design_quality.yaml}"
LOCK_FILE="/tmp/shogun_to_karo.lock"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/firefighting_keywords.sh"

CMD_DIAGNOSIS=""
PRIOR_ATTEMPT_COUNT=0
CMD_SAVE_STDERR_LOG="$(mktemp)"
exec 3>&2
exec 2> >(tee -a "$CMD_SAVE_STDERR_LOG" >&3)

extract_cmd_diagnosis() {
    local block_text="${1:-}"
    echo "$block_text" | awk '
        /quality_gate:/ { in_qg=1; next }
        in_qg && /^[[:space:]]{6,}diagnosis:[[:space:]]*/ {
            sub(/^[[:space:]]*diagnosis:[[:space:]]*/, "")
            gsub(/^["'\'']|["'\'']$/, "")
            print
            exit
        }
        in_qg && /^[[:space:]]{4}[a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
    '
}

show_prior_attempts() {
    [[ -f "$QUALITY_LOG_FILE" ]] || return 0

    local prior_output
    prior_output=$(CMD_SAVE_CMD_ID="$CMD_ID" CMD_SAVE_QUALITY_LOG="$QUALITY_LOG_FILE" python3 - <<'PY'
import os
import yaml

cmd_id = os.environ.get("CMD_SAVE_CMD_ID", "")
log_path = os.environ.get("CMD_SAVE_QUALITY_LOG", "")

if not cmd_id or not log_path or not os.path.exists(log_path):
    print(0)
    raise SystemExit(0)

with open(log_path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

entries = data.get("entries", []) if isinstance(data, dict) else []
filtered = []
for entry in entries:
    if not isinstance(entry, dict):
        continue
    if entry.get("cmd_id") != cmd_id:
        continue
    if entry.get("gate_result") != "BLOCK":
        continue
    if entry.get("source") != "cmd_save":
        continue
    filtered.append(entry)

print(len(filtered))
for idx, entry in enumerate(filtered, start=1):
    reason = str(entry.get("notes", "") or "").split("|")[0].strip() or "unknown"
    diagnosis = str(entry.get("diagnosis", "") or "").strip()
    if diagnosis:
        print(f"Attempt {idx}: {reason} diagnosis: {diagnosis}")
    else:
        print(f"Attempt {idx}: {reason}")
PY
)

    PRIOR_ATTEMPT_COUNT=$(echo "$prior_output" | head -n1 | tr -d '[:space:]')
    [[ "${PRIOR_ATTEMPT_COUNT:-0}" =~ ^[0-9]+$ ]] || PRIOR_ATTEMPT_COUNT=0
    (( PRIOR_ATTEMPT_COUNT > 0 )) || return 0

    echo "★ Prior attempts (同じcmd):" >&2
    echo "$prior_output" | tail -n +2 | while IFS= read -r line; do
        [[ -n "$line" ]] && echo "  $line" >&2
    done
    echo "  DO NOT repeat these — 別のアプローチを取れ" >&2
}

count_same_reason_prior_blocks() {
    local current_reason="${1:-}"
    [[ -n "$current_reason" && -f "$QUALITY_LOG_FILE" ]] || {
        echo 0
        return 0
    }

    CMD_SAVE_CMD_ID="$CMD_ID" \
    CMD_SAVE_QUALITY_LOG="$QUALITY_LOG_FILE" \
    CMD_SAVE_BLOCK_REASON="$current_reason" \
    python3 - <<'PY'
import os
import yaml

cmd_id = os.environ.get("CMD_SAVE_CMD_ID", "")
log_path = os.environ.get("CMD_SAVE_QUALITY_LOG", "")
current_reason = os.environ.get("CMD_SAVE_BLOCK_REASON", "").strip()

if not cmd_id or not current_reason or not log_path or not os.path.exists(log_path):
    print(0)
    raise SystemExit(0)

with open(log_path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

entries = data.get("entries", []) if isinstance(data, dict) else []
filtered = [
    entry for entry in entries
    if isinstance(entry, dict)
    and entry.get("cmd_id") == cmd_id
    and entry.get("gate_result") == "BLOCK"
    and entry.get("source") == "cmd_save"
]

count = 0
for entry in reversed(filtered[-5:]):
    reason = str(entry.get("notes", "") or "").split("|")[0].strip()
    if reason == current_reason:
        count += 1
    else:
        break

print(count)
PY
}

extract_last_block_reason() {
    python3 - "$CMD_SAVE_STDERR_LOG" <<'PY'
import re
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()
except FileNotFoundError:
    print("")
    raise SystemExit(0)

for line in reversed(lines):
    match = re.match(r"BLOCK:\s*(.+)", line.strip())
    if match:
        print(match.group(1).strip())
        break
else:
    print("")
PY
}

log_cmd_save_block() {
    local block_reason="${1:-}"
    [[ -n "$block_reason" && -f "$SCRIPT_DIR/cmd_quality_log.sh" ]] || return 0

    CMD_QUALITY_LOG_FILE="$QUALITY_LOG_FILE" \
    CMD_QUALITY_SOURCE="cmd_save" \
    CMD_QUALITY_DIAGNOSIS="$CMD_DIAGNOSIS" \
    bash "$SCRIPT_DIR/cmd_quality_log.sh" "$CMD_ID" "BLOCK" "no" "0" "$block_reason" >/dev/null 2>&1 || true
}

handle_cmd_save_exit() {
    local status=$?
    trap - EXIT

    if [[ "$status" -ne 0 ]]; then
        local block_reason same_reason_count
        block_reason="$(extract_last_block_reason)"

        if [[ -n "$block_reason" ]]; then
            if [[ -n "$CMD_DIAGNOSIS" ]]; then
                echo "診断: $CMD_DIAGNOSIS" >&2
            fi

            echo "★ 診断せよ: なぜこのBLOCKが起きたか？根本原因を1行で書け。" >&2
            echo '★ 修正前に: quality_gateに diagnosis: "根本原因の1行記述" を追加してから再実行せよ。' >&2

            same_reason_count="$(count_same_reason_prior_blocks "$block_reason" | tr -d '[:space:]')"
            [[ "$same_reason_count" =~ ^[0-9]+$ ]] || same_reason_count=0
            if (( same_reason_count >= 1 )); then
                echo "★ DIVERGENT: 同じチェック($block_reason)で2回連続BLOCK。" >&2
                echo "  根本的に異なるアプローチを検討せよ。" >&2
            fi

            log_cmd_save_block "$block_reason"
        fi
    fi

    rm -f "$CMD_SAVE_STDERR_LOG"
    exit "$status"
}

trap 'handle_cmd_save_exit' EXIT

# --- Usage ---
if [[ $# -lt 1 ]]; then
    echo "Usage: bash scripts/cmd_save.sh <cmd_id>" >&2
    echo "  cmd_id: 数字のみ（例: 1148）またはcmd_付き（例: cmd_1148）" >&2
    exit 1
fi

# --- cmd_id正規化（cmd_プレフィックスを付与） ---
RAW_ID="$1"
if [[ "$RAW_ID" =~ ^cmd_ ]]; then
    CMD_ID="$RAW_ID"
else
    CMD_ID="cmd_${RAW_ID}"
fi

WARN_COUNT=0
CMD_BLOCK=""
CMD_BLOCK_NC=""

# --- Check 1: cmdブロック存在確認 ---
if [[ ! -f "$QUEUE_FILE" ]]; then
    echo "WARN: $QUEUE_FILE が存在しません" >&2
    WARN_COUNT=$((WARN_COUNT + 1))
elif ! grep -q "  ${CMD_ID}:" "$QUEUE_FILE"; then
    echo "WARN: ${CMD_ID} のブロックが $QUEUE_FILE に見つかりません" >&2
    WARN_COUNT=$((WARN_COUNT + 1))
fi

# --- Check 1.5: 委任済みcmd再保存BLOCK ---
# cmd_1688事故: 将軍が委任済みcmdを3回上書き→忍者フリーズ→殿指摘
# delegated_at存在 = 既に家老に委任済み。再保存は設計変更を意味する。
# CLAUDE.mdルール: 途中修正の二択(別CMD or 神速停止→再CMD)。inbox_writeで途中修正するな
if [[ -f "$QUEUE_FILE" ]] && grep -q "  ${CMD_ID}:" "$QUEUE_FILE"; then
    _DELEGATED_AT=$(awk "/^  ${CMD_ID}:/{found=1; next} found && /^  cmd_/{exit} found && /delegated_at:/{print; exit}" "$QUEUE_FILE")
    if [[ -n "$_DELEGATED_AT" ]]; then
        echo "BLOCK: ${CMD_ID} は既に委任済みです。" >&2
        echo "  $_DELEGATED_AT" >&2
        echo "  途中修正の二択: (1)別CMD_IDで発令 (2)忍者を神速停止→回復後に新CMD" >&2
        echo "  同一cmd_idの上書きは忍者のフリーズ・成果物無効化を引き起こします(cmd_1688実証済み)" >&2
        exit 1
    fi
fi

# --- Check 2: 重複チェック（アーカイブ済みcmd_idとの衝突） ---
if [[ -d "$ARCHIVE_CMD_DIR" ]]; then
    # パターン: cmd_XXXX_completed_YYYYMMDD.yaml
    if ls "$ARCHIVE_CMD_DIR"/"${CMD_ID}"_completed_*.yaml 1>/dev/null 2>&1; then
        echo "WARN: ${CMD_ID} は既にアーカイブ済みです（重複の可能性）" >&2
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
fi

# --- Session State: 同一cmdの過去BLOCK履歴を表示 ---
if [[ -f "$QUEUE_FILE" ]] && grep -q "  ${CMD_ID}:" "$QUEUE_FILE"; then
    CMD_BLOCK=$(awk "/^  ${CMD_ID}:/{found=1; next} found && /^  cmd_/{exit} found{print}" "$QUEUE_FILE")
    CMD_BLOCK_NC=$(echo "$CMD_BLOCK" | grep -v '^\s*#' || true)
    CMD_DIAGNOSIS="$(extract_cmd_diagnosis "$CMD_BLOCK_NC")"
    show_prior_attempts
fi

# --- Check 3: quality_gateフィールド検査 ---
# cmdブロック内にquality_gate（q1_firefighting, q2_learning, q3_next_quality）があるか検査
if [[ -f "$QUEUE_FILE" ]] && grep -q "  ${CMD_ID}:" "$QUEUE_FILE"; then
    # cmdブロックを抽出（cmd_id行の次行から、次のcmd_行の直前まで）
    CMD_BLOCK=$(awk "/^  ${CMD_ID}:/{found=1; next} found && /^  cmd_/{exit} found{print}" "$QUEUE_FILE")

    # コメント行を事前除去（Check 3内で7回の重複grep -v削減）
    CMD_BLOCK_NC=$(echo "$CMD_BLOCK" | grep -v '^\s*#' || true)

    if ! echo "$CMD_BLOCK_NC" | grep -q "quality_gate:"; then
        echo "BLOCK: quality_gate未記入。3問に答えてからcmd_save.shを実行せよ" >&2
        cat >&2 <<'QG_TEMPLATE'
---
quality_gate:
  q1_firefighting: "no/yes — 理由"
  q2_learning: "奪わない/奪う — 学習機会への影響"
  q3_next_quality: "上がる/下がる — 品質への影響"
---
QG_TEMPLATE
        exit 1
    fi

    # --- Preflight: 全必須項目の存在を一括チェック（逐次BLOCK防止） ---
    # 起源: cmd_1951で7回連続BLOCK。1項目ずつexit 1するため全項目埋めるのに7往復
    # 修正: 全必須項目を一括チェックし、全ての不足を1回で表示してexit 1
    MISSING_KEYS=()
    MISSING_HINTS=()

    for _QG_KEY in q1_firefighting q2_learning q3_next_quality; do
        if ! echo "$CMD_BLOCK_NC" | grep -q "${_QG_KEY}:"; then
            MISSING_KEYS+=("$_QG_KEY")
            case "$_QG_KEY" in
                q1_firefighting)  MISSING_HINTS+=('  q1_firefighting: "no/yes — 理由"') ;;
                q2_learning)      MISSING_HINTS+=('  q2_learning: "奪わない/奪う — 学習機会への影響"') ;;
                q3_next_quality)  MISSING_HINTS+=('  q3_next_quality: "上がる/下がる — 品質への影響"') ;;
            esac
        fi
    done

    if ! echo "$CMD_BLOCK_NC" | grep -q "q5_verified_source:"; then
        MISSING_KEYS+=("q5_verified_source")
        MISSING_HINTS+=('  q5_verified_source: "structure_verified — 確認方法と対象を記載"')
    fi

    if ! echo "$CMD_BLOCK_NC" | grep -q "q8_why_what:"; then
        MISSING_KEYS+=("q8_why_what")
        MISSING_HINTS+=('  q8_why_what: "WHY: 殿指示「...」 → WHAT: ...=正の複利(...)"')
    fi

    if ! echo "$CMD_BLOCK_NC" | grep -q "q11_not_already_done:"; then
        MISSING_KEYS+=("q11_not_already_done")
        MISSING_HINTS+=('  q11_not_already_done: "未達成。確認方法と結果を記載"')
    fi

    # q7: dm-signal impl のみBLOCK
    _PF_PROJECT=$(echo "$CMD_BLOCK_NC" | grep "project:" | head -1 | sed 's/.*project: *//' | tr -d '"' | tr -d "'" | xargs)
    _PF_TASK_TYPE=$(echo "$CMD_BLOCK_NC" | awk '/task_type:/{gsub(/.*task_type: */, ""); gsub(/"/, ""); print; exit}')
    if [[ "${_PF_PROJECT:-}" == "dm-signal" && "${_PF_TASK_TYPE:-}" == "impl" ]]; then
        if ! echo "$CMD_BLOCK_NC" | grep -q "q7_definition_verified:"; then
            MISSING_KEYS+=("q7_definition_verified")
            MISSING_HINTS+=('  q7_definition_verified: "yes — 定義を一次情報で照合した事実"')
        fi
    fi

    # assumptions: AC数3以上で必須
    _PF_AC_COUNT=$(echo "$CMD_BLOCK" | grep -c "description:" 2>/dev/null || true)
    _PF_AC_COUNT=$(( ${_PF_AC_COUNT:-0} + 0 ))
    if [ "$_PF_AC_COUNT" -ge 3 ]; then
        if ! echo "$CMD_BLOCK_NC" | grep -q "assumptions:"; then
            MISSING_KEYS+=("assumptions")
            MISSING_HINTS+=('  assumptions: [{claim: "...", source: "...", trust: "verified"}]')
        fi
    fi

    if [[ ${#MISSING_KEYS[@]} -gt 0 ]]; then
        echo "BLOCK: 必須項目 ${#MISSING_KEYS[@]}件 未記入。全て記入してからcmd_save.shを再実行せよ" >&2
        echo "  未記入: ${MISSING_KEYS[*]}" >&2
        echo "  ---" >&2
        for _hint in "${MISSING_HINTS[@]}"; do
            echo "$_hint" >&2
        done
        echo "  ---" >&2
        exit 1
    fi

    # q4_depth: 段階的導入のためBLOCKではなくWARNING（WARN_COUNTに加算しない）
    if ! echo "$CMD_BLOCK_NC" | grep -q "q4_depth:"; then
        echo "WARNING: q4_depth未記入。深堀り度を記入推奨: q4_depth: \"shallow/medium/deep — 理由\"" >&2
    else
        # q4_depth値チェック: deep/mediumは時間コスト大。概算表示で確認を促す（WARN_COUNTに加算しない）
        _Q4_VAL=$(echo "$CMD_BLOCK_NC" | grep "q4_depth:" | head -1)
        if echo "$_Q4_VAL" | grep -qiE '\b(deep|medium)\b'; then
            if echo "$_Q4_VAL" | grep -qiE '\bdeep\b'; then
                echo "WARNING: q4_depth=deep/medium — 時間コスト概算: 30-60分(全忍者投入)。時間は最も高価な資源。分割・並列化を検討せよ" >&2
            else
                echo "WARNING: q4_depth=deep/medium — 時間コスト概算: 15-30分(2-3忍者)。分割で時間短縮を検討せよ" >&2
            fi
        fi
    fi

    # q5_verified_source: 存在チェックはpreflight済み。以下は内容検証のみ
    # q5検証レベル分類（cmd_1692: code_readingのみはBLOCK）
    # cmd_1481教訓: code_readingをproduction_verifiedに見せかけた。忍者に信頼度を正直に伝える(利他)
    # cmd_1692: code_readingのみでは前提未検証のためBLOCK。追加検証(isolated_test等)があれば通過
    # 除外条件: scope_mode=SCOUT OR scout_exempt=true（偵察cmdは実行前確認が目的のためcode_readingでも可）
    # infraの道具磨き(cmd_1891): q4_depth=shallow は軽微変更のためINFOに留める
    _q5_scope_mode=$(echo "$CMD_BLOCK_NC" | grep "scope_mode:" | head -1 | sed 's/.*scope_mode: *//' | tr -d '"' || true)
    _q5_scout_exempt=$(echo "$CMD_BLOCK_NC" | grep "scout_exempt:" | head -1 | sed 's/.*scout_exempt: *//' | tr -d '"' || true)
    _q5_project=$(echo "$CMD_BLOCK_NC" | grep "project:" | head -1 | sed 's/.*project: *//' | tr -d '"' || true)
    _q5_depth=$(echo "$CMD_BLOCK_NC" | grep "q4_depth:" | head -1 | sed 's/.*q4_depth: *//' | tr -d '"' || true)
    q5_val=$(echo "$CMD_BLOCK_NC" | grep "q5_verified_source:" | head -1)
    if echo "$q5_val" | grep -qiE "code_reading|コード読み|読んだだけ"; then
        if [[ "${_q5_scope_mode:-}" == "SCOUT" || "${_q5_scout_exempt:-}" == "true" ]]; then
            echo "INFO: q5=code_reading。scope_mode=SCOUTまたはscout_exempt=trueのため除外。OK" >&2
        elif [[ "${_q5_project:-}" == "infra" && "${_q5_depth:-}" == "shallow" ]]; then
            echo "INFO: q5=code_reading。project=infra かつ q4_depth=shallow のためINFO扱い。OK" >&2
        elif ! echo "$q5_val" | grep -qiE "isolated_test|structure_verified|production_verified|pipeline_test|実行|execute|本番|production|API応答|DB確認|テスト実行"; then
            echo "BLOCK: q5=code_readingのみ。コード読みだけでは前提未検証。isolated_test/structure_verified/production_verifiedのいずれかで実確認せよ" >&2
            echo '  例: q5_verified_source: "engine.py L107 code_reading + isolated_test(スクリプト実行確認)"' >&2
            exit 1
        else
            echo "INFO: q5にcode_readingを含むが追加検証あり。OK" >&2
        fi
    elif ! echo "$q5_val" | grep -qiE "実行|execute|pipeline|本番|production|API応答|DB確認|テスト実行"; then
        echo "WARNING: q5に検証方法が不明確。レベル明記推奨: code_reading(コード読み) / isolated_test(単体実行) / pipeline_test(結合実行) / production_verified(本番確認)" >&2
    fi

    # q6_not_hiding: SG8自動消火チェック（段階的導入 — BLOCKではなくWARNING）
    # 目的: 表面的対処で根源的問題を隠し改革動機を殺すcmdを防止
    # 起源: cmd_1278事件 — lessons.yaml読込削除が7,552行の構造問題を隠蔽
    if ! echo "$CMD_BLOCK_NC" | grep -q "q6_not_hiding:"; then
        echo "WARNING: q6_not_hiding未記入。「この変更は根源的問題を隠さないか？表面的対処で改革動機を殺さないか？」" >&2
        echo '  例: q6_not_hiding: "no — Vercel化は構造改革であり表面的対処ではない"' >&2
    fi

    # q7_definition_verified: cmd内定義の一次情報照合明示
    # 起源: L542 — High/Low等の研究用語は実装とテストに同じ意味を固定しないと結論がずれる
    # 目的: cmd固有定義を一次情報に照合した事実をquality_gateに明示させる
    # dm-signal impl cmd → BLOCK昇格（cmd_1903）。infra/他PJ・scout/reconはWARNING維持
    _Q7_PROJECT=$(echo "$CMD_BLOCK_NC" | grep "project:" | head -1 | sed 's/.*project: *//' | tr -d '"' | tr -d "'" | xargs)
    _Q7_TASK_TYPE=$(echo "$CMD_BLOCK_NC" | awk '/task_type:/{gsub(/.*task_type: */, ""); gsub(/"/, ""); print; exit}')
    # q7: dm-signal impl BLOCKはpreflight済み。それ以外はWARNING
    if ! echo "$CMD_BLOCK_NC" | grep -q "q7_definition_verified:"; then
        if [[ "${_Q7_PROJECT:-}" != "dm-signal" || "${_Q7_TASK_TYPE:-}" != "impl" ]]; then
            echo "WARNING: q7_definition_verified未記入。High/Lowなどcmd固有定義を一次情報へ照合したか記載推奨" >&2
            echo '  例: q7_definition_verified: "yes — High=rolling max。trade-rule/テスト期待値に定義を固定"' >&2
        fi
    fi

    # q8_why_what: 存在チェックはpreflight済み。以下は内容検証のみ
    if echo "$CMD_BLOCK_NC" | grep -q "q8_why_what:"; then
        # WHAT部分の縮小表現検出（WARN — AC2）
        _Q8_WW_VAL=$(echo "$CMD_BLOCK_NC" | grep "q8_why_what:" | head -1)
        _Q8_WHAT_PART="${_Q8_WW_VAL#*WHAT:}"
        if echo "$_Q8_WHAT_PART" | grep -qE 'のみ|だけ|一部|代表'; then
            echo "WARN: q8_why_whatのWHATに縮小表現を検出。全量やることを確認せよ" >&2
            echo "  → のみ/だけ/一部/代表 は範囲縮小のシグナル(殿厳命 2026-04-04)" >&2
            WARN_COUNT=$((WARN_COUNT + 1))
        fi
        # COMPOUND(複利の問い)検査（WARN — 2026-04-15 殿指摘「将軍に因果をたどる仕組みを」）
        # 起源: 軍師のcausal_chain+複利の問いが因果思考を強制。将軍にはなかった
        # 方法: q8に「正の複利」or「負の複利」or「複利」が含まれるか検査
        if ! echo "$_Q8_WW_VAL" | grep -qE '複利|compound'; then
            echo "WARN: q8に複利の問いがありません。「この実装選択を10回繰り返したら正の複利か負の複利か」を追記せよ" >&2
            echo '  例: q8_why_what: "WHY: 殿指摘「浅い」 WHAT: lessons_shogun.yaml作成=正の複利(毎セッション具体化)"' >&2
            WARN_COUNT=$((WARN_COUNT + 1))
        fi
        # WHY部分に殿の指示引用を強制（WARN — 2026-04-14 L-CmdDialogueFirst）
        # 起源: 殿の指示→即cmd起票で4/4失敗。対話完了前のcmd起票を防ぐ
        # 方法: q8 WHYに殿の言葉(「」引用 or 殿指示/殿裁定)が含まれるか検査
        _Q8_WHY_PART="${_Q8_WW_VAL%%→ WHAT:*}"
        if ! echo "$_Q8_WHY_PART" | grep -qE '「.*」|殿指示|殿裁定|殿指摘|殿提案'; then
            echo "WARN: q8 WHYに殿の指示引用がありません。対話で理解を固めてからcmd起票せよ" >&2
            echo "  → 「殿の言葉を引用」 or 殿指示/殿裁定/殿指摘 を含めよ(L-CmdDialogueFirst)" >&2
            WARN_COUNT=$((WARN_COUNT + 1))
        fi
    fi

    # q9_firefighting_root_cause: 消火cmdでは真因+再発防止を必須化（BLOCK — cmd_1801）
    # 起源: 消火禁止原則が理解止まりで、症状修正cmdが真因未記載のまま繰り返された
    # 対象: titleに消火キーワードが含まれるcmd（command本文は対象外 — cmd_1803）
    _Q9_SIGNAL_TEXT=$(echo "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*title:/ {
            sub(/^[[:space:]]*title:[[:space:]]*/, "")
            print
            next
        }
    ')
    if echo "$_Q9_SIGNAL_TEXT" | grep -qiE "$FIREFIGHTING_PATTERN"; then
        if ! echo "$CMD_BLOCK_NC" | grep -q "q9_firefighting_root_cause:"; then
            echo "BLOCK: 消火cmdなのにq9_firefighting_root_cause未記入。真因と再発防止を記載してからcmd_save.shを実行せよ" >&2
            echo '  形式: q9_firefighting_root_cause: "root_cause: 真因1行 | prevention: 二度と起きない仕組み1行"' >&2
            exit 1
        fi
        # q9の中身検証: root_cause: と prevention: の両方が含まれ非空であること（GP-176）
        # 存在チェックのみでは "q9: TBD" で通過する = 形式的コンプライアンス = 消火
        _Q9_VAL=$(echo "$CMD_BLOCK_NC" | grep "q9_firefighting_root_cause:" | head -1 | sed 's/.*q9_firefighting_root_cause:[[:space:]]*//')
        if ! echo "$_Q9_VAL" | grep -q "root_cause:"; then
            echo "BLOCK: q9にroot_cause:が含まれていない。真因を具体的に記載せよ" >&2
            echo '  形式: q9_firefighting_root_cause: "root_cause: 真因1行 | prevention: 二度と起きない仕組み1行"' >&2
            exit 1
        fi
        if ! echo "$_Q9_VAL" | grep -q "prevention:"; then
            echo "BLOCK: q9にprevention:が含まれていない。二度と起きない仕組みを記載せよ" >&2
            echo '  形式: q9_firefighting_root_cause: "root_cause: 真因1行 | prevention: 二度と起きない仕組み1行"' >&2
            exit 1
        fi
        _Q9_ROOT=$(echo "$_Q9_VAL" | sed -E 's/.*root_cause:[[:space:]]*([^|]*).*/\1/' | sed 's/[[:space:]]*$//')
        _Q9_PREVENTION=$(echo "$_Q9_VAL" | sed -E 's/.*prevention:[[:space:]]*(.*)/\1/' | sed 's/[[:space:]]*$//')
        if [[ ${#_Q9_ROOT} -lt 10 ]]; then
            echo "BLOCK: q9のroot_causeが短すぎる。10文字以上で具体的に記載せよ" >&2
            echo '  形式: q9_firefighting_root_cause: "root_cause: 真因1行 | prevention: 二度と起きない仕組み1行"' >&2
            exit 1
        fi
        if [[ ${#_Q9_PREVENTION} -lt 10 ]]; then
            echo "BLOCK: q9のpreventionが短すぎる。10文字以上で具体的に記載せよ" >&2
            echo '  形式: q9_firefighting_root_cause: "root_cause: 真因1行 | prevention: 二度と起きない仕組み1行"' >&2
            exit 1
        fi
        if echo "$_Q9_PREVENTION" | grep -qiE '気をつけ|注意し|徹底|意識し|漏れないよう|覚えておく|次は.*ようにする'; then
            echo "WARNING: q9のpreventionが意志依存です。『気をつける/徹底する』ではなく、gate追加・自動化・チェック強制など仕組みに置き換えてください" >&2
        fi
    fi

    # (causal_chain各論パッチは削除。q5_verified_sourceに複利の問いを統合 — 2026-04-05)

    # (q8_tool_readiness各論パッチは削除。q5の複利の問いで十分 — cmd_1742 cancel 2026-04-05)

    # q10_knowledge_boundary: 検証済み空間の明示（段階的導入 — WARNING）
    # 起源: cmd_1903 — Phase 31-32の11過ちが全てgateを通過。「無知の知」がcmd起票に強制されていない
    # 目的: cmdの前提が「前Phase/前cmdの到達点(検証済み事実)」に基づいているかを明示させる
    if ! echo "$CMD_BLOCK_NC" | grep -q "q10_knowledge_boundary:"; then
        echo "WARNING: q10_knowledge_boundary未記入。cmdの前提は検証済み空間内か？前Phase/前cmdの到達点を使っているか？" >&2
        echo '  形式例: q10_knowledge_boundary: "空間内。根拠: Phase30 β調整確立 + cmd_1896結果確認済み"' >&2
    fi

    # q11_not_already_done: 存在チェックはpreflight済み。以下は自動検索のみ

    # q11自動検索: command内スクリプト名とdocs/researchの既存成果物を照合（INFO）
    # 起源: cmd_1916 — q11手動記入は嘘が書ける。自動露出で車輪の再発明を補助的に防ぐ
    _Q11_PROJECT_DIR="${PROJECT_DIR:-${PROJECT_ROOT:-.}}"
    _Q11_RESEARCH_DIR="${_Q11_PROJECT_DIR}/docs/research"
    if [[ -d "$_Q11_RESEARCH_DIR" ]]; then
        _Q11_COMMAND_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
            /^\s*command:\s*\|/ { found=1; next }
            /^\s*command:\s*[^|]/ { found=1; sub(/^\s*command:\s*/, ""); print; next }
            found && /^\s{4,}/ { print; next }
            found && /^\s*[a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
        ')
        if [[ -n "${_Q11_COMMAND_SECTION:-}" ]]; then
            _Q11_TARGETS=$(printf '%s\n' "$_Q11_COMMAND_SECTION" | grep -oE 'scripts/[A-Za-z0-9_./-]+\.(sh|py)|[A-Za-z0-9_./-]+\.(sh|py)' | sort -u || true)
            if [[ -n "${_Q11_TARGETS:-}" ]]; then
                _Q11_ANY_MATCH=false
                while IFS= read -r _q11_target; do
                    [[ -z "$_q11_target" ]] && continue
                    _q11_base="${_q11_target##*/}"
                    # rg優先、未インストール環境はgrep -rl にフォールバック
                    # 同一ターゲット/basenameを単一走査にまとめ、docs/researchの再読込を削減する
                    if command -v rg >/dev/null 2>&1; then
                        if [[ "$_q11_base" == "$_q11_target" ]]; then
                            _Q11_MATCHES=$(rg -l -F "$_q11_target" "$_Q11_RESEARCH_DIR" 2>/dev/null || true)
                        else
                            _Q11_MATCHES=$(rg -l -F -e "$_q11_target" -e "$_q11_base" "$_Q11_RESEARCH_DIR" 2>/dev/null || true)
                        fi
                    else
                        if [[ "$_q11_base" == "$_q11_target" ]]; then
                            _Q11_MATCHES=$(grep -rl -F "$_q11_target" "$_Q11_RESEARCH_DIR" 2>/dev/null || true)
                        else
                            _Q11_MATCHES=$(
                                {
                                    grep -rl -F "$_q11_target" "$_Q11_RESEARCH_DIR" 2>/dev/null || true
                                    grep -rl -F "$_q11_base" "$_Q11_RESEARCH_DIR" 2>/dev/null || true
                                } | sort -u
                            )
                        fi
                    fi
                    [[ -z "${_Q11_MATCHES:-}" ]] && continue
                    if [[ "$_Q11_ANY_MATCH" == false ]]; then
                        echo "INFO: 関連する既存成果物を検出:" >&2
                        _Q11_ANY_MATCH=true
                    fi
                    while IFS= read -r _q11_doc; do
                        [[ -z "$_q11_doc" ]] && continue
                        _q11_rel="${_q11_doc#"${_Q11_PROJECT_DIR}"/}"
                        echo "  ${_q11_target} → ${_q11_rel}" >&2
                    done <<< "$_Q11_MATCHES"
                done <<< "$_Q11_TARGETS"
            fi
        fi
    fi

    # q8_branch_coverage: 条件分岐変更cmdの本番データ分岐確認AC提案（段階的導入 — WARNING）
    # 起源: cmd_1443事例 — 本番未使用コードパスへの無駄修正
    # 目的: type=impl + 条件分岐キーワード検出時に、本番での分岐実行頻度確認ACの追加を提案
    _Q8_TASK_TYPE=$(echo "$CMD_BLOCK_NC" | awk '/task_type:/{gsub(/.*task_type: */, ""); gsub(/"/, ""); print; exit}')
    if [[ "${_Q8_TASK_TYPE:-}" == "impl" ]]; then
        _Q8_FIELDS=$(echo "$CMD_BLOCK_NC" | grep -E '^\s*(purpose|title):' || true)
        if echo "$_Q8_FIELDS" | grep -qiE '\bif\b|\bcase\b|条件|分岐|フラグ|\bflag\b|\belif\b|\bswitch\b'; then
            echo "WARNING: q8_branch_coverage — 条件分岐変更を含むimpl cmdです。本番データでの分岐実行頻度確認ACの追加を検討してください" >&2
            echo "  推奨アクション: 本番DBで該当条件がtrue/falseになるレコード数を確認せよ" >&2
            echo "  (cmd_1443教訓: 本番未使用コードパスへの修正は無駄コスト+リスク)" >&2
        fi
    fi

    # --- Check 3.7: チェックリスト制約転写確認（WARNING） ---
    # cmd_1397事故: チェックリストStep7(再計算禁止)がcmdに転写されず忍者が再計算実行
    # cmdにチェックリスト参照がある場合、隣接Step制約の転写を促す
    if echo "$CMD_BLOCK_NC" | grep -qiE 'チェックリスト|checklist-'; then
        echo "WARNING: チェックリスト参照cmdです。隣接Stepの🛑制約(禁止事項)をACまたは制約欄に転写しましたか？" >&2
        echo "  (cmd_1397教訓: Step7再計算禁止がcmd未記載→忍者が再計算実行)" >&2
    fi
fi

# --- Check 4: flock競合検出 ---
# flock -n: ノンブロッキング。取得成功=競合なし、取得失敗=家老が書き込み中
if ! (flock -n 200) 200>"$LOCK_FILE" 2>/dev/null; then
    echo "WARN: $LOCK_FILE がロック中です（家老が書き込み中の可能性）" >&2
    WARN_COUNT=$((WARN_COUNT + 1))
fi

show_recent_completed_ninjas() {
    local snapshot_file="$PROJECT_DIR/queue/karo_snapshot.txt"
    [[ -f "$snapshot_file" ]] || return 0

    local completed_ninjas
    completed_ninjas=$(
        awk -F'|' '
            NR == FNR {
                if ($1 == "report" && ($4 == "completed" || $4 == "done")) {
                    report_done[$2] = 1
                    if (!seen[$2]++) {
                        names[++count] = $2
                    }
                }
                next
            }
            $1 == "ninja" && ($4 == "completed" || $4 == "done") {
                if (!report_done[$2] && !seen[$2]++) {
                    names[++count] = $2
                }
            }
            END {
                for (i = 1; i <= count; i++) {
                    printf "%s%s", names[i], (i < count ? ", " : "")
                }
            }
        ' "$snapshot_file" "$snapshot_file" 2>/dev/null || true
    )

    [[ -n "$completed_ninjas" ]] || return 0
    echo "  直近完了忍者一覧: $completed_ninjas" >&2
}

show_uncommitted_changes_warning() {
    local uncommitted="${1:-}"
    [[ -n "$uncommitted" ]] || return 0

    echo "WARN: 未コミット変更を検出（コミット忘れ注意）:" >&2
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        echo "  $line" >&2
    done <<< "$uncommitted"

    show_recent_completed_ninjas
}

# --- Check 5: uncommitted changes検出 ---
# WSL2 NTFS最適化: 全ファイルgit status(1.7s)→パス限定(0.2s)。7倍高速化
UNCOMMITTED=$(git -C "$PROJECT_DIR" diff --name-only -- scripts/ CLAUDE.md instructions/ config/ 2>/dev/null || true)
show_uncommitted_changes_warning "$UNCOMMITTED"

# --- Check 6: パイプラインGP重複チェック（非BLOCK — WARN_COUNTに加算しない） ---
# 新cmdのcommandフィールドからGP-XXXパターンを抽出し、
# 直近20件のdelegated/in_progress cmdと照合。一致時WARN（非BLOCK）
if [[ -f "$QUEUE_FILE" ]] && grep -q "  ${CMD_ID}:" "$QUEUE_FILE"; then
    NEW_CMD_LINE=$(awk "/^  ${CMD_ID}:/{found=1; next} found && /^  cmd_/{exit} found && /command:/{print; exit}" "$QUEUE_FILE")
    NEW_GP=$(echo "$NEW_CMD_LINE" | grep -oE 'GP-[0-9]+' | sort -u || true)

    if [[ -n "$NEW_GP" ]]; then
        RECENT_CMDS=$(grep -oE "^  cmd_[0-9]+:" "$QUEUE_FILE" | sed 's/: *$//; s/^ *//' | tail -20 | grep -v "^${CMD_ID}$" || true)

        if [[ -n "$RECENT_CMDS" ]]; then
            while IFS= read -r OTHER_CMD; do
                [[ -z "$OTHER_CMD" ]] && continue
                OTHER_BLOCK=$(awk "/^  ${OTHER_CMD}:/{found=1; next} found && /^  cmd_/{exit} found{print}" "$QUEUE_FILE")
                OTHER_STATUS=$(echo "$OTHER_BLOCK" | awk '/status:/{gsub(/.*status: */, ""); gsub(/"/, ""); print; exit}')

                if [[ "$OTHER_STATUS" == "delegated" || "$OTHER_STATUS" == "in_progress" ]]; then
                    OTHER_CMD_LINE=$(echo "$OTHER_BLOCK" | grep -m1 "command:" || true)
                    while IFS= read -r gp; do
                        [[ -z "$gp" ]] && continue
                        if echo "$OTHER_CMD_LINE" | grep -qF "$gp"; then
                            echo "WARN: ${CMD_ID} のGP番号 ${gp} が ${OTHER_CMD}(status:${OTHER_STATUS}) と重複" >&2
                        fi
                    done <<< "$NEW_GP"
                fi
            done <<< "$RECENT_CMDS"
        fi
    fi
fi

# --- Check 7: 軍師既存分析チェック（偵察cmd重複防止） ---
# 起源: cmd_1451事件 — 軍師OPT-6分析完了済みなのに偵察cmd重複起票
# 目的: recon/scout cmdの起票前に軍師の関連分析有無を確認させる
check_gunshi_analysis_overlap() {
    [[ ! -f "$QUEUE_FILE" ]] && return 0
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # task_typeがrecon/scoutの場合のみチェック（impl等は対象外）
    local TASK_TYPE
    TASK_TYPE=$(echo "$CMD_BLOCK_NC" | awk '/task_type:/{gsub(/.*task_type: */, ""); gsub(/"/, ""); print; exit}')
    if [[ "$TASK_TYPE" != "recon" && "$TASK_TYPE" != "scout" ]]; then
        return 0
    fi

    # context/gunshi-*.md の存在チェック
    local GUNSHI_FILES
    GUNSHI_FILES=$(find "$PROJECT_DIR/context" -name "gunshi-*.md" -type f 2>/dev/null)
    [[ -z "$GUNSHI_FILES" ]] && return 0

    # 軍師分析ファイルの見出しを表示
    local HIT=false
    while IFS= read -r gfile; do
        [[ -z "$gfile" || ! -f "$gfile" ]] && continue
        local title mtime_hr
        title=$(head -5 "$gfile" | grep -m1 '^#' | sed 's/^# *//')
        mtime_hr=$(date -r "$gfile" '+%m-%d %H:%M' 2>/dev/null || echo "unknown")
        if [[ "$HIT" == false ]]; then
            echo "WARNING: 偵察cmd起票前に軍師の既存分析を確認したか？" >&2
            HIT=true
        fi
        echo "  $(basename "$gfile") [$mtime_hr] — $title" >&2
    done <<< "$GUNSHI_FILES"

    if [[ "$HIT" == true ]]; then
        echo "  → 重複起票防止(cmd_1451教訓): 軍師が先行分析済みの可能性あり" >&2
    fi
}

check_gunshi_analysis_overlap

# --- Check 8: PI番号衝突チェック（Production Invariant重複防止） ---
# 起源: cmd_1453事件 — PI-015を起票したが既存PI-015と衝突。hayateがPI-016に修正
# 目的: cmdにPI-0XXが含まれる場合、既存PIと衝突しないか自動チェック
check_pi_number_collision() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # cmdブロックからPI-0XX番号を抽出
    local PI_NUMS
    PI_NUMS=$(echo "$CMD_BLOCK_NC" | grep -oE 'PI-[0-9]{3}' | sort -u || true)
    [[ -z "$PI_NUMS" ]] && return 0

    # 全projects/*.yamlから既存PI番号を収集
    local EXISTING_PIS
    EXISTING_PIS=$(grep -ohE 'PI-[0-9]{3}' "$PROJECT_DIR"/projects/*.yaml 2>/dev/null | sort -u || true)
    [[ -z "$EXISTING_PIS" ]] && return 0

    # 衝突検出
    local HIT=false
    while IFS= read -r pi; do
        [[ -z "$pi" ]] && continue
        if echo "$EXISTING_PIS" | grep -qx "$pi"; then
            if [[ "$HIT" == false ]]; then
                echo "WARNING: PI番号衝突検出（cmd_1453教訓）" >&2
                HIT=true
            fi
            echo "  $pi は既に projects/*.yaml に登録済み" >&2
        fi
    done <<< "$PI_NUMS"

    if [[ "$HIT" == true ]]; then
        # 次の空き番号を表示
        local MAX_PI
        MAX_PI=$(echo "$EXISTING_PIS" | grep -oE '[0-9]+' | sort -n | tail -1)
        local NEXT_PI
        NEXT_PI=$(printf "PI-%03d" $((10#$MAX_PI + 1)))
        echo "  → 次の空き番号: $NEXT_PI" >&2
    fi
}

check_pi_number_collision

# --- Check 9: 未消化insightsサーフェス（知識循環デッドエンド防止） ---
# 起源: insights 18件死蔵発見(2026-03-28) — 書込み専用で消費者不在
# 目的: cmd起票時にpending insightsを表示し、将軍がinsightsを消費する動線を作る
show_pending_insights() {
    local INSIGHTS_FILE="$PROJECT_DIR/queue/insights.yaml"
    [[ ! -f "$INSIGHTS_FILE" ]] && return 0

    local PENDING_COUNT
    PENDING_COUNT=$(grep -c 'status: pending' "$INSIGHTS_FILE" 2>/dev/null) || PENDING_COUNT=0
    [[ "$PENDING_COUNT" -eq 0 ]] && return 0

    echo "INFO: 未消化insights ${PENDING_COUNT}件 — 起票前に確認推奨:" >&2
    python3 - "$INSIGHTS_FILE" 3 <<'PY' >&2
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
items = data.get("insights", []) if isinstance(data, dict) else (data if isinstance(data, list) else [])
limit = int(sys.argv[2])
shown = 0
for i in items:
    if not isinstance(i, dict) or i.get("status") != "pending": continue
    text = str(i.get("insight", ""))[:70].replace("\n", " ")
    print(f"  → {text}")
    shown += 1
    if shown >= limit: break
PY
    if [[ "$PENDING_COUNT" -gt 3 ]]; then
        echo "  ... 他 $((PENDING_COUNT - 3))件 (queue/insights.yaml)" >&2
    fi
}

show_pending_insights

# --- Check 10: AC内ファイルパス存在チェック（親ディレクトリありはINFO、親も不在はBLOCK） ---
# 起源: cmd_1464事故 + cmd_1896/1899で3回連続パス誤り(2026-04-14なぜなぜ7回)
# 目的: AC内のファイルパス参照が実在するか検証。未作成でも親ディレクトリがあれば作成対象として許容する
# 真因: WARNを無視する習慣が定着し、パス誤りcmdが家老・忍者に到達する
check_ac_file_paths() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # AC内からファイルパス(拡張子付き)を抽出
    local PATHS
    PATHS=$(echo "$CMD_BLOCK_NC" | grep -oE '[A-Za-z0-9_-]+(/[A-Za-z0-9_.+-]+)+\.(py|ts|tsx|js|jsx|sh|bash|yaml|yml|json|sql|html|css|toml|cfg|env)' | sort -u || true)
    [[ -z "$PATHS" ]] && return 0

    # プロジェクトWDを取得: cmdブロックのproject → current_project → fallback
    local PROJECT_ID PROJECT_WD
    PROJECT_ID=$(echo "$CMD_BLOCK_NC" | awk '/project:/{gsub(/.*project: */, ""); gsub(/"/, ""); print; exit}')
    [[ -z "$PROJECT_ID" ]] && PROJECT_ID=$(awk '/^current_project:/{print $2}' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null)

    if [[ -n "${PROJECT_ID:-}" ]]; then
        PROJECT_WD=$(awk -v id="$PROJECT_ID" '
            /^  - id:/ { current_id = $3; gsub(/"/, "", current_id) }
            /^    path:/ && current_id == id { gsub(/.*path: *"?/, ""); gsub(/"$/, ""); print; exit }
        ' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null)
    fi

    [[ -z "${PROJECT_WD:-}" ]] && return 0

    # 各パスの存在チェック
    local HAS_MISSING=false
    local HAS_CREATABLE=false
    while IFS= read -r fpath; do
        [[ -z "$fpath" ]] && continue
        if [[ ! -e "$PROJECT_WD/$fpath" ]]; then
            local parent_dir
            parent_dir=$(dirname "$fpath")

            if [[ -d "$PROJECT_WD/$parent_dir" ]]; then
                if [[ "$HAS_CREATABLE" == false ]]; then
                    echo "INFO: AC内の未作成ファイルは親ディレクトリが存在するため作成対象として扱います:" >&2
                    HAS_CREATABLE=true
                fi
                echo "  • $fpath (parent: $PROJECT_WD/$parent_dir)" >&2
            else
                if [[ "$HAS_MISSING" == false ]]; then
                    echo "WARNING: AC内のファイルパスが存在せず、親ディレクトリも不在です（cmd_1464教訓）:" >&2
                    HAS_MISSING=true
                fi
                echo "  ✗ $fpath (missing parent: $PROJECT_WD/$parent_dir)" >&2
            fi
        fi
    done <<< "$PATHS"

    if [[ "$HAS_MISSING" == true ]]; then
        echo "  BLOCK: 親ディレクトリも不在のパスはcmd品質低下の根因。現物確認してからcmd_save.shを再実行せよ" >&2
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
}

check_ac_file_paths

# --- Check 11: impl cmd post-deploy verification AC検出（informational — WARN_COUNTに加算しない） ---
# 目的: project=dm-signal + type=impl のcmdのacceptance_criteria内にデプロイ後検証ACがない場合に警告
# 起源: cmd_1491でpush漏れ→cmd_1492で後追い発生
check_impl_push_ac() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # project取得
    local PROJECT_ID
    PROJECT_ID=$(echo "$CMD_BLOCK_NC" | awk '/project:/{gsub(/.*project: */, ""); gsub(/"/, ""); print; exit}')
    [[ "$PROJECT_ID" != "dm-signal" ]] && return 0

    # task_type取得
    local TASK_TYPE
    TASK_TYPE=$(echo "$CMD_BLOCK_NC" | awk '/task_type:/{gsub(/.*task_type: */, ""); gsub(/"/, ""); print; exit}')
    [[ "$TASK_TYPE" != "impl" ]] && return 0

    # acceptance_criteria セクションを抽出
    local AC_SECTION
    AC_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /acceptance_criteria:/ { found=1; next }
        found && /^    - / { print; next }
        found && /^      / { print; next }
        found { exit }
    ')

    # acceptance_criteriaがない場合はCMD_BLOCK_NC全体にフォールバック
    if [[ -z "$AC_SECTION" ]]; then
        AC_SECTION="$CMD_BLOCK_NC"
    fi

    # AC内にpush/deploy/verify/本番確認関連キーワードがあるか
    if ! echo "$AC_SECTION" | grep -qiE 'push|deploy|デプロイ|verify|本番確認|本番反映|本番動作|Render'; then
        echo "WARNING: project=dm-signal + type=impl のACにデプロイ後の本番動作確認が含まれていません" >&2
        echo "  デプロイ後の本番動作確認ACを追加せよ。例:" >&2
        echo '  - "ACN: git push後、Render自動デプロイ完了を確認。本番エンドポイントで変更反映を目視確認"' >&2
        echo "  (cmd_1491教訓: push漏れ→cmd_1492で後追い発生)" >&2
    fi
}

check_impl_push_ac

# --- Check 11.3: AC推奨/必須混在検出（informational — WARN_COUNTに加算しない） ---
# 起源: GP-173。verdict_override 2件(cmd_karo_fix_flock_silent)。ACに推奨事項混入→忍者正FAIL→家老override
# 目的: ACテキストに推奨キーワードが含まれる場合にWARNし、notesへの分離を促す
check_ac_must_should_mix() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local AC_SECTION
    AC_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /acceptance_criteria:/ { found=1; next }
        found && /^    - / { print; next }
        found && /^      / { print; next }
        found { exit }
    ')
    [[ -z "$AC_SECTION" ]] && return 0

    local RECOMMEND_LINES
    RECOMMEND_LINES=$(echo "$AC_SECTION" | grep -inE '推奨|optional|nice.to.have|できれば|望ましい' || true)
    if [[ -n "$RECOMMEND_LINES" ]]; then
        echo "BLOCK: ACに推奨事項が混在しています。推奨はnotesに分離し、ACは必須(MUST)のみにせよ" >&2
        echo "  AC定義: 忍者が二値(yes/no)で判定する必須完了基準。推奨/optional/nice-to-haveはnotes欄に" >&2
        echo "  該当行: $(echo "$RECOMMEND_LINES" | head -3 | tr '\n' ' ')" >&2
        echo "  根拠: verdict_override WA 2件(cmd_karo_fix_flock_silent)。推奨にno→FAIL→家老override。WARN→BLOCK昇格(GP-175)" >&2
        exit 1
    fi
}

check_ac_must_should_mix

# --- Check 11.5: 研究cmdの道具成長AC検出（informational — WARN_COUNTに加算しない） ---
# 起源: 軍師SG10 — 研究cmdで新規関数を増やしてもresearch_engine.py統合ACがないと意志依存で分岐する
# 目的: research系キーワードを含むimpl cmdで、ACにengine統合/追加/移設の明示がない場合にWARNING
check_research_tool_growth_ac() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local PROJECT_ID TASK_TYPE
    PROJECT_ID=$(echo "$CMD_BLOCK_NC" | awk '/project:/{gsub(/.*project: */, ""); gsub(/"/, ""); print; exit}')
    [[ "$PROJECT_ID" != "dm-signal" ]] && return 0

    TASK_TYPE=$(echo "$CMD_BLOCK_NC" | awk '/task_type:/{gsub(/.*task_type: */, ""); gsub(/"/, ""); print; exit}')
    [[ "$TASK_TYPE" != "impl" ]] && return 0

    local COMMAND_SECTION
    COMMAND_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /command:/ { found=1; print; next }
        found && /^    [a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
        found { print }
    ')
    [[ -z "$COMMAND_SECTION" ]] && return 0

    if ! echo "$COMMAND_SECTION" | grep -qiE 'research_engine|simulate|analysis|研究'; then
        return 0
    fi

    local AC_SECTION
    AC_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /acceptance_criteria:/ { found=1; next }
        found && /^    - / { print; next }
        found && /^      / { print; next }
        found { exit }
    ')
    [[ -z "$AC_SECTION" ]] && AC_SECTION="$CMD_BLOCK_NC"

    if echo "$AC_SECTION" | grep -qiE 'research_engine(\.py)?|engine[^[:cntrl:]]*(統合|追加|移設)|(統合|追加|移設)[^[:cntrl:]]*(research_engine|engine)'; then
        return 0
    fi

    echo "WARNING: 研究cmdで新規関数を定義する場合、research_engine.pyへの統合ACを検討せよ" >&2
    echo '  例: "ACN: 新規関数をresearch_engine.pyへ統合し、呼び出し側を移設"' >&2
    echo "  (軍師SG10: engine未統合の研究ロジックは再利用が意志依存になる)" >&2
}

check_research_tool_growth_ac

# --- Check 12: 内容重複チェック（informational — WARN_COUNTに加算しない） ---
# 起源: 重複cmd起票の構造的防止
# 目的: 新cmdのtitle+purposeと直近20件(キュー+archive)の類似度を比較しWARN（50%以上）
check_content_duplicate() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0
    [[ ! -f "$QUEUE_FILE" ]] && return 0

    python3 - "$QUEUE_FILE" "$CMD_ID" "${ARCHIVE_CMD_DIR:-}" >&2 <<'PY'
import sys, re, os, json

def tokenize(text):
    """title+purposeをトークン集合に変換。ASCII単語+日本語2gramで混合テキスト対応"""
    if not text:
        return set()
    tokens = set()
    for t in re.findall(r'[a-zA-Z][a-zA-Z0-9_.]*[a-zA-Z0-9]|[a-zA-Z0-9]{2,}', text.lower()):
        tokens.add(t)
    jp_chars = re.sub(r'[\x00-\x7f\s]', '', text)
    for i in range(len(jp_chars) - 1):
        tokens.add(jp_chars[i:i+2])
    return tokens

def similarity(s1, s2):
    """共通単語数/全単語数(Jaccard)"""
    if not s1 or not s2:
        return 0.0
    union = s1 | s2
    return len(s1 & s2) / len(union) * 100 if union else 0.0

def strip_scalar(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    return value

def parse_title_purpose(path):
    commands = {}
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.readlines()
    except Exception:
        return commands

    current_cmd = None
    current_field = None
    block_indent = None

    def ensure_entry(cmd_id):
        return commands.setdefault(cmd_id, {"title": "", "purpose": ""})

    def finalize_block():
        nonlocal current_field, block_indent
        current_field = None
        block_indent = None

    for raw_line in lines:
        line = raw_line.rstrip("\n")

        cmd_match = re.match(r"^  (cmd_\d+):\s*$", line)
        if cmd_match:
            current_cmd = cmd_match.group(1)
            ensure_entry(current_cmd)
            finalize_block()
            continue

        if current_cmd is None:
            continue

        next_cmd_match = re.match(r"^  cmd_\d+:\s*$", line)
        if next_cmd_match:
            current_cmd = None
            finalize_block()
            continue

        if current_field is not None:
            indent = len(line) - len(line.lstrip(" "))
            if not line.strip():
                commands[current_cmd][current_field] += "\n"
                continue
            if indent <= block_indent:
                finalize_block()
            else:
                commands[current_cmd][current_field] += line[block_indent:].rstrip() + "\n"
                continue

        field_match = re.match(r"^    (title|purpose):\s*(.*)$", line)
        if not field_match:
            continue

        field = field_match.group(1)
        value = field_match.group(2)
        if value in {"|", ">"} or value == "":
            commands[current_cmd][field] = ""
            current_field = field
            block_indent = 6
        else:
            commands[current_cmd][field] = strip_scalar(value)
            finalize_block()

    for entry in commands.values():
        for key in ("title", "purpose"):
            entry[key] = entry[key].strip()
    return commands

queue_file, current_cmd_id, archive_dir = sys.argv[1], sys.argv[2], sys.argv[3]
cmds = parse_title_purpose(queue_file)
current = cmds.get(current_cmd_id)
if not isinstance(current, dict):
    sys.exit(0)

new_title = str(current.get("title", "") or "")
new_purpose = str(current.get("purpose", "") or "")
new_words = tokenize(new_title) | tokenize(new_purpose)
if not new_words:
    sys.exit(0)

# Phase 1: キュー内の直近20件と比較
cmd_ids = sorted(cmds.keys())
cmd_ids = [c for c in cmd_ids if c != current_cmd_id][-20:]

hits = []
for cid in cmd_ids:
    entry = cmds[cid]
    if not isinstance(entry, dict):
        continue
    t = str(entry.get("title", "") or "")
    p = str(entry.get("purpose", "") or "")
    other_words = tokenize(t) | tokenize(p)
    sim = similarity(new_words, other_words)
    if sim >= 50:
        hits.append((cid, t[:50], sim))

if hits:
    hits.sort(key=lambda x: -x[2])
    print("WARNING: 内容重複の可能性を検出（類似度50%以上）", file=sys.stderr)
    for cid, title, sim in hits:
        print(f"  {cid}: {title} — 類似度{sim:.0f}%", file=sys.stderr)
    print("  → 重複起票でないか確認してください（BLOCKではありません）", file=sys.stderr)

# Phase 2: archive/cmds/の直近20ファイルと比較
# os.scandir()でstat情報を一括取得（glob+getmtimeのsyscall×n削減）
if os.path.isdir(archive_dir):
    cache_path = "/tmp/cmd_save_content_dup_cache.json"
    try:
        with open(cache_path, encoding="utf-8") as fh:
            cache = json.load(fh)
        if not isinstance(cache, dict):
            cache = {}
    except Exception:
        cache = {}

    cache_dirty = False
    try:
        archive_dir_stat = os.stat(archive_dir)
    except OSError:
        archive_dir_stat = None

    recent_index = cache.get("_archive_recent_files", {})
    if (
        archive_dir_stat is not None
        and isinstance(recent_index, dict)
        and recent_index.get("archive_dir") == os.path.abspath(archive_dir)
        and recent_index.get("dir_mtime_ns") == archive_dir_stat.st_mtime_ns
        and isinstance(recent_index.get("files"), list)
    ):
        archive_files = recent_index["files"]
    else:
        scanned_files = []
        for entry in os.scandir(archive_dir):
            if not entry.name.endswith(".yaml"):
                continue
            st = entry.stat()
            scanned_files.append(
                {
                    "path": entry.path,
                    "mtime_ns": st.st_mtime_ns,
                    "size": st.st_size,
                }
            )
        scanned_files.sort(key=lambda item: item["mtime_ns"], reverse=True)
        archive_files = scanned_files[:20]
        if archive_dir_stat is not None:
            cache["_archive_recent_files"] = {
                "archive_dir": os.path.abspath(archive_dir),
                "dir_mtime_ns": archive_dir_stat.st_mtime_ns,
                "files": archive_files,
            }
            cache_dirty = True

    archive_hits = []
    for archive_file in archive_files:
        af = archive_file.get("path") if isinstance(archive_file, dict) else str(archive_file)
        if not af:
            continue
        try:
            st_mtime_ns = archive_file.get("mtime_ns") if isinstance(archive_file, dict) else None
            st_size = archive_file.get("size") if isinstance(archive_file, dict) else None
            if st_mtime_ns is None or st_size is None:
                st = os.stat(af)
                st_mtime_ns = st.st_mtime_ns
                st_size = st.st_size
        except OSError:
            continue
        cache_key = os.path.abspath(af)
        cache_entry = cache.get(cache_key, {})
        if (
            isinstance(cache_entry, dict)
            and cache_entry.get("mtime_ns") == st_mtime_ns
            and cache_entry.get("size") == st_size
            and isinstance(cache_entry.get("commands"), dict)
        ):
            acmds = cache_entry["commands"]
        else:
            acmds = parse_title_purpose(af)
            cache[cache_key] = {
                "mtime_ns": st_mtime_ns,
                "size": st_size,
                "commands": acmds,
            }
            cache_dirty = True
        for acid, aentry in acmds.items():
            if not isinstance(aentry, dict):
                continue
            t = str(aentry.get("title", "") or "")
            p = str(aentry.get("purpose", "") or "")
            other_words = tokenize(t) | tokenize(p)
            sim = similarity(new_words, other_words)
            if sim >= 50:
                archive_hits.append((acid, t[:50], sim))

    if archive_hits:
        archive_hits.sort(key=lambda x: -x[2])
        print("WARNING: archive内に類似cmdを検出（類似度50%以上）(archive)", file=sys.stderr)
        for cid, title, sim in archive_hits:
            print(f"  (archive) {cid}: {title} — 類似度{sim:.0f}%", file=sys.stderr)
        print("  → 過去の完了cmdとの重複でないか確認してください（BLOCKではありません）", file=sys.stderr)

    if cache_dirty:
        try:
            tmp_path = f"{cache_path}.tmp"
            with open(tmp_path, "w", encoding="utf-8") as fh:
                json.dump(cache, fh, ensure_ascii=False)
            os.replace(tmp_path, cache_path)
        except Exception:
            pass
PY
}

check_content_duplicate

# --- Check 13: ACパラメータ充足度チェック（WARN — WARN_COUNTに加算） ---
# 起源: cmd_1681事故 — ACに「前処理4条件」とだけ書き具体値未記載→忍者が独自判断でKalman_auto使用→条件不一致
# 目的: ACに「N条件」「N項目」等の数量指定があり具体値列挙がない場合にWARN
check_ac_param_sufficiency() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # acceptance_criteria セクションを抽出（なければCMD_BLOCK_NC全体をフォールバック）
    local AC_SECTION
    AC_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /acceptance_criteria:/ { found=1; next }
        found && /^    - / { print; next }
        found && /^      / { print; next }
        found { exit }
    ')
    [[ -z "$AC_SECTION" ]] && AC_SECTION="$CMD_BLOCK_NC"

    # 数量指定パターン検出: 「N条件」「N項目」「N手法」「N種類」「N種」「Nパラメータ」等
    local QUANT_LINES
    QUANT_LINES=$(echo "$AC_SECTION" | grep -E '[0-9]+(条件|項目|手法|種類|パラメータ|要件|ステップ|設定|フィールド|種)' || true)
    [[ -z "$QUANT_LINES" ]] && return 0

    local HIT=false
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # 具体値列挙チェック: 括弧内にスラッシュ区切り or カンマ区切り or 中点区切りの項目
        if ! echo "$line" | grep -qE '\([^)]*[/,・][^)]*\)'; then
            if [[ "$HIT" == false ]]; then
                echo "WARN: ACに数量指定があるが具体値が列挙されていません（cmd_1681教訓）" >&2
                HIT=true
            fi
            echo "  → $(echo "$line" | sed 's/^[[:space:]]*//' | cut -c1-80)" >&2
        fi
    done <<< "$QUANT_LINES"

    if [[ "$HIT" == true ]]; then
        echo "  具体値を列挙せよ。例: 「4条件」→「4条件(EMA/SMA/Kalman/Bandpass)」" >&2
        echo "  理由: 忍者は独自判断で条件を補完する（cmd_1681実証済み）" >&2
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
}

check_ac_param_sufficiency

# --- Check 14: 前段results.yamlとのパラメータ空間縮小検出（BLOCK） ---
# 起源: 2026-04-04 将軍4回連続で範囲縮小(top_n=5/lookback=6/PBO=5/MaxDD=1)
# 目的: 後段cmdが前段cmdを参照している場合、前段results.yamlのconfig空間を削っていないか構造的に検査
check_param_space_against_results() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local CMD_SECTION
    CMD_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*command:[[:space:]]*\|/ { found=1; next }
        found && /^      / { sub(/^      /, ""); print; next }
        found { exit }
    ')
    if [[ -z "$CMD_SECTION" ]]; then
        CMD_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
            /^[[:space:]]*command:[[:space:]]*/ {
                sub(/^[[:space:]]*command:[[:space:]]*/, "")
                gsub(/^"/, "")
                gsub(/"$/, "")
                print
                exit
            }
        ')
    fi
    [[ -z "$CMD_SECTION" ]] && return 0

    local PROJECT_ID PROJECT_ROOT_FOR_CMD PROJECT_FILE
    PROJECT_ID=$(echo "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*project:/ {
            sub(/^[[:space:]]*project:[[:space:]]*/, "")
            gsub(/["'\''[:space:]]/, "")
            print
            exit
        }
    ')
    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "infra" ]]; then
        PROJECT_ROOT_FOR_CMD="$PROJECT_DIR"
    else
        PROJECT_FILE="$PROJECT_DIR/projects/${PROJECT_ID}.yaml"
        [[ ! -f "$PROJECT_FILE" ]] && return 0
        PROJECT_ROOT_FOR_CMD=$(awk '
            /^project:/ { in_project=1; next }
            in_project && /^[^[:space:]]/ { exit }
            in_project && /^  path:/ {
                sub(/^  path:[[:space:]]*/, "")
                gsub(/["'\''[:space:]]/, "")
                print
                exit
            }
        ' "$PROJECT_FILE")
        [[ -z "$PROJECT_ROOT_FOR_CMD" ]] && return 0
    fi

    CMD_SECTION="$CMD_SECTION" \
    CURRENT_CMD_ID="$CMD_ID" \
    PROJECT_ROOT_FOR_CMD="$PROJECT_ROOT_FOR_CMD" \
    python3 - <<'PY'
import glob
import os
import re
import sys

cmd_section = os.environ.get("CMD_SECTION", "")
current_cmd_id = os.environ.get("CURRENT_CMD_ID", "")
project_root = os.environ.get("PROJECT_ROOT_FOR_CMD", "")

if not cmd_section or not project_root:
    sys.exit(0)


def unique(values):
    seen = set()
    out = []
    for value in values:
        marker = repr(value)
        if marker in seen:
            continue
        seen.add(marker)
        out.append(value)
    return out


def normalize_scalar(raw):
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in {"'", '"'}:
        raw = raw[1:-1]
    if re.fullmatch(r"-?\d+", raw):
        return int(raw)
    return raw


def parse_config_lists(path):
    config = {}
    in_config = False
    current_key = None
    with open(path, encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\n")
            if not in_config:
                if line.strip() == "config:":
                    in_config = True
                continue

            if re.match(r"^\S", line):
                break

            match = re.match(r"^  ([A-Za-z0-9_]+):\s*$", line)
            if match:
                current_key = match.group(1)
                config.setdefault(current_key, [])
                continue

            match = re.match(r"^  ([A-Za-z0-9_]+):\s+.+$", line)
            if match:
                current_key = None
                continue

            match = re.match(r"^  -\s*(.+)$", line)
            if match and current_key:
                config.setdefault(current_key, []).append(normalize_scalar(match.group(1)))
                continue

            if line.strip():
                current_key = None

    return {key: unique(values) for key, values in config.items() if values}


def parse_value_expr(expr):
    expr = expr.strip()
    if expr.startswith("["):
        end = expr.find("]")
        if end == -1:
            return None
        content = expr[1:end]
        parts = [part.strip() for part in content.split(",") if part.strip()]
        return [normalize_scalar(part) for part in parts]

    range_match = re.match(r"^(\d+)\s*-\s*(\d+)\b", expr)
    if range_match:
        start = int(range_match.group(1))
        end = int(range_match.group(2))
        step = 1 if end >= start else -1
        return list(range(start, end + step, step))

    csv_match = re.match(r"^(\d+(?:\s*,\s*\d+)+)\b", expr)
    if csv_match:
        return [int(part.strip()) for part in csv_match.group(1).split(",")]

    return None


ALIASES = {
    "lookbacks": ["lookbacks", "lookback"],
    "top_ns": ["top_ns", "top_n"],
    "rolling_windows": ["rolling_windows", "rolling_window"],
}


def extract_cmd_values(text, config_key):
    aliases = ALIASES.get(config_key, [config_key])
    found = []
    for alias in aliases:
        patterns = [
            rf"\b{re.escape(alias)}\b\s*[:=]\s*(\[[^\]]+\])",
            rf"\b{re.escape(alias)}\b\s*[:=]\s*([0-9]+\s*-\s*[0-9]+)",
            rf"\b{re.escape(alias)}\b\s*[:=]\s*([0-9]+(?:\s*,\s*[0-9]+)+)",
        ]
        for pattern in patterns:
            for match in re.finditer(pattern, text, flags=re.IGNORECASE):
                values = parse_value_expr(match.group(1))
                if values:
                    found.extend(values)
    return unique(found)


blocked = []
ref_cmds = unique(re.findall(r"(?<![A-Za-z0-9_])cmd_\d+(?![A-Za-z0-9_])", cmd_section))
for ref_cmd in ref_cmds:
    if ref_cmd == current_cmd_id:
        continue

    matches = glob.glob(os.path.join(project_root, "outputs", "analysis", "*", f"{ref_cmd}_results.yaml"))
    if not matches:
        continue

    result_path = matches[0]
    config_lists = parse_config_lists(result_path)
    if not config_lists:
        continue

    for config_key, previous_values in config_lists.items():
        current_values = extract_cmd_values(cmd_section, config_key)
        if not current_values:
            continue
        if set(current_values).issubset(set(previous_values)) and set(current_values) != set(previous_values):
            blocked.append((ref_cmd, config_key, previous_values, current_values, result_path))

if blocked:
    ref_cmd, config_key, previous_values, current_values, result_path = blocked[0]
    print(
        f"BLOCK: 前段cmdのパラメータ空間を縮小しています "
        f"({ref_cmd} {config_key}: current={current_values} previous={previous_values})",
        file=sys.stderr,
    )
    print(f"  参照results: {result_path}", file=sys.stderr)
    print("  後段cmdは前段と同一または拡張のみ許可。部分列挙での縮小は不可。", file=sys.stderr)
    sys.exit(1)
PY
}

check_param_space_against_results

# --- Check 15: パラメータ空間縮小検出（WARN） ---
# 起源: 2026-04-04 将軍4回連続で範囲縮小(top_n=5/lookback=6/PBO=5/MaxDD=1)
# 目的: commandに「計算量を言い訳に範囲を狭めた」記述があればWARN
check_param_space_shrink() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local CMD_SECTION
    CMD_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*command:/ { found=1; next }
        found && /^[[:space:]]{4,}/ { print; next }
        found && /^[[:space:]]*[a-z]/ { exit }
    ')
    [[ -z "$CMD_SECTION" ]] && return 0

    local SHRINK_PATTERNS="代表[0-9]+組|代表[0-9]+点|主要な[0-9]+パターン|計算量を考慮し|重いため[0-9]|に絞って検証|に絞って実行|非現実的なので|コスト的に[0-9]"
    local HITS
    HITS=$(echo "$CMD_SECTION" | grep -Ec "$SHRINK_PATTERNS" || true)

    if [[ "$HITS" -gt 0 ]]; then
        echo "WARN: パラメータ空間を縮小していないか？(${HITS}箇所で縮小表現を検出)" >&2
        echo "  → 計算量が多いなら: (1)道具を磨け (2)並列にせよ (3)チャンクに分けよ" >&2
        echo "  → 範囲を狭めることは殿の時間を奪う最大の無駄(2026-04-04殿厳命)" >&2
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
}

check_param_space_shrink

# --- Check 17: 軍師設計書参照cmdの数値緩和検出（WARN — WARN_COUNTに加算しない） ---
# 起源: cmd_1781事故 — 軍師設計書の数値→cmdで緩和して起票(cmd_1783教訓)
# 目的: gunshi設計書参照cmdでq8_why_what数値とAC数値を突合し、緩和をWARN
check_gunshi_design_num_relax() {
    [[ -z "${CMD_BLOCK_NC:-}" ]] && return 0

    # 軍師設計書参照検出: q5_verified_sourceに設計書パスが含まれる場合（gunshi補足 2026-04-07）
    # 理由: q5は検証ソースの一次情報→設計書参照の信頼性が最も高い判定基準
    local Q5_VAL
    Q5_VAL=$(echo "$CMD_BLOCK_NC" | grep "q5_verified_source:" | head -1)
    if ! echo "$Q5_VAL" | grep -qiE 'gunshi[-_]|設計書|context/gunshi'; then
        return 0
    fi

    # q8_why_whatの存在確認（なければ上のBLOCKで終了済み）
    local Q8_LINE
    Q8_LINE=$(echo "$CMD_BLOCK_NC" | grep "q8_why_what:" | head -1)
    [[ -z "$Q8_LINE" ]] && return 0

    # WHAT部分から数値を抽出
    local WHAT_PART Q8_NUMS Q8_MAX
    WHAT_PART="${Q8_LINE#*WHAT:}"
    Q8_NUMS=$(echo "$WHAT_PART" | grep -oE '[0-9]+(\.[0-9]+)?' | sort -n || true)
    [[ -z "$Q8_NUMS" ]] && return 0
    Q8_MAX=$(echo "$Q8_NUMS" | tail -1)

    # acceptance_criteriaから数値を抽出
    local AC_SECTION AC_NUMS AC_MAX
    AC_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /acceptance_criteria:/ { found=1; next }
        found && /^    - / { print; next }
        found && /^      / { print; next }
        found { exit }
    ')
    [[ -z "$AC_SECTION" ]] && AC_SECTION="$CMD_BLOCK_NC"
    AC_NUMS=$(echo "$AC_SECTION" | grep -oE '[0-9]+(\.[0-9]+)?' | sort -n || true)

    if [[ -z "$AC_NUMS" ]]; then
        echo "WARN: 軍師設計書参照cmdでAC数値不一致を検出（cmd_1783教訓）" >&2
        echo "  q8のWHAT数値: ${Q8_MAX} → ACに数値なし（緩和/抜落ちの可能性）" >&2
        echo "  設計書の数値をACに明記せよ" >&2
        return 0
    fi

    AC_MAX=$(echo "$AC_NUMS" | tail -1)

    # AC最大値 > q8最大値 = 緩和の可能性（大きいtimeout/少ない対象数の逆）
    if python3 -c "import sys; sys.exit(0 if float('$AC_MAX') > float('$Q8_MAX') else 1)" 2>/dev/null; then
        echo "WARN: 軍師設計書参照cmdで数値緩和を検出（cmd_1783教訓）" >&2
        echo "  q8のWHAT最大値: ${Q8_MAX} → AC最大値: ${AC_MAX}（ACがq8より大きい=緩和の可能性）" >&2
        echo "  設計書の数値をACで緩和するな。元の設計書数値を維持せよ" >&2
    fi
}

check_gunshi_design_num_relax

# --- Check 16: 行動→即確認原則（全cmd対象 — PI-023汎用化） ---
# 真因: 全ての問題の根源は「行動した後に結果を確認しない」。
# 本番変更かどうかのキーワード判定は各論。全cmdの全ACに確認を問う。
# reason: リアルワールドに事前通告はない(2026-04-07殿指摘)
_AC_COUNT=$(echo "$CMD_BLOCK" | grep -c "description:" 2>/dev/null || true)
_AC_COUNT=$(( ${_AC_COUNT:-0} + 0 ))
_VERIFY_AC_COUNT=$(echo "$CMD_BLOCK" | grep -i "description:" | grep -ciE "確認|verify|パリティ|parity|検証|validate|assert|比較|突合|PASS" 2>/dev/null || true)
_VERIFY_AC_COUNT=$(( ${_VERIFY_AC_COUNT:-0} + 0 ))
if [ "$_AC_COUNT" -gt 0 ] && [ "$_VERIFY_AC_COUNT" -eq 0 ]; then
    echo "WARNING: 全ACが行動のみで確認を含みません。行動→即確認(PI-023)。" >&2
    echo "  各ACに「やった後どう確認するか」を含めよ。確認なき行動は想像と同じ" >&2
fi

# --- Check 18: 研究cmd道具明示チェック（dm-signal研究cmd対象 — WARNING） ---
# 起源: cmd_1822事故 — 将軍がACに研究エンジンのCLI引数を書かず忍者がhang
# 目的: dm-signal研究cmdでAC内にスクリプトパスが未記載の場合WARNING表示（WARN_COUNTに加算しない）
# カタログ: context/dm-signal-ops.md §18 参照
check_research_tool_explicit() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # project=dm-signalのみ対象
    local PROJECT_ID
    PROJECT_ID=$(echo "$CMD_BLOCK_NC" | awk '/project:/{gsub(/.*project: */, ""); gsub(/"/, ""); print; exit}')
    [[ "$PROJECT_ID" != "dm-signal" ]] && return 0

    # title + command本文から研究ツールキーワード検出
    local FULL_CMD TITLE_LINE SEARCH_TEXT
    FULL_CMD=$(echo "$CMD_BLOCK_NC" | awk '
        /^\s*command:\s*\|/ { found=1; next }
        /^\s*command:\s*[^|]/ { found=1; sub(/^\s*command:\s*/, ""); print; next }
        found && /^\s{4,}/ { print; next }
        found && /^\s*[a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
    ')
    TITLE_LINE=$(echo "$CMD_BLOCK_NC" | grep '^\s*title:' | head -1)
    SEARCH_TEXT="${TITLE_LINE}
${FULL_CMD}"

    local HIT_GS=false HIT_WF=false

    # GS検出: run_077 / grid_search / GS(大文字) / グリッドサーチ
    if echo "$SEARCH_TEXT" | grep -qE 'run_077|grid[_-]search|グリッドサーチ|[[:space:]]GS[[:space:]　]|[[:space:]]GS新規|忍法GS|GS[[:space:]を]|GS[[:space:]の]'; then
        HIT_GS=true
    fi

    # WF検出: l1_alm_wf_engine / walk.forward / WF(大文字) / ウォークフォワード
    if echo "$SEARCH_TEXT" | grep -qE 'l1_alm_wf_engine|wf_engine|walk[_-]forward|ウォークフォワード|[[:space:]]WF[[:space:]　]|窓WF|WF[[:space:]を]|WFで'; then
        HIT_WF=true
    fi

    # どちらも検出されなければ対象外
    [[ "$HIT_GS" == false && "$HIT_WF" == false ]] && return 0

    # ACセクションを抽出
    local AC_SECTION
    AC_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /acceptance_criteria:/ { found=1; next }
        found && /^    - / { print; next }
        found && /^      / { print; next }
        found { exit }
    ')
    [[ -z "$AC_SECTION" ]] && AC_SECTION="$CMD_BLOCK_NC"

    local HIT=false

    # GS検出 → ACにrun_077が含まれるか確認
    if [[ "$HIT_GS" == true ]]; then
        if ! echo "$AC_SECTION" | grep -qE 'run_077|grid_search/run'; then
            if [[ "$HIT" == false ]]; then
                echo "WARNING: 研究cmd道具明示チェック(Check 18)。ACに研究スクリプトパスが未記載(cmd_1822教訓)" >&2
                HIT=true
            fi
            echo "  GS道具: scripts/analysis/grid_search/run_077_{忍法}.py をACに明記せよ" >&2
            echo '  例: "run_077_oikaze.py --universe config/portfolio_universes/XXX.yaml を実行"' >&2
        fi
    fi

    # WF検出 → ACにl1_alm_wf_engineが含まれるか確認
    if [[ "$HIT_WF" == true ]]; then
        if ! echo "$AC_SECTION" | grep -qE 'l1_alm_wf_engine|wf_engine'; then
            if [[ "$HIT" == false ]]; then
                echo "WARNING: 研究cmd道具明示チェック(Check 18)。ACに研究スクリプトパスが未記載(cmd_1822教訓)" >&2
                HIT=true
            fi
            echo "  WF道具: outputs/scripts/l1_alm_wf_engine.py をACに明記せよ" >&2
            echo '  例: "l1_alm_wf_engine.py --batch-csvs <paths> --multi-is --cmd-id XXX を実行"' >&2
        fi
    fi

    if [[ "$HIT" == true ]]; then
        echo "  道具カタログ: context/dm-signal-ops.md §18 参照" >&2
    fi
}

check_research_tool_explicit

# --- Quality Summary (品質パターン表示) ---
show_quality_summary() {
    local QUALITY_LOG="$QUALITY_LOG_FILE"

    # AC3: ファイル不存在・空→スキップ（エラーなし）
    if [[ ! -f "$QUALITY_LOG" ]] || [[ ! -s "$QUALITY_LOG" ]]; then
        return 0
    fi

    # Single awk pass: parse entries, output AC1 summary + AC2 warnings
    awk '
    /^ *- cmd_id:/ { n++ }
    /karo_rework:/ {
        val = $2; gsub(/[" ]/, "", val)
        if (val == "yes") rw[n] = 1
    }
    /ninja_blockers:/ {
        val = $2 + 0
        if (val > 0) bl[n] = 1
    }
    /supplementary_cmds:/ {
        val = $2 + 0
        if (val > 0) sp[n] = 1
    }
    END {
        if (n == 0) exit

        # AC1: 直近10件サマリー（10件未満ならあるだけ）
        s10 = (n > 10) ? n - 9 : 1
        c10 = n - s10 + 1
        rw10 = 0; bl10 = 0; sp10 = 0
        for (i = s10; i <= n; i++) {
            rw10 += rw[i]; bl10 += bl[i]; sp10 += sp[i]
        }
        printf "品質: %dcmd中 rework=%d blocker=%d supplementary=%d\n", c10, rw10, bl10, sp10

        # AC2: 直近5件でパターン警告
        s5 = (n > 5) ? n - 4 : 1
        c5 = n - s5 + 1
        if (c5 < 2) exit
        r5 = 0; b5 = 0; p5 = 0
        for (i = s5; i <= n; i++) {
            r5 += rw[i]; b5 += bl[i]; p5 += sp[i]
        }
        rr = (r5 / c5) * 100
        br = (b5 / c5) * 100
        sr = (p5 / c5) * 100
        if (rr > 20) printf "WARNING: rework率%.0f%%。AC設計の精度を確認せよ\n", rr
        if (br > 10) printf "WARNING: blocker率%.0f%%。前提条件の確認を強化せよ\n", br
        if (sr > 30) printf "WARNING: 補足cmd率%.0f%%。スコープ漏れの傾向\n", sr
    }
    ' "$QUALITY_LOG" || true
}

show_quality_summary

# --- Gunshi直近指摘表示（informational — WARN_COUNTに加算しない） ---
show_gunshi_recent_issues() {
    local GUNSHI_LOG="$PROJECT_DIR/logs/gunshi_review_log.yaml"

    # AC3: ファイル不存在/空→スキップ
    if [[ ! -f "$GUNSHI_LOG" ]] || [[ ! -s "$GUNSHI_LOG" ]]; then
        return 0
    fi

    # AC1+AC2: 直近REQ_CHANGES/FAILを最大3件表示
    awk '
    /^- cmd_id:/ {
        n++
        cmd[n] = $3
    }
    /^  verdict:/ {
        v = $2
        gsub(/#.*/, "", v)
        gsub(/[" ]/, "", v)
        verdict[n] = v
    }
    /^  findings_summary:/ {
        s = $0
        sub(/^  findings_summary: *"?/, "", s)
        sub(/"$/, "", s)
        summary[n] = substr(s, 1, 60)
    }
    END {
        m = 0
        for (i = 1; i <= n; i++) {
            if (verdict[i] == "REQUEST_CHANGES" || verdict[i] == "FAIL") {
                issues[++m] = i
            }
        }
        if (m == 0) exit
        start = (m > 3) ? m - 2 : 1
        for (j = start; j <= m; j++) {
            k = issues[j]
            printf "軍師直近指摘: %s %s — %s\n", cmd[k], verdict[k], summary[k]
        }
    }
    ' "$GUNSHI_LOG" 2>/dev/null || true
}

show_gunshi_recent_issues

# --- 軍師ペイン活動状況表示（informational — WARN_COUNTに加算しない） ---
show_gunshi_pane_status() {
    local PANE_TARGET="shogun:2.2"

    # ペイン存在確認（tmux未起動 or ペインなし → スキップ）
    if ! tmux capture-pane -t "$PANE_TARGET" -p >/dev/null 2>&1; then
        return 0
    fi

    # 最終3行をキャプチャ（空行を除去してから末尾3行）
    local PANE_CONTENT
    PANE_CONTENT=$(tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | sed '/^$/d' | tail -n 3) || return 0

    if [[ -n "$PANE_CONTENT" ]]; then
        echo "軍師ペイン(最終3行):"
        while IFS= read -r line; do
            echo "  $line"
        done <<< "$PANE_CONTENT"
    fi
}

show_gunshi_pane_status

# AC_TEXT: acceptance_criteriaセクションのdescription行を結合（Check 19/20で使用）
AC_TEXT=$(echo "$CMD_BLOCK" | awk '/acceptance_criteria:/,0' | grep 'description:' || true)

# --- Check 19: パリティcmdのP1-P6全基準チェック（WARN） ---
# 本番DB操作cmd（パリティ/登録/recalculate含む）のACにP1-P6が網羅されているか
# トリガー対象はtitle+purpose+AC_TEXTのみ（not_in_scopeの否定文による誤検知防止）
_CHECK19_TRIGGER=$(echo "$CMD_BLOCK" | grep -E 'title:|purpose:|description:' || true)
if echo "$_CHECK19_TRIGGER" | grep -qiE 'パリティ|parity|登録.*本番|本番.*登録|recalculate.*sync'; then
    PARITY_MISSING=()
    # P1: holding_signal
    if ! echo "$AC_TEXT" | grep -qi 'holding_signal'; then
        PARITY_MISSING+=("P1:holding_signal完全一致")
    fi
    # P2: monthly_return
    if ! echo "$AC_TEXT" | grep -qi 'monthly_return.*1e-6\|monthly_return.*差\|return.*一致'; then
        PARITY_MISSING+=("P2:monthly_return完全一致(1e-6)")
    fi
    # P3: 既存PF不変
    if ! echo "$AC_TEXT" | grep -qi 'ゴールデン\|golden\|既存.*不変\|不変.*確認'; then
        PARITY_MISSING+=("P3:既存PF不変(ゴールデンデータ)")
    fi
    # P4: FE UI
    if ! echo "$AC_TEXT" | grep -qi 'FE\|UI\|frontend\|Dashboard\|ページ'; then
        PARITY_MISSING+=("P4:FE UI全ページ整合")
    fi
    # P5: hide-first
    if ! echo "$AC_TEXT" | grep -qi 'hide\|is_visible\|非表示'; then
        PARITY_MISSING+=("P5:hide-first原則")
    fi
    if [[ ${#PARITY_MISSING[@]} -gt 0 ]]; then
        echo "WARNING: パリティcmdのAC基準欠落を検出(dm-signal-ops.md §6-7 チェックリスト参照)"
        for m in "${PARITY_MISSING[@]}"; do
            echo "  ✗ $m"
        done
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
fi

# --- Check 20: assumptionsフィールド検査（BLOCK昇格 cmd_1906） ---
# 起源: cmd_1905 — 暗黙前提を構造的に可視化し、未検証前提がcmdに混入するのを防ぐ
# 目的: AC数3以上のcmdにassumptionsがない/未検証前提があるcmdをBLOCKし、暗黙前提の混入を防ぐ
# cmd_1906: trust:unverified→BLOCK昇格。trust:verified+sourceにファイルパスがある場合実在確認
_ASSUMP_AC_COUNT=$(echo "$CMD_BLOCK" | grep -c "description:" 2>/dev/null || true)
_ASSUMP_AC_COUNT=$(( ${_ASSUMP_AC_COUNT:-0} + 0 ))
if [ "$_ASSUMP_AC_COUNT" -ge 3 ]; then
    # assumptions存在チェックはpreflight済み。以下は内容検証のみ
    if echo "$CMD_BLOCK_NC" | grep -q "assumptions:"; then
        # AC1: trust: unverified が含まれる場合BLOCK(exit 1)
        if echo "$CMD_BLOCK_NC" | grep -A5 "assumptions:" | grep -q "trust:.*unverified\|trust: unverified"; then
            echo "BLOCK: 未検証前提あり。現物確認してtrust:verifiedに変更せよ" >&2
            exit 1
        fi
        # AC2: trust:verified + sourceにファイルパスがある場合、プロジェクトWD内の実在確認
        _ASSUMP_PROJECT_ID=$(echo "$CMD_BLOCK_NC" | awk '/project:/{gsub(/.*project: */, ""); gsub(/"/, ""); print; exit}')
        [[ -z "${_ASSUMP_PROJECT_ID:-}" ]] && _ASSUMP_PROJECT_ID=$(awk '/^current_project:/{print $2}' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null || true)
        if [[ -n "${_ASSUMP_PROJECT_ID:-}" ]]; then
            _ASSUMP_PROJECT_WD=$(awk -v id="$_ASSUMP_PROJECT_ID" '
                /^  - id:/ { current_id = $3; gsub(/"/, "", current_id) }
                /^    path:/ && current_id == id { gsub(/.*path: *"?/, ""); gsub(/"$/, ""); print; exit }
            ' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null || true)
        fi
        if [[ -n "${_ASSUMP_PROJECT_WD:-}" ]]; then
            _ASSUMP_VERIFIED_PATHS=$(echo "$CMD_BLOCK_NC" | python3 -c "
import sys, re
content = sys.stdin.read()
lines = content.split('\n')
in_assumptions = False
current = {}
entries = []
for line in lines:
    if re.match(r'\s*assumptions\s*:', line):
        in_assumptions = True
        continue
    if in_assumptions:
        if re.match(r'\s*-\s', line):
            if current:
                entries.append(dict(current))
            current = {}
        m = re.search(r'source\s*:\s*(.+)', line)
        if m: current['source'] = m.group(1).strip().strip('\"').strip(\"'\")
        m = re.search(r'trust\s*:\s*(.+)', line)
        if m: current['trust'] = m.group(1).strip().strip('\"').strip(\"'\")
        if line and not line[0].isspace() and line.strip():
            in_assumptions = False
            if current: entries.append(dict(current))
            current = {}
if current: entries.append(current)
pat = re.compile(r'[A-Za-z0-9_/-]+\.(py|ts|tsx|js|jsx|sh|bash|yaml|yml|json|sql|html|css|toml|cfg|env)')
for e in entries:
    trust = e.get('trust', '')
    if 'verified' in trust and 'unverified' not in trust:
        for m in pat.finditer(e.get('source', '')):
            print(m.group(0))
" 2>/dev/null || true)
            if [[ -n "${_ASSUMP_VERIFIED_PATHS:-}" ]]; then
                _ASSUMP_HAS_MISSING=false
                while IFS= read -r fpath; do
                    [[ -z "$fpath" ]] && continue
                    if [[ ! -e "$_ASSUMP_PROJECT_WD/$fpath" ]]; then
                        if [[ "$_ASSUMP_HAS_MISSING" == false ]]; then
                            echo "BLOCK: assumptions sourceのファイルパスが存在しません:" >&2
                            _ASSUMP_HAS_MISSING=true
                        fi
                        echo "  ✗ $fpath (in $_ASSUMP_PROJECT_WD)" >&2
                    fi
                done <<< "$_ASSUMP_VERIFIED_PATHS"
                if [[ "$_ASSUMP_HAS_MISSING" == true ]]; then
                    echo "  現物確認してからcmd_save.shを再実行せよ" >&2
                    exit 1
                fi
            fi
        fi
    fi
fi

# --- Check 21: ACの数値絶対値WARN検出（informational — WARN_COUNTに加算しない） ---
# 起源: cmd_1910事故 — ACに「テスト数=118」のような固定値を記載し、並行cmdで即陳腐化
# 目的: AC description内の絶対値パターンを検出し、相対条件への書換えを促す
check_ac_absolute_literals() {
    [[ -z "${AC_TEXT:-}" ]] && return 0

    local ABSOLUTE_HITS
    ABSOLUTE_HITS=$(echo "$AC_TEXT" | grep -iE \
        '=[[:space:]]*[0-9]+|テスト数[[:space:]]*[=:：]?[[:space:]]*[0-9]+|[0-9]+(件|個|本|行|回|分|秒|時間|箇所|テスト)([[:space:]]*(PASS|成功|通過))?|ゼロ' \
        || true)
    [[ -z "$ABSOLUTE_HITS" ]] && return 0

    echo "WARN: ACに数値絶対値パターンを検出。並行配備時に陳腐化リスクあり(cmd_1910教訓)" >&2
    echo "  → 相対条件(例: 減少しないこと)への書換えを検討せよ。Check 21はinformationalのみ" >&2
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "  → $(echo "$line" | sed -E 's/^[[:space:]-]*description:[[:space:]]*//; s/^\"//; s/\"$//' | cut -c1-100)" >&2
    done <<< "$ABSOLUTE_HITS"
}

check_ac_absolute_literals

# --- Check 22: command欄ステップ数 vs AC数の不整合検出（WARN） ---
# 起源: cmd_1953-1958でcommand欄に(1)(2)(3)(4)の4ステップを書いたがAC2個→忍者がspec/設計書をスキップ
# 原理: command欄の番号付きステップ数 > AC数 = 中間成果物がACに分解されていない可能性
# CoDD固有でなく全cmdに適用。手順が増えれば自動検出(100億パターン対応)
if [[ -n "${CMD_BLOCK_NC:-}" ]]; then
    _CMD_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /^\s*command:\s*\|/ { found=1; next }
        /^\s*command:\s*[^|]/ { found=1; sub(/^\s*command:\s*/, ""); print; next }
        found && /^\s{4,}/ { print; next }
        found && /^\s*[a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
    ')
    _STEP_COUNT=$(echo "$_CMD_SECTION" | grep -cE '^\s*\([0-9]+\)|^\s*[0-9]+[\.\)]\s' 2>/dev/null || echo 0)
    _AC_COUNT=$(echo "$CMD_BLOCK_NC" | grep -c "description:" 2>/dev/null || echo 0)
    if (( _STEP_COUNT > 0 && _STEP_COUNT > _AC_COUNT )); then
        echo "WARN: command欄に${_STEP_COUNT}ステップあるがACは${_AC_COUNT}個。中間成果物がACに分解されていない可能性" >&2
        echo "  忍者はACにないことは実行しない。各ステップの成果物をACに対応させよ" >&2
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
fi

# --- 結果出力 ---
if [[ "$WARN_COUNT" -eq 0 ]]; then
    echo "保存確認OK: ${CMD_ID}"
    # status: pending 自動注入（未設定時のみ。cmdライフサイクル追跡の起点）
    _EXISTING_STATUS=$(echo "$CMD_BLOCK" | awk '/status:/{gsub(/.*status: */, ""); gsub(/"/, ""); print; exit}')
    if [[ -z "$_EXISTING_STATUS" ]]; then
        if bash "$SCRIPT_DIR/lib/yaml_field_set.sh" "$QUEUE_FILE" "$CMD_ID" status pending 2>/dev/null; then
            echo "  status: pending — 自動設定"
        fi
    fi
else
    echo "保存確認NG: ${CMD_ID} (${WARN_COUNT}件のWARN)" >&2
    exit 1
fi
