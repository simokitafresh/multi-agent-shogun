#!/usr/bin/env bats
# test_deploy_task_stale_report_verdict.bats - cmd_1382: stale report archive verdict protection
# AC1: verdict=PASS/FAILの報告はアーカイブされない
# AC2: verdict=FILL_THIS/未設定/空の報告は従来通りアーカイブされる

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_FIELD_GET_SCRIPT="$PROJECT_ROOT/scripts/lib/field_get.sh"
    [ -f "$SRC_FIELD_GET_SCRIPT" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/stale_verdict.XXXXXX")"

    mkdir -p "$TEST_TMPDIR/queue/reports" "$TEST_TMPDIR/archive/reports" "$TEST_TMPDIR/logs"

    # source field_get
    source "$SRC_FIELD_GET_SCRIPT"
    export FIELD_GET_NO_LOG=1
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# ─── Helper: stale report archive logic extracted from deploy_task.sh ───
run_stale_archive() {
    local SCRIPT_DIR="$TEST_TMPDIR"
    local ninja_name="$1"
    local parent_cmd="$2"
    local log_file="$SCRIPT_DIR/logs/stale_archive_test.log"

    log() { echo "$*" >> "$log_file"; }

    if [[ -n "$parent_cmd" && "$parent_cmd" == cmd_* ]]; then
        local stale_basename
        for stale_report in "$SCRIPT_DIR/queue/reports/"*"_report_${parent_cmd}.yaml"; do
            [ -f "$stale_report" ] || continue
            stale_basename=$(basename "$stale_report")
            # 自分の報告はスキップ
            if [[ "$stale_basename" == "${ninja_name}_report_"* ]]; then
                continue
            fi
            # cmd_1382: 完了済み報告(verdict=PASS/FAIL)はアーカイブしない
            local stale_verdict
            stale_verdict=$(FIELD_GET_NO_LOG=1 field_get "$stale_report" "verdict" "")
            if [[ "$stale_verdict" == "PASS" || "$stale_verdict" == "FAIL" ]]; then
                log "report_template: completed report preserved (${stale_basename}, verdict=${stale_verdict})"
                continue
            fi
            mkdir -p "$SCRIPT_DIR/archive/reports"
            mv "$stale_report" "$SCRIPT_DIR/archive/reports/"
            log "report_template: stale report archived (${stale_basename})"
        done
    fi
}

# ─── AC1: verdict=PASSの報告は保護される ───
@test "stale archive skips report with verdict=PASS" {
    cat > "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_999.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_999
verdict: PASS
result:
  summary: "test completed"
EOF

    run_stale_archive hayate cmd_999

    # sasuke's PASS report should still be in queue/reports
    [ -f "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_999.yaml" ]
    # should NOT be in archive
    [ ! -f "$TEST_TMPDIR/archive/reports/sasuke_report_cmd_999.yaml" ]
}

# ─── AC1: verdict=FAILの報告も保護される ───
@test "stale archive skips report with verdict=FAIL" {
    cat > "$TEST_TMPDIR/queue/reports/hanzo_report_cmd_999.yaml" <<'EOF'
worker_id: hanzo
parent_cmd: cmd_999
verdict: FAIL
result:
  summary: "test failed"
EOF

    run_stale_archive hayate cmd_999

    [ -f "$TEST_TMPDIR/queue/reports/hanzo_report_cmd_999.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/hanzo_report_cmd_999.yaml" ]
}

# ─── AC2: verdict=FILL_THISの報告はアーカイブされる ───
@test "stale archive moves report with verdict=FILL_THIS" {
    cat > "$TEST_TMPDIR/queue/reports/saizo_report_cmd_999.yaml" <<'EOF'
worker_id: saizo
parent_cmd: cmd_999
verdict: FILL_THIS
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_999

    [ ! -f "$TEST_TMPDIR/queue/reports/saizo_report_cmd_999.yaml" ]
    [ -f "$TEST_TMPDIR/archive/reports/saizo_report_cmd_999.yaml" ]
}

# ─── AC2: verdictフィールドが空の報告はアーカイブされる ───
@test "stale archive moves report with empty verdict" {
    cat > "$TEST_TMPDIR/queue/reports/kotaro_report_cmd_999.yaml" <<'EOF'
worker_id: kotaro
parent_cmd: cmd_999
verdict: ""
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_999

    [ ! -f "$TEST_TMPDIR/queue/reports/kotaro_report_cmd_999.yaml" ]
    [ -f "$TEST_TMPDIR/archive/reports/kotaro_report_cmd_999.yaml" ]
}

# ─── AC2: verdictフィールドが存在しない報告はアーカイブされる ───
@test "stale archive moves report without verdict field" {
    cat > "$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_999

    [ ! -f "$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml" ]
    [ -f "$TEST_TMPDIR/archive/reports/tobisaru_report_cmd_999.yaml" ]
}

# ─── 複合テスト: PASS/FAIL保護+テンプレートアーカイブの同時動作 ───
@test "stale archive preserves completed reports and archives templates in same cmd" {
    # PASS report
    cat > "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_888.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_888
verdict: PASS
result:
  summary: "completed"
EOF

    # FAIL report
    cat > "$TEST_TMPDIR/queue/reports/hanzo_report_cmd_888.yaml" <<'EOF'
worker_id: hanzo
parent_cmd: cmd_888
verdict: FAIL
result:
  summary: "failed"
EOF

    # FILL_THIS template
    cat > "$TEST_TMPDIR/queue/reports/saizo_report_cmd_888.yaml" <<'EOF'
worker_id: saizo
parent_cmd: cmd_888
verdict: FILL_THIS
result:
  summary: ""
EOF

    # Empty verdict template
    cat > "$TEST_TMPDIR/queue/reports/kotaro_report_cmd_888.yaml" <<'EOF'
worker_id: kotaro
parent_cmd: cmd_888
verdict: ""
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_888

    # PASS/FAIL preserved
    [ -f "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_888.yaml" ]
    [ -f "$TEST_TMPDIR/queue/reports/hanzo_report_cmd_888.yaml" ]
    # Templates archived
    [ ! -f "$TEST_TMPDIR/queue/reports/saizo_report_cmd_888.yaml" ]
    [ -f "$TEST_TMPDIR/archive/reports/saizo_report_cmd_888.yaml" ]
    [ ! -f "$TEST_TMPDIR/queue/reports/kotaro_report_cmd_888.yaml" ]
    [ -f "$TEST_TMPDIR/archive/reports/kotaro_report_cmd_888.yaml" ]
}

# ─── 自分の報告はスキップされる（既存動作の保持） ───
@test "stale archive skips own report regardless of verdict" {
    cat > "$TEST_TMPDIR/queue/reports/hayate_report_cmd_999.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_999
verdict: FILL_THIS
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_999

    # Own report should remain untouched
    [ -f "$TEST_TMPDIR/queue/reports/hayate_report_cmd_999.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/hayate_report_cmd_999.yaml" ]
}
