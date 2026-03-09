#!/usr/bin/env bash
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

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SHOGUN_TO_KARO="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
KARO_INBOX="$SCRIPT_DIR/queue/inbox/karo.yaml"
DASHBOARD="$SCRIPT_DIR/dashboard.md"
SNAPSHOT="$SCRIPT_DIR/queue/karo_snapshot.txt"

source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"

HAS_ALERT=0
HAS_WARN=0
CHECKED=0

if [ ! -f "$SHOGUN_TO_KARO" ]; then
    echo "OK: shogun_to_karo.yaml not found — no cmds to check"
    echo "--- 総合判定: OK ---"
    exit 0
fi

# Extract all cmd IDs with status=pending
# Parse YAML: find "- id: cmd_XXX" blocks and check their status field
mapfile -t CMD_IDS < <(
    awk '
    /^[[:space:]]*- id: cmd_/ {
        sub(/^[[:space:]]*- id:[[:space:]]*/, "")
        sub(/[[:space:]]*$/, "")
        current_id = $0
    }
    /^[[:space:]]+status:[[:space:]]*pending/ {
        if (current_id != "") {
            print current_id
            current_id = ""
        }
    }
    /^[[:space:]]*- id:/ && !/cmd_/ { current_id = "" }
    ' "$SHOGUN_TO_KARO"
)

if [ ${#CMD_IDS[@]} -eq 0 ]; then
    echo "OK: pending cmd なし"
    echo "--- 総合判定: OK ---"
    exit 0
fi

for cmd_id in "${CMD_IDS[@]}"; do
    CHECKED=$((CHECKED + 1))

    # Check delegated_at field
    delegated_at=$(_yaml_field_get_in_block "$SHOGUN_TO_KARO" "$cmd_id" "delegated_at" 2>/dev/null) || true

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
        echo "WARN: $cmd_id — delegated_at未設定だが二次証跡あり。再送不要。"
        HAS_WARN=1
    else
        echo "ALERT: $cmd_id — 未委任の可能性。委任を確認せよ。"
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
