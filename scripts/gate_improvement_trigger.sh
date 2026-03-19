#!/usr/bin/env bash
# ============================================================
# gate_improvement_trigger.sh
# gate ALERT検知 → 穴検出3問を家老inbox送信 + ntfy通知
#
# 設計原則（殿厳命）:
#   「自動消火は最悪の手段。問題を隠し先送りして被害を拡大させる。
#    まっとうに成長して賢くなり結果論としてゲートブロックが起きないループを回せ。」
#
# ❌ 自動消火: ALERT→自動で処理→終わり（問題が隠れる）
# ✅ 改善トリガー: ALERT→ntfy通知→穴検出3問を家老に送信
#    →家老が調査→教訓化→防御層強化→根本原因修正
#
# Usage:
#   bash scripts/gate_improvement_trigger.sh
#
# Exit code: 0 (always — this script is a notification trigger, not a blocker)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATES_DIR="$SCRIPT_DIR/scripts/gates"
ALERTS_FILE="$SCRIPT_DIR/logs/gate_alerts.yaml"
STATE_DIR="/tmp"

# --- alert_id連番管理 ---
get_next_alert_id() {
    local counter_file="$SCRIPT_DIR/logs/gate_alert_counter.txt"
    local current=0
    if [ -f "$counter_file" ]; then
        current=$(tr -d '[:space:]' < "$counter_file" 2>/dev/null) || current=0
        if ! [[ "$current" =~ ^[0-9]+$ ]]; then
            current=0
        fi
    fi
    local next=$((current + 1))
    echo "$next" > "$counter_file"
    printf "GA-%03d" "$next"
}

# --- gate_alerts.yaml記録 ---
record_alert() {
    local alert_id="$1"
    local gate_name="$2"
    local alert_detail="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')

    # ファイルが存在しなければヘッダ作成
    if [ ! -f "$ALERTS_FILE" ]; then
        echo "alerts:" > "$ALERTS_FILE"
    fi

    cat >> "$ALERTS_FILE" <<EOF
  - alert_id: ${alert_id}
    gate: ${gate_name}
    detected_at: "${timestamp}"
    alert_detail: "${alert_detail}"
    three_questions_sent: true
    investigation_cmd: null
    improvement_done: false
EOF
}

# --- 冪等性チェック ---
# 前回と同一のALERT状態なら送信しない（状態遷移時のみ送信）
check_idempotent() {
    local gate_name="$1"
    local current_state="$2"
    local state_file="${STATE_DIR}/gate_improvement_last_state_${gate_name}"

    if [ -f "$state_file" ]; then
        local prev_state
        prev_state=$(cat "$state_file" 2>/dev/null) || prev_state=""
        if [ "$prev_state" = "$current_state" ]; then
            return 1  # 同一状態 → 送信しない
        fi
    fi

    echo "$current_state" > "$state_file"
    return 0  # 状態遷移 → 送信する
}

# --- 穴検出3問テンプレート + gate固有補足 ---
build_three_questions() {
    local gate_name="$1"
    local alert_id="$2"
    local alert_detail="$3"
    local supplement="$4"

    cat <<EOF
【gate穴検出3問】${gate_name} ALERT (alert_id: ${alert_id})
検知内容: ${alert_detail}
Q1: なぜこのgateが鳴ったか？直接原因と根本原因の仮説を立てよ
Q2: 同じカテゴリの穴が他にないか？横展開候補を洗い出せ
Q3: 次にこのgateが鳴らないようにする防御層は何か？
→ 忍者に調査配備し、結果をlesson登録+防御層に反映せよ
補足: ${supplement}
EOF
}

# --- Gate固有の補足情報 ---
get_gate_supplement() {
    local gate_name="$1"
    case "$gate_name" in
        lesson_health)
            echo "未振り分け教訓が溜まっている。なぜ溜まった？教訓登録の頻度/品質に問題はないか？"
            ;;
        cmd_state)
            echo "未委任cmdがある。なぜ委任されていない？将軍の委任手順に穴はないか？"
            ;;
        context_freshness)
            echo "contextが古い。なぜ更新されていない？更新トリガーの設計に穴はないか？"
            ;;
        p_average_freshness)
            echo "p̄計算が古い。なぜバッチが実行されていない？バッチ実行の仕組みに穴はないか？"
            ;;
        ci_red)
            echo "CIが赤い。なぜテストが失敗した？テストカバレッジの穴はないか？"
            ;;
        *)
            echo "gate固有の補足なし。"
            ;;
    esac
}

# --- 各gateの実行+ALERT判定+3問送信 ---

process_gate() {
    local gate_name="$1"
    local gate_script="$2"
    local output
    local exit_code=0

    output=$($gate_script 2>&1) || exit_code=$?

    # ALERT判定: exit_code=1 または出力に "ALERT:" を含む
    if [ "$exit_code" -eq 1 ] || echo "$output" | grep -q "^ALERT:"; then
        # ALERT行を抽出（複数あり得る）
        local alert_lines
        alert_lines=$(echo "$output" | grep "^ALERT:" | head -5)
        if [ -z "$alert_lines" ]; then
            alert_lines="exit_code=$exit_code (ALERT detail not captured)"
        fi

        # 冪等性チェック
        if ! check_idempotent "$gate_name" "$alert_lines"; then
            echo "SKIP: ${gate_name} — 前回と同一ALERT状態。送信済み。"
            return 0
        fi

        # alert_id発行
        local alert_id
        alert_id=$(get_next_alert_id)

        # 3問メッセージ組立て
        local supplement
        supplement=$(get_gate_supplement "$gate_name")
        local message
        message=$(build_three_questions "$gate_name" "$alert_id" "$alert_lines" "$supplement")

        # 家老inboxに送信
        bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" gate_alert gate_improvement_trigger

        # gate_alerts.yaml記録
        record_alert "$alert_id" "$gate_name" "$alert_lines"

        # ntfy通知
        bash "$SCRIPT_DIR/scripts/ntfy.sh" "【改善トリガー】${gate_name} ALERT (${alert_id})" || true

        echo "SENT: ${gate_name} → ${alert_id}"
    else
        # ALERT解消時: 状態ファイルをクリア（次回ALERTで再送可能にする）
        local state_file="${STATE_DIR}/gate_improvement_last_state_${gate_name}"
        if [ -f "$state_file" ]; then
            rm -f "$state_file"
        fi
        echo "OK: ${gate_name} — no ALERT"
    fi
}

# --- (5) CI赤チェック ---
check_ci_red() {
    local gate_name="ci_red"
    local output
    local exit_code=0

    # gh run list で最新runの結論を取得
    output=$(gh run list --limit 3 --json conclusion,name,headBranch \
        --jq '.[] | select(.headBranch=="main") | .conclusion' 2>&1) || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        echo "SKIP: ci_red — gh run list failed: $output"
        return 0
    fi

    # 最新mainブランチの結論を取得
    local latest_conclusion
    latest_conclusion=$(echo "$output" | head -1)

    if [ "$latest_conclusion" = "failure" ]; then
        local alert_lines="ALERT: CI赤 — 最新mainブランチのCIが失敗"

        if ! check_idempotent "$gate_name" "$alert_lines"; then
            echo "SKIP: ${gate_name} — 前回と同一ALERT状態。送信済み。"
            return 0
        fi

        local alert_id
        alert_id=$(get_next_alert_id)

        local supplement
        supplement=$(get_gate_supplement "$gate_name")
        local message
        message=$(build_three_questions "$gate_name" "$alert_id" "$alert_lines" "$supplement")

        bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" gate_alert gate_improvement_trigger
        record_alert "$alert_id" "$gate_name" "$alert_lines"
        bash "$SCRIPT_DIR/scripts/ntfy.sh" "【改善トリガー】CI赤 ALERT (${alert_id})" || true

        echo "SENT: ${gate_name} → ${alert_id}"
    else
        local state_file="${STATE_DIR}/gate_improvement_last_state_${gate_name}"
        if [ -f "$state_file" ]; then
            rm -f "$state_file"
        fi
        echo "OK: ${gate_name} — conclusion=${latest_conclusion:-none}"
    fi
}

# =========================
# メイン処理
# =========================
echo "=== gate_improvement_trigger.sh ==="
echo "timestamp: $(date '+%Y-%m-%dT%H:%M:%S%z')"
echo ""

# (1) gate_lesson_health
process_gate "lesson_health" "bash $GATES_DIR/gate_lesson_health.sh"

# (2) gate_cmd_state
process_gate "cmd_state" "bash $GATES_DIR/gate_cmd_state.sh"

# (3) gate_context_freshness (WARN/ALERT両方をトリガー対象)
# context_freshnessはexit=2(WARN)もトリガー対象のため、専用処理
process_gate_context_freshness() {
    local gate_name="context_freshness"
    local output
    local exit_code=0

    output=$(bash "$GATES_DIR/gate_context_freshness.sh" 2>&1) || exit_code=$?

    # WARN(exit=2) または ALERT(exit=1)
    if [ "$exit_code" -eq 1 ] || [ "$exit_code" -eq 2 ] || echo "$output" | grep -qE "^(ALERT|WARN):"; then
        local alert_lines
        alert_lines=$(echo "$output" | grep -E "^(ALERT|WARN):" | head -5)
        if [ -z "$alert_lines" ]; then
            alert_lines="exit_code=$exit_code"
        fi

        if ! check_idempotent "$gate_name" "$alert_lines"; then
            echo "SKIP: ${gate_name} — 前回と同一状態。送信済み。"
            return 0
        fi

        local alert_id
        alert_id=$(get_next_alert_id)

        local supplement
        supplement=$(get_gate_supplement "$gate_name")
        local message
        message=$(build_three_questions "$gate_name" "$alert_id" "$alert_lines" "$supplement")

        bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" gate_alert gate_improvement_trigger
        record_alert "$alert_id" "$gate_name" "$alert_lines"
        bash "$SCRIPT_DIR/scripts/ntfy.sh" "【改善トリガー】${gate_name} (${alert_id})" || true

        echo "SENT: ${gate_name} → ${alert_id}"
    else
        local state_file="${STATE_DIR}/gate_improvement_last_state_${gate_name}"
        if [ -f "$state_file" ]; then
            rm -f "$state_file"
        fi
        echo "OK: ${gate_name} — no ALERT/WARN"
    fi
}
process_gate_context_freshness

# (4) gate_p_average_freshness
process_gate "p_average_freshness" "bash $GATES_DIR/gate_p_average_freshness.sh"

# (5) CI赤
check_ci_red

echo ""
echo "=== gate_improvement_trigger.sh complete ==="
