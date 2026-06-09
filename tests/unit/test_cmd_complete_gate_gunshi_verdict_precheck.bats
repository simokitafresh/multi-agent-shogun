#!/usr/bin/env bats
# test_cmd_complete_gate_gunshi_verdict_precheck.bats
# cmd_3248: GATE判定前の軍師verdict WARN表示テスト
# テスト対象: cmd_complete_gate.sh内のgunshi verdict pre-check Pythonロジック

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    # Extract the Python script from cmd_complete_gate.sh
    export GV_PRECHECK_PY="$BATS_FILE_TMPDIR/gv_precheck.py"
    sed -n "/^END_GV_PRECHECK_PY$/q;/^import sys, re, os, glob$/,\$p" "$SRC_GATE_SCRIPT" > "$GV_PRECHECK_PY"
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gv_precheck.XXXXXX")"
    export REVIEW_LOG="$TEST_TMPDIR/gunshi_review_log.yaml"
    export ARCHIVE_DIR="$TEST_TMPDIR/archive"
    mkdir -p "$ARCHIVE_DIR"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# ─── AC1: cmd_complete_gate.shがGATE実行時にgunshi_review_logから該当cmd_idのverdictを取得している ───

@test "AC1: verdict LGTM の場合はOKを返す" {
    cat > "$REVIEW_LOG" <<'EOF'
- cmd_id: cmd_100
  review_type: report
  verdict: LGTM
  findings_summary: "全AC確認OK"
EOF
    run python3 "$GV_PRECHECK_PY" cmd_100 "$REVIEW_LOG" "$ARCHIVE_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
}

@test "AC1: verdict APPROVE の場合はOKを返す" {
    cat > "$REVIEW_LOG" <<'EOF'
- cmd_id: cmd_101
  review_type: draft
  verdict: APPROVE
  findings_summary: "設計OK"
EOF
    run python3 "$GV_PRECHECK_PY" cmd_101 "$REVIEW_LOG" "$ARCHIVE_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
}

@test "AC1: 該当cmd_idが存在しない場合はOKを返す" {
    cat > "$REVIEW_LOG" <<'EOF'
- cmd_id: cmd_200
  review_type: report
  verdict: LGTM
  findings_summary: "別cmd"
EOF
    run python3 "$GV_PRECHECK_PY" cmd_999 "$REVIEW_LOG" "$ARCHIVE_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
}

# ─── AC2: verdict=FAILまたはREQUEST_CHANGESの場合にWARN+findings_summaryが自動表示されている ───

@test "AC2: verdict FAIL の場合はWARN+findings_summaryを返す" {
    cat > "$REVIEW_LOG" <<'EOF'
- cmd_id: cmd_300
  review_type: report
  verdict: FAIL
  findings_summary: "binary_checks AC2 result:no"
EOF
    run python3 "$GV_PRECHECK_PY" cmd_300 "$REVIEW_LOG" "$ARCHIVE_DIR"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "WARN" ]]
    [[ "${lines[1]}" == *"verdict=FAIL"* ]]
    [[ "${lines[1]}" == *"binary_checks AC2 result:no"* ]]
}

@test "AC2: verdict REQUEST_CHANGES の場合はWARN+findings_summaryを返す" {
    cat > "$REVIEW_LOG" <<'EOF'
- cmd_id: cmd_301
  review_type: draft
  verdict: REQUEST_CHANGES
  findings_summary: "assumptions.claimが事実誤認"
EOF
    run python3 "$GV_PRECHECK_PY" cmd_301 "$REVIEW_LOG" "$ARCHIVE_DIR"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "WARN" ]]
    [[ "${lines[1]}" == *"verdict=REQUEST_CHANGES"* ]]
    [[ "${lines[1]}" == *"assumptions.claimが事実誤認"* ]]
}

@test "AC2: review_type が表示される" {
    cat > "$REVIEW_LOG" <<'EOF'
- cmd_id: cmd_302
  review_type: draft
  verdict: REQUEST_CHANGES
  findings_summary: "問題あり"
EOF
    run python3 "$GV_PRECHECK_PY" cmd_302 "$REVIEW_LOG" "$ARCHIVE_DIR"
    [ "$status" -eq 0 ]
    [[ "${lines[1]}" == *"[draft]"* ]]
}

@test "AC2: 複数のFAILエントリがある場合に全て表示される" {
    cat > "$REVIEW_LOG" <<'EOF'
- cmd_id: cmd_303
  review_type: draft
  verdict: REQUEST_CHANGES
  findings_summary: "claim誤認"
- cmd_id: cmd_303
  review_type: report
  verdict: FAIL
  findings_summary: "bc:no検出"
EOF
    run python3 "$GV_PRECHECK_PY" cmd_303 "$REVIEW_LOG" "$ARCHIVE_DIR"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "WARN" ]]
    [[ "${lines[1]}" == *"REQUEST_CHANGES"* ]]
    [[ "${lines[2]}" == *"FAIL"* ]]
}

# ─── AC2: self_study/consultationは対象外 ───

@test "AC2: self_study verdictは対象外" {
    cat > "$REVIEW_LOG" <<'EOF'
- cmd_id: cmd_304
  review_type: self_study
  findings_summary: "自己学習でFAIL分析"
  verdict: FAIL
EOF
    run python3 "$GV_PRECHECK_PY" cmd_304 "$REVIEW_LOG" "$ARCHIVE_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
}

@test "AC2: consultation verdictは対象外" {
    cat > "$REVIEW_LOG" <<'EOF'
- cmd_id: cmd_305
  review_type: consultation
  findings_summary: "相談結果"
  verdict: FAIL
EOF
    run python3 "$GV_PRECHECK_PY" cmd_305 "$REVIEW_LOG" "$ARCHIVE_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
}

# ─── AC3: archiveからも検索される ───

@test "AC3: archiveのみにFAILがある場合もWARNを返す" {
    # メインログには別cmd
    cat > "$REVIEW_LOG" <<'EOF'
- cmd_id: cmd_400
  review_type: report
  verdict: LGTM
  findings_summary: "別cmd"
EOF
    # archiveにFAILあり
    cat > "$ARCHIVE_DIR/gunshi_review_log_archive1.yaml" <<'EOF'
- cmd_id: cmd_401
  review_type: report
  verdict: FAIL
  findings_summary: "archive内のFAIL"
EOF
    run python3 "$GV_PRECHECK_PY" cmd_401 "$REVIEW_LOG" "$ARCHIVE_DIR"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "WARN" ]]
    [[ "${lines[1]}" == *"FAIL"* ]]
    [[ "${lines[1]}" == *"archive内のFAIL"* ]]
}

@test "AC3: findings_summaryがない場合はフォールバックメッセージ" {
    cat > "$REVIEW_LOG" <<'EOF'
- cmd_id: cmd_402
  review_type: report
  verdict: FAIL
  observations:
    - "観察のみ"
EOF
    run python3 "$GV_PRECHECK_PY" cmd_402 "$REVIEW_LOG" "$ARCHIVE_DIR"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "WARN" ]]
    [[ "${lines[1]}" == *"findings_summary not found"* ]]
}

@test "AC3: review_logが空の場合はOKを返す" {
    : > "$REVIEW_LOG"
    run python3 "$GV_PRECHECK_PY" cmd_500 "$REVIEW_LOG" "$ARCHIVE_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
}
