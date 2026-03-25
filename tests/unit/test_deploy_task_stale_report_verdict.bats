#!/usr/bin/env bats
# test_deploy_task_stale_report_verdict.bats - stale report archive verdict protection
# cmd_1382: verdict=PASS/FAILの報告はアーカイブされない
# cmd_cycle_001: 他忍者の報告は絶対にアーカイブされない

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
# cmd_cycle_001: 他忍者の報告は無条件保護。配備対象の忍者報告のみアーカイブ対象。
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
            # 自分の報告はスキップ（下のown-reportブロックで処理）
            if [[ "$stale_basename" == "${ninja_name}_report_"* ]]; then
                continue
            fi
            # 他忍者の報告: 無条件で保護
            log "report_template: PROTECTED other ninja report (${stale_basename})"
        done
    fi
}

# ─── Helper: own stale report archive logic extracted from deploy_task.sh ───
run_own_stale_archive() {
    local SCRIPT_DIR="$TEST_TMPDIR"
    local ninja_name="$1"
    local parent_cmd="$2"
    local report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report_${parent_cmd}.yaml"
    local log_file="$SCRIPT_DIR/logs/stale_archive_test.log"

    log() { echo "$*" >> "$log_file"; }

    local stale_own_basename stale_own_pcmd stale_own_verdict
    for stale_own_report in "$SCRIPT_DIR/queue/reports/${ninja_name}_report_"*.yaml; do
        [ -f "$stale_own_report" ] || continue
        stale_own_basename=$(basename "$stale_own_report")
        # 今回のターゲット報告はスキップ
        if [[ "$stale_own_report" == "$report_file" ]]; then
            continue
        fi
        # 既存報告のparent_cmdを取得
        stale_own_pcmd=$(FIELD_GET_NO_LOG=1 field_get "$stale_own_report" "parent_cmd" "")
        # parent_cmdが同じならスキップ（同cmdの報告）
        if [[ "$stale_own_pcmd" == "$parent_cmd" ]]; then
            continue
        fi
        # 別cmdの報告: verdict確認
        stale_own_verdict=$(FIELD_GET_NO_LOG=1 field_get "$stale_own_report" "verdict" "")
        if [[ -n "$stale_own_verdict" && "$stale_own_verdict" != "null" && "$stale_own_verdict" != '""' ]]; then
            log "report_template: completed own report preserved (${stale_own_basename}, verdict=${stale_own_verdict})"
            continue
        fi
        # verdict空のテンプレート → staleアーカイブ
        mkdir -p "$SCRIPT_DIR/archive/reports/stale"
        mv "$stale_own_report" "$SCRIPT_DIR/archive/reports/stale/"
        log "report_template: stale own report archived (${stale_own_basename}, old_cmd=${stale_own_pcmd})"
    done
}

# ═══════════════════════════════════════════════════════════
# 他忍者の報告保護テスト
# ═══════════════════════════════════════════════════════════

# ─── 他忍者のverdict=PASS報告は保護される ───
@test "other ninja report with verdict=PASS is PROTECTED" {
    cat > "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_999.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_999
verdict: PASS
result:
  summary: "test completed"
EOF

    run_stale_archive hayate cmd_999

    [ -f "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_999.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/sasuke_report_cmd_999.yaml" ]
}

# ─── 他忍者のverdict=FAIL報告も保護される ───
@test "other ninja report with verdict=FAIL is PROTECTED" {
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

# ─── 他忍者のverdict=FILL_THIS報告も保護される(cmd_cycle_001) ───
@test "other ninja report with verdict=FILL_THIS is PROTECTED" {
    cat > "$TEST_TMPDIR/queue/reports/saizo_report_cmd_999.yaml" <<'EOF'
worker_id: saizo
parent_cmd: cmd_999
verdict: FILL_THIS
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_999

    # 他忍者の報告は無条件保護
    [ -f "$TEST_TMPDIR/queue/reports/saizo_report_cmd_999.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/saizo_report_cmd_999.yaml" ]
}

# ─── 他忍者のverdict空報告も保護される(cmd_cycle_001) ───
@test "other ninja report with empty verdict is PROTECTED" {
    cat > "$TEST_TMPDIR/queue/reports/kotaro_report_cmd_999.yaml" <<'EOF'
worker_id: kotaro
parent_cmd: cmd_999
verdict: ""
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_999

    [ -f "$TEST_TMPDIR/queue/reports/kotaro_report_cmd_999.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/kotaro_report_cmd_999.yaml" ]
}

# ─── 他忍者のverdictフィールド無し報告も保護される(cmd_cycle_001) ───
@test "other ninja report without verdict field is PROTECTED" {
    cat > "$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_999

    [ -f "$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/tobisaru_report_cmd_999.yaml" ]
}

# ─── PROTECTEDログが出力される(cmd_cycle_001) ───
@test "PROTECTED log message is output for other ninja reports" {
    cat > "$TEST_TMPDIR/queue/reports/kagemaru_report_cmd_999.yaml" <<'EOF'
worker_id: kagemaru
parent_cmd: cmd_999
verdict: ""
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_999

    local log_file="$TEST_TMPDIR/logs/stale_archive_test.log"
    [ -f "$log_file" ]
    grep -q "PROTECTED other ninja report (kagemaru_report_cmd_999.yaml)" "$log_file"
}

# ═══════════════════════════════════════════════════════════
# 自分の報告スキップテスト
# ═══════════════════════════════════════════════════════════

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

    [ -f "$TEST_TMPDIR/queue/reports/hayate_report_cmd_999.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/hayate_report_cmd_999.yaml" ]
}

# ═══════════════════════════════════════════════════════════
# 自分のstale report(別cmd)アーカイブテスト
# ═══════════════════════════════════════════════════════════

# ─── 自分のstale報告(verdict空)はアーカイブされる ───
@test "own stale report with empty verdict is archived" {
    cat > "$TEST_TMPDIR/queue/reports/hayate_report_cmd_777.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_777
verdict: ""
result:
  summary: ""
EOF

    run_own_stale_archive hayate cmd_999

    [ ! -f "$TEST_TMPDIR/queue/reports/hayate_report_cmd_777.yaml" ]
    [ -f "$TEST_TMPDIR/archive/reports/stale/hayate_report_cmd_777.yaml" ]
}

# ─── 自分の完了済み報告(verdict=PASS)は保護される ───
@test "own completed report with verdict=PASS is preserved" {
    cat > "$TEST_TMPDIR/queue/reports/hayate_report_cmd_777.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_777
verdict: PASS
result:
  summary: "completed"
EOF

    run_own_stale_archive hayate cmd_999

    [ -f "$TEST_TMPDIR/queue/reports/hayate_report_cmd_777.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/stale/hayate_report_cmd_777.yaml" ]
}

# ─── 自分の完了済み報告(verdict=done)は保護される ───
@test "own completed report with verdict=done is preserved" {
    cat > "$TEST_TMPDIR/queue/reports/hayate_report_cmd_777.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_777
verdict: done
result:
  summary: "completed"
EOF

    run_own_stale_archive hayate cmd_999

    [ -f "$TEST_TMPDIR/queue/reports/hayate_report_cmd_777.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/stale/hayate_report_cmd_777.yaml" ]
}

# ═══════════════════════════════════════════════════════════
# 複合テスト
# ═══════════════════════════════════════════════════════════

# ─── 複合: 他忍者は全員保護+自分のstaleのみアーカイブ ───
@test "compound: all other ninja reports PROTECTED, own stale archived" {
    # 他忍者PASS report
    cat > "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_888.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_888
verdict: PASS
result:
  summary: "completed"
EOF

    # 他忍者FAIL report
    cat > "$TEST_TMPDIR/queue/reports/hanzo_report_cmd_888.yaml" <<'EOF'
worker_id: hanzo
parent_cmd: cmd_888
verdict: FAIL
result:
  summary: "failed"
EOF

    # 他忍者FILL_THIS template
    cat > "$TEST_TMPDIR/queue/reports/saizo_report_cmd_888.yaml" <<'EOF'
worker_id: saizo
parent_cmd: cmd_888
verdict: FILL_THIS
result:
  summary: ""
EOF

    # 他忍者empty verdict template
    cat > "$TEST_TMPDIR/queue/reports/kotaro_report_cmd_888.yaml" <<'EOF'
worker_id: kotaro
parent_cmd: cmd_888
verdict: ""
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_888

    # 他忍者は全員保護
    [ -f "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_888.yaml" ]
    [ -f "$TEST_TMPDIR/queue/reports/hanzo_report_cmd_888.yaml" ]
    [ -f "$TEST_TMPDIR/queue/reports/saizo_report_cmd_888.yaml" ]
    [ -f "$TEST_TMPDIR/queue/reports/kotaro_report_cmd_888.yaml" ]
    # アーカイブに移動された報告はゼロ
    [ ! -f "$TEST_TMPDIR/archive/reports/saizo_report_cmd_888.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/kotaro_report_cmd_888.yaml" ]
}
