#!/usr/bin/env bats
# test_necessity: report-only RC notifications must not pre-decide whether prior
# measurements remain valid or whether recalculation/reimplementation is forbidden;
# that decision belongs exclusively to the concrete review instructions.

setup_file() {
    export REVIEW_APPROVAL_SCRIPT
    REVIEW_APPROVAL_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/scripts/review_approval.sh"
}

@test "report-only RC notification keeps recalculation decision neutral" {
    run grep -c '前報告の実測・成果物は有効\|再計算・再実装は禁止' "$REVIEW_APPROVAL_SCRIPT"
    [ "$status" -eq 1 ]
    [ "$output" -eq 0 ]

    run grep -c '現task YAMLとRC指摘を正本として再読' "$REVIEW_APPROVAL_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c '再計算・再実装の要否はレビュー指示に従え' "$REVIEW_APPROVAL_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# test_necessity: the asynchronous completion gate must never inherit the
# report-approval flock descriptor after the durable review transaction ends.
@test "completion trigger closes approval lock fd before asynchronous execution" {
    run grep -E -c 'setsid nohup bash .*cmd_complete_gate\.sh.*200>&- &$' "$REVIEW_APPROVAL_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

setup_fail_close_fixture() {
    export FAIL_CLOSE_ROOT="$BATS_TEST_TMPDIR/fail-close-root"
    mkdir -p "$FAIL_CLOSE_ROOT/queue/reports" "$FAIL_CLOSE_ROOT/queue/gates" \
        "$FAIL_CLOSE_ROOT/queue/tasks" "$FAIL_CLOSE_ROOT/queue/inbox" "$FAIL_CLOSE_ROOT/logs"
    ln -s "$BATS_TEST_DIRNAME/../../scripts" "$FAIL_CLOSE_ROOT/scripts"
}

make_fail_close_task() {
    local worker="$1" cmd_id="$2"
    cat > "$FAIL_CLOSE_ROOT/queue/tasks/${worker}.yaml" <<YAML
task:
  task_id: ${cmd_id}_normal
  parent_cmd: ${cmd_id}
  issued_cmd_id: ${cmd_id}
  status: done
  reviewed: true
  review_result: ACCEPT
  deployed_at: "2026-08-11T00:00:00"
  acknowledged_at: "2026-08-11T00:01:00"
  completed_at: "2026-08-11T00:10:00"
  done_at: "2026-08-11T00:10:00"
YAML
}

make_fail_close_report() {
    local worker="$1" cmd_id="$2"
    local report="$FAIL_CLOSE_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml"
    cat > "$report" <<YAML
worker_id: ${worker}
task_id: ${cmd_id}_normal
parent_cmd: ${cmd_id}
task_type: hotfix
status: completed
verdict: PASS
commit_hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
binary_checks:
  commit:
    - check: "implementation commit exists"
      result: "yes"
files_modified:
  - path: scripts/foo.sh
YAML
    printf '%s\n' "$report"
}

fail_close_review() {
    REVIEW_APPROVAL_ROOT="$FAIL_CLOSE_ROOT" \
    REVIEW_APPROVAL_NO_TRIGGER=1 \
    REVIEW_APPROVAL_NO_NOTIFY=1 \
    bash "$FAIL_CLOSE_ROOT/scripts/review_approval.sh" "$@"
}

# test_necessity: a failed report formally accepted by Karo after a report-only
# RC is a terminal failure close, not a fresh report correction requiring a new
# Gunshi LGTM.
# regression_justification: cmd_karo_hotfix_fail_close_after_report_rc_202608110653
@test "report-only RC followed by failed Karo ACCEPT is the fail-close boundary" {
    setup_fail_close_fixture
    local cmd_id=cmd_karo_fail_close_report_rc worker=failcloseworker
    make_fail_close_task "$worker" "$cmd_id"
    local report
    report="$(make_fail_close_report "$worker" "$cmd_id")"

    run fail_close_review "$cmd_id" karo RC "$report" report
    [ "$status" -eq 0 ]
    bash "$FAIL_CLOSE_ROOT/scripts/report_field_set.sh" "$report" result.summary "failed after report-only RC"
    sed -i 's/^status: revision_requested/status: failed/; s/^verdict: PASS/verdict: FAIL/' "$report"

    run fail_close_review "$cmd_id" karo ACCEPT "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"fail-close review recorded"* ]]
}

# test_necessity: a non-failed report-only correction still requires a fresh
# Gunshi approval bound to the corrected payload.
# regression_justification: the fail-close exception must not weaken the
# existing report-only fingerprint review boundary.
@test "completed report-only correction still requires current Gunshi LGTM" {
    setup_fail_close_fixture
    local cmd_id=cmd_karo_report_correction_guard worker=reportguardworker
    make_fail_close_task "$worker" "$cmd_id"
    local report
    report="$(make_fail_close_report "$worker" "$cmd_id")"

    run fail_close_review "$cmd_id" karo RC "$report" report
    [ "$status" -eq 0 ]
    bash "$FAIL_CLOSE_ROOT/scripts/report_field_set.sh" "$report" result.summary "corrected report payload"
    bash "$FAIL_CLOSE_ROOT/scripts/report_field_set.sh" "$report" status completed

    run fail_close_review "$cmd_id" karo ACCEPT "$report"
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires current Gunshi LGTM"* ]]
}

# test_necessity: an implementation-scope RC cannot be closed by resubmitting
# the same implementation commit, even though the fail-close lane is exempt.
# regression_justification: the exception is keyed to failed+FAIL+Karo ACCEPT,
# not to every post-RC acceptance.
@test "implementation correction still rejects an unchanged commit" {
    setup_fail_close_fixture
    local cmd_id=cmd_karo_implementation_guard worker=implementationguard
    make_fail_close_task "$worker" "$cmd_id"
    local report
    report="$(make_fail_close_report "$worker" "$cmd_id")"

    run fail_close_review "$cmd_id" karo RC "$report"
    [ "$status" -eq 0 ]
    sed -i 's/^status: revision_requested/status: completed/' "$report"

    run fail_close_review "$cmd_id" karo ACCEPT "$report"
    [ "$status" -ne 0 ]
    [[ "$output" == *"implementation commit unchanged since Karo RC"* ]]
}
