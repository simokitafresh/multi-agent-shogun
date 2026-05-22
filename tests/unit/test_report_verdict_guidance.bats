#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
}

@test "deploy_task report template does not instruct manual verdict writes" {
    run grep -n 'RFS verdict "PASS"\|verdict→PASS/FAIL\|verdict: "PASS" or "FAIL" を記入' "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 1 ]

    run grep -n 'verdict は gate_report_format.sh が binary_checks から自動導出する。手動記入禁止。' "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]

    run grep -n '^verdict: ""[[:space:]]*#' "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 1 ]
}

@test "report gate failure hints do not suggest setting verdict directly" {
    run grep -n 'report_field_set.sh \$REPORT_PATH verdict PASS' "$PROJECT_ROOT/scripts/inbox_write.sh"
    [ "$status" -eq 1 ]

    run grep -n 'verdict は gate_report_format.sh が binary_checks から自動導出' "$PROJECT_ROOT/scripts/inbox_write.sh"
    [ "$status" -eq 0 ]
}
