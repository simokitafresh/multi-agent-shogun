#!/usr/bin/env bats

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_recent_noncmd_warn"

    git -C "$TEST_PROJECT" init --quiet
    git -C "$TEST_PROJECT" config user.name "Test User"
    git -C "$TEST_PROJECT" config user.email "test@example.com"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "recent noncmd commit warn test"
  task_type: impl
  parent_cmd: cmd_karo_gp110_deploy_warn
  task_id: cmd_karo_gp110_deploy_warn_impl
  project: infra
  target_path: "scripts/target.sh"
  acceptance_criteria:
    - id: AC1
      description: "warn behavior"
EOF
}

teardown() {
    deploy_task_teardown
}

run_recent_commit_warn() {
    (
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        warn_recent_noncmd_commit_targets "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    ) 2>&1
}

make_commit() {
    local rel_path="$1"
    local message="$2"
    local commit_date="$3"

    mkdir -p "$TEST_PROJECT/$(dirname "$rel_path")"
    printf '%s\n' "$message" > "$TEST_PROJECT/$rel_path"
    git -C "$TEST_PROJECT" add "$rel_path"
    GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" \
        git -C "$TEST_PROJECT" commit --quiet -m "$message"
}

@test "軍師/家老の自走commit(cmd_を含まないmessage+24h以内)があるファイルを含むcmd配備でWARN出力される" {
    local recent_date
    recent_date="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    make_commit "scripts/target.sh" "refactor deploy warning check" "$recent_date"

    run run_recent_commit_warn
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: target_path=scripts/target.sh"* ]]
    [[ "$output" == *"refactor deploy warning check"* ]]
}

@test "忍者のcmd commit(messageにcmd_XXXXを含む)があるファイルではWARN出力されない" {
    local recent_date
    recent_date="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    make_commit "scripts/target.sh" "cmd_1891 adjust deploy behavior" "$recent_date"

    run run_recent_commit_warn
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING: target_path=scripts/target.sh"* ]]
}

@test "24h以上前のcommitではWARN出力されない" {
    local old_date
    old_date="$(date -u -d '2 days ago' '+%Y-%m-%dT%H:%M:%SZ')"
    make_commit "scripts/target.sh" "refactor deploy warning check" "$old_date"

    run run_recent_commit_warn
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING: target_path=scripts/target.sh"* ]]
}
