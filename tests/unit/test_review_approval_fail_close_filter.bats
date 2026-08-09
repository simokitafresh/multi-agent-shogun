#!/usr/bin/env bats
# test_necessity: A fingerprint-bound Karo-accepted FAIL attempt is terminal and must not deadlock a successful sibling's two-phase completion manifest.
# regression_justification: cmd_4211 had one successful replacement report plus one formally closed failed attempt; the gate required impossible Gunshi LGTM for the failed report forever.

setup() {
    export PROJECT_ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$PROJECT_ROOT/queue/reports" "$PROJECT_ROOT/queue/archive/reports" "$PROJECT_ROOT/queue/gates/cmd_mix/review_approvals/reports"
    ln -s "$BATS_TEST_DIRNAME/../../scripts" "$PROJECT_ROOT/scripts"
    source "$BATS_TEST_DIRNAME/../../scripts/lib/review_approval.sh"
    cat > "$PROJECT_ROOT/queue/reports/failed_report.yaml" <<'YAML'
report_id: rpt-failed
parent_cmd: cmd_mix
status: failed
verdict: FAIL
commit_hash: no-code-change
YAML
    cat > "$PROJECT_ROOT/queue/reports/pass_report.yaml" <<'YAML'
report_id: rpt-pass
parent_cmd: cmd_mix
status: completed
verdict: PASS
commit_hash: 0123456789012345678901234567890123456789
YAML
}

@test "mixed FAIL close and PASS sibling leaves only PASS in two-phase set" {
    local failed="$PROJECT_ROOT/queue/reports/failed_report.yaml"
    local pass="$PROJECT_ROOT/queue/reports/pass_report.yaml"
    local logical key dir fp
    logical=$(PROJECT_ROOT="$PROJECT_ROOT" review_report_logical_path "$failed")
    key=$(review_report_key "$logical")
    dir="$PROJECT_ROOT/queue/gates/cmd_mix/review_approvals/reports/$key"
    mkdir -p "$dir"
    fp=$(REVIEW_FAIL_CLOSE_IDENTITY_EXEMPT=1 review_report_fingerprint "$failed")
    cat > "$dir/karo.yaml" <<YAML
role: karo
result: ACCEPT
fingerprint: $fp
YAML

    run review_resolve_gate_reports cmd_mix "$failed" "$pass"
    [ "$status" -eq 0 ]
    [ "$output" = "$pass" ]

    printf '\nmutation: true\n' >> "$failed"
    run review_resolve_gate_reports cmd_mix "$failed" "$pass"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]
}

# test_necessity: a pre-v2 archived sibling must remain reviewable after its task slot is reused by a current v2 worker, without weakening duplicate-report rejection.
# regression_justification: compare-summary had a valid active v2 report, but an older archived sibling without report_id made the canonical registry return rc=1 and blocked SG7 generation.
@test "canonical registry accepts archived legacy sibling and still rejects duplicate basename" {
    mkdir -p "$PROJECT_ROOT/queue/tasks"
    cat > "$PROJECT_ROOT/queue/tasks/current.yaml" <<'YAML'
task:
  parent_cmd: cmd_legacy
  report_filename: current_report_cmd_legacy.yaml
YAML
    cat > "$PROJECT_ROOT/queue/reports/current_report_cmd_legacy.yaml" <<'YAML'
report_id: rpt-current
report_identity_version: 2
parent_cmd: cmd_legacy
status: completed
verdict: PASS
commit_hash: 0123456789012345678901234567890123456789
YAML
    cat > "$PROJECT_ROOT/queue/archive/reports/old_report_cmd_legacy_20260802.yaml" <<'YAML'
parent_cmd: cmd_legacy
status: failed
verdict: FAIL
commit_hash: no-code-change
YAML

    run review_resolve_reports cmd_legacy
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]

    cp "$PROJECT_ROOT/queue/archive/reports/old_report_cmd_legacy_20260802.yaml" \
        "$PROJECT_ROOT/queue/reports/old_report_cmd_legacy_20260802.yaml"
    cat > "$PROJECT_ROOT/queue/tasks/duplicate.yaml" <<'YAML'
task:
  parent_cmd: cmd_legacy
  report_filename: old_report_cmd_legacy_20260802.yaml
YAML
    run review_resolve_reports cmd_legacy
    [ "$status" -eq 1 ]
}

# test_necessity: a revised live report with a new v2 identity supersedes its
# immutable archived generation for approval, without deleting that history.
@test "canonical registry reviews only active v2 generation for same worker task" {
    mkdir -p "$PROJECT_ROOT/queue/tasks"
    cat > "$PROJECT_ROOT/queue/tasks/current.yaml" <<'YAML'
task:
  parent_cmd: cmd_revised
  report_filename: ninja_report_cmd_revised.yaml
YAML
    cat > "$PROJECT_ROOT/queue/reports/ninja_report_cmd_revised.yaml" <<'YAML'
worker_id: ninja
task_id: cmd_revised_full
report_id: rpt-current
report_identity_version: 2
parent_cmd: cmd_revised
status: completed
verdict: PASS
commit_hash: 0123456789012345678901234567890123456789
YAML
    cat > "$PROJECT_ROOT/queue/archive/reports/ninja_report_cmd_revised_20260810.yaml" <<'YAML'
worker_id: ninja
task_id: cmd_revised_full
report_id: rpt-archived
report_identity_version: 2
parent_cmd: cmd_revised
status: completed
verdict: PASS
commit_hash: 0123456789012345678901234567890123456789
YAML

    run review_resolve_reports cmd_revised
    [ "$status" -eq 0 ]
    [ "$output" = "$PROJECT_ROOT/queue/reports/ninja_report_cmd_revised.yaml" ]
    [ -f "$PROJECT_ROOT/queue/archive/reports/ninja_report_cmd_revised_20260810.yaml" ]
}
