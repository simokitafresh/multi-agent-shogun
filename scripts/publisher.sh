#!/usr/bin/env bash
# publisher.sh — 単一 publisher 化 U3
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${PUBLISHER_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
STATE_DIR="${SHOGUN_STATE_DIR:-$HOME/.local/share/multi-agent-shogun}"

resolve_state_dir() {
    local real_state real_root
    mkdir -p "$STATE_DIR"
    real_state="$(cd "$STATE_DIR" && pwd)"
    real_root="$(cd "$REPO_ROOT" && pwd)"
    case "$real_state" in
        /tmp|/tmp/*) echo "publisher: STATE_DIR under /tmp is not persistent: $real_state" >&2; return 2 ;;
        "$real_root"|"$real_root"/*) echo "publisher: STATE_DIR must be outside repository root: $real_state" >&2; return 2 ;;
    esac
    STATE_DIR="$real_state"
}

resolve_state_dir
QUEUE_ROOT="$STATE_DIR/publish_queue"
RC_DIR="$QUEUE_ROOT/rc"
DONE_DIR="$QUEUE_ROOT/done"
PID_FILE="$QUEUE_ROOT/publisher.pid"
EVENT_LIB="$SCRIPT_DIR/lib/publisher_event.sh"
QUEUE_LIB="$SCRIPT_DIR/publisher_queue.sh"
INBOX_WRITER="${PUBLISHER_INBOX_WRITER:-$SCRIPT_DIR/inbox_write.sh}"
mkdir -p "$QUEUE_ROOT" "$RC_DIR" "$DONE_DIR"

request_field() {
    local request="$1" field="$2"
    python3 - "$request" "$field" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
value = data.get(sys.argv[2])
if isinstance(value, list):
    print("\n".join(str(item) for item in value))
elif value is not None:
    print(str(value))
PY
}

manifest_field() {
    local manifest="$1" field="$2"
    python3 - "$manifest" "$field" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
value = data.get(sys.argv[2])
if isinstance(value, list):
    print("\n".join(str(item) for item in value))
elif value is not None:
    print(str(value))
PY
}

request_id() { request_field "$1" task_id | head -n1; }

notify_karo() {
    local message="$1" action="${2:-investigation_result}"
    if ! bash "$INBOX_WRITER" karo "$message" "$action" publisher notify_karo; then
        echo "publisher: failed to notify karo: $message" >&2
        return 1
    fi
}

event() {
    if ! bash "$EVENT_LIB" append "$1" "$2" "$3" "$4"; then
        echo "publisher: failed to append event kind=$1 request=$2" >&2
        return 1
    fi
}

move_to_rc() { mv "$1" "$RC_DIR/$(basename "$1")"; }
move_to_done() { mv "$1" "$DONE_DIR/$(basename "$1")"; }
requeue_request() { mv "$1" "$QUEUE_ROOT/$(basename "$1")"; }

increment_publish_attempts() {
    local request="$1" current next
    current="$(request_field "$request" publish_attempts)"
    current="${current:-0}"
    [[ "$current" =~ ^[0-9]+$ ]] || { echo "publisher: invalid publish_attempts=$current" >&2; return 2; }
    next=$((current + 1))
    bash "$SCRIPT_DIR/lib/yaml_field_set.sh" "$request" root publish_attempts "$next"
    printf '%s\n' "$next"
}

cleanup_isolated() {
    local isolated="${1:-}"
    [ -n "$isolated" ] && [ -d "$isolated" ] || return 0
    case "$isolated" in
        "$REPO_ROOT/.git/publisher-isolated."*) find "$isolated" -depth -delete ;;
        *) echo "publisher: refusing to clean unexpected isolated path: $isolated" >&2; return 1 ;;
    esac
}

root_has_untracked_collision() {
    local root="$1" tip="$2" status_file diff_file
    status_file="$(mktemp)"; diff_file="$(mktemp)"
    git -C "$root" status --porcelain -uall > "$status_file"
    git -C "$root" diff --name-only HEAD "$tip" > "$diff_file"
    python3 - "$status_file" "$diff_file" <<'PY'
import sys
untracked = {line[3:].rstrip("\n") for line in open(sys.argv[1], encoding="utf-8") if line.startswith("?? ")}
changed = {line.rstrip("\n") for line in open(sys.argv[2], encoding="utf-8") if line.strip()}
print("1" if untracked & changed else "0")
PY
    rm -f "$status_file" "$diff_file"
}

tracked_dirty_count() { git -C "$1" status --porcelain -uno | awk 'NF { n++ } END { print n + 0 }'; }

sync_root() {
    local root="$1" tip="$2" dirty collision
    dirty="$(tracked_dirty_count "$root")"
    collision="$(root_has_untracked_collision "$root" "$tip")"
    if [ "$dirty" -ne 0 ] || [ "$collision" -ne 0 ]; then
        echo "publisher: root sync BLOCK tracked_dirty=$dirty untracked_collision=$collision" >&2
        return 32
    fi
    git -C "$root" merge --ff-only origin/main
    [ "$(git -C "$root" rev-parse HEAD)" = "$(git -C "$root" rev-parse origin/main)" ]
    [ "$(tracked_dirty_count "$root")" -eq 0 ]
}

process_request() {
    local request="$1" mode="$2" task artifact manifest base tip origin_url isolated
    task="$(request_id "$request")"
    artifact="$STATE_DIR/publish_queue/artifacts/$task"
    manifest="$artifact/manifest.yaml"
    [ -f "$manifest" ] && [ -f "$artifact/patch.diff" ] || { echo "publisher: missing artifact task=$task" >&2; return 31; }
    timeout 120 git -C "$REPO_ROOT" fetch origin
    tip="$(git -C "$REPO_ROOT" rev-parse origin/main)"
    base="$(manifest_field "$manifest" base | head -n1)"
    [ -n "$base" ] || { echo "publisher: manifest base missing task=$task" >&2; return 31; }

    local path tip_blob base_blob
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if git -C "$REPO_ROOT" cat-file -e "$tip:$path"; then
            tip_blob="$(git -C "$REPO_ROOT" rev-parse "$tip:$path")"
        else
            tip_blob=ABSENT
        fi
        if git -C "$REPO_ROOT" cat-file -e "$base:$path"; then
            base_blob="$(git -C "$REPO_ROOT" rev-parse "$base:$path")"
        else
            base_blob=ABSENT
        fi
        if [ "$tip_blob" != "$base_blob" ]; then
            event c2a_rc "$task" 1 "base_blob_mismatch path=$path"; notify_karo "publisher C2a RC task=$task path=$path tip=$tip base=$base"; move_to_rc "$request"; return 30
        fi
    done < <(manifest_field "$manifest" paths)

    origin_url="$(git -C "$REPO_ROOT" remote get-url origin)"
    isolated="$(mktemp -d "$REPO_ROOT/.git/publisher-isolated.XXXXXX")"
    trap 'cleanup_isolated "${isolated:-}"' RETURN
    git clone --no-checkout "$origin_url" "$isolated"
    git -C "$isolated" remote set-url origin "$origin_url"
    git -C "$isolated" checkout --detach "$tip"
    bash "$SCRIPT_DIR/publish_artifact.sh" restore "$task" "$isolated"
    local tree published_sha
    tree="$(git -C "$isolated" write-tree)"
    published_sha="$(printf 'publisher: task=%s\n\nPublished-By: publisher\n' "$task" | git -C "$isolated" -c user.name=single-publisher -c user.email=publisher@localhost commit-tree "$tree" -p "$tip")"
    if [ "$mode" = dry-run ]; then
        event dry_run_publish "$task" 0 "published_sha=$published_sha origin_update=0"
    else
        timeout 120 git -C "$isolated" push origin "$published_sha:refs/heads/main"
        timeout 120 git -C "$REPO_ROOT" fetch origin
        sync_root "$REPO_ROOT" origin/main
    fi
    cleanup_isolated "$isolated"; trap - RETURN
    move_to_done "$request"
}

handle_lock_failure() {
    local request="$1" rc="$2" task next
    task="$(request_id "$request")"
    if [ "$rc" -eq 210 ]; then
        notify_karo "publisher lock-run timeout rc=210 task=$task"
        next="$(increment_publish_attempts "$request")"
        if [ "$next" -gt 3 ]; then
            event retry_exhausted "$task" 210 "publish_attempts=$next"; notify_karo "publisher retry exhausted task=$task publish_attempts=$next"; move_to_rc "$request"
        else
            requeue_request "$request"
        fi
    elif [ "$rc" -ne 0 ]; then
        # C2a already rotated the request and emitted its own terminal evidence.
        # Do not manufacture a second generic failure event for the same request.
        [ -f "$request" ] || return 0
        event git_fail "$task" "$rc" "publisher request failed"; notify_karo "publisher request failed task=$task rc=$rc"; [ -f "$request" ] && move_to_rc "$request"
    fi
}

run_one() {
    local request rc mode="${PUBLISHER_MODE:-dry-run}"
    case "$mode" in dry-run|active) ;; *) echo "publisher: PUBLISHER_MODE must be dry-run or active" >&2; return 2 ;; esac
    if ! request="$(bash "$QUEUE_LIB" dequeue)"; then
        rc=$?; [ "$rc" -eq 3 ] && return 0; return "$rc"
    fi
    if bash "$QUEUE_LIB" lock-run --bound 600 -- bash "$SCRIPT_DIR/publisher.sh" --process-request "$request" "$mode"; then return 0; fi
    rc=$?; handle_lock_failure "$request" "$rc"
}

daemon_main() {
    local once="${PUBLISHER_ONCE:-0}" sleep_seconds="${PUBLISHER_SLEEP_SECONDS:-2}"
    printf '%s\n' "$$" > "$PID_FILE"; trap 'rm -f "$PID_FILE"' EXIT
    while :; do run_one; [ "$once" = 1 ] && break; sleep "$sleep_seconds"; done
}

if [ "${1:-}" = --process-request ]; then process_request "$2" "$3"
elif [ "${PUBLISHER_LIB_ONLY:-0}" != 1 ]; then daemon_main
fi
