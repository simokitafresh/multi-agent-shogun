#!/usr/bin/env bats
# test_necessity: karo RC must reset the worker's task_file status/lifecycle
# fields as ONE atomic batch (not N separate flock-acquire/release calls),
# so no external writer can observe or leave a half-reset state where the
# task file's other RC fields (deployed_at/reviewed/review_result) already
# reflect the RC but status still reads the pre-RC value (2026-07-27 13:39
# incident: kotaro's task stayed status=done after a formal RC, keeping the
# worker's own Stop hook nagging "Task completed..." for 9 minutes).
# Positive control: RC flips status to a reworkable state.
# Negative control: a normal ACCEPT/LGTM completion path must not be touched
# by this batch write and must not have its status wrongly reset.

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

setup() {
    export FAKE_ROOT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$FAKE_ROOT/queue/reports" \
             "$FAKE_ROOT/queue/gates" \
             "$FAKE_ROOT/queue/tasks" \
             "$FAKE_ROOT/queue/locks" \
             "$FAKE_ROOT/queue/archive" \
             "$FAKE_ROOT/logs"
    ln -s "$PROJECT_ROOT/scripts" "$FAKE_ROOT/scripts"
    export REVIEW_APPROVAL_ROOT="$FAKE_ROOT"
}

_make_task() {
    local name="$1" cmd_id="$2"
    cat > "$FAKE_ROOT/queue/tasks/${name}.yaml" <<YAML
task:
  task_id: ${cmd_id}_normal
  parent_cmd: ${cmd_id}
  issued_cmd_id: ${cmd_id}
  status: done
  reviewed: true
  review_result: ACCEPT
  deployed_at: "2026-07-27T00:00:00"
  retry_deployed_at: "2026-07-27T00:00:00"
  acknowledged_at: "2026-07-27T00:01:00"
  completed_at: "2026-07-27T00:10:00"
  done_at: "2026-07-27T00:10:00"
YAML
}

_make_report() {
    local name="$1" cmd_id="$2" worker="$3"
    local report="$FAKE_ROOT/queue/reports/${name}.yaml"
    cat > "$report" <<YAML
worker_id: ${worker}
task_id: ${cmd_id}_normal
parent_cmd: ${cmd_id}
status: completed
verdict: PASS
commit_hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
binary_checks:
  commit:
    - check: "commitが完了したか"
      result: "yes"
ac_evidence_mapping:
  AC1: "all good"
files_modified:
  - path: scripts/foo.sh
YAML
    echo "$report"
}

_review() {
    REVIEW_APPROVAL_ROOT="$FAKE_ROOT" bash "$PROJECT_ROOT/scripts/review_approval.sh" "$@"
}

# ---------------------------------------------------------------------------
# Positive control: RC resets status (and the rest of the lifecycle fields)
# together, in one batch — status is never left stale relative to its peers.
# ---------------------------------------------------------------------------
@test "RC resets task status atomically alongside the other lifecycle fields" {
    local cmd_id=cmd_rc_atomic_p1 worker=atomicworker1
    _make_task "$worker" "$cmd_id"
    local report
    report="$(_make_report "${worker}_rpt_${cmd_id}" "$cmd_id" "$worker")"

    run _review "$cmd_id" karo RC "$report"
    echo "$output" >&3
    [ "$status" -eq 0 ]

    local tf="$FAKE_ROOT/queue/tasks/${worker}.yaml"
    grep -q '^  status: assigned' "$tf"
    grep -q '^  reviewed: false' "$tf"
    grep -qE '^  review_result: *(""|'"'"''"'"')?$' "$tf"
    grep -qE '^  acknowledged_at: *(""|'"'"''"'"')?$' "$tf"
    grep -qE '^  completed_at: *(""|'"'"''"'"')?$' "$tf"
    grep -qE '^  done_at: *(""|'"'"''"'"')?$' "$tf"

    # exactly one review_approval.sh-owned lock cycle: only one yaml_field_set
    # invocation for the task file's whole RC reset (the batch call), not 8.
    run grep -c 'yaml_field_set.sh" "\$task_file" task ' "$PROJECT_ROOT/scripts/review_approval.sh"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    [ "${output:-0}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Negative control: normal ACCEPT completion (no RC anywhere in this report's
# history) must not have its status reset or otherwise disturbed.
# ---------------------------------------------------------------------------
@test "normal Karo ACCEPT completion does not reset or touch task status" {
    local cmd_id=cmd_rc_atomic_n1 worker=atomicworker2
    _make_task "$worker" "$cmd_id"
    local report
    report="$(_make_report "${worker}_rpt_${cmd_id}" "$cmd_id" "$worker")"

    local tf="$FAKE_ROOT/queue/tasks/${worker}.yaml"
    local before_status before_reviewed
    before_status="$(awk '/^  status:/{print; exit}' "$tf")"
    before_reviewed="$(awk '/^  reviewed:/{print; exit}' "$tf")"

    run _review "$cmd_id" karo ACCEPT "$report"
    echo "$output" >&3
    [ "$status" -eq 0 ]

    # ACCEPT is a formal decision record only; it must never touch the
    # worker's task_file (that is exclusively the RC/RC_REVOKE lifecycle's job).
    local after_status after_reviewed
    after_status="$(awk '/^  status:/{print; exit}' "$tf")"
    after_reviewed="$(awk '/^  reviewed:/{print; exit}' "$tf")"
    [ "$before_status" = "$after_status" ]
    [ "$before_reviewed" = "$after_reviewed" ]
    [ "$after_status" = "  status: done" ]
}
