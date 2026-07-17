#!/usr/bin/env bash
# semantic-links: [[ゲート品質統合フレームワーク]]
# ============================================================
# gate_cmd_state.sh
# 将軍復帰時にpending cmdの委任状態を判定するゲート
#
# Usage:
#   bash scripts/gates/gate_cmd_state.sh
#
# 各pending cmdに対し:
#   - delegated_at あり → OK: 委任済み。再送不要
#   - delegated_at なし + 二次証跡あり → WARN: 委任証拠あり。再送不要
#   - delegated_at なし + 証跡なし → ALERT: 未委任の可能性。委任を確認せよ
#
# Exit code: 0=全OK, 1=1つ以上ALERT, 2=WARNのみ(ALERTなし)
# ============================================================
set -euo pipefail

_self="${BASH_SOURCE[0]}"  # use BASH_SOURCE not $0: $0 may be just the name when called via PATH
SCRIPT_DIR="${_self%/*}"
[[ "$SCRIPT_DIR" != /* ]] && SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
SCRIPT_DIR="${SCRIPT_DIR%/scripts/gates}"
SHOGUN_TO_KARO="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
KARO_INBOX="$SCRIPT_DIR/queue/inbox/karo.yaml"
DASHBOARD="$SCRIPT_DIR/dashboard.md"
SNAPSHOT="$SCRIPT_DIR/queue/karo_snapshot.txt"

HAS_ALERT=0
HAS_WARN=0
CHECKED=0

emit_actionable() {
    local message="$1"
    local action="$2"
    echo "$message"
    echo "action: $action"
}

if [ ! -f "$SHOGUN_TO_KARO" ]; then
    echo "OK: shogun_to_karo.yaml not found — no cmds to check"
    echo "--- 総合判定: OK ---"
    exit 0
fi

if ! grep -q '^[[:space:]][[:space:]]*status:[[:space:]]*pending' "$SHOGUN_TO_KARO" 2>/dev/null; then
    echo "OK: pending cmd なし"
    echo "--- 総合判定: OK ---"
    exit 0
fi

# Extract pending cmd IDs and delegated_at in one pass.  Keeping the value
# beside the ID avoids sourcing the general YAML mutation library and then
# rescanning the same file once per pending command.
mapfile -t CMD_ROWS < <(
    awk '
    function flush() {
        if (current_id != "" && status == "pending") {
            print current_id "\t" delegated_at
        }
    }
    /^[[:space:]]*- id: cmd_/ {
        flush()
        sub(/^[[:space:]]*- id:[[:space:]]*/, "")
        sub(/[[:space:]]*$/, "")
        current_id = $0
        status = ""
        delegated_at = ""
        next
    }
    current_id != "" && /^[[:space:]]+status:[[:space:]]*/ {
        status = $0
        sub(/^[[:space:]]+status:[[:space:]]*/, "", status)
        sub(/[[:space:]]*$/, "", status)
        next
    }
    current_id != "" && /^[[:space:]]+delegated_at:[[:space:]]*/ {
        delegated_at = $0
        sub(/^[[:space:]]+delegated_at:[[:space:]]*/, "", delegated_at)
        sub(/[[:space:]]*$/, "", delegated_at)
    }
    /^[[:space:]]*- id:/ && !/cmd_/ { flush(); current_id = ""; status = ""; delegated_at = "" }
    END { flush() }
    ' "$SHOGUN_TO_KARO"
)

if [ ${#CMD_ROWS[@]} -eq 0 ]; then
    echo "OK: pending cmd なし"
    echo "--- 総合判定: OK ---"
    exit 0
fi

for cmd_row in "${CMD_ROWS[@]}"; do
    IFS=$'\t' read -r cmd_id delegated_at <<< "$cmd_row"
    CHECKED=$((CHECKED + 1))

    if [ -n "$delegated_at" ]; then
        echo "OK: $cmd_id — 委任済み($delegated_at)。再送不要。"
        continue
    fi

    # delegated_at なし → 二次証跡チェック
    has_evidence=0

    # 証跡1: karo inbox に cmd_new メッセージが存在するか
    if [ -f "$KARO_INBOX" ]; then
        if grep -q "$cmd_id" "$KARO_INBOX" 2>/dev/null; then
            has_evidence=1
        fi
    fi

    # 証跡2: dashboard.md に cmd_id の記載があるか
    if [ "$has_evidence" -eq 0 ] && [ -f "$DASHBOARD" ]; then
        if grep -q "$cmd_id" "$DASHBOARD" 2>/dev/null; then
            has_evidence=1
        fi
    fi

    # 証跡3: karo_snapshot.txt に cmd_id の記載があるか
    if [ "$has_evidence" -eq 0 ] && [ -f "$SNAPSHOT" ]; then
        if grep -q "$cmd_id" "$SNAPSHOT" 2>/dev/null; then
            has_evidence=1
        fi
    fi

    if [ "$has_evidence" -eq 1 ]; then
        emit_actionable \
            "WARN: $cmd_id — delegated_at未設定だが二次証跡あり。再送不要。" \
            "queue/shogun_to_karo.yaml の delegated_at 欠落だけを修正し、家老への再送はするな。"
        HAS_WARN=1
    else
        emit_actionable \
            "ALERT: $cmd_id — 未委任の可能性。委任を確認せよ。" \
            "queue/shogun_to_karo.yaml・queue/inbox/karo.yaml・dashboard.md を確認し、未委任なら家老へ委任せよ。"
        HAS_ALERT=1
    fi
done

# 総合判定
if [ "$HAS_ALERT" -gt 0 ]; then
    echo "--- 総合判定: ALERT ---"
    exit 1
elif [ "$HAS_WARN" -gt 0 ]; then
    echo "--- 総合判定: WARN ---"
    exit 2
else
    echo "--- 総合判定: OK ---"
    exit 0
fi
