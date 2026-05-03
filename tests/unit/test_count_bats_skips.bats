#!/usr/bin/env bats
# test_count_bats_skips.bats - TAP skip directive counting

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPT="$PROJECT_ROOT/scripts/count_bats_skips.sh"
    [ -f "$SCRIPT" ] || return 1
}

@test "counts zero skips without rerunning bats" {
    tap="$BATS_TEST_TMPDIR/zero.tap"
    cat > "$tap" <<'TAP'
1..3
ok 1 first test
ok 2 skip appears in test name
ok 3 third test
TAP

    run bash "$SCRIPT" "$tap"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "counts skip directives from existing TAP logs" {
    tap="$BATS_TEST_TMPDIR/skips.tap"
    cat > "$tap" <<'TAP'
1..4
ok 1 first test
ok 2 second test # skip reason here
ok 3 third test # SKIP uppercase reason
not ok 4 failing test
TAP

    run bash "$SCRIPT" "$tap"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "workflow verify step does not invoke bats" {
    run awk '
      /name: Verify zero SKIPs/ { in_step = 1 }
      in_step && /name: Upload test results/ { in_step = 0 }
      in_step { print }
    ' "$PROJECT_ROOT/.github/workflows/test.yml"

    [ "$status" -eq 0 ]
    [[ "$output" == *"scripts/count_bats_skips.sh"* ]]
    [[ "$output" != *"bats "* ]]
}
