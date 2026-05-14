#!/usr/bin/env bash
# shogun_lesson_ack.sh — record that a cmd_save BLOCK matched an existing Shogun lesson cluster.
#
# Usage:
#   bash scripts/shogun_lesson_ack.sh <cmd_id> <lesson_id>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

QUALITY_LOG_FILE="${SHOGUN_LESSON_ACK_QUALITY_LOG_FILE:-$PROJECT_DIR/logs/cmd_design_quality.yaml}"
SHOGUN_LESSONS_FILE="${SHOGUN_LESSON_ACK_LESSONS_FILE:-$PROJECT_DIR/projects/infra/lessons_shogun.yaml}"
ACK_FILE="${SHOGUN_LESSON_ACK_FILE:-$PROJECT_DIR/queue/shogun_lesson_ack.yaml}"
LOCK_FILE="${SHOGUN_LESSON_ACK_LOCK_FILE:-$ACK_FILE.lock}"

usage() {
    echo "Usage: bash scripts/shogun_lesson_ack.sh <cmd_id> <lesson_id>" >&2
}

die() {
    echo "BLOCK: $*" >&2
    exit 1
}

cmd_id="${1:-}"
lesson_id="${2:-}"

[[ $# -eq 2 ]] || {
    usage
    exit 1
}
[[ "$cmd_id" =~ ^cmd_[0-9A-Za-z_-]+$ ]] || die "cmd_id must look like cmd_XXXX (got: $cmd_id)"
[[ "$lesson_id" =~ ^LS-[A-Za-z0-9_-]+$ ]] || die "lesson_id must look like LS-XXXX (got: $lesson_id)"
[[ -f "$SHOGUN_LESSONS_FILE" ]] || die "lessons_shogun.yaml not found: $SHOGUN_LESSONS_FILE"
[[ -f "$QUALITY_LOG_FILE" ]] || die "quality log not found: $QUALITY_LOG_FILE"

lesson_exists() {
    awk -v target="$lesson_id" '
        function strip(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            sub(/^["'\''"]/, "", value)
            sub(/["'\''"]$/, "", value)
            return value
        }
        /^[[:space:]]*-[[:space:]]+id:[[:space:]]*/ {
            value = $0
            sub(/^[[:space:]]*-[[:space:]]+id:[[:space:]]*/, "", value)
            if (strip(value) == target) {
                found = 1
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$SHOGUN_LESSONS_FILE"
}

cmd_save_block_count() {
    awk -v target="$cmd_id" '
        function strip(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            sub(/^["'\''"]/, "", value)
            sub(/["'\''"]$/, "", value)
            return value
        }
        function flush_entry() {
            if (entry_cmd == target && gate_result == "BLOCK" && source == "cmd_save") {
                count++
            }
            entry_cmd = ""
            gate_result = ""
            source = ""
        }
        BEGIN {
            count = 0
            in_entry = 0
        }
        /^[[:space:]]*-[[:space:]]+cmd_id:[[:space:]]*/ {
            if (in_entry) {
                flush_entry()
            }
            in_entry = 1
            value = $0
            sub(/^[[:space:]]*-[[:space:]]+cmd_id:[[:space:]]*/, "", value)
            entry_cmd = strip(value)
            next
        }
        in_entry && /^[[:space:]]+gate_result:[[:space:]]*/ {
            value = $0
            sub(/^[[:space:]]+gate_result:[[:space:]]*/, "", value)
            gate_result = strip(value)
            next
        }
        in_entry && /^[[:space:]]+source:[[:space:]]*/ {
            value = $0
            sub(/^[[:space:]]+source:[[:space:]]*/, "", value)
            source = strip(value)
            next
        }
        END {
            if (in_entry) {
                flush_entry()
            }
            print count
        }
    ' "$QUALITY_LOG_FILE"
}

ack_exists() {
    [[ -f "$ACK_FILE" ]] || return 1
    awk -v target_cmd="$cmd_id" -v target_lesson="$lesson_id" '
        function strip(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            sub(/^["'\''"]/, "", value)
            sub(/["'\''"]$/, "", value)
            return value
        }
        /^[[:space:]]*-[[:space:]]+cmd_id:[[:space:]]*/ {
            if (in_entry && entry_cmd == target_cmd && entry_lesson == target_lesson) {
                found = 1
            }
            in_entry = 1
            entry_lesson = ""
            value = $0
            sub(/^[[:space:]]*-[[:space:]]+cmd_id:[[:space:]]*/, "", value)
            entry_cmd = strip(value)
            next
        }
        in_entry && /^[[:space:]]+lesson_id:[[:space:]]*/ {
            value = $0
            sub(/^[[:space:]]+lesson_id:[[:space:]]*/, "", value)
            entry_lesson = strip(value)
            next
        }
        END {
            if (in_entry && entry_cmd == target_cmd && entry_lesson == target_lesson) {
                found = 1
            }
            exit(found ? 0 : 1)
        }
    ' "$ACK_FILE"
}

lesson_exists || die "lesson_id not found in lessons_shogun.yaml: $lesson_id"

block_count="$(cmd_save_block_count)"
[[ "$block_count" =~ ^[0-9]+$ ]] || block_count=0
(( block_count > 0 )) || die "$cmd_id has no cmd_save BLOCK entry in quality log"

mkdir -p "$(dirname "$ACK_FILE")"

(
    flock -w 10 200 || die "failed to acquire ack lock"
    if [[ ! -f "$ACK_FILE" ]]; then
        printf 'acks:\n' > "$ACK_FILE"
    fi
    if ack_exists; then
        echo "OK: ack already exists for $cmd_id -> $lesson_id"
        exit 0
    fi
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    {
        printf -- '- cmd_id: "%s"\n' "$cmd_id"
        printf '  lesson_id: "%s"\n' "$lesson_id"
        printf '  block_count: %s\n' "$block_count"
        printf '  timestamp: "%s"\n' "$timestamp"
    } >> "$ACK_FILE"
) 200>"$LOCK_FILE"

echo "OK: recorded ack for $cmd_id -> $lesson_id (blocks=$block_count)"
