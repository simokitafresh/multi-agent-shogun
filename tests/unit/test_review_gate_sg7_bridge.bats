#!/usr/bin/env bats
# test_necessity: a fingerprint-bound formal SG7 approval must satisfy review_gate for direct implementation tasks while absent bundles retain legacy review-task compatibility and malformed bundles fail closed.
# regression_justification: compare-summary had Gunshi LGTM, SG7, and Karo ACCEPT but remained permanently BLOCKED because review_gate.sh recognized only task_type=review tasks.

setup() {
    export ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$ROOT/scripts/lib" "$ROOT/queue/tasks" "$ROOT/queue/gates" "$ROOT/queue/reports"
    cp "$BATS_TEST_DIRNAME/../../scripts/review_gate.sh" "$ROOT/scripts/review_gate.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/review_bundle.py" "$ROOT/scripts/review_bundle.py"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/review_approval.sh" "$ROOT/scripts/lib/review_approval.sh"
}

write_code_task() {
    local cmd="$1"
    cat > "$ROOT/queue/tasks/code.yaml" <<YAML
task:
  task_id: ${cmd}_implementation
  parent_cmd: $cmd
  task_type: hotfix
  purpose: fix implementation
  status: done
  report_path: queue/reports/code_report_${cmd}.yaml
YAML
    cat > "$ROOT/queue/reports/code_report_${cmd}.yaml" <<YAML
worker_id: code
report_id: rpt-${cmd}
report_identity_version: 2
task_id: ${cmd}_implementation
parent_cmd: $cmd
status: completed
verdict: PASS
YAML
}

write_valid_bundle() {
    local cmd="$1"
    mkdir -p "$ROOT/queue/gates/$cmd"
    cat > "$ROOT/queue/gates/$cmd/sg7_bundle.json" <<JSON
{"review":{"cmd_id":"$cmd","verdict":"APPROVE","report_verdict":"PASS","report":"queue/reports/code_report_${cmd}.yaml","report_id":"rpt-${cmd}","cmd_spec_summary":{"acceptance_criteria_count":1,"scope":"scripts","project":"infra"},"dashboard_line":"- **$cmd**: done"}}
JSON
}

@test "formal SG7 bridges direct review, legacy fallback remains, and malformed SG7 blocks" {
    write_code_task cmd_sg7
    write_valid_bundle cmd_sg7
    run bash "$ROOT/scripts/review_gate.sh" cmd_sg7
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: 正式SG7レビュー済み"* ]]
    [ -f "$ROOT/queue/gates/cmd_sg7/review_gate.done" ]

    write_code_task cmd_legacy
    cat > "$ROOT/queue/tasks/review.yaml" <<'YAML'
task:
  task_id: cmd_legacy_review
  parent_cmd: cmd_legacy
  task_type: review
  assigned_to: gunshi
  status: done
YAML
    run bash "$ROOT/scripts/review_gate.sh" cmd_legacy
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: レビュー済み"* ]]

    write_code_task cmd_bad
    mkdir -p "$ROOT/queue/gates/cmd_bad"
    printf '{}\n' > "$ROOT/queue/gates/cmd_bad/sg7_bundle.json"
    run bash "$ROOT/scripts/review_gate.sh" cmd_bad
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: 正式SG7 bundleが不正"* ]]
    [ ! -f "$ROOT/queue/gates/cmd_bad/review_gate.done" ]
}
