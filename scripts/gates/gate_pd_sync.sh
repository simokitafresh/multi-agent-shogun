#!/bin/bash
# gate_pd_sync.sh — PD解決後のcontext反映チェックゲート（BLOCK）
# Usage: bash scripts/gates/gate_pd_sync.sh <pd_id>
#
# - pending_decisions.yamlから未反映PD(context_synced: false)を全件確認
# - 1件でも存在すればBLOCK表示 + pd_unsync.logに追記 + exit 1
# - 未反映が0件なら該当PD状態を表示してexit 0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DATA_FILE="$SCRIPT_DIR/queue/pending_decisions.yaml"
ALERT_DIR="$SCRIPT_DIR/queue/alerts"
UNSYNC_LOG="$ALERT_DIR/pd_unsync.log"

PD_ID="$1"

emit_prefixed_actionable_stderr() {
    local message="$1"
    local action="$2"
    echo "$message" >&2
    echo "[gate_pd_sync] action: $action" >&2
}

if [ -z "$PD_ID" ]; then
    echo "Usage: gate_pd_sync.sh <pd_id>" >&2
    exit 1
fi

if [ ! -f "$DATA_FILE" ]; then
    emit_prefixed_actionable_stderr \
        "[gate_pd_sync] WARNING: $DATA_FILE not found" \
        "queue/pending_decisions.yaml の配置を確認し、PD同期の一次データを復旧せよ。"
    exit 0
fi

mkdir -p "$ALERT_DIR"

# Check context_synced for the given PD
mapfile -t _pd_sync_lines < <(
    awk -v pd_id="$PD_ID" '
function flush_decision() {
    if (!in_decision || current_id == "") return

    if (current_id == pd_id) {
        if (context_seen && current_context == "true") {
            target_result = "SYNCED"
        } else {
            target_result = "NOT_SYNCED"
        }
    }

    if (context_seen && current_context == "false") {
        if (unsynced_ids != "") unsynced_ids = unsynced_ids ","
        unsynced_ids = unsynced_ids current_id
    }
}
BEGIN {
    in_decision = 0
    current_id = ""
    current_context = ""
    context_seen = 0
    target_result = "NOT_FOUND"
    unsynced_ids = ""
}
/^- id:[[:space:]]*/ {
    flush_decision()
    in_decision = 1
    current_id = $3
    current_context = ""
    context_seen = 0
    next
}
in_decision && /^[[:space:]]+context_synced:[[:space:]]*/ {
    current_context = $2
    context_seen = 1
    next
}
END {
    flush_decision()
    print target_result
    print unsynced_ids
}
' "$DATA_FILE"
)

TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S")
RESULT_STATUS="${_pd_sync_lines[0]:-ERROR}"
UNSYNCED_IDS_RAW="${_pd_sync_lines[1]:-}"

if [ -n "$UNSYNCED_IDS_RAW" ]; then
    BLOCK_MSG="$TIMESTAMP  BLOCK: context未反映PDあり: $UNSYNCED_IDS_RAW"
    emit_prefixed_actionable_stderr \
        "[gate_pd_sync] $BLOCK_MSG" \
        "pending_decisions.yaml の context_synced=false を解消し、対応する context/*.md を更新せよ。"
    echo "$BLOCK_MSG" >> "$UNSYNC_LOG"
    exit 1
fi

case "$RESULT_STATUS" in
    SYNCED)
        echo "[gate_pd_sync] $PD_ID: context_synced=true (OK)"
        ;;
    NOT_SYNCED)
        emit_prefixed_actionable_stderr \
            "[gate_pd_sync] BLOCK: $PD_ID context_synced=false" \
            "該当PDの内容を context へ反映し、context_synced を true に更新せよ。"
        exit 1
        ;;
    NOT_FOUND)
        emit_prefixed_actionable_stderr \
            "[gate_pd_sync] WARNING: $PD_ID not found in pending_decisions.yaml" \
            "PD ID を確認し、pending_decisions.yaml に存在する正しい ID で再実行せよ。"
        ;;
    *)
        echo "[gate_pd_sync] ERROR checking $PD_ID" >&2
        exit 1
        ;;
esac

exit 0
