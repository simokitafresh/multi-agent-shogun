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
call_lines = [
    idx
    for idx, line in enumerate(lines, start=1)
    if line.lstrip().startswith("(set_matching_tasks_idle")
]

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

# cmd_karo_hotfix_task_idle_transition_verify_202607041407: append_codd_registry_entry
# is called bare (no "||" guard) between "GATE CLEAR: cmd完了許可" and
# set_matching_tasks_idle. Under `set -e` (active at the top of cmd_complete_gate.sh),
# an unguarded failing command anywhere in that call chain aborts the whole script
# before set_matching_tasks_idle ever runs, leaving the ninja's task status stuck at
# "done" instead of transitioning to "idle". This test proves the function itself
# never propagates a non-zero exit even when its embedded python3 subprocess raises.
@test "append_codd_registry_entry never propagates failure (would abort GATE CLEAR post-processing under set -e)" {
    eval "$(sed -n '/^append_codd_registry_entry()/,/^}/p' "$SRC_GATE_SCRIPT")"

    lock_path() { echo "$TEST_PROJECT/registry.lock.$$"; }
    SCRIPT_DIR="$TEST_PROJECT"
    CMD_ID="cmd_999"
    YAML_FILE="$TEST_PROJECT/dummy.yaml"
    MATCHING_TASK_FILES=()

    mkdir -p "$TEST_PROJECT/docs/research"
    printf '# registry\n|------|\n' > "$TEST_PROJECT/docs/research/codd_refactor_registry.md"

    # Simulate ANY unhandled exception inside the embedded CoDD registry python
    # body (malformed ledger YAML, unexpected data shape, etc.) by hijacking
    # python3 on PATH to always fail — mirrors the real failure class without
    # needing to reverse-engineer the exact python bug.
    mkdir -p "$TEST_PROJECT/stub_bin"
    cat > "$TEST_PROJECT/stub_bin/python3" <<'PYSTUB'
#!/usr/bin/env bash
echo "Traceback (most recent call last): simulated CoDD registry bug" >&2
exit 1
PYSTUB
    chmod +x "$TEST_PROJECT/stub_bin/python3"
    PATH="$TEST_PROJECT/stub_bin:$PATH" run append_codd_registry_entry "$CMD_ID"

    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN] CoDD registry append failed (non-blocking)"* ]]
}

stub_cmd_complete_side_effects() {
    local stub
    for stub in \
        archive_completed dashboard_auto_section dashboard_update gist_sync ntfy_cmd ntfy \
        gunshi_gate_reflux bulletin_write lesson_impact_rotate lesson_impact_analysis \
        lesson_deprecation_scan rotate_gate_metrics auto_failure_lesson skill_gate_feedback
    do
        printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_PROJECT/scripts/${stub}.sh"
        chmod +x "$TEST_PROJECT/scripts/${stub}.sh"
    done
}

@test "no-task/no-report benchmark fast path still clears" {
    stub_cmd_complete_side_effects
    rm -f "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/"*.done
    : > "$TEST_PROJECT/queue/shogun_to_karo.yaml"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No-task benchmark fast path"* ]]
    [[ "$output" == *"GATE CLEAR: cmd完了許可"* ]]
}

@test "no-task parent report with FAIL verdict blocks instead of benchmark fast path clear" {
    stub_cmd_complete_side_effects
    rm -f "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/"*.done
    : > "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    cat > "$TEST_PROJECT/queue/reports/hanzo_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: hanzo
parent_cmd: $TEST_CMD_ID
status: completed
verdict: FAIL
binary_checks:
  commit:
  - check: git commitが完了したか
    result: no
EOF

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 1 ]
    [[ "$output" != *"No-task benchmark fast path"* ]]
    [[ "$output" == *"No-task parent report validation"* ]]
    [[ "$output" == *"hanzo_report_${TEST_CMD_ID}.yaml: verdict=FAIL"* ]]
    [[ "$output" == *"GATE BLOCK"* ]]
}
