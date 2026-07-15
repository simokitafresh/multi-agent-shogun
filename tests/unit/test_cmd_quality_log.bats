#!/usr/bin/env bats
# test_cmd_quality_log.bats — cmd_quality_log idempotency tests

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_quality_log.XXXXXX")"
    export CMD_QUALITY_LOG_FILE="$TEST_TMPDIR/cmd_design_quality.yaml"
    export CMD_QUALITY_FAST_METADATA=1
    export MEMORY_DB_LIVE_INSERT="$TEST_TMPDIR/missing_memory_db_live_insert.py"
}

setup_ac_fixtures() {
    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports"
    export CMD_QUALITY_COMMAND_FILE="$TEST_TMPDIR/queue/shogun_to_karo.yaml"
    export CMD_QUALITY_TASKS_DIR="$TEST_TMPDIR/queue/tasks"
    export CMD_QUALITY_REPORTS_DIR="$TEST_TMPDIR/queue/reports"
    unset CMD_QUALITY_FAST_METADATA
    printf 'commands: {}\n' > "$CMD_QUALITY_COMMAND_FILE"
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

@test "cmd_quality_log monotonically upgrades duplicate CLEAR rework no to yes" {
    run bash "$PROJECT_ROOT/scripts/cmd_quality_log.sh" cmd_quality_upgrade CLEAR no 0
    [ "$status" -eq 0 ]

    run bash "$PROJECT_ROOT/scripts/cmd_quality_log.sh" cmd_quality_upgrade CLEAR yes 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"UPGRADED rework no->yes"* ]]
    [ "$(count_entries)" -eq 1 ]
    grep -A4 'cmd_id: "cmd_quality_upgrade"' "$CMD_QUALITY_LOG_FILE" | grep -q 'karo_rework: "yes"'

    run bash "$PROJECT_ROOT/scripts/cmd_quality_log.sh" cmd_quality_upgrade CLEAR no 0
    [ "$status" -eq 0 ]
    [ "$(count_entries)" -eq 1 ]
    grep -A4 'cmd_id: "cmd_quality_upgrade"' "$CMD_QUALITY_LOG_FILE" | grep -q 'karo_rework: "yes"'
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

@test "cmd_save custom quality-log override cannot rotate repository operational log" {
    grep -Fq 'if [[ "$QUALITY_LOG_FILE" == "$PROJECT_DIR/logs/cmd_design_quality.yaml" ]]; then' \
        "$PROJECT_ROOT/scripts/cmd_save.sh"
}

@test "direct task AC count falls back to unique parent_cmd task" {
    setup_ac_fixtures
    cat > "$CMD_QUALITY_TASKS_DIR/saizo.yaml" <<'EOF'
task:
  parent_cmd: cmd_karo_hotfix_dm_signal_core_freshness_202607120345
  acceptance_criteria: {AC1: {}, AC2: {}, AC3: {}, AC4: {}, AC5: {}, AC6: {}}
EOF
    run bash "$PROJECT_ROOT/scripts/cmd_quality_log.sh" cmd_karo_hotfix_dm_signal_core_freshness_202607120345 PASS no 0
    [ "$status" -eq 0 ]
    grep -q 'ac_count: 6' "$CMD_QUALITY_LOG_FILE"
}

@test "normal command authoritative AC count remains three" {
    setup_ac_fixtures
    cat > "$CMD_QUALITY_COMMAND_FILE" <<'EOF'
cmd_3857:
  acceptance_criteria: [one, two, three]
EOF
    run bash "$PROJECT_ROOT/scripts/cmd_quality_log.sh" cmd_3857 PASS no 0
    [ "$status" -eq 0 ]
    grep -q 'ac_count: 3' "$CMD_QUALITY_LOG_FILE"
}

@test "ambiguous tasks fail closed with diagnostic" {
    setup_ac_fixtures
    for name in a b; do
      printf 'task:\n  parent_cmd: cmd_direct\n  acceptance_criteria: {AC1: {}}\n' > "$CMD_QUALITY_TASKS_DIR/$name.yaml"
    done
    run bash "$PROJECT_ROOT/scripts/cmd_quality_log.sh" cmd_direct PASS no 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"ambiguous tasks"* ]]
    grep -q 'ac_count: 0' "$CMD_QUALITY_LOG_FILE"
}

@test "malformed task is diagnosed and unique report fallback excludes commit" {
    setup_ac_fixtures
    printf 'task: [broken\n' > "$CMD_QUALITY_TASKS_DIR/broken.yaml"
    cat > "$CMD_QUALITY_REPORTS_DIR/worker.yaml" <<'EOF'
parent_cmd: cmd_report_only
binary_checks: {AC1: {}, AC2: {}, commit: {}}
EOF
    run bash "$PROJECT_ROOT/scripts/cmd_quality_log.sh" cmd_report_only PASS no 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"unreadable YAML"* ]]
    grep -q 'ac_count: 2' "$CMD_QUALITY_LOG_FILE"
}
