#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/scripts/model_switch_preflight.sh"
}

@test "combined preflight scan preserves all cli_lookup dependency targets" {
    run bash "$SCRIPT" tobisaru
    # Repository hardcode findings may make the preflight itself fail; this test
    # owns the scan contract, not the current policy findings.
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
    [[ "$output" == *"全依存スクリプト(11件)チェック完了"* ]]
    [[ "$output" != *"ファイルが見つからない"* ]]
}

@test "check 1 and check 4 share one bounded rg scan" {
    run grep -c 'found=$(rg -n' "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]

    run grep -c 'PREFLIGHT_FORCE_LEGACY_SCAN.*1' "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}
