#!/usr/bin/env bash
set -euo pipefail

_SELF="${BASH_SOURCE[0]}"
case "$_SELF" in
    */*) _SCRIPT_DIR="${_SELF%/*}" ;;
    *) _SCRIPT_DIR="." ;;
esac
SCRIPT_DIR="${_SCRIPT_DIR}/.."
[[ "$SCRIPT_DIR" != /* ]] && SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
unset _SELF _SCRIPT_DIR

QUEUE_DIR="$SCRIPT_DIR/queue"
QUEUE_FILE="$QUEUE_DIR/ntfy_batch_queue.txt"
LOCK_FILE="${QUEUE_FILE}.lock"
NTFY_SCRIPT="$SCRIPT_DIR/scripts/ntfy.sh"

ensure_queue_paths() {
    [[ -d "$QUEUE_DIR" ]] || mkdir -p "$QUEUE_DIR"
    [[ -e "$QUEUE_FILE" ]] || : > "$QUEUE_FILE"
}

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

ensure_queue_paths

(
    flush_queue
) 200>"$LOCK_FILE" || {
    status=$?
    if [[ "$status" -eq 3 ]]; then
        exit 0
    fi
    exit "$status"
}
