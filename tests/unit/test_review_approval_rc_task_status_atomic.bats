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

_make_failed_report() {
    local name="$1" cmd_id="$2" worker="$3"
    local report="$FAKE_ROOT/queue/reports/${name}.yaml"
    cat > "$report" <<YAML
worker_id: ${worker}
task_id: ${cmd_id}_normal
parent_cmd: ${cmd_id}
status: failed
verdict: FAIL
binary_checks:
  AC1:
    - check: "implementation failed before commit"
      result: "no"
files_modified:
  - path: scripts/foo.sh
YAML
    echo "$report"
}

_review() {
    REVIEW_APPROVAL_ROOT="$FAKE_ROOT" bash "$PROJECT_ROOT/scripts/review_approval.sh" "$@"
}

_seed_gunshi_lgtm() {
    local cmd_id="$1" report="$2" key fingerprint approval_dir
    key="$(PROJECT_ROOT="$FAKE_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_key "${2#"$1"/}"' _ "$FAKE_ROOT" "$report")"
    fingerprint="$(PROJECT_ROOT="$FAKE_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_fingerprint "$2"' _ "$FAKE_ROOT" "$report")"
    approval_dir="$FAKE_ROOT/queue/gates/$cmd_id/review_approvals/reports/$key"
    mkdir -p "$approval_dir"
    printf 'timestamp: 2026-07-27T00:11:00+09:00\nrole: gunshi\nresult: LGTM\nfingerprint: %s\nreport: queue/reports/%s\n' \
        "$fingerprint" "$(basename "$report")" > "$approval_dir/gunshi.yaml"
}

# test_necessity: a truthful failed report may lack a commit precisely because
# implementation failed; Karo RC must bind that one exception to exact report
# bytes and the current worker task, while every PASS/identity boundary remains
# fail-closed.
# regression_justification: cmd_karo_hotfix_memory_db_recovery_stall_20260802
# reached failed+FAIL, but RC passed fail_close=0 to the commit identity gate and
# deadlocked on the absence that the report was truthfully recording.
@test "failed uncommitted RC is exact-generation and task-identity bound" {
    local cmd_id=cmd_karo_failed_uncommitted worker=atomicworker6
    _make_task "$worker" "$cmd_id"
    local report
    report="$(_make_failed_report "${worker}_rpt_${cmd_id}" "$cmd_id" "$worker")"

    run _review "$cmd_id" karo RC "$report"
    echo "$output" >&3
    [ "$status" -eq 0 ]
    grep -q '^status: revision_requested' "$report"
    grep -q '^  status: assigned' "$FAKE_ROOT/queue/tasks/${worker}.yaml"

    local key approval generation
    key="$(PROJECT_ROOT="$FAKE_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_key "${2#"$1"/}"' _ "$FAKE_ROOT" "$report")"
    approval="$FAKE_ROOT/queue/gates/$cmd_id/review_approvals/reports/$key/karo.yaml"
    generation="$(sed -n 's/^generation: //p' "$approval")"
    [[ "$generation" =~ ^[0-9a-f]{64}$ ]]

    # The formal record is for the pre-RC exact bytes, so the lifecycle write
    # performed by RC itself must already make the recorded generation stale.
    [ "$generation" != "$(sha256sum "$report" | awk '{print $1}')" ]
}

@test "failed uncommitted RC exception does not admit PASS or wrong task identity" {
    local cmd_id=cmd_karo_failed_uncommitted_negative worker=atomicworker7
    _make_task "$worker" "$cmd_id"
    local report
    report="$(_make_failed_report "${worker}_rpt_${cmd_id}" "$cmd_id" "$worker")"

    sed -i 's/status: failed/status: completed/; s/verdict: FAIL/verdict: PASS/' "$report"
    run _review "$cmd_id" karo RC "$report"
    [ "$status" -ne 0 ]

    sed -i 's/status: completed/status: failed/; s/verdict: PASS/verdict: FAIL/; s/task_id: cmd_karo_failed_uncommitted_negative_normal/task_id: wrong_task/' "$report"
    run _review "$cmd_id" karo RC "$report"
    [ "$status" -ne 0 ]
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

# test_necessity: report-only RC must preserve already-valid measurements and
# prohibit whole-task replay while still forcing the current task YAML reload.
# regression_justification: extends the existing RC lifecycle fixture to cover
# the distinct report fingerprint/approval identity boundary after rework.
@test "report-only RC records its scope and tells the worker to reuse valid results" {
    local cmd_id=cmd_rc_report_scope worker=atomicworker3
    _make_task "$worker" "$cmd_id"
    local report
    report="$(_make_report "${worker}_rpt_${cmd_id}" "$cmd_id" "$worker")"

    run _review "$cmd_id" karo RC "$report" report
    echo "$output" >&3
    [ "$status" -eq 0 ]

    local tf="$FAKE_ROOT/queue/tasks/${worker}.yaml"
    grep -q '^  review_correction_scope: report' "$tf"
    grep -q '現task YAMLとRC指摘を正本として再読' "$FAKE_ROOT/queue/inbox/${worker}.yaml"
    grep -q '再計算・再実装の要否はレビュー指示に従え' "$FAKE_ROOT/queue/inbox/${worker}.yaml"
    ! grep -q '前taskの情報は無効' "$FAKE_ROOT/queue/inbox/${worker}.yaml"
}

# test_necessity: report-only RC success requires a changed report payload, a
# completed terminal status, and a Gunshi approval for that exact fingerprint;
# an unchanged implementation commit is intentionally allowed in this lane.
# regression_justification: overlaps the RC scope setup above but uniquely
# protects the post-RC approval matrix and exact fingerprint binding.
@test "report-only RC accepts corrected payload with unchanged implementation and exact fingerprint" {
    local cmd_id=cmd_rc_report_success worker=atomicworker4
    _make_task "$worker" "$cmd_id"
    local report
    report="$(_make_report "${worker}_rpt_${cmd_id}" "$cmd_id" "$worker")"

    run _review "$cmd_id" karo RC "$report" report
    [ "$status" -eq 0 ]
    bash "$PROJECT_ROOT/scripts/report_field_set.sh" "$report" result.summary "report payload corrected"
    bash "$PROJECT_ROOT/scripts/report_field_set.sh" "$report" status completed

    local key fingerprint approval_dir
    key="$(PROJECT_ROOT="$FAKE_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_key "${2#"$1"/}"' _ "$FAKE_ROOT" "$report")"
    fingerprint="$(PROJECT_ROOT="$FAKE_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_fingerprint "$2"' _ "$FAKE_ROOT" "$report")"
    approval_dir="$FAKE_ROOT/queue/gates/$cmd_id/review_approvals/reports/$key"
    mkdir -p "$approval_dir"
    printf 'role: gunshi\nresult: LGTM\nfingerprint: %s\n' "$fingerprint" > "$approval_dir/gunshi.yaml"

    run _review "$cmd_id" karo ACCEPT "$report"
    echo "$output" >&3
    [ "$status" -eq 0 ]
}

# test_necessity: a report-only correction may not reuse an approval for an
# older report fingerprint, even when status and implementation identity pass.
# regression_justification: negative control for the exact-fingerprint success
# fixture above; without it a stale Gunshi approval could authorize new bytes.
@test "report-only RC rejects stale Gunshi fingerprint after another payload change" {
    local cmd_id=cmd_rc_report_stale_fp worker=atomicworker5
    _make_task "$worker" "$cmd_id"
    local report
    report="$(_make_report "${worker}_rpt_${cmd_id}" "$cmd_id" "$worker")"

    run _review "$cmd_id" karo RC "$report" report
    [ "$status" -eq 0 ]
    bash "$PROJECT_ROOT/scripts/report_field_set.sh" "$report" result.summary "first correction"
    bash "$PROJECT_ROOT/scripts/report_field_set.sh" "$report" status completed

    local key fingerprint approval_dir
    key="$(PROJECT_ROOT="$FAKE_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_key "${2#"$1"/}"' _ "$FAKE_ROOT" "$report")"
    fingerprint="$(PROJECT_ROOT="$FAKE_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_fingerprint "$2"' _ "$FAKE_ROOT" "$report")"
    approval_dir="$FAKE_ROOT/queue/gates/$cmd_id/review_approvals/reports/$key"
    mkdir -p "$approval_dir"
    printf 'role: gunshi\nresult: LGTM\nfingerprint: %s\n' "$fingerprint" > "$approval_dir/gunshi.yaml"
    bash "$PROJECT_ROOT/scripts/report_field_set.sh" "$report" result.summary "second unreviewed correction"

    run _review "$cmd_id" karo ACCEPT "$report"
    echo "$output" >&3
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires current Gunshi LGTM"* ]]
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

    _seed_gunshi_lgtm "$cmd_id" "$report"

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
