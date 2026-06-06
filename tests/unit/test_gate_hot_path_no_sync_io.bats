#!/usr/bin/env bats
# test_gate_hot_path_no_sync_io.bats — unit tests for gate_hot_path_no_sync_io.sh

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE="$PROJECT_ROOT/scripts/gates/gate_hot_path_no_sync_io.sh"
    [ -f "$SRC_GATE" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_DIR
    TEST_DIR="$(mktemp -d "$BATS_TMPDIR/hpnsi.XXXXXX")"
    mkdir -p "$TEST_DIR/scripts/gates"
    export HPNSI_CACHE="$TEST_DIR/gate_hpnsi_cache"
    export TMPDIR="$TEST_DIR"
    cp "$SRC_GATE" "$TEST_DIR/scripts/gates/gate_hot_path_no_sync_io.sh"
}

teardown() {
    [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ] && rm -rf "$TEST_DIR"
}

# Helper: create a clean hot path stub with no violations
_make_clean_stub() {
    local name="$1"
    mkdir -p "$TEST_DIR/$(dirname "$name")"
    printf '#!/usr/bin/env bash\n# clean stub\necho ok\n' > "$TEST_DIR/$name"
}

@test "gate exits 0 when all hot paths are clean stubs" {
    local hot_paths=(
        "scripts/inbox_watcher.sh"
        "scripts/inbox_write.sh"
        "scripts/bulletin_write.sh"
        "scripts/report_field_set.sh"
        "scripts/gates/gate_report_format.sh"
        "scripts/gates/gate_gunshi_report_precheck.sh"
        "scripts/cmd_save.sh"
        "scripts/cmd_complete_gate.sh"
        "scripts/deploy_task.sh"
        "scripts/ninja_monitor.sh"
    )
    for p in "${hot_paths[@]}"; do
        _make_clean_stub "$p"
    done

    run bash "$TEST_DIR/scripts/gates/gate_hot_path_no_sync_io.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: hot paths have no unbounded heavy synchronous I/O"* ]]
}

@test "gate exits 1 and reports BLOCK when hot path calls memory_db_live_insert.py directly" {
    _make_clean_stub "scripts/inbox_write.sh"
    # Add a synchronous call (non-comment)
    printf 'bash scripts/memory_db_live_insert.py "$data"\n' >> "$TEST_DIR/scripts/inbox_write.sh"

    run bash "$TEST_DIR/scripts/gates/gate_hot_path_no_sync_io.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"direct memory_db_live_insert.py in hot path"* ]]
}

@test "gate allows memory_db_live_insert_async.py reference" {
    _make_clean_stub "scripts/inbox_write.sh"
    printf 'bash scripts/memory_db_live_insert_async.py "$data"\n' >> "$TEST_DIR/scripts/inbox_write.sh"

    run bash "$TEST_DIR/scripts/gates/gate_hot_path_no_sync_io.sh"
    [ "$status" -eq 0 ]
}

@test "gate exits 1 when hot path calls git log without timeout" {
    _make_clean_stub "scripts/cmd_save.sh"
    printf 'result=$(git log --oneline -5)\n' >> "$TEST_DIR/scripts/cmd_save.sh"

    run bash "$TEST_DIR/scripts/gates/gate_hot_path_no_sync_io.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"git heavy command without timeout"* ]]
}

@test "gate allows git log with timeout prefix" {
    _make_clean_stub "scripts/cmd_save.sh"
    printf 'result=$(timeout 5 git log --oneline -5)\n' >> "$TEST_DIR/scripts/cmd_save.sh"

    run bash "$TEST_DIR/scripts/gates/gate_hot_path_no_sync_io.sh"
    [ "$status" -eq 0 ]
}

@test "gate skips nonexistent hot paths without error" {
    # Only create one stub; others are absent
    _make_clean_stub "scripts/inbox_watcher.sh"

    run bash "$TEST_DIR/scripts/gates/gate_hot_path_no_sync_io.sh"
    [ "$status" -eq 0 ]
}

@test "gate returns cached result on second call without re-running Python" {
    local hot_paths=(
        "scripts/inbox_watcher.sh"
        "scripts/inbox_write.sh"
        "scripts/bulletin_write.sh"
        "scripts/report_field_set.sh"
        "scripts/gates/gate_report_format.sh"
        "scripts/gates/gate_gunshi_report_precheck.sh"
        "scripts/cmd_save.sh"
        "scripts/cmd_complete_gate.sh"
        "scripts/deploy_task.sh"
        "scripts/ninja_monitor.sh"
    )
    for p in "${hot_paths[@]}"; do
        _make_clean_stub "$p"
    done

    # First call populates cache
    run bash "$TEST_DIR/scripts/gates/gate_hot_path_no_sync_io.sh"
    [ "$status" -eq 0 ]
    [ -f "$HPNSI_CACHE" ]

    # Second call uses cache (same output)
    run bash "$TEST_DIR/scripts/gates/gate_hot_path_no_sync_io.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: hot paths have no unbounded heavy synchronous I/O"* ]]
}

@test "gate cache is invalidated when hot path file is modified" {
    local hot_paths=(
        "scripts/inbox_watcher.sh"
        "scripts/inbox_write.sh"
        "scripts/bulletin_write.sh"
        "scripts/report_field_set.sh"
        "scripts/gates/gate_report_format.sh"
        "scripts/gates/gate_gunshi_report_precheck.sh"
        "scripts/cmd_save.sh"
        "scripts/cmd_complete_gate.sh"
        "scripts/deploy_task.sh"
        "scripts/ninja_monitor.sh"
    )
    for p in "${hot_paths[@]}"; do
        _make_clean_stub "$p"
    done

    # First call: OK, cache written
    run bash "$TEST_DIR/scripts/gates/gate_hot_path_no_sync_io.sh"
    [ "$status" -eq 0 ]

    # Modify a hot path to add a violation (changes mtime)
    sleep 1
    printf 'bash scripts/memory_db_live_insert.py "$data"\n' >> "$TEST_DIR/scripts/inbox_write.sh"
    touch "$TEST_DIR/scripts/inbox_write.sh"  # ensure mtime changes

    # Gate should re-run Python and BLOCK
    run bash "$TEST_DIR/scripts/gates/gate_hot_path_no_sync_io.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
}
