#!/usr/bin/env bats
# test_necessity: deploy_taskのdelivery後まで続くbash processは、並行編集されるworking-tree原本ではなく構文検証済みimmutable self-snapshotだけをparseし続けなければならない。

setup() {
    PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    WORK_DIR="$(mktemp -d "$BATS_TMPDIR/deploy-self-snapshot.XXXXXX")"
    mkdir -p "$WORK_DIR/scripts" "$WORK_DIR/hold"
    cp "$PROJECT_ROOT/scripts/deploy_task.sh" "$WORK_DIR/scripts/deploy_task.sh"
}

teardown() {
    rm -rf "$WORK_DIR"
}

@test "running deploy parses immutable snapshot when working-tree source changes mid-process" {
    run bash -c '
        set -euo pipefail
        fixture="$1"
        root="$2"
        hold="$3"
        out="$4"
        err="$5"

        DEPLOY_TASK_ROOT_OVERRIDE="$root" \
        DEPLOY_TASK_SELF_SNAPSHOT_TEST_ONLY=1 \
        DEPLOY_TASK_SELF_SNAPSHOT_TEST_HOLD_DIR="$hold" \
            bash "$fixture" >"$out" 2>"$err" &
        child=$!

        for _ in $(seq 1 500); do
            [ -e "$hold/ready" ] && break
            sleep 0.01
        done
        [ -e "$hold/ready" ]

        # This deliberately makes the original path unparsable while the
        # already-running deployment is paused near the start of its snapshot.
        printf "if then impossible\n" > "$fixture"
        touch "$hold/release"
        wait "$child"
        grep -qx SELF_SNAPSHOT_OK "$out"
        [ ! -s "$err" ]
    ' _ "$WORK_DIR/scripts/deploy_task.sh" "$PROJECT_ROOT" "$WORK_DIR/hold" \
        "$WORK_DIR/out" "$WORK_DIR/err"

    [ "$status" -eq 0 ]
}

@test "invalid source snapshot fails closed before deployment" {
    printf 'if then invalid\n' > "$WORK_DIR/scripts/deploy_task.sh"

    run env DEPLOY_TASK_ROOT_OVERRIDE="$PROJECT_ROOT" \
        bash "$WORK_DIR/scripts/deploy_task.sh"

    [ "$status" -ne 0 ]
}
