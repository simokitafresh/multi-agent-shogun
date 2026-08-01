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
