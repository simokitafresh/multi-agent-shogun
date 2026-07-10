#!/usr/bin/env bats
# test_cmd_quality_log.bats — cmd_quality_log idempotency tests

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_quality_log.XXXXXX")"
    export CMD_QUALITY_LOG_FILE="$TEST_TMPDIR/cmd_design_quality.yaml"
    export CMD_QUALITY_FAST_METADATA=1
    export MEMORY_DB_LIVE_INSERT="$TEST_TMPDIR/missing_memory_db_live_insert.py"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

count_entries() {
    grep -c '^- cmd_id:' "$CMD_QUALITY_LOG_FILE"
}

@test "cmd_quality_log skips duplicate CLEAR for same cmd and source" {
    run bash "$PROJECT_ROOT/scripts/cmd_quality_log.sh" cmd_quality_dup CLEAR no 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Logged: cmd_quality_dup"* ]]

    run bash "$PROJECT_ROOT/scripts/cmd_quality_log.sh" cmd_quality_dup CLEAR no 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP duplicate CLEAR: cmd_quality_dup"* ]]
    [ "$(count_entries)" -eq 1 ]
}

@test "cmd_quality_log keeps non-CLEAR retry history" {
    run bash "$PROJECT_ROOT/scripts/cmd_quality_log.sh" cmd_quality_retry BLOCK no 0 first_reason
    [ "$status" -eq 0 ]

    run bash "$PROJECT_ROOT/scripts/cmd_quality_log.sh" cmd_quality_retry BLOCK no 0 second_reason
    [ "$status" -eq 0 ]
    [ "$(count_entries)" -eq 2 ]
}

@test "cmd_quality_log uses the hot log's lock path shared with rotation" {
    run bash -c '
        source="$1"
        log="$2"
        grep -Fq "LOCK_FILE=\"\${LOG_FILE}.lock\"" "$source" && \
        [ "$log.lock" = "${log}.lock" ]
    ' _ "$PROJECT_ROOT/scripts/cmd_quality_log.sh" "$CMD_QUALITY_LOG_FILE"
    [ "$status" -eq 0 ]
}

@test "quality-log rotation aborts instead of applying a five-entry trim" {
    mkdir -p "$TEST_TMPDIR/logs" "$TEST_TMPDIR/config"
    cat > "$TEST_TMPDIR/config/yaml_auto_archive.tsv" <<'EOF'
logs/cmd_design_quality.yaml	5	entries	^\s*-\s+cmd_id:	logs/archive/cmd_design_quality.yaml
EOF
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: cmd_one
- cmd_id: cmd_two
- cmd_id: cmd_three
EOF

    run env SHOGUN_ROOT="$TEST_TMPDIR" \
        YAML_AUTO_ARCHIVE_CONFIG="$TEST_TMPDIR/config/yaml_auto_archive.tsv" \
        bash "$PROJECT_ROOT/scripts/yaml_auto_archive.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ALERT logs/cmd_design_quality.yaml"* ]]
    [ "$(grep -c '^- cmd_id:' "$TEST_TMPDIR/logs/cmd_design_quality.yaml")" -eq 3 ]
    [ ! -e "$TEST_TMPDIR/logs/archive/cmd_design_quality.yaml" ]
}
