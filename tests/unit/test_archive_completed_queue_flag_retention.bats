#!/usr/bin/env bats
# contract test: queue flag retention
# test_necessity: 稼働中cmd(archive.doneなし/稼働参照あり/reopen中/lock保持中)のqueue配下flagを
#                 retention回収が1件も移動・削除しないこと。この不変量が破れると稼働中cmdの
#                 配備・GATE状態が失われ、復旧不能な配備事故になる。
# origin: [[cmd_karo_hotfix_queue_flag_retention_20260725]] -> [[保持期限なきsentinel累積]] -> [[queue全走査コスト]]

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIX="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$FIX/queue/gates" "$FIX/queue/dispatch_ntfy_started" \
             "$FIX/queue/draft_review_started" "$FIX/queue/locks" \
             "$FIX/queue/reopened_cmds" "$FIX/queue/tasks" "$FIX/queue/reports" \
             "$FIX/logs" "$FIX/archive"
    : > "$FIX/queue/shogun_to_karo.yaml"

    OLD_TS="202601010000"   # 保持期限を大きく超過

    # (a) 完了済み・参照なし → 回収対象
    mkdir -p "$FIX/queue/gates/cmd_done_old"
    touch "$FIX/queue/gates/cmd_done_old/lesson.done" "$FIX/queue/gates/cmd_done_old/archive.done"
    touch "$FIX/queue/dispatch_ntfy_started/cmd_done_old.started"
    touch "$FIX/queue/draft_review_started/cmd_done_old.draft_review.started"
    touch "$FIX/queue/locks/deploy_cmd_done_old.lock"
    touch -t "$OLD_TS" "$FIX/queue/gates/cmd_done_old/archive.done"

    # (b) 稼働中: archive.doneなし
    mkdir -p "$FIX/queue/gates/cmd_active_running"
    touch "$FIX/queue/gates/cmd_active_running/lesson.done"
    touch -t "$OLD_TS" "$FIX/queue/gates/cmd_active_running/lesson.done"

    # (c) 完了済みだが稼働参照あり(task YAMLが参照)
    mkdir -p "$FIX/queue/gates/cmd_referenced"
    touch "$FIX/queue/gates/cmd_referenced/archive.done"
    touch -t "$OLD_TS" "$FIX/queue/gates/cmd_referenced/archive.done"
    echo "parent_cmd: cmd_referenced" > "$FIX/queue/tasks/hayate.yaml"

    # (d) reopen中
    mkdir -p "$FIX/queue/gates/cmd_reopened"
    touch "$FIX/queue/gates/cmd_reopened/archive.done"
    touch -t "$OLD_TS" "$FIX/queue/gates/cmd_reopened/archive.done"
    : > "$FIX/queue/reopened_cmds/cmd_reopened.yaml"

    # (e) 完了済みだが保持期限内(新しい)
    mkdir -p "$FIX/queue/gates/cmd_done_recent"
    touch "$FIX/queue/gates/cmd_done_recent/archive.done"

    run_retention() {
        ARCHIVE_COMPLETED_PROJECT_DIR="$FIX" \
        QUEUE_FLAG_RETENTION_LIB_ONLY=1 \
        QUEUE_FLAG_RETENTION_MODE="${1:-quarantine}" \
        QUEUE_FLAG_RETENTION_DAYS=30 \
        QUEUE_FLAG_RETENTION_INTERVAL_SEC=0 \
        QUEUE_FLAG_QUARANTINE_DIR="$FIX/archive/quarantine" \
        QUEUE_FLAG_RETENTION_REPORT="$FIX/logs/cand.tsv" \
        REPO="$REPO_ROOT" \
        bash -c '
            set -euo pipefail
            TMP=$(mktemp -d)
            trap "rm -rf $TMP" EXIT
            set --
            source "$REPO/scripts/archive_completed.sh"
            TMP=$TMP prune_queue_flag_retention
        '
    }
}

@test "完了済み・無参照のflagはquarantineへ移動される" {
    run run_retention quarantine
    [ "$status" -eq 0 ]
    [ ! -d "$FIX/queue/gates/cmd_done_old" ]
    [ ! -f "$FIX/queue/dispatch_ntfy_started/cmd_done_old.started" ]
    [ ! -f "$FIX/queue/draft_review_started/cmd_done_old.draft_review.started" ]
    [ ! -f "$FIX/queue/locks/deploy_cmd_done_old.lock" ]
    [ -n "$(find "$FIX/archive/quarantine" -name 'archive.done' -print -quit)" ]
}

@test "稼働中cmdのflagは1件も動かない" {
    run run_retention quarantine
    [ "$status" -eq 0 ]
    [ -f "$FIX/queue/gates/cmd_active_running/lesson.done" ]
    [ -f "$FIX/queue/gates/cmd_referenced/archive.done" ]
    [ -f "$FIX/queue/gates/cmd_reopened/archive.done" ]
    [ -f "$FIX/queue/gates/cmd_done_recent/archive.done" ]
}

@test "dry-runは候補一覧を出力するが何も移動しない" {
    run run_retention dry-run
    [ "$status" -eq 0 ]
    [ -d "$FIX/queue/gates/cmd_done_old" ]
    [ -f "$FIX/queue/locks/deploy_cmd_done_old.lock" ]
    grep -q "cmd_done_old" "$FIX/logs/cand.tsv"
    ! grep -q "cmd_active_running" "$FIX/logs/cand.tsv"
    ! grep -q "cmd_reopened" "$FIX/logs/cand.tsv"
}

@test "保持中のlockは回収されない" {
    exec {lockfd}>>"$FIX/queue/locks/deploy_cmd_done_old.lock"
    flock -n "$lockfd"
    run run_retention quarantine
    exec {lockfd}>&-
    [ "$status" -eq 0 ]
    [ -f "$FIX/queue/locks/deploy_cmd_done_old.lock" ]
}
