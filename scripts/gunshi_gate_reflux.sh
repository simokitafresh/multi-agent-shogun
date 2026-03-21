#!/bin/bash
# gunshi_gate_reflux.sh — GATE CLEAR時に軍師レビューログのgate_resultを自動更新
# Usage: bash scripts/gunshi_gate_reflux.sh <cmd_id> <gate_result>
# cmd_complete_gate.shのGATE CLEARセクションから呼び出される（ベストエフォート）

set -e

CMD_ID="${1:?Usage: gunshi_gate_reflux.sh <cmd_id> <gate_result>}"
GATE_RESULT="${2:?Usage: gunshi_gate_reflux.sh <cmd_id> <gate_result>}"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/gunshi_review_log.yaml"

if [ ! -f "$LOG_FILE" ]; then
    exit 0
fi

# sed: 該当cmd_idのエントリのgate_result: nullをgate_result: <GATE_RESULT>に更新
# 同一cmd_idに複数エントリ(draft+report)がありえるので全て更新
# archiveファイルは対象外（LOG_FILEのみ操作）

# 方針: awkで状態機械。cmd_idマッチ中にgate_result: nullを見つけたら置換
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

awk -v cmd_id="$CMD_ID" -v gate_result="$GATE_RESULT" '
BEGIN { in_entry = 0; match_cmd = 0 }
/^- cmd_id:/ {
    in_entry = 1
    match_cmd = 0
    if ($0 ~ "cmd_id: " cmd_id "$") {
        match_cmd = 1
    }
}
/^- cmd_id:/ && in_entry && !match_cmd { in_entry = 1 }
/^[^- ]/ && !/^  / && !/^#/ { in_entry = 0; match_cmd = 0 }
match_cmd && /^  gate_result: null/ {
    sub(/gate_result: null/, "gate_result: " gate_result)
    updated++
}
{ print }
END { print updated+0 > "/dev/stderr" }
' "$LOG_FILE" > "$TMPFILE" 2>/tmp/gunshi_reflux_count

UPDATE_COUNT=$(cat /tmp/gunshi_reflux_count 2>/dev/null || echo "0")
rm -f /tmp/gunshi_reflux_count

if [ "$UPDATE_COUNT" -gt 0 ]; then
    cp "$TMPFILE" "$LOG_FILE"
    echo "  gunshi_gate_reflux: ${UPDATE_COUNT} entries updated (${CMD_ID} → ${GATE_RESULT})"
fi
