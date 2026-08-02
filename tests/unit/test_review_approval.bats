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
