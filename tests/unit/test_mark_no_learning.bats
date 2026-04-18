#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPT_PATH="$PROJECT_ROOT/scripts/gates/mark_no_learning.sh"
    [ -f "$SCRIPT_PATH" ] || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/mark_no_learning.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates"
    cp "$SCRIPT_PATH" "$TEST_TMPDIR/scripts/gates/mark_no_learning.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/mark_no_learning.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "MNL-001: learning loop done file is created with UTC timestamp" {
    run bash -lc "cd '$TEST_TMPDIR' && scripts/gates/mark_no_learning.sh cmd_999"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[mark_no_learning] Created:"* ]]
    [ -f "$TEST_TMPDIR/queue/gates/cmd_999/learning_loop.done" ]
    run cat "$TEST_TMPDIR/queue/gates/cmd_999/learning_loop.done"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no_friction_no_workaround"* ]]
    [[ "$output" =~ timestamp:\ [0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "MNL-002: invalid cmd id fails" {
    run bash -lc "cd '$TEST_TMPDIR' && scripts/gates/mark_no_learning.sh 999"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cmd_id must be cmd_XXX format"* ]]
}
