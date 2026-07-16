#!/usr/bin/env bats

@test "ralph metrics batches verdict scan with ripgrep and preserves safety fallbacks" {
    script="${BATS_TEST_DIRNAME}/../../scripts/ralph_loop_metrics.sh"

    run grep -F 'rg --no-heading --with-filename "^verdict:" "$REPORTS_DIR"/ 2>/dev/null \' "$script"
    [ "$status" -eq 0 ]

    run grep -A3 -F 'rg --no-heading --with-filename "^verdict:"' "$script"
    [ "$status" -eq 0 ]
    [[ "$output" == *'|| true'* ]]
}
