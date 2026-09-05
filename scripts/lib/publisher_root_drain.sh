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
    # 2026-09-05 将軍 D0(殿 19:02『未コミットをゼロに』/19:09『ledger hotfix を将軍が』):
    # root には常時 append される runtime 台帳(lessons*.yaml / cmd-chronicle / karo_workarounds /
    # x_live_oos / session_alerts / insights / bulletin / semantic index / review_log)が dirty で
    # 残り、drain が『tracked_dirty』で永久 BLOCK していた(本日 6 万行超の BLOCK 行、root 収束 2.5h 停止)。
    # これらは ledger publisher または各 lane が別経路で origin へ出す runtime data であり、
    # root の commit を push する drain の安全性(commit 内容)とは無関係。drain の dirty 判定から
    # 除外し、除外した path は ignored_dirty として log に残す。除外集合は
    # PUBLISHER_ROOT_DRAIN_DIRTY_IGNORE(ERE)で上書き可。source/config/docs の dirty は従来どおり BLOCK。
    local dirty_ignore_re="${PUBLISHER_ROOT_DRAIN_DIRTY_IGNORE:-^(projects/[^/]+/lessons[^/]*\.yaml|projects/infra/lessons_[^/]+\.yaml|context/cmd-chronicle\.md|logs/karo_workarounds\.yaml|logs/gunshi_review_log\.yaml|queue/x_live_oos/.*|queue/session_alerts_[^/]+\.txt|queue/insights\.yaml|queue/bulletin_board\.yaml|docs/semantic-index/index\.md|tasks/lessons\.md)$}"
    local dirty_paths ignored_paths
    dirty_paths="$(git -C "$repo_root" status --porcelain=v1 -uno 2>/dev/null | sed 's/^.. //' | sort -u | { grep -Ev -- "$dirty_ignore_re" || true; } | paste -sd, -)"
    ignored_paths="$(git -C "$repo_root" status --porcelain=v1 -uno 2>/dev/null | sed 's/^.. //' | sort -u | { grep -E -- "$dirty_ignore_re" || true; } | paste -sd, -)"
    if [ -n "$dirty_paths" ]; then
        printf '%s\n' "publisher: root drain BLOCK tracked_dirty_paths=$dirty_paths ignored_dirty=${ignored_paths:-none}" >> "$log_path"
        return 32
    fi
    [ -z "$ignored_paths" ] || printf '%s\n' "publisher: root drain ignored_dirty=$ignored_paths" >> "$log_path"
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
