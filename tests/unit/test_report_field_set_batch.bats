# test_necessity: required-commit reports may omit commit identity only for the exact failed/FAIL/commit=no terminal lane; every success or contradictory lane remains blocked.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    REPORT="$BATS_TEST_TMPDIR/report.yaml"
    TASK_STUB="$BATS_TEST_TMPDIR/task.yaml"
    INBOX_STUB="$BATS_TEST_TMPDIR/inbox_write_stub.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$INBOX_STUB"
    printf '%s\n' 'task:' '  status: in_progress' > "$TASK_STUB"
    chmod +x "$INBOX_STUB"
}

write_report() {
    local status="$1" ac_result="$2" commit_result="$3" required="$4"
    cat > "$REPORT" <<YAML
worker_id: saizo
parent_cmd: cmd_fixture
ac_version_read: fixture01
status: pending
verdict: ""
commit_contract: {required: ${required}}
result: {summary: fixture}
purpose_validation: {fit: true}
files_modified: [{path: scripts/report_field_set.sh, change: fixture}]
lessons_useful: [{id: L1490, useful: true, reason: fixture contract}]
lesson_candidate: {found: false, no_lesson_reason: existing contract}
binary_checks:
  AC1: [{check: fixture, result: ${ac_result}}]
  commit: [{check: commit, result: ${commit_result}}]
YAML
    cat > "$BATS_TEST_TMPDIR/payload.yaml" <<YAML
status: ${status}
binary_checks.AC1[0].result: ${ac_result}
binary_checks.commit[0].result: ${commit_result}
YAML
}

# write_live_task/write_lesson_report build the fixture pair for the
# terminal-readiness lesson-empty-allowed boundary: a live worker task file
# (independent of the report's own identity) and a report that may or may not
# carry an immutable task_contract_snapshot lesson_set. Neither fixture sets
# task_id: _autolink_terminal_test_receipt keys its own (unrelated) receipt
# check off task_id and would otherwise BLOCK before the lesson logic runs;
# identity for this boundary is driven by parent_cmd alone, which is all
# _report_identity_matches_task/_snapshot_lesson_contract need to disagree.
write_live_task() {
    local parent_cmd="$1" related_lessons_yaml="$2"
    cat > "$LIVE_TASK" <<YAML
task:
  parent_cmd: ${parent_cmd}
  related_lessons: ${related_lessons_yaml}
YAML
}

write_lesson_report() {
    local parent_cmd="$1" snapshot_yaml="$2"
    cat > "$REPORT" <<YAML
worker_id: saizo
parent_cmd: ${parent_cmd}
ac_version_read: fixture01
status: pending
verdict: ""
commit_contract: {required: false}
commit_hash: '1111111111111111111111111111111111111111'
result: {summary: fixture}
purpose_validation: {fit: true}
files_modified: [{path: scripts/report_field_set.sh, change: fixture}]
lessons_useful: []
lesson_candidate: {found: false, no_lesson_reason: existing contract}
binary_checks:
  AC1: [{check: fixture, result: 'yes'}]
  commit: [{check: commit, result: 'yes'}]
${snapshot_yaml}
YAML
    cat > "$BATS_TEST_TMPDIR/payload.yaml" <<'YAML'
status: completed
YAML
}

run_lesson_batch() {
    run env RFS_DISABLE_FAST_RECONCILER=1 RFS_INBOX_WRITE_PATH="$INBOX_STUB" RFS_TASK_FILE_PATH="$LIVE_TASK" \
        bash "$REPO_ROOT/scripts/report_field_set.sh" --batch "$REPORT" < "$BATS_TEST_TMPDIR/payload.yaml"
}

# test_necessity: an empty deploy-time lesson snapshot must keep authorizing
# an empty lessons_useful even after the live task file is overwritten by a
# later, lesson-bearing deployment for the same worker (worker lease reuse).
@test "empty lesson snapshot allows empty lessons_useful despite a lesson-bearing live task" {
    LIVE_TASK="$BATS_TEST_TMPDIR/live_task.yaml"
    write_live_task cmd_new '[{id: L097}, {id: L019}]'
    write_lesson_report cmd_old \
        'task_contract_snapshot: {parent_cmd: cmd_old, lesson_set: {mode: subset, ids: []}}'
    run_lesson_batch
    [ "$status" -eq 0 ]
    run python3 - "$REPORT" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
assert d["status"] == "completed", d["status"]
PY
    [ "$status" -eq 0 ]
}

# test_necessity: a non-empty deploy-time lesson snapshot must keep requiring
# lesson feedback even after the live task file is overwritten by a later
# deployment with no lessons at all (worker lease reuse must not silently
# excuse the original report from reporting on its own snapshot).
@test "non-empty lesson snapshot blocks empty lessons_useful despite an empty live task" {
    LIVE_TASK="$BATS_TEST_TMPDIR/live_task.yaml"
    write_live_task cmd_new '[]'
    write_lesson_report cmd_old \
        'task_contract_snapshot: {parent_cmd: cmd_old, lesson_set: {mode: subset, ids: [L097, L019]}}'
    run_lesson_batch
    [ "$status" -ne 0 ]
    [[ "$output" == *"terminal readiness missing"* ]]
    [[ "$output" == *"lessons_useful"* ]]
}

# test_necessity: a structurally malformed snapshot must fail closed (block)
# rather than silently falling back to an empty allowlist.
@test "malformed lesson snapshot fails closed and blocks empty lessons_useful" {
    LIVE_TASK="$BATS_TEST_TMPDIR/live_task.yaml"
    write_live_task cmd_new '[]'
    write_lesson_report cmd_old \
        'task_contract_snapshot: {parent_cmd: cmd_old, lesson_set: {mode: bogus, ids: [L097]}}'
    run_lesson_batch
    [ "$status" -ne 0 ]
    [[ "$output" == *"snapshot-invalid"* ]]
}

# test_necessity: a legacy report (no snapshot) whose identity no longer
# matches the live task must fail closed rather than borrowing whatever the
# unrelated replacement task currently declares.
@test "identity mismatch without a snapshot fails closed and blocks empty lessons_useful" {
    LIVE_TASK="$BATS_TEST_TMPDIR/live_task.yaml"
    write_live_task cmd_new '[]'
    write_lesson_report cmd_old ''
    run_lesson_batch
    [ "$status" -ne 0 ]
    [[ "$output" == *"terminal readiness missing"* ]]
    [[ "$output" == *"lessons_useful"* ]]
}

# test_necessity: legacy same-identity behavior must not regress — an empty
# related_lessons on the still-matching live task keeps excusing an empty
# lessons_useful when the report carries no snapshot at all.
@test "legacy report without snapshot still allows empty lessons_useful when live task identity matches" {
    LIVE_TASK="$BATS_TEST_TMPDIR/live_task.yaml"
    write_live_task cmd_fixture '[]'
    write_lesson_report cmd_fixture ''
    run_lesson_batch
    [ "$status" -eq 0 ]
    run python3 - "$REPORT" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
assert d["status"] == "completed", d["status"]
PY
    [ "$status" -eq 0 ]
}

@test "truthful failed report is terminal while three commit-absence contradictions are blocked" {
    write_report failed no no true
    run env RFS_DISABLE_FAST_RECONCILER=1 RFS_INBOX_WRITE_PATH="$INBOX_STUB" RFS_TASK_FILE_PATH="$TASK_STUB" bash "$REPO_ROOT/scripts/report_field_set.sh" --batch "$REPORT" < "$BATS_TEST_TMPDIR/payload.yaml"
    [ "$status" -eq 0 ]
    run python3 - "$REPORT" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
assert d["status"] == "failed" and d["verdict"] == "FAIL" and "commit_hash" not in d
PY
    [ "$status" -eq 0 ]

    for tuple in "completed yes yes true" "failed no yes true" "failed no no false"; do
        set -- $tuple
        write_report "$1" "$2" "$3" "$4"
        run env RFS_DISABLE_FAST_RECONCILER=1 RFS_INBOX_WRITE_PATH="$INBOX_STUB" RFS_TASK_FILE_PATH="$TASK_STUB" bash "$REPO_ROOT/scripts/report_field_set.sh" --batch "$REPORT" < "$BATS_TEST_TMPDIR/payload.yaml"
        [ "$status" -ne 0 ]
        [[ "$output" == *"terminal readiness requires"* ]]
    done

    run python3 - "$REPO_ROOT/scripts/gates/gate_report_format.sh" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
assert 'required(report) and required(task)' in text
assert 'snapshot_acs' in text and 'snapshot_covers_report' in text
assert 'commit_contract: required commit_hash is missing or invalid' in text
print('negative_guards=3 snapshot_ssot=1')
PY
    [ "$status" -eq 0 ]
    [ "$output" = "negative_guards=3 snapshot_ssot=1" ]
}
