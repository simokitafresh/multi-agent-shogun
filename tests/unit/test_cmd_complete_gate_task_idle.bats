#!/usr/bin/env bats

load '../helpers/cmd_gate_scaffold'

setup_file() {
    cmd_gate_setup_file
}

setup() {
    cmd_gate_scaffold "cmd_gate_idle"
    export SCRIPT_DIR="$TEST_PROJECT"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"

    source "$TEST_PROJECT/scripts/lib/field_get.sh"
    source "$TEST_PROJECT/scripts/lib/yaml_field_set.sh"
    eval "$(sed -n '/^set_matching_tasks_idle()/,/^}/p' "$TEST_PROJECT/scripts/cmd_complete_gate.sh")"
}

teardown() {
    cmd_gate_teardown
}

write_nested_task() {
    local ninja_name="$1"
    local status="${2:-done}"
    cat > "$TEST_PROJECT/queue/tasks/${ninja_name}.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  assigned_to: $ninja_name
  task_id: ${ninja_name}_task
  status: $status
EOF
}

@test "set_matching_tasks_idle transitions matching nested task YAMLs to idle" {
    write_nested_task "hayate" "done"
    write_nested_task "sasuke" "acknowledged"
    MATCHING_TASK_FILES=(
        "$TEST_PROJECT/queue/tasks/hayate.yaml"
        "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    )

    run set_matching_tasks_idle
    [ "$status" -eq 0 ]
    [[ "$output" == *"hayate: done → idle"* ]]
    [[ "$output" == *"sasuke: acknowledged → idle"* ]]
    [[ "$output" == *"summary: updated=2 skipped=0 warn=0"* ]]

    run grep -n "^  status: idle$" "$TEST_PROJECT/queue/tasks/hayate.yaml"
    [ "$status" -eq 0 ]
    run grep -n "^  status: idle$" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
}

@test "set_matching_tasks_idle handles flat task YAML" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<EOF
parent_cmd: $TEST_CMD_ID
assigned_to: hayate
task_id: hayate_task
status: done
EOF
    MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/hayate.yaml")

    run set_matching_tasks_idle
    [ "$status" -eq 0 ]
    [[ "$output" == *"hayate: done → idle"* ]]
    [[ "$output" == *"summary: updated=1 skipped=0 warn=0"* ]]

    run grep -n "^status: idle$" "$TEST_PROJECT/queue/tasks/hayate.yaml"
    [ "$status" -eq 0 ]
}

@test "set_matching_tasks_idle skips disappeared snapshot task YAML with WARN" {
    write_nested_task "hayate" "done"
    MATCHING_TASK_FILES=(
        "$TEST_PROJECT/queue/tasks/hayate.yaml"
        "$TEST_PROJECT/queue/tasks/missing.yaml"
    )
    MATCHING_TASK_FILES_PROCESSED_COUNT=0
    MATCHING_TASK_FILES_SKIPPED_COUNT=0

    run set_matching_tasks_idle
    [ "$status" -eq 0 ]
    [[ "$output" == *"hayate: done → idle"* ]]
    [[ "$output" == *"[WARN] matching task file disappeared, skipping: $TEST_PROJECT/queue/tasks/missing.yaml"* ]]
    [[ "$output" == *"summary: updated=1 skipped=0 warn=0"* ]]
}

@test "cmd_complete_gate logs matching task snapshot and final processing summary" {
    run grep -n "Matching task files snapshot:" "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
    run grep -n "Matching task files summary: snapshot=" "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
    run grep -n "skipped_missing=" "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
}

@test "cmd_complete_gate wires task idle transition only in GATE CLEAR branch" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
from pathlib import Path

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
call_lines = [idx for idx, line in enumerate(lines, start=1) if line.strip() == "set_matching_tasks_idle"]

if len(call_lines) != 1:
    raise SystemExit(f"expected single set_matching_tasks_idle call, got {len(call_lines)}")

archive_lines = [idx for idx, line in enumerate(lines, start=1) if "Archive (post-GATE CLEAR):" in line]
git_push_lines = [idx for idx, line in enumerate(lines, start=1) if "Git push (post-GATE CLEAR):" in line]

if not archive_lines or not git_push_lines:
    raise SystemExit("missing post-GATE CLEAR markers")

call_line = call_lines[0]
if not (archive_lines[-1] < call_line < git_push_lines[-1]):
    raise SystemExit(
        f"set_matching_tasks_idle call not between archive and git push: "
        f"archive={archive_lines[-1]} call={call_line} git_push={git_push_lines[-1]}"
    )
PY
    [ "$status" -eq 0 ]
}
