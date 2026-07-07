#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPT="$PROJECT_ROOT/scripts/lib/extract_command_files.sh"
    [ -f "$SCRIPT" ] || return 1
}

@test "readonly source followed by content operation is excluded with debug trace" {
    local cmd="docs/source.mdから必要な数値を算出して報告に追加する"

    run env EXTRACT_COMMAND_FILES_DEBUG=1 bash "$SCRIPT" \
        --command-text "$cmd" \
        --repo "$PROJECT_ROOT" \
        --files-modified ""

    [ "$status" -eq 0 ]
    [[ "$output" == *"DEBUG: source.md"* ]]
    [[ "$output" == *"content_op_after_read=True"* || "$output" == *"content_op_after_read=true"* ]]
    [[ "$output" == *"READONLY_EXCLUDED: source.md"* ]]
    [[ "$output" != *"WARN:"* ]]
}

@test "write reference detection still reports missing modified file" {
    local cmd="scripts/lib/extract_command_files.shに判定改善を追加する"

    run bash "$SCRIPT" \
        --command-text "$cmd" \
        --repo "$PROJECT_ROOT" \
        --files-modified $'tests/unit/test_extract_command_files.bats'

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: extract_command_files.sh"* ]]
}

@test "write reference detection passes when files_modified contains basename" {
    local cmd="scripts/lib/extract_command_files.shに判定改善を追加する"

    run bash "$SCRIPT" \
        --command-text "$cmd" \
        --repo "$PROJECT_ROOT" \
        --files-modified $'scripts/lib/extract_command_files.sh'

    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"WARN:"* ]]
}
