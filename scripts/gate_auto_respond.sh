#!/usr/bin/env bash
# ============================================================
# gate_auto_respond.sh
# gate検知→自動応答スクリプト
#
# 5つのgateを順次チェックし、状態変化時のみアクション実行。
# 冪等性: /tmp/gate_auto_last_state_{gate名} に前回状態保存。
# 同一ALERT連続時は再送しない（OK→ALERT遷移時のみACTION）。
#
# Usage:
#   bash scripts/gate_auto_respond.sh
#
# stdout: 各gate毎に OK / SKIP / ACTION を1行出力
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATES_DIR="$SCRIPT_DIR/gates"
STATE_DIR="/tmp"

# ── 冪等性チェック共通関数 ──
# $1: gate名, $2: 今回の状態(OK/WARN/ALERT), $3: トリガーとなる状態群(スペース区切り)
# 戻り値: 0=ACTIONすべき, 1=SKIP
should_act() {
    local gate_name="$1"
    local current_state="$2"
    shift 2
    local trigger_states=("$@")

    local state_file="${STATE_DIR}/gate_auto_last_state_${gate_name}"
    local prev_state="OK"

    if [ -f "$state_file" ]; then
        prev_state=$(cat "$state_file" 2>/dev/null || echo "OK")
    fi

    # 状態保存（常に更新）
    echo "$current_state" > "$state_file"

    # 今回の状態がトリガー対象でなければOK
    local is_trigger=false
    for ts in "${trigger_states[@]}"; do
        if [ "$current_state" = "$ts" ]; then
            is_trigger=true
            break
        fi
    done

    if [ "$is_trigger" = false ]; then
        return 1
    fi

    # 前回と同じトリガー状態 → SKIP（再送抑止）
    if [ "$prev_state" = "$current_state" ]; then
        return 1
    fi

    # 状態遷移あり → ACTION
    return 0
}

# ============================================================
# (1) gate_lesson_health ALERT → 家老にinbox_write
# ============================================================
handle_lesson_health() {
    local output
    local exit_code=0
    output=$(bash "$GATES_DIR/gate_lesson_health.sh" 2>&1) || exit_code=$?

    local state="OK"
    if [ "$exit_code" -eq 1 ]; then
        # ALERT行またはWARN行の有無で判定
        if echo "$output" | grep -q "^ALERT:"; then
            state="ALERT"
        fi
    fi

    if should_act "lesson_health" "$state" "ALERT"; then
        local detail
        detail=$(echo "$output" | grep "^ALERT:" | head -3)
        bash "$SCRIPT_DIR/inbox_write.sh" karo \
            "教訓振り分けALERT。未振り分け教訓あり。lesson-sort相当の振り分けを実施せよ。詳細: ${detail}" \
            gate_alert gate_auto
        echo "ACTION: lesson_health (→ALERT)"
    elif [ "$state" = "ALERT" ]; then
        echo "SKIP: lesson_health (ALERT→ALERT 再送抑止)"
    else
        echo "OK: lesson_health"
    fi
}

# ============================================================
# (2) gate_cmd_state ALERT → 未委任cmdをcmd_delegate.sh実行
# ============================================================
handle_cmd_state() {
    local output
    local exit_code=0
    output=$(bash "$GATES_DIR/gate_cmd_state.sh" 2>&1) || exit_code=$?

    local state="OK"
    if [ "$exit_code" -eq 1 ]; then
        state="ALERT"
    elif [ "$exit_code" -eq 2 ]; then
        state="WARN"
    fi

    # ALERTのみ対応（WARN/OKは何もしない）— 通知のみ、自動委任しない
    if should_act "cmd_state" "$state" "ALERT"; then
        # ALERT行からcmd_IDを抽出
        local cmd_ids
        mapfile -t cmd_ids < <(echo "$output" | grep -oP '(?<=^ALERT: )(cmd_[0-9]+)' || true)

        if [ ${#cmd_ids[@]} -gt 0 ]; then
            bash "$SCRIPT_DIR/ntfy.sh" "【要確認】cmd未委任ALERT: ${cmd_ids[*]} — 将軍確認待ち"
        fi
        echo "NOTIFY: cmd_state (→ALERT, cmds: ${cmd_ids[*]:-none})"
    elif [ "$state" = "ALERT" ]; then
        echo "SKIP: cmd_state (ALERT→ALERT 再送抑止)"
    else
        echo "OK: cmd_state"
    fi
}

# ============================================================
# (3) gate_context_freshness WARN/ALERT → ntfy通知
# ============================================================
handle_context_freshness() {
    local output
    local exit_code=0
    output=$(bash "$GATES_DIR/gate_context_freshness.sh" 2>&1) || exit_code=$?

    local state="OK"
    if [ "$exit_code" -eq 1 ]; then
        state="ALERT"
    elif [ "$exit_code" -eq 2 ]; then
        state="WARN"
    fi

    # WARN/ALERT両方で通知
    if should_act "context_freshness" "$state" "WARN" "ALERT"; then
        local detail
        detail=$(echo "$output" | grep -E "^(WARN|ALERT):" | head -5 | tr '\n' ' ')
        bash "$SCRIPT_DIR/ntfy.sh" "【gate自動】context鮮度${state}: ${detail}"
        echo "ACTION: context_freshness (→${state})"
    elif [ "$state" = "WARN" ] || [ "$state" = "ALERT" ]; then
        echo "SKIP: context_freshness (${state}→${state} 再送抑止)"
    else
        echo "OK: context_freshness"
    fi
}

# ============================================================
# (4) gate_p_average_freshness ALERT → ntfy通知
# ============================================================
handle_p_average_freshness() {
    local output
    local exit_code=0
    output=$(bash "$GATES_DIR/gate_p_average_freshness.sh" 2>&1) || exit_code=$?

    local state="OK"
    if [ "$exit_code" -eq 1 ]; then
        state="ALERT"
    elif [ "$exit_code" -eq 2 ]; then
        state="WARN"
    fi

    # ALERTのみ対応
    if should_act "p_average_freshness" "$state" "ALERT"; then
        bash "$SCRIPT_DIR/ntfy.sh" "【gate自動】p̄鮮度ALERT: ${output}"
        echo "ACTION: p_average_freshness (→ALERT)"
    elif [ "$state" = "ALERT" ]; then
        echo "SKIP: p_average_freshness (ALERT→ALERT 再送抑止)"
    else
        echo "OK: p_average_freshness"
    fi
}

# ============================================================
# (5) CI赤検知（gh run listで最新CI結果を確認）
# ============================================================
handle_ci_red() {
    local state="OK"
    local detail=""

    if ! command -v gh >/dev/null 2>&1; then
        echo "OK: ci_red (gh CLI not available, skip)"
        return 0
    fi

    local ci_result
    ci_result=$(gh run list --repo simokitafresh/multi-agent-shogun \
        --workflow test.yml --branch main --limit 1 \
        --json conclusion,databaseId 2>/dev/null || true)

    if [ -z "$ci_result" ]; then
        echo "OK: ci_red (no CI data)"
        return 0
    fi

    local ci_conclusion
    ci_conclusion=$(printf '%s' "$ci_result" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if data and isinstance(data, list) and len(data) > 0:
        print(data[0].get('conclusion') or '')
    else:
        print('')
except:
    print('')
" 2>/dev/null)

    local ci_run_id
    ci_run_id=$(printf '%s' "$ci_result" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if data and isinstance(data, list) and len(data) > 0:
        print(data[0].get('databaseId') or '')
    else:
        print('')
except:
    print('')
" 2>/dev/null)

    if [ "$ci_conclusion" = "failure" ]; then
        state="ALERT"
        detail="run ${ci_run_id}"
    fi

    if should_act "ci_red" "$state" "ALERT"; then
        bash "$SCRIPT_DIR/ntfy.sh" "【gate自動】CI赤: ${detail}"
        bash "$SCRIPT_DIR/inbox_write.sh" karo \
            "CI赤検知(${detail})。修正検討せよ" gate_alert gate_auto
        echo "ACTION: ci_red (→ALERT, ${detail})"
    elif [ "$state" = "ALERT" ]; then
        echo "SKIP: ci_red (ALERT→ALERT 再送抑止)"
    else
        echo "OK: ci_red"
    fi
}

# ============================================================
# メイン
# ============================================================
echo "=== gate_auto_respond.sh $(date '+%Y-%m-%dT%H:%M:%S') ==="

handle_lesson_health
handle_cmd_state
handle_context_freshness
handle_p_average_freshness
handle_ci_red

echo "=== done ==="
