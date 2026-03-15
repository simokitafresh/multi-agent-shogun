#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUEUE_FILE="$SCRIPT_DIR/queue/ntfy_batch_queue.txt"
LOCK_FILE="${QUEUE_FILE}.lock"
NTFY_SCRIPT="$SCRIPT_DIR/scripts/ntfy.sh"

mkdir -p "$(dirname "$QUEUE_FILE")"
touch "$QUEUE_FILE"

flush_queue() {
    flock -w 10 200 || { echo "[ntfy_batch_flush] ERROR: lock timeout" >&2; exit 1; }

    if [[ ! -s "$QUEUE_FILE" ]]; then
        return 3
    fi

    mapfile -t queued_lines < "$QUEUE_FILE"
    if [[ ${#queued_lines[@]} -eq 0 ]]; then
        : > "$QUEUE_FILE"
        return 3
    fi

    local payload
    payload=$'【INFOバッチ】\n'
    payload+=$(printf '%s\n' "${queued_lines[@]}")

    bash "$NTFY_SCRIPT" "$payload"
    : > "$QUEUE_FILE"
}

(
    flush_queue
) 200>"$LOCK_FILE" || {
    status=$?
    if [[ "$status" -eq 3 ]]; then
        exit 0
    fi
    exit "$status"
}
