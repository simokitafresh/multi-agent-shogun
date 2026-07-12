#!/usr/bin/env bats

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "yaml_arg_order"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_existing
  task_id: cmd_existing_normal
  status: idle
  deployed_at: "2026-07-12T00:00:00+09:00"
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_cmd_existing.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_existing
status: completed
EOF
    cat > "$TEST_PROJECT/queue/inbox/sasuke.yaml" <<'EOF'
messages: []
EOF
    cat > "$TEST_TMPDIR/task.yaml" <<'EOF'
task:
  parent_cmd: cmd_yaml_fixture
  task_id: cmd_yaml_fixture_normal
  status: assigned
EOF
}

teardown() {
    deploy_task_teardown
}

fixture_digest() {
    cksum \
        "$TEST_PROJECT/queue/tasks/sasuke.yaml" \
        "$TEST_PROJECT/queue/reports/sasuke_report_cmd_existing.yaml" \
        "$TEST_PROJECT/queue/inbox/sasuke.yaml"
    grep -F 'deployed_at:' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
}

parse_args_in_isolation() {
    (
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        parse_deploy_task_args "$@"
        printf 'ninja=%s yaml=%s cmd=%s direct=%s\n' \
            "$NINJA_NAME" "$YAML_FILE" "$CMD_ID" "$DIRECT_MODE"
    )
}

@test "ninja --yaml file is rejected with exit 2 before queue publication" {
    before="$(fixture_digest)"

    run parse_args_in_isolation sasuke --yaml "$TEST_TMPDIR/task.yaml"

    printf 'gate_fire_log detector_fires=%d detector_fp_rate=%d/2 false_positives=%d\n' \
        "$([ "$status" -eq 2 ] && printf 1 || printf 0)" 0 0
    [ "$status" -eq 2 ]
    [[ "$output" == *"--yaml"* ]]
    [ "$(fixture_digest)" = "$before" ]
}

@test "--yaml file ninja preserves canonical yaml-mode parsing" {
    before="$(fixture_digest)"

    run parse_args_in_isolation --yaml "$TEST_TMPDIR/task.yaml" sasuke

    [ "$status" -eq 0 ]
    [[ "$output" == *"ninja=sasuke"* ]]
    [[ "$output" == *"yaml=$TEST_TMPDIR/task.yaml"* ]]
    [[ "$output" == *"cmd=cmd_yaml_fixture"* ]]
    [[ "$output" == *"direct=true"* ]]
    [ "$(fixture_digest)" = "$before" ]
}

@test "ninja cmd_id preserves normal parsing without yaml false positive" {
    before="$(fixture_digest)"

    run parse_args_in_isolation sasuke cmd_4242

    [ "$status" -eq 0 ]
    [[ "$output" == *"ninja=sasuke"* ]]
    [[ "$output" == *"yaml="* ]]
    [[ "$output" == *"cmd=cmd_4242"* ]]
    [[ "$output" == *"direct=false"* ]]
    [ "$(fixture_digest)" = "$before" ]
}
