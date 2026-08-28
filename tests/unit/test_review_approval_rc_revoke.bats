#!/usr/bin/env bats
# test_necessity: karo RC_REVOKE must restore a mistakenly-RC'd report/task to
# its pre-RC state (revision-requested reports become reviewable again, RC's
# rejection markers clear so a stale-payload BLOCK does not resurface) while
# retreating (not deleting) the erroneous RC record with a mandatory reason,
# and must not weaken the existing RC path for genuinely rejected work.

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

_seed_gunshi_lgtm() {
    local cmd_id="$1" report="$2" key fingerprint approval_dir
    key="$(PROJECT_ROOT="$FAKE_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_key "${2#"$1"/}"' _ "$FAKE_ROOT" "$report")"
    fingerprint="$(PROJECT_ROOT="$FAKE_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_fingerprint "$2"' _ "$FAKE_ROOT" "$report")"
    approval_dir="$FAKE_ROOT/queue/gates/$cmd_id/review_approvals/reports/$key"
    mkdir -p "$approval_dir"
    printf 'timestamp: 2026-07-27T00:11:00+09:00\nrole: gunshi\nresult: LGTM\nfingerprint: %s\nreport: queue/reports/%s\n' \
        "$fingerprint" "$(basename "$report")" > "$approval_dir/gunshi.yaml"
}

# ---------------------------------------------------------------------------
# fixture (1): erroneous RC -> RC_REVOKE -> Gunshi LGTM passes again
# ---------------------------------------------------------------------------
@test "erroneous RC can be revoked, then Karo ACCEPT succeeds on the untouched report" {
    local cmd_id=cmd_rc_revoke_f1 worker=fixworker1
    _make_task "$worker" "$cmd_id"
    local report
    report="$(_make_report "${worker}_rpt_${cmd_id}" "$cmd_id" "$worker")"

    run _review "$cmd_id" karo RC "$report"
    [ "$status" -eq 0 ]
    [ -f "$FAKE_ROOT/queue/tasks/${worker}.yaml" ]
    grep -q 'status: assigned' "$FAKE_ROOT/queue/tasks/${worker}.yaml"

    run _review "$cmd_id" karo RC_REVOKE "$report" "誤ってRCしてしまった。報告は最初から正しかった"
    echo "$output" >&3
    [ "$status" -eq 0 ]

    # report status restored to completed
    grep -q '^status: completed' "$report"
    # task fields restored to pre-RC values
    grep -q 'status: done' "$FAKE_ROOT/queue/tasks/${worker}.yaml"
    grep -q 'reviewed: true' "$FAKE_ROOT/queue/tasks/${worker}.yaml"

    # RC record retreated (archived), not left as a live rejection marker
    local key
    key="$(PROJECT_ROOT="$FAKE_ROOT" bash -c '
        source "$1/scripts/lib/review_approval.sh"
        review_report_key "queue/reports/'"${worker}_rpt_${cmd_id}"'.yaml"
    ' _ "$FAKE_ROOT")"
    local dir="$FAKE_ROOT/queue/gates/$cmd_id/review_approvals/reports/$key"
    [ ! -f "$dir/last_rc_commit" ]
    [ ! -f "$dir/karo.yaml" ]
    [ -d "$FAKE_ROOT/queue/archive/rc_erroneous" ]
    run bash -c "find '$FAKE_ROOT/queue/archive/rc_erroneous' -name reason.yaml | xargs grep -l '誤ってRC'"
    [ "$status" -eq 0 ]

    # A formal decision now succeeds against the exact same, unchanged report:
    # the "implementation commit unchanged since Karo RC" gate that would
    # otherwise fire (see fixture 4) is cleared because the RC was revoked.
    # No forced content edit was required to get past the erroneous RC.
    _seed_gunshi_lgtm "$cmd_id" "$report"
    run _review "$cmd_id" karo ACCEPT "$report"
    echo "$output" >&3
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# fixture (2): after revoke, a fresh RC can still be issued (revoke is not a
# one-way disable of the RC mechanism for that report)
# ---------------------------------------------------------------------------
@test "RC can be recorded again on the same report after a revoke" {
    local cmd_id=cmd_rc_revoke_f2 worker=fixworker2
    _make_task "$worker" "$cmd_id"
    local report
    report="$(_make_report "${worker}_rpt_${cmd_id}" "$cmd_id" "$worker")"

    run _review "$cmd_id" karo RC "$report"
    [ "$status" -eq 0 ]
    run _review "$cmd_id" karo RC_REVOKE "$report" "誤操作のため撤回"
    [ "$status" -eq 0 ]

    # report is back to completed; a second, genuine RC must still work
    run _review "$cmd_id" karo RC "$report"
    echo "$output" >&3
    [ "$status" -eq 0 ]
    grep -q 'status: assigned' "$FAKE_ROOT/queue/tasks/${worker}.yaml"
}

# ---------------------------------------------------------------------------
# fixture (3): revoke without a reason is rejected (structural arg, not a
# display-type essay requirement — an empty/whitespace-only 5th arg BLOCKs)
# ---------------------------------------------------------------------------
@test "RC_REVOKE without a reason is rejected" {
    local cmd_id=cmd_rc_revoke_f3 worker=fixworker3
    _make_task "$worker" "$cmd_id"
    local report
    report="$(_make_report "${worker}_rpt_${cmd_id}" "$cmd_id" "$worker")"

    run _review "$cmd_id" karo RC "$report"
    [ "$status" -eq 0 ]

    run _review "$cmd_id" karo RC_REVOKE "$report" ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"reason"* ]]

    run _review "$cmd_id" karo RC_REVOKE "$report" "   "
    [ "$status" -ne 0 ]

    # report must remain in the post-RC (revision_requested) state; the
    # rejected revoke must not have mutated anything
    grep -q '^status: revision_requested' "$report"
}

# ---------------------------------------------------------------------------
# fixture (4): a legitimate RC (not revoked) still blocks resubmission of the
# same unchanged implementation commit — AC6 unchanged-contract
# ---------------------------------------------------------------------------
@test "legitimate (non-revoked) RC still blocks an unchanged resubmission" {
    local cmd_id=cmd_rc_revoke_f4 worker=fixworker4
    _make_task "$worker" "$cmd_id"
    local report
    report="$(_make_report "${worker}_rpt_${cmd_id}" "$cmd_id" "$worker")"

    run _review "$cmd_id" karo RC "$report" implementation
    [ "$status" -eq 0 ]

    # Re-submit the report as completed again without changing the
    # implementation commit — a genuine karo ACCEPT must still be blocked.
    python3 - "$report" <<'PY'
import sys, yaml
p = sys.argv[1]
d = yaml.safe_load(open(p, encoding="utf-8")) or {}
d["status"] = "completed"
yaml.dump(d, open(p, "w", encoding="utf-8"), allow_unicode=True, default_flow_style=False)
PY

    _seed_gunshi_lgtm "$cmd_id" "$report"

    run _review "$cmd_id" karo ACCEPT "$report"
    echo "$output" >&3
    [ "$status" -ne 0 ]
    [[ "$output" == *"unchanged since Karo RC"* ]]
}
