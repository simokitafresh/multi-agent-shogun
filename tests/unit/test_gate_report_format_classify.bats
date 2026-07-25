#!/usr/bin/env bats
# cmd_karo_hotfix_singleflight_fail_misattribution_20260725
# test_necessity: gate_report_format.sh's exit code (0/2/other) is the single machine-readable
# contract every caller (inbox_write.sh/ninja_done.sh/cmd_complete_gate.sh/dashboard_update.sh)
# relies on to avoid re-deriving its own ad-hoc, divergent classification of the same signal.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$REPO_ROOT/scripts/lib/gate_report_format_classify.sh"
}

@test "exit code 0 classifies as PASS" {
    [ "$(gate_report_format_classify 0)" = "PASS" ]
}

@test "exit code 2 classifies as INFRA_TIMEOUT" {
    [ "$(gate_report_format_classify 2)" = "INFRA_TIMEOUT" ]
}

@test "exit code 1 (and any other non-zero) classifies as QUALITY_FAIL" {
    [ "$(gate_report_format_classify 1)" = "QUALITY_FAIL" ]
    [ "$(gate_report_format_classify 3)" = "QUALITY_FAIL" ]
    [ "$(gate_report_format_classify 127)" = "QUALITY_FAIL" ]
}
