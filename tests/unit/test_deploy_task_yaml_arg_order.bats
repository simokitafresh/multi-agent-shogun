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
        printf 'ninja=%s yaml=%s cmd=%s direct=%s message=%s type=%s from=%s\n' \
            "$NINJA_NAME" "$YAML_FILE" "$CMD_ID" "$DIRECT_MODE" "$MESSAGE" "$TYPE" "$FROM"
    )
}

write_legacy_failed_task() {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_old_failed
  cmd_id: cmd_old_failed
  task_id: cmd_old_failed_impl
  task_type: impl
  status: failed
  command: "旧failed taskを再実行してはならない"
  legacy_marker: preserve-me
  acceptance_criteria:
    AC1:
      description: "旧ACも再注入してはならない"
EOF
}

run_legacy_status_control() {
    local control_status="$1"
    run bash -c '
        set -euo pipefail
        project="$1"
        control_status="$2"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$project/scripts/deploy_task.sh"
        log() { :; }
        resolve_pane() { echo "test-pane"; }
        get_ctx_pct() { echo 0; }
        check_idle() { return 0; }
        normalize_task_yaml() { echo "unexpected normalization" >&2; return 91; }
        repair_training_parent_cmd_from_cmd_id() { echo "unexpected repair" >&2; return 92; }
        deploy_task_guard_target_path_collision() { echo "unexpected collision check" >&2; return 93; }
        deploy_task_apply_task_mutations() { echo "unexpected task injection" >&2; return 94; }
        bash() {
            if [[ "${1:-}" == */inbox_write.sh ]]; then
                printf "%s|%s|%s|%s|%s\n" "$2" "$3" "$4" "$5" "$6" > "$project/status_notice.log"
                return 0
            fi
            command bash "$@"
        }
        deploy_task_main sasuke status "$control_status" karo
    ' _ "$TEST_PROJECT" "$control_status"
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

@test "legacy status controls preserve message and bypass task deployment for all lifecycle states" {
    local control_status

    for control_status in idle done in_progress; do
        write_legacy_failed_task

        run parse_args_in_isolation sasuke status "$control_status" karo
        [ "$status" -eq 0 ]
        [[ "$output" == *"cmd= direct=false message=status type=$control_status from=karo"* ]]
        [[ "$output" != *"タスクYAML:"* ]]

        run_legacy_status_control "$control_status"
        [ "$status" -eq 0 ]
        [[ "$output" != *"unexpected"* ]]

        run python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" "$control_status" <<'PY'
import sys
import yaml

task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
assert task == {
    "parent_cmd": "cmd_old_failed",
    "cmd_id": "cmd_old_failed",
    "task_id": "cmd_old_failed_impl",
    "task_type": "impl",
    "status": sys.argv[2],
    "command": "旧failed taskを再実行してはならない",
    "legacy_marker": "preserve-me",
    "acceptance_criteria": {
        "AC1": {"description": "旧ACも再注入してはならない"},
    },
}
PY
        [ "$status" -eq 0 ]

        run cat "$TEST_PROJECT/status_notice.log"
        [ "$status" -eq 0 ]
        [ "$output" = "sasuke|status|$control_status|karo|status_update" ]
    done
}
