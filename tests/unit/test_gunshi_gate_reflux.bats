#!/usr/bin/env bats
# test_gunshi_gate_reflux.bats — GATE CLEAR時の軍師review_log gate_result同期

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export REFLUX_SCRIPT="$PROJECT_ROOT/scripts/gunshi_gate_reflux.sh"
    [ -f "$REFLUX_SCRIPT" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gunshi_reflux.XXXXXX")"
    export REVIEW_LOG="$TEST_TMPDIR/gunshi_review_log.yaml"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "updates gate_result null for all matching cmd entries" {
    cat > "$REVIEW_LOG" <<'YAML'
- cmd_id: cmd_100
  review_type: draft
  gate_result: null
  verdict: APPROVE
- cmd_id: cmd_100
  review_type: report
  gate_result: null
  verdict: LGTM
YAML

    run env GUNSHI_REVIEW_LOG="$REVIEW_LOG" bash "$REFLUX_SCRIPT" cmd_100 CLEAR
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 entries updated"* ]]
    [ "$(grep -c 'gate_result: CLEAR' "$REVIEW_LOG")" -eq 2 ]
    ! grep -q 'gate_result: null' "$REVIEW_LOG"
}

@test "inserts missing gate_result after review_type for matching cmd entry" {
    cat > "$REVIEW_LOG" <<'YAML'
- cmd_id: cmd_200
  review_type: report
  verdict: LGTM
  findings_summary: "ok"
YAML

    run env GUNSHI_REVIEW_LOG="$REVIEW_LOG" bash "$REFLUX_SCRIPT" cmd_200 CLEAR
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 entries updated"* ]]
    grep -A2 'review_type: report' "$REVIEW_LOG" | grep -q 'gate_result: CLEAR'
}

@test "does not overwrite non-null gate_result" {
    cat > "$REVIEW_LOG" <<'YAML'
- cmd_id: cmd_300
  review_type: report
  gate_result: BLOCK
  verdict: FAIL
YAML

    run env GUNSHI_REVIEW_LOG="$REVIEW_LOG" bash "$REFLUX_SCRIPT" cmd_300 CLEAR
    [ "$status" -eq 0 ]
    [[ "$output" == "" ]]
    grep -q 'gate_result: BLOCK' "$REVIEW_LOG"
    ! grep -q 'gate_result: CLEAR' "$REVIEW_LOG"
}

@test "leaves other cmd entries untouched" {
    cat > "$REVIEW_LOG" <<'YAML'
- cmd_id: cmd_400
  review_type: report
  gate_result: null
  verdict: LGTM
- cmd_id: cmd_401
  review_type: report
  gate_result: null
  verdict: LGTM
YAML

    run env GUNSHI_REVIEW_LOG="$REVIEW_LOG" bash "$REFLUX_SCRIPT" cmd_400 CLEAR
    [ "$status" -eq 0 ]
    grep -A3 'cmd_400' "$REVIEW_LOG" | grep -q 'gate_result: CLEAR'
    grep -A3 'cmd_401' "$REVIEW_LOG" | grep -q 'gate_result: null'
}

@test "2nd run updates report entry added after 1st run (post-GATE CLEAR scenario)" {
    # GATE CLEAR前: draftエントリのみ存在
    cat > "$REVIEW_LOG" <<'YAML'
- cmd_id: cmd_500
  review_type: draft
  gate_result: null
  verdict: APPROVE
YAML

    # 1回目のreflux（GATE CLEAR通知前に実行）
    run env GUNSHI_REVIEW_LOG="$REVIEW_LOG" bash "$REFLUX_SCRIPT" cmd_500 CLEAR
    [ "$status" -eq 0 ]
    [ "$(grep -c 'gate_result: CLEAR' "$REVIEW_LOG")" -eq 1 ]

    # GATE CLEAR後に軍師がreport reviewを追記（gate_result: null）
    printf -- '- cmd_id: cmd_500\n  review_type: report\n  gate_result: null\n  verdict: LGTM\n' >> "$REVIEW_LOG"

    # 2回目のreflux（GATE CLEAR後の最終ステップ）でreportエントリも更新される
    run env GUNSHI_REVIEW_LOG="$REVIEW_LOG" bash "$REFLUX_SCRIPT" cmd_500 CLEAR
    [ "$status" -eq 0 ]
    [ "$(grep -c 'gate_result: CLEAR' "$REVIEW_LOG")" -eq 2 ]
    ! grep -q 'gate_result: null' "$REVIEW_LOG"
}
