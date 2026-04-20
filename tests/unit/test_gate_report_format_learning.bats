#!/usr/bin/env bats
# test_gate_report_format_learning.bats
# cmd_2161: gate_report_format BLOCK学習ループ

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_report_format.sh"
    export GATE_MAIN_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_report_format_main.py"
    [ -f "$GATE_SCRIPT" ] || return 1
    [ -f "$GATE_MAIN_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$PROJECT_ROOT/.tmp_grfl.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/queue/reports" \
             "$TEST_TMPDIR/queue/tasks" \
             "$TEST_TMPDIR/logs"
    cp "$GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
    cp "$GATE_MAIN_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_report_format_main.py"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_combined.py" "$TEST_TMPDIR/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_autofix_main.py" "$TEST_TMPDIR/scripts/gates/"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
    export LEARNING_FILE="$TEST_TMPDIR/logs/gate_report_format_learning.yaml"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

_write_fail_report() {
    local ninja_name="$1"
    local report_path="$TEST_TMPDIR/queue/reports/${ninja_name}_report_cmd_2161.yaml"
    cat > "$report_path" <<EOF
worker_id: $ninja_name
parent_cmd: cmd_2161
ac_version_read: test_hash
status: completed
result:
  summary: "テスト"
  details: "詳細"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified:
  - scripts/gates/gate_report_format.sh
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンの再現"
  title: ""
  detail: ""
lessons_useful:
  - id: L001
    useful: true
    reason: ""
binary_checks:
  AC1:
    - check: "学習ループ確認"
      result: ""
verdict: FAIL
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
EOF
    printf '%s\n' "$report_path"
}

@test "cmd_2161: same BLOCK pattern counts accumulate across ninjas" {
    local report1 report2
    report1="$(_write_fail_report hayate)"
    report2="$(_write_fail_report saizo)"

    run env \
        GATE_REPORT_FORMAT_LEARNING_FILE="$LEARNING_FILE" \
        GATE_REPORT_FORMAT_PREFILL_THRESHOLD=3 \
        bash "$TEST_GATE" "$report1"
    [ "$status" -eq 1 ]

    run env \
        GATE_REPORT_FORMAT_LEARNING_FILE="$LEARNING_FILE" \
        GATE_REPORT_FORMAT_PREFILL_THRESHOLD=3 \
        bash "$TEST_GATE" "$report2"
    [ "$status" -eq 1 ]

    run python3 - <<EOF
import yaml
from pathlib import Path

data = yaml.safe_load(Path("$LEARNING_FILE").read_text(encoding="utf-8"))
patterns = data["patterns"]
assert patterns["bc_result_empty"]["count"] == 2
assert patterns["lu_reason_empty"]["count"] == 2
assert patterns["bc_result_empty"]["prefill_active"] is False
assert patterns["lu_reason_empty"]["prefill_active"] is False
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "cmd_2161: prefill activates when threshold is reached" {
    local report1 report2
    report1="$(_write_fail_report hayate)"
    report2="$(_write_fail_report kagemaru)"

    run env \
        GATE_REPORT_FORMAT_LEARNING_FILE="$LEARNING_FILE" \
        GATE_REPORT_FORMAT_PREFILL_THRESHOLD=2 \
        bash "$TEST_GATE" "$report1"
    [ "$status" -eq 1 ]

    run env \
        GATE_REPORT_FORMAT_LEARNING_FILE="$LEARNING_FILE" \
        GATE_REPORT_FORMAT_PREFILL_THRESHOLD=2 \
        bash "$TEST_GATE" "$report2"
    [ "$status" -eq 1 ]

    run python3 - <<EOF
import yaml
from pathlib import Path

data = yaml.safe_load(Path("$LEARNING_FILE").read_text(encoding="utf-8"))
patterns = data["patterns"]
assert data["threshold"] == 2
assert patterns["bc_result_empty"]["count"] == 2
assert patterns["bc_result_empty"]["prefill_active"] is True
assert patterns["lu_reason_empty"]["count"] == 2
assert patterns["lu_reason_empty"]["prefill_active"] is True
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "cmd_2164: learning records generic pattern names and prefill metadata" {
    local report_path="$TEST_TMPDIR/queue/reports/hayate_report_cmd_2164.yaml"
    cat > "$report_path" <<'EOF'
worker_id: hayate
parent_cmd: cmd_2164
status: completed
result:
  summary: ""
  details: "詳細"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンの再現"
  title: ""
  detail: ""
lessons_useful:
  - id: L001
    useful: true
    reason: ""
binary_checks:
  AC1:
    - check: "学習ループ確認"
      result: ""
verdict: FAIL
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
EOF

    run env \
        GATE_REPORT_FORMAT_LEARNING_FILE="$LEARNING_FILE" \
        GATE_REPORT_FORMAT_PREFILL_THRESHOLD=5 \
        bash "$TEST_GATE" "$report_path"
    [ "$status" -eq 1 ]

    run python3 - <<EOF
import yaml
from pathlib import Path

data = yaml.safe_load(Path("$LEARNING_FILE").read_text(encoding="utf-8"))
patterns = data["patterns"]
assert patterns["lu_reason_empty"]["count"] == 1
assert patterns["lu_reason_empty"]["prefill_field"] == "lessons_useful.reason"
assert patterns["bc_result_empty"]["count"] == 1
assert patterns["bc_result_empty"]["prefill_field"] == "binary_checks.result"
assert patterns["result_summary_empty"]["count"] == 1
assert patterns["result_summary_empty"]["prefill_field"] == "result.summary"
assert patterns["files_modified_missing"]["count"] == 1
assert patterns["files_modified_missing"]["prefill_field"] == "files_modified"
assert patterns["ac_version_read_missing"]["count"] == 1
assert "prefill_field" not in patterns["ac_version_read_missing"]
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
