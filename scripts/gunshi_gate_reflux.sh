#!/usr/bin/env bash
# gunshi_gate_reflux.sh — GATE CLEAR時に軍師レビューログのgate_resultを自動更新
# Usage: bash scripts/gunshi_gate_reflux.sh <cmd_id> <gate_result>
# cmd_complete_gate.shのGATE CLEARセクションから呼び出される（ベストエフォート）

set -euo pipefail

CMD_ID="${1:?Usage: gunshi_gate_reflux.sh <cmd_id> <gate_result>}"
GATE_RESULT="${2:?Usage: gunshi_gate_reflux.sh <cmd_id> <gate_result>}"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/gunshi_review_log.yaml"

case "$GATE_RESULT" in
    CLEAR|BLOCK|FAIL|WARN|N/A) ;;
    *)
        echo "gunshi_gate_reflux: invalid gate_result: $GATE_RESULT" >&2
        exit 1
        ;;
esac

if [ ! -f "$LOG_FILE" ]; then
    exit 0
fi

# 該当cmd_idのエントリのgate_result: nullをgate_result: <GATE_RESULT>に更新
# 同一cmd_idに複数エントリ(draft+report)がありえるので全て更新
# archiveファイルは対象外（LOG_FILEのみ操作）

# 方針: awkで状態機械。cmd_idマッチ中にgate_result: nullを見つけたら置換
TMPFILE=$(mktemp "${LOG_FILE}.tmp.XXXXXX")
COUNT_TMPFILE=$(mktemp "${LOG_FILE}.count.XXXXXX")
trap 'rm -f "$TMPFILE" "$COUNT_TMPFILE"' EXIT

source "$SCRIPT_DIR/scripts/lib/lock_path.sh"
LOCK_FILE="$(lock_path "$LOG_FILE")"

exec 9>"$LOCK_FILE"
flock -w 10 9

awk -v cmd_id="$CMD_ID" -v gate_result="$GATE_RESULT" '
function regex_escape(str,    out,i,c) {
    out = ""
    for (i = 1; i <= length(str); i++) {
        c = substr(str, i, 1)
        if (c ~ /[][\\.^$*+?(){}|]/) out = out "\\" c
        else out = out c
    }
    return out
}
BEGIN {
    in_entry = 0
    match_cmd = 0
    quote = sprintf("%c", 39)
    cmd_re = "^[-] cmd_id:[[:space:]]*[\042" quote "]?" regex_escape(cmd_id) "[\042" quote "]?[[:space:]]*$"
}
/^- cmd_id:/ {
    in_entry = 1
    match_cmd = 0
    if ($0 ~ cmd_re) {
        match_cmd = 1
    }
}
/^[^- ]/ && !/^  / && !/^#/ { in_entry = 0; match_cmd = 0 }
match_cmd && /^  gate_result: null/ {
    sub(/gate_result: null/, "gate_result: " gate_result)
    updated++
}
{ print }
END { print updated+0 > "/dev/stderr" }
' "$LOG_FILE" > "$TMPFILE" 2>"$COUNT_TMPFILE"

UPDATE_COUNT=$(cat "$COUNT_TMPFILE" 2>/dev/null || echo "0")

if [ "$UPDATE_COUNT" -gt 0 ]; then
    mv "$TMPFILE" "$LOG_FILE"
    echo "  gunshi_gate_reflux: ${UPDATE_COUNT} entries updated (${CMD_ID} → ${GATE_RESULT})"
fi
