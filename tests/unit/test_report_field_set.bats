#!/usr/bin/env bats
# test_necessity: terminal report publication must bind exactly one valid
# run_tests receipt to the same task and commit, or fail closed.
# regression_justification: three consecutive production reports omitted
# test_receipt_path because terminal publication had no automatic receipt join.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    REPORT="$BATS_TEST_TMPDIR/report.yaml"
    TASK="$BATS_TEST_TMPDIR/queue/tasks/kagemaru.yaml"
    RECEIPTS="$BATS_TEST_TMPDIR/receipts"
    INBOX="$BATS_TEST_TMPDIR/inbox_write_stub.sh"
    mkdir -p "$RECEIPTS" "${TASK%/*}"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$INBOX"
    chmod +x "$INBOX"
    cat > "$TASK" <<YAML
task:
  task_id: task_receipt_fixture
  status: in_progress
  related_lessons: []
  test_receipt_path: $RECEIPTS/unique.json
  planned_paths:
    - scripts/report_field_set.sh
    - tests/unit/test_report_field_set.bats
YAML
    cat > "$REPORT" <<'YAML'
worker_id: kagemaru
task_id: task_receipt_fixture
parent_cmd: cmd_fixture
ac_version_read: fixture01
status: pending
verdict: ""
commit_contract: {required: true}
commit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
result: {summary: receipt fixture}
purpose_validation: {fit: true}
files_modified: [{path: scripts/report_field_set.sh, change: fixture}]
lessons_useful: []
lesson_candidate: {found: false, no_lesson_reason: existing receipt contract}
operational_simulation:
  command: fixture
  expected: receipt link
  actual: receipt link
  result: PASS
binary_checks:
  AC1: [{check: receipt, result: yes}]
  AC2: [{check: receipt, result: yes}]
YAML
}

write_receipt() {
    local name="$1" commit="$2" task_id="${3:-}"
    local artifact="$RECEIPTS/${name}.output"
    local receipt="$RECEIPTS/${name}.json"
    printf '1..1\nok 1 receipt-fixture\n' > "$artifact"
    python3 - "$receipt" "$artifact" "$commit" "$task_id" <<'PY'
import hashlib, json, sys
receipt, artifact, commit, task_id = sys.argv[1:]
data = {
    "version": 3, "complete": True, "result": "PASS", "rc": 0,
    "output_sha256": hashlib.sha256(open(artifact, "rb").read()).hexdigest(),
    "artifact": artifact, "skip_count": 0,
    "declared_test_count": 1, "observed_test_count": 1,
    "test_paths": ["tests/unit/test_report_field_set.bats"],
    "commit_sha": commit, "source_head": commit,
}
if task_id:
    data["task_id"] = task_id
data["run_id"] = "fixture-run"
data["source_fingerprint"] = "b" * 64
json.dump(data, open(receipt, "w"), sort_keys=True)
PY
}

publish_terminal() {
    env REPORT_FIELD_SET_TASK_ROOT="$BATS_TEST_TMPDIR" \
        RFS_TASK_FILE_PATH="$TASK" \
        RFS_DISABLE_FAST_RECONCILER=1 RFS_INBOX_WRITE_PATH="$INBOX" \
        bash "$REPO_ROOT/scripts/report_field_set.sh" --batch "$REPORT" <<'YAML'
status: completed
binary_checks.AC1[0].result: yes
binary_checks.AC2[0].result: yes
YAML
}

@test "terminal publication atomically links the unique same-task same-commit receipt" {
    write_receipt unique aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa task_receipt_fixture
    run publish_terminal
    [ "$status" -eq 0 ]
    run python3 - "$REPORT" "$RECEIPTS/unique.json" <<'PY'
import sys, yaml
report, expected = sys.argv[1:]
data = yaml.safe_load(open(report, encoding="utf-8"))
assert data["status"] == "completed"
assert data["test_receipt_path"] == expected
assert data["verdict"] == "PASS"
PY
    [ "$status" -eq 0 ]
}

@test "explicit task receipt path ignores unrelated candidates" {
    write_receipt unique aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa task_receipt_fixture
    write_receipt extra aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa task_receipt_fixture
    run publish_terminal
    [ "$status" -eq 0 ]
    run python3 - "$REPORT" "$RECEIPTS/unique.json" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "completed"
assert data["test_receipt_path"] == sys.argv[2]
PY
    [ "$status" -eq 0 ]
}

@test "missing, stale, mismatched, and corrupt explicit receipts fail closed" {
    for case in missing stale mismatched corrupt; do
        setup
        case "$case" in
            stale)
                sed -i "s|unique.json|stale.json|" "$TASK"
                write_receipt stale bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb task_receipt_fixture
                ;;
            mismatched)
                sed -i "s|unique.json|mismatched.json|" "$TASK"
                write_receipt mismatched aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa other_task
                ;;
            corrupt)
                sed -i "s|unique.json|corrupt.json|" "$TASK"
                write_receipt corrupt aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa task_receipt_fixture
                printf 'tampered\n' >> "$RECEIPTS/corrupt.output"
                ;;
        esac
        run publish_terminal
        [ "$status" -ne 0 ]
        case "$case" in
            missing) [[ "$output" == *"missing or invalid"* ]] ;;
            stale) [[ "$output" == *"stale"* ]] ;;
            mismatched) [[ "$output" == *"task_id mismatch"* ]] ;;
            corrupt) [[ "$output" == *"missing or invalid"* ]] ;;
        esac
        run python3 - "$REPORT" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "pending"
assert "test_receipt_path" not in data
PY
        [ "$status" -eq 0 ]
    done
}
