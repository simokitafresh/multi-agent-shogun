#!/usr/bin/env bats
# test_necessity: 同一のCI REDに対する追いpushが上限(既定2回)を超えたら新規配備はBLOCKされ、REDを消すためのtask_type=ci_fixだけは常に通る。

setup() {
    REPO_ROOT="$BATS_TEST_DIRNAME/../.."
    RED='[{"conclusion":"failure","databaseId":1,"headSha":"deadbeefdeadbeef"}]'
    GREEN='[{"conclusion":"success","databaseId":1,"headSha":"deadbeefdeadbeef"}]'
    printf 'task:\n  task_type: hotfix\n' > "$BATS_TEST_TMPDIR/hotfix.yaml"
    printf 'task:\n  task_type: ci_fix\n' > "$BATS_TEST_TMPDIR/ci_fix.yaml"
}

guard() {
    run env "$@" bash -c '
        SCRIPT_DIR="'"$REPO_ROOT"'"
        source "$SCRIPT_DIR/scripts/lib/field_get.sh"
        log() { :; }
        eval "$(sed -n "/^deploy_task_ci_red_followup_push_guard() {/,/^}$/p" "$SCRIPT_DIR/scripts/deploy_task.sh")"
        deploy_task_ci_red_followup_push_guard "$1"
    ' _ "$SOURCE_YAML"
}

@test "CI GREEN never blocks deployment regardless of push count" {
    SOURCE_YAML="$BATS_TEST_TMPDIR/hotfix.yaml"
    guard DEPLOY_TASK_CI_RED_JSON="$GREEN" DEPLOY_TASK_CI_FOLLOWUP_PUSHES=9
    [ "$status" -eq 0 ]
}

@test "CI RED with follow-up pushes at the limit still allows deployment" {
    SOURCE_YAML="$BATS_TEST_TMPDIR/hotfix.yaml"
    guard DEPLOY_TASK_CI_RED_JSON="$RED" DEPLOY_TASK_CI_FOLLOWUP_PUSHES=2
    [ "$status" -eq 0 ]
}

@test "CI RED beyond the follow-up push limit blocks new deployment" {
    SOURCE_YAML="$BATS_TEST_TMPDIR/hotfix.yaml"
    guard DEPLOY_TASK_CI_RED_JSON="$RED" DEPLOY_TASK_CI_FOLLOWUP_PUSHES=3
    [ "$status" -eq 1 ]
    [[ "$output" == *"追いpushが3回"* ]]
}

@test "ci_fix deployment is always allowed so RED can be repaired" {
    SOURCE_YAML="$BATS_TEST_TMPDIR/ci_fix.yaml"
    guard DEPLOY_TASK_CI_RED_JSON="$RED" DEPLOY_TASK_CI_FOLLOWUP_PUSHES=9
    [ "$status" -eq 0 ]
}
