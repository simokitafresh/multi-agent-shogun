#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${1:-}" ]]; then
    echo "Usage: ntfy_batch.sh <message>" >&2
    exit 1
fi

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
SCRIPT_DIR="${_self%/scripts/ntfy_batch.sh}"
QUEUE_DIR="$SCRIPT_DIR/queue"
QUEUE_FILE="$QUEUE_DIR/ntfy_batch_queue.txt"
LOCK_FILE="${QUEUE_FILE}.lock"

mkdir -p "$QUEUE_DIR"

MESSAGE="$1"
MESSAGE="${MESSAGE//$'\r'/ }"
MESSAGE="${MESSAGE//$'\n'/ }"
MESSAGE="${MESSAGE//$'\t'/ }"
MESSAGE="${MESSAGE#"${MESSAGE%%[![:space:]]*}"}"
MESSAGE="${MESSAGE%"${MESSAGE##*[![:space:]]}"}"
while [[ "$MESSAGE" == *"  "* ]]; do
    MESSAGE="${MESSAGE//  / }"
done
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

if [[ -z "$MESSAGE" ]]; then
    exit 0
fi

(
    flock -w 10 200 || { echo "[ntfy_batch] ERROR: lock timeout" >&2; exit 1; }
    printf '%s|%s\n' "$TIMESTAMP" "$MESSAGE" >> "$QUEUE_FILE"
) 200>"$LOCK_FILE"
