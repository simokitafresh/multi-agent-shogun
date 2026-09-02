#!/bin/bash
# publisher_queue.sh — 単一 publisher 化 U1: publish request の FIFO queue + lock-run 起動口
#
# Usage:
#   publisher_queue.sh enqueue <request.yaml>          # -> stdout: queue内path
#   publisher_queue.sh dequeue                          # -> stdout: 取り出したpath (rc=3: 空)
#   publisher_queue.sh peek                             # -> stdout: 先頭path (rc=3: 空、削除しない)
#   publisher_queue.sh lock-run --bound <sec> -- <cmd...>
#
# 設計書: docs/research/single_publisher_asis_tobe_5w1h_20260902.md §9.1 U1 / §9.0 共通
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# STATE_DIR は tracked root の外・永続領域のみ許可(H2: /tmp は再起動で消失する実績あり)。
# 既定 = $HOME/.local/share/multi-agent-shogun。root配下・/tmp配下は起動拒否(rc=2)。
resolve_state_dir() {
    local dir="${SHOGUN_STATE_DIR:-$HOME/.local/share/multi-agent-shogun}"
    local real_dir real_root
    mkdir -p "$dir" 2>/dev/null || true
    real_dir="$(cd "$dir" 2>/dev/null && pwd)"
    if [ -z "$real_dir" ]; then
        echo "publisher_queue: FATAL cannot resolve STATE_DIR: $dir" >&2
        return 2
    fi
    case "$real_dir" in
        /tmp|/tmp/*)
            echo "publisher_queue: FATAL STATE_DIR under /tmp (非永続、H2禁止): $real_dir" >&2
            return 2
            ;;
    esac
    real_root="$(cd "$REPO_ROOT" && pwd)"
    case "$real_dir" in
        "$real_root"|"$real_root"/*)
            echo "publisher_queue: FATAL STATE_DIR under tracked repo root: $real_dir" >&2
            return 2
            ;;
    esac
    STATE_DIR="$real_dir"
}

STATE_DIR=""
resolve_state_dir || exit 2

QUEUE_DIR="$STATE_DIR/publish_queue"
RUN_DIR="$QUEUE_DIR/run"
DEQUEUED_DIR="$QUEUE_DIR/dequeued"
SEQ_FILE="$QUEUE_DIR/.seq"
SEQ_LOCK="$QUEUE_DIR/.seq.lock"

mkdir -p "$QUEUE_DIR" "$RUN_DIR" "$DEQUEUED_DIR"

# next_seq: 呼出元が保持するflock下でグローバル単調増加のseqを払い出す
# (12桁ゼロ埋め、辞書順=数値順を保証)。seq払い出しからrequest公開まで
# 同じlockを保持し、後続enqueueが先にdequeue可能になる窓を閉じる。
next_seq() {
    local n
    n=$(cat "$SEQ_FILE" 2>/dev/null || echo 0)
    n=$((n + 1))
    printf '%s' "$n" > "$SEQ_FILE"
    printf '%012d' "$n"
}

cmd_enqueue() {
    local req="$1"
    if [ -z "$req" ] || [ ! -f "$req" ]; then
        echo "publisher_queue: enqueue requires an existing request file" >&2
        return 1
    fi
    local task_id
    task_id="$(grep -m1 '^task_id:' "$req" 2>/dev/null | sed -E 's/^task_id:[[:space:]]*//; s/^["'"'"']//; s/["'"'"']$//')"
    task_id="$(printf '%s' "$task_id" | tr -c 'A-Za-z0-9_-' '_')"
    [ -n "$task_id" ] || task_id="unknown"

    local epoch seq dest tmp
    # The timestamp and sequence are submission-order metadata.  Keep the
    # lock until the atomically-renamed request is visible so dequeue cannot
    # observe a later sequence while an earlier request is still being copied.
    exec 8>"$SEQ_LOCK"
    flock -x 8
    epoch="$(date +%s)"
    seq="$(next_seq)"
    dest="$QUEUE_DIR/${epoch}_${seq}_${task_id}.request"
    tmp="$dest.tmp.$$"
    cp "$req" "$tmp"
    mv "$tmp" "$dest"
    flock -u 8
    exec 8>&-
    printf '%s\n' "$dest"
}

cmd_dequeue() {
    exec 8>"$SEQ_LOCK"
    flock -x 8
    local first base dest
    first="$(find "$QUEUE_DIR" -maxdepth 1 -type f -name '*.request' 2>/dev/null | sort | head -n1)"
    if [ -z "$first" ]; then
        flock -u 8
        exec 8>&-
        return 3
    fi
    base="$(basename "$first")"
    dest="$DEQUEUED_DIR/$base"
    mv "$first" "$dest"
    flock -u 8
    exec 8>&-
    printf '%s\n' "$dest"
}

cmd_peek() {
    local first
    first="$(find "$QUEUE_DIR" -maxdepth 1 -type f -name '*.request' 2>/dev/null | sort | head -n1)"
    [ -n "$first" ] || return 3
    printf '%s\n' "$first"
}

cmd_lock_run() {
    local bound=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --bound) bound="$2"; shift 2 ;;
            --) shift; break ;;
            *) echo "publisher_queue: lock-run unknown arg: $1" >&2; return 1 ;;
        esac
    done
    if [ -z "$bound" ]; then
        echo "publisher_queue: lock-run requires --bound <sec>" >&2
        return 1
    fi
    if [ $# -eq 0 ]; then
        echo "publisher_queue: lock-run requires -- <command...>" >&2
        return 1
    fi

    local repo lock_file run_id shim events_lib rc
    repo="${PUBLISHER_REPO_NAME:-$(basename "$REPO_ROOT")}"
    lock_file="$STATE_DIR/publish.lock.$repo"
    run_id="$(date +%s%N)_$$"
    shim="$SCRIPT_DIR/lib/lock_run_shim.sh"
    events_lib="$SCRIPT_DIR/lib/publisher_event.sh"

    set +e
    bash "$shim" --bound "$bound" --lock-file "$lock_file" --run-dir "$RUN_DIR" --run-id "$run_id" -- "$@"
    rc=$?
    set -e

    # H9: サイレントフォールバック禁止。rc=210/211 は events.jsonl+家老 inbox で沈黙0にする。
    if [ "$rc" -eq 211 ]; then
        bash "$events_lib" append rc211 "$run_id" 211 "lock-run child unknown termination(root_cause=see done receipt)" || true
        bash "$SCRIPT_DIR/inbox_write.sh" karo "publisher lock-run rc=211(child不明終了) run_id=$run_id lock=$lock_file" investigation_result publisher_queue notify_karo >/dev/null 2>&1 || true
    elif [ "$rc" -eq 210 ]; then
        bash "$events_lib" append rc210 "$run_id" 210 "lock-run bound timeout(GNU timeout group signal escalation)" || true
    fi
    return "$rc"
}

main() {
    local sub="$1"
    if [ -z "$sub" ]; then
        echo "Usage: publisher_queue.sh <enqueue|dequeue|peek|lock-run> ..." >&2
        exit 1
    fi
    shift
    case "$sub" in
        enqueue) cmd_enqueue "$@" ;;
        dequeue) cmd_dequeue "$@" ;;
        peek) cmd_peek "$@" ;;
        lock-run) cmd_lock_run "$@" ;;
        *) echo "publisher_queue: unknown subcommand: $sub" >&2; exit 1 ;;
    esac
}

main "$@"
