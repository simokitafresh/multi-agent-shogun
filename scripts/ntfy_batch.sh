#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${1:-}" ]]; then
    echo "Usage: ntfy_batch.sh <message>" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUEUE_FILE="$SCRIPT_DIR/queue/ntfy_batch_queue.txt"
LOCK_FILE="${QUEUE_FILE}.lock"

mkdir -p "$(dirname "$QUEUE_FILE")"

MESSAGE="$(printf '%s' "$1" | tr '\r\n' '  ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

if [[ -z "$MESSAGE" ]]; then
    exit 0
fi

(
    flock -w 10 200 || { echo "[ntfy_batch] ERROR: lock timeout" >&2; exit 1; }
    printf '%s|%s\n' "$TIMESTAMP" "$MESSAGE" >> "$QUEUE_FILE"
) 200>"$LOCK_FILE"
