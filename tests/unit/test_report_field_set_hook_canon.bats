#!/usr/bin/env bats
# test_report_field_set_hook_canon.bats
# Purpose: report_field_set.sh writes to the exact path
# hook_failures.details.post_verification_result must canonicalize the known
# PASS/all_pass, NO_NEW_FAILURE/no_new_failure, REGRESSION_DETECTED/regression_detected
# spellings review_bundle.py's _HOOK_POST_RESULTS enforces, so gunshi APPROVE never
# round-trips on a spelling mismatch alone. Unknown values and the direct-sibling
# path hook_failures.post_verification_result (not nested under details) must stay
# untouched so the existing downstream BLOCK still catches genuine mistakes.
# Origin: cmd_karo_hotfix_report_hook_result_canonicalization_20260729 — WA evidence
# logs/karo_workarounds.yaml cmd_karo_hotfix_recalculate_sync_end_date_20260729
# (2 manual WA in report_yaml_format category, same root cause).
# test_necessity: hook_failures.details.post_verification_result canonicalization
# (exact path only, unknown values pass through unchanged) is a permanent contract
# with review_bundle.py's _HOOK_POST_RESULTS enum, not implementation-detail scaffolding.

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPT="$PROJECT_ROOT/scripts/report_field_set.sh"
    [ -f "$SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/rfs_hook_canon.XXXXXX")"
    export TEST_REPORT="$TEST_TMPDIR/report.yaml"
    cat > "$TEST_REPORT" <<'EOF'
worker_id: rfs_hook_canon_test
parent_cmd: cmd_test
ac_version_read: abc12345
EOF
    export TEST_BATCH_REPORT="$TEST_TMPDIR/batch_report.yaml"
    cat > "$TEST_BATCH_REPORT" <<'EOF'
worker_id: rfs_hook_canon_test
parent_cmd: cmd_test
ac_version_read: abc12345
files_modified: []
lessons_useful: []
binary_checks: {}
EOF
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

_hook_result() {
    python3 -c "import yaml, sys; print(yaml.safe_load(open(sys.argv[1]))['hook_failures']['details']['post_verification_result'])" "$1"
}

# --- canonical 6 inputs (single-key CLI lane) ---

@test "hook_failures.details.post_verification_result: PASS canonicalizes to all_pass" {
    run bash "$SCRIPT" "$TEST_REPORT" hook_failures.details.post_verification_result "PASS"
    [ "$status" -eq 0 ]
    [ "$(_hook_result "$TEST_REPORT")" = "all_pass" ]
}

@test "hook_failures.details.post_verification_result: all_pass stays all_pass (idempotent)" {
    run bash "$SCRIPT" "$TEST_REPORT" hook_failures.details.post_verification_result "all_pass"
    [ "$status" -eq 0 ]
    [ "$(_hook_result "$TEST_REPORT")" = "all_pass" ]
}

@test "hook_failures.details.post_verification_result: NO_NEW_FAILURE canonicalizes to no_new_failure" {
    run bash "$SCRIPT" "$TEST_REPORT" hook_failures.details.post_verification_result "NO_NEW_FAILURE"
    [ "$status" -eq 0 ]
    [ "$(_hook_result "$TEST_REPORT")" = "no_new_failure" ]
}

@test "hook_failures.details.post_verification_result: no_new_failure stays no_new_failure (idempotent)" {
    run bash "$SCRIPT" "$TEST_REPORT" hook_failures.details.post_verification_result "no_new_failure"
    [ "$status" -eq 0 ]
    [ "$(_hook_result "$TEST_REPORT")" = "no_new_failure" ]
}

@test "hook_failures.details.post_verification_result: REGRESSION_DETECTED canonicalizes to regression_detected" {
    run bash "$SCRIPT" "$TEST_REPORT" hook_failures.details.post_verification_result "REGRESSION_DETECTED"
    [ "$status" -eq 0 ]
    [ "$(_hook_result "$TEST_REPORT")" = "regression_detected" ]
}

@test "hook_failures.details.post_verification_result: regression_detected stays regression_detected (idempotent)" {
    run bash "$SCRIPT" "$TEST_REPORT" hook_failures.details.post_verification_result "regression_detected"
    [ "$status" -eq 0 ]
    [ "$(_hook_result "$TEST_REPORT")" = "regression_detected" ]
}

# --- non-canonical 3 cases: must NOT be auto-fixed (false_positive=0 contract) ---

@test "hook_failures.details.post_verification_result: unknown value FAIL passes through unchanged" {
    run bash "$SCRIPT" "$TEST_REPORT" hook_failures.details.post_verification_result "FAIL"
    [ "$status" -eq 0 ]
    [ "$(_hook_result "$TEST_REPORT")" = "FAIL" ]
}

@test "hook_failures.details.post_verification_result: mixed-case All_Pass is not exact-match canonicalized" {
    run bash "$SCRIPT" "$TEST_REPORT" hook_failures.details.post_verification_result "All_Pass"
    [ "$status" -eq 0 ]
    [ "$(_hook_result "$TEST_REPORT")" = "All_Pass" ]
}

@test "hook_failures.post_verification_result (direct sibling, not under details) is not canonicalized" {
    run bash "$SCRIPT" "$TEST_REPORT" hook_failures.post_verification_result "PASS"
    [ "$status" -eq 0 ]
    result="$(python3 -c "import yaml, sys; print(yaml.safe_load(open(sys.argv[1]))['hook_failures']['post_verification_result'])" "$TEST_REPORT")"
    [ "$result" = "PASS" ]
}

# --- batch lane (report-write skill's primary lane) mirrors the same contract ---

@test "batch: hook_failures.details.post_verification_result PASS canonicalizes to all_pass" {
    run bash "$SCRIPT" --batch "$TEST_BATCH_REPORT" <<< "hook_failures.details.post_verification_result: PASS"
    [ "$status" -eq 0 ]
    [ "$(_hook_result "$TEST_BATCH_REPORT")" = "all_pass" ]
}

@test "batch: unknown value passes through unchanged" {
    run bash "$SCRIPT" --batch "$TEST_BATCH_REPORT" <<< "hook_failures.details.post_verification_result: FAIL"
    [ "$status" -eq 0 ]
    [ "$(_hook_result "$TEST_BATCH_REPORT")" = "FAIL" ]
}

@test "batch: direct sibling path is not canonicalized" {
    run bash "$SCRIPT" --batch "$TEST_BATCH_REPORT" <<< "hook_failures.post_verification_result: PASS"
    [ "$status" -eq 0 ]
    result="$(python3 -c "import yaml, sys; print(yaml.safe_load(open(sys.argv[1]))['hook_failures']['post_verification_result'])" "$TEST_BATCH_REPORT")"
    [ "$result" = "PASS" ]
}
