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
