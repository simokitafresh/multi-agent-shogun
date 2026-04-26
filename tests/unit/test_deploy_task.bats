#!/usr/bin/env bats
# test_deploy_task.bats — deploy_task.sh --yaml モード鮮度チェックのユニットテスト
# AC1: スクリプトがYAML作成後にcommit → WARN表示
# AC2: スクリプトがYAML作成前にcommit → WARN非表示

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_yaml_freshness"

    export TEST_GIT_ROOT
    TEST_GIT_ROOT="$(mktemp -d "$BATS_TMPDIR/test_git_root.XXXXXX")"
    git -C "$TEST_GIT_ROOT" init --quiet
    git -C "$TEST_GIT_ROOT" config user.name "Test User"
    git -C "$TEST_GIT_ROOT" config user.email "test@example.com"
    mkdir -p "$TEST_GIT_ROOT/scripts"
}

teardown() {
    deploy_task_teardown
    [ -n "${TEST_GIT_ROOT:-}" ] && [ -d "$TEST_GIT_ROOT" ] && rm -rf "$TEST_GIT_ROOT"
}

run_yaml_freshness_check() {
    local yaml_file="$1"
    local git_root="$2"
    (
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        check_yaml_freshness "$yaml_file" "$git_root"
    ) 2>&1
}

make_script_commit() {
    local rel_path="$1"
    local commit_date="$2"

    mkdir -p "$TEST_GIT_ROOT/$(dirname "$rel_path")"
    printf '#!/usr/bin/env bash\n# test script\n' > "$TEST_GIT_ROOT/$rel_path"
    git -C "$TEST_GIT_ROOT" add "$rel_path"
    GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" \
        git -C "$TEST_GIT_ROOT" commit --quiet -m "cmd_test update script"
}

@test "スクリプトがYAML作成後にcommitされていた場合WARNが出力される" {
    local recent_date
    recent_date="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    make_script_commit "scripts/my_tool.sh" "$recent_date"

    local yaml_file="$TEST_GIT_ROOT/test_task.yaml"
    cat > "$yaml_file" <<'EOF'
task:
  command: "bash scripts/my_tool.sh を実行せよ"
  task_id: cmd_test_impl
EOF
    touch -d "2 hours ago" "$yaml_file"

    run run_yaml_freshness_check "$yaml_file" "$TEST_GIT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DEPLOY] WARN:"* ]]
    [[ "$output" == *"scripts/my_tool.sh"* ]]
    [[ "$output" == *"task YAMLを再作成せよ"* ]]
}

@test "スクリプトがYAML作成前にcommitされていた場合WARNは出力されない" {
    local old_date
    old_date="$(date -u -d '2 hours ago' '+%Y-%m-%dT%H:%M:%SZ')"
    make_script_commit "scripts/my_tool.sh" "$old_date"

    local yaml_file="$TEST_GIT_ROOT/test_task.yaml"
    cat > "$yaml_file" <<'EOF'
task:
  command: "bash scripts/my_tool.sh を実行せよ"
  task_id: cmd_test_impl
EOF

    run run_yaml_freshness_check "$yaml_file" "$TEST_GIT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" != *"[DEPLOY] WARN:"* ]]
}
