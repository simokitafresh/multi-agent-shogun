#!/usr/bin/env bash
# publisher_root_drain.sh — publish committed root commits through the single publisher lock.

set -euo pipefail

publisher_root_drain() {
    local repo_root="${1:-}" queue_script remote_ref head base log_path inbox_writer bound
    if [ -z "$repo_root" ] || [ ! -d "$repo_root/.git" ]; then
        echo "publisher: root drain requires a git repository" >&2
        return 2
    fi

    repo_root="$(cd "$repo_root" && pwd)"
    queue_script="${PUBLISHER_QUEUE_SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/publisher_queue.sh}"
    remote_ref="${PUBLISHER_ROOT_DRAIN_REMOTE_REF:-origin/main}"
    log_path="${PUBLISHER_DAEMON_LOG:-$repo_root/logs/publisher_daemon.log}"
    inbox_writer="${PUBLISHER_INBOX_WRITER:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/inbox_write.sh}"
    bound="${PUBLISHER_ROOT_DRAIN_BOUND:-600}"

    mkdir -p "$(dirname "$log_path")"
    if ! timeout 120 git -C "$repo_root" fetch origin; then
        printf '%s\n' "publisher: root drain BLOCK fetch_failed" >> "$log_path"
        return 1
    fi

    head="$(git -C "$repo_root" rev-parse HEAD)"
    if ! base="$(git -C "$repo_root" merge-base "$remote_ref" HEAD)"; then
        printf '%s\n' "publisher: root drain BLOCK missing_ref remote=$remote_ref head=$head" >> "$log_path"
        return 1
    fi

    if [ "$base" != "$(git -C "$repo_root" rev-parse "$remote_ref")" ]; then
        printf '%s\n' "publisher: root drain BLOCK divergence base=$base" >> "$log_path"
        if ! bash "$inbox_writer" karo "publisher: root drain BLOCK divergence base=$base head=$head task_id=commander_directive subject_task_id=publisher_root_drain parent_cmd=publisher_root_drain" task_supplement publisher_root_drain notify_karo; then
            return 1
        fi
        return 1
    fi

    if [ "$head" = "$base" ]; then
        printf '%s\n' "publisher: root drain no-op head=$head" >> "$log_path"
        return 0
    fi

    if bash "$queue_script" lock-run --bound "$bound" -- git -C "$repo_root" push origin "$head:refs/heads/main"; then
        printf '%s\n' "publisher: root drain push=1 $base..$head" >> "$log_path"
        return 0
    fi

    local push_rc=$?
    printf '%s\n' "publisher: root drain BLOCK push_failed base=$base head=$head rc=$push_rc" >> "$log_path"
    return "$push_rc"
}

