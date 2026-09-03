#!/usr/bin/env bats
# test_necessity: Quality records retain their lock/monotonic contracts and generic rotation cannot evict status-bearing insight work; violation can lose completion quality or pending learning work and is BLOCK.
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

setup_review_fixtures() {
    setup_ac_fixtures
    export CMD_QUALITY_REVIEW_LOG="$TEST_TMPDIR/gunshi_review_log.yaml"
    export CMD_QUALITY_SG7_ROOT="$TEST_TMPDIR/queue/gates"
    mkdir -p "$CMD_QUALITY_SG7_ROOT"
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

@test "all quality-log writers use the same canonical lock identity" {
    run bash -c '
        root="$1"
        source "$root/scripts/lib/lock_path.sh"
        log="$root/logs/cmd_design_quality.yaml"
        canonical="$(lock_path "$log")"
        # The canonical lock may live beside the log on ext4 or under /tmp on DrvFs.
        [[ "$canonical" == "${log}.lock" || "$canonical" == /tmp/shogun_lock_*.lock ]] &&
        grep -Fq '\''LOCK_FILE="$(lock_path "$LOG_FILE")"'\'' "$root/scripts/cmd_quality_log.sh" &&
        grep -Fq '\''exec 201>"$(lock_path "$fp")"'\'' "$root/scripts/yaml_auto_archive.sh" &&
        grep -Fq '\''200>"$(lock_path "$_GV_DQ_FILE")"'\'' "$root/scripts/cmd_complete_gate.sh"
    ' _ "$PROJECT_ROOT"
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

@test "generic rotation refuses the status-bearing insights ledger" {
    mkdir -p "$TEST_TMPDIR/queue" "$TEST_TMPDIR/config"
    cat > "$TEST_TMPDIR/config/yaml_auto_archive.tsv" <<'EOF'
queue/insights.yaml	1	insights	^\s*-\s+id:	queue/archive/insights_archive.yaml
EOF
    cat > "$TEST_TMPDIR/queue/insights.yaml" <<'EOF'
insights:
- id: INS-pending
  status: pending
- id: INS-resolved
  status: resolved
EOF

    run env SHOGUN_ROOT="$TEST_TMPDIR" \
        YAML_AUTO_ARCHIVE_CONFIG="$TEST_TMPDIR/config/yaml_auto_archive.tsv" \
        bash "$PROJECT_ROOT/scripts/yaml_auto_archive.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"generic count rotation forbidden"* ]]
    [ "$(grep -c '^- id:' "$TEST_TMPDIR/queue/insights.yaml")" -eq 2 ]
    [ ! -e "$TEST_TMPDIR/queue/archive/insights_archive.yaml" ]
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

# test_necessity: 同一task_idの再配備後、旧担当をAC母数へ重複算入せず、
# 最新世代だけから品質記録のAC数を確定する不変量を守る。
@test "reassigned duplicate task_id uses newest deployed generation for AC count" {
    setup_ac_fixtures
    cat > "$CMD_QUALITY_TASKS_DIR/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_reassigned
  task_id: cmd_reassigned_full
  deployed_at: '2026-08-03T03:04:56+09:00'
  acceptance_criteria: {AC1: {}}
EOF
    cat > "$CMD_QUALITY_TASKS_DIR/hanzo.yaml" <<'EOF'
task:
  parent_cmd: cmd_reassigned
  task_id: cmd_reassigned_full
  deployed_at: '2026-08-03T03:06:08+09:00'
  acceptance_criteria: {AC1: {}, AC2: {}}
EOF

    run bash "$PROJECT_ROOT/scripts/cmd_quality_log.sh" cmd_reassigned PASS no 0
    [ "$status" -eq 0 ]
    [[ "$output" != *"ambiguous tasks"* ]]
    grep -q 'ac_count: 2' "$CMD_QUALITY_LOG_FILE"
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

@test "gunshi verdict selects latest formal report and validates its SG7 fingerprint" {
    setup_review_fixtures
    cat > "$CMD_QUALITY_REVIEW_LOG" <<'EOF'
- cmd_id: cmd_old_fail_new_lgtm
  review_type: report
  verdict: FAIL
  timestamp: 2026-08-02T13:51:00+09:00
- cmd_id: cmd_old_fail_new_lgtm
  review_type: report
  verdict: LGTM
  timestamp: 2026-08-02T14:05:00+09:00
- cmd_id: cmd_old_lgtm_new_fail
  review_type: report
  verdict: LGTM
  timestamp: 2026-08-02T13:51:00+09:00
- cmd_id: cmd_old_lgtm_new_fail
  review_type: report
  verdict: FAIL
  timestamp: 2026-08-02T14:05:00+09:00
- cmd_id: cmd_draft_and_report
  review_type: draft
  verdict: APPROVE
  timestamp: 2026-08-02T14:06:00+09:00
- cmd_id: cmd_draft_and_report
  review_type: report
  verdict: LGTM
  timestamp: 2026-08-02T14:05:00+09:00
- cmd_id: cmd_single
  review_type: report
  verdict: LGTM
  timestamp: 2026-08-02T14:05:00+09:00
EOF
    mkdir -p "$CMD_QUALITY_SG7_ROOT/cmd_old_fail_new_lgtm"
    cat > "$CMD_QUALITY_SG7_ROOT/cmd_old_fail_new_lgtm/sg7_bundle.json" <<'EOF'
{"review":{"cmd_id":"cmd_old_fail_new_lgtm","report_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","verdict":"APPROVE"}}
EOF

    for spec in \
        cmd_old_fail_new_lgtm:LGTM \
        cmd_old_lgtm_new_fail:FAIL \
        cmd_draft_and_report:LGTM \
        cmd_single:LGTM \
        cmd_no_review:unknown; do
        cmd="${spec%%:*}"
        expected="${spec#*:}"
        run bash "$PROJECT_ROOT/scripts/cmd_quality_log.sh" "$cmd" PASS no 0
        [ "$status" -eq 0 ]
        grep -A8 "cmd_id: \"$cmd\"" "$CMD_QUALITY_LOG_FILE" | grep -q "gunshi_verdict: \"$expected\""
    done
}
