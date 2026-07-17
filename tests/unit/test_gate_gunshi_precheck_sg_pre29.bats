#!/usr/bin/env bats

setup() {
    TEST_REPORT="${BATS_TEST_TMPDIR}/pre29.yaml"
    eval "$(sed -n '/_sg_pre29_check()/,/^}/p' scripts/gates/gate_gunshi_report_precheck.sh)"
}

@test "SG-PRE29 ignores non-frontend changes" {
    printf '%s\n' 'files_modified:' '  - path: scripts/a.sh' > "$TEST_REPORT"
    run _sg_pre29_check "$TEST_REPORT"
    [ "$status" -eq 0 ]
}

@test "SG-PRE29 blocks frontend change without Next build" {
    printf '%s\n' 'files_modified:' '  - path: frontend/app/page.tsx' 'result:' '  details: pytest PASS' > "$TEST_REPORT"
    run _sg_pre29_check "$TEST_REPORT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(LG045)"* ]]
}

@test "SG-PRE29 blocks failed or ambiguous Next build" {
    printf '%s\n' 'files_modified:' '  - path: frontend/app/page.tsx' 'result:' '  details: npm run build failed' > "$TEST_REPORT"
    run _sg_pre29_check "$TEST_REPORT"
    [ "$status" -eq 2 ]
    printf '%s\n' 'files_modified:' '  - path: frontend/app/page.tsx' 'result:' '  details: npm run build executed' > "$TEST_REPORT"
    run _sg_pre29_check "$TEST_REPORT"
    [ "$status" -eq 2 ]
}

@test "SG-PRE29 accepts measured Next build PASS" {
    printf '%s\n' 'files_modified:' '  - path: frontend/app/page.tsx' 'test_results:' '  - command: npm run build' '    result: PASS' > "$TEST_REPORT"
    run _sg_pre29_check "$TEST_REPORT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS(LG045)"* ]]
}

@test "SG-PRE29 does not accept build words outside evidence fields" {
    printf '%s\n' 'files_modified:' '  - path: frontend/app/page.tsx' 'lesson_candidate:' '  detail: npm run build PASS should be required' > "$TEST_REPORT"
    run _sg_pre29_check "$TEST_REPORT"
    [ "$status" -eq 2 ]
}
