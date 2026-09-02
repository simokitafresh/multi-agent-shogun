#!/bin/bash
# publisher_event.sh — 単一 publisher 化 D14: events.jsonl の唯一の writer
#
# Usage: publisher_event.sh append <kind> <request_id> <rc> <reason>
#
# 契約(設計書 §6 D14):
#   唯一のwriter。$STATE_DIR/publish_queue/events.lock 下でseqをcounter fileから+1し、
#   1行(<=4KB)をO_APPENDで1write。fields=seq/ts/kind/request/rc/reason/pid。
#   kind ∈ {rc210, rc211, c2a_rc, already_published, r11_hold, r13_reject, cas_rejected, deploy_check_started,
#           deploy_check_terminal, deploy_check_stale, retry_exhausted, deploy_check_exhausted, git_fail}
#   直接 echo >> による追記は禁止(このscript経由のみ)。
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

resolve_state_dir() {
    local dir="${SHOGUN_STATE_DIR:-$HOME/.local/share/multi-agent-shogun}"
    local real_dir real_root
    mkdir -p "$dir" 2>/dev/null || true
    real_dir="$(cd "$dir" 2>/dev/null && pwd)"
    if [ -z "$real_dir" ]; then
        echo "publisher_event: FATAL cannot resolve STATE_DIR: $dir" >&2
        return 2
    fi
    case "$real_dir" in
        /tmp|/tmp/*)
            echo "publisher_event: FATAL STATE_DIR under /tmp: $real_dir" >&2
            return 2
            ;;
    esac
    real_root="$(cd "$REPO_ROOT" && pwd)"
    case "$real_dir" in
        "$real_root"|"$real_root"/*)
            echo "publisher_event: FATAL STATE_DIR under tracked repo root: $real_dir" >&2
            return 2
            ;;
    esac
    STATE_DIR="$real_dir"
}

STATE_DIR=""
resolve_state_dir || exit 2

QUEUE_DIR="$STATE_DIR/publish_queue"
EVENTS_FILE="$QUEUE_DIR/events.jsonl"
EVENTS_LOCK="$QUEUE_DIR/events.lock"
SEQ_COUNTER="$QUEUE_DIR/events.seq"

mkdir -p "$QUEUE_DIR"

VALID_KINDS="rc210 rc211 c2a_rc already_published dry_run_publish ledger r11_hold r13_reject cas_rejected deploy_check_started deploy_check_terminal deploy_check_stale retry_exhausted deploy_check_exhausted git_fail"

cmd_append() {
    local kind="$1" request="$2" rc="$3" reason="$4"
    if [ -z "$kind" ]; then
        echo "publisher_event: append requires <kind>" >&2
        return 1
    fi
    local ok=0 k
    for k in $VALID_KINDS; do
        [ "$k" = "$kind" ] && ok=1 && break
    done
    if [ "$ok" -ne 1 ]; then
        echo "publisher_event: unknown kind: $kind" >&2
        return 1
    fi

    local line seq
    exec 8>"$EVENTS_LOCK"
    flock -x 8
    seq="$(cat "$SEQ_COUNTER" 2>/dev/null || echo 0)"
    seq=$((seq + 1))
    printf '%s' "$seq" > "$SEQ_COUNTER"
    line="$(jq -nc \
        --argjson seq "$seq" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
        --arg kind "$kind" \
        --arg request "$request" \
        --arg rc "$rc" \
        --arg reason "$reason" \
        --arg pid "$$" \
        '{seq:$seq, ts:$ts, kind:$kind, request:$request, rc:$rc, reason:$reason, pid:($pid|tonumber)}')"
    printf '%s\n' "$line" >> "$EVENTS_FILE"
    flock -u 8
    exec 8>&-
}

main() {
    local sub="$1"
    if [ -z "$sub" ]; then
        echo "Usage: publisher_event.sh append <kind> <request_id> <rc> <reason>" >&2
        exit 1
    fi
    shift
    case "$sub" in
        append) cmd_append "$@" ;;
        *) echo "publisher_event: unknown subcommand: $sub" >&2; exit 1 ;;
    esac
}

main "$@"
