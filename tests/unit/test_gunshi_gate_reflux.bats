#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export REFLUX_SCRIPT="$PROJECT_ROOT/scripts/gunshi_gate_reflux.sh"
    export LOCK_PATH_SCRIPT="$PROJECT_ROOT/scripts/lib/lock_path.sh"

    [ -f "$REFLUX_SCRIPT" ] || return 1
    [ -f "$LOCK_PATH_SCRIPT" ] || return 1
}

setup() {
    TEST_TMP="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_TMP/scripts/lib" "$TEST_TMP/logs"
    cp "$REFLUX_SCRIPT" "$TEST_TMP/scripts/gunshi_gate_reflux.sh"
    cp "$LOCK_PATH_SCRIPT" "$TEST_TMP/scripts/lib/lock_path.sh"
}

@test "updates all matching null gate_result entries under lock" {
    cat > "$TEST_TMP/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_100
  review_type: draft
  gate_result: null
- cmd_id: cmd_100
  review_type: report
  gate_result: null
- cmd_id: cmd_200
  review_type: report
  gate_result: null
YAML

    run bash "$TEST_TMP/scripts/gunshi_gate_reflux.sh" cmd_100 CLEAR

    [ "$status" -eq 0 ]
    [[ "$output" == *"2 entries updated"* ]]
    [ "$(grep -c 'gate_result: CLEAR' "$TEST_TMP/logs/gunshi_review_log.yaml")" -eq 2 ]
    [ "$(grep -A2 'cmd_200' "$TEST_TMP/logs/gunshi_review_log.yaml" | grep -c 'gate_result: null')" -eq 1 ]
}

@test "matches quoted cmd_id literally when id contains regex metacharacters" {
    cat > "$TEST_TMP/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: "cmd_1.2"
  gate_result: null
- cmd_id: cmd_1x2
  gate_result: null
YAML

    run bash "$TEST_TMP/scripts/gunshi_gate_reflux.sh" "cmd_1.2" BLOCK

    [ "$status" -eq 0 ]
    [ "$(grep -c 'gate_result: BLOCK' "$TEST_TMP/logs/gunshi_review_log.yaml")" -eq 1 ]
    [ "$(grep -A1 'cmd_1x2' "$TEST_TMP/logs/gunshi_review_log.yaml" | grep -c 'gate_result: null')" -eq 1 ]
}

@test "rejects invalid gate_result before writing log" {
    cat > "$TEST_TMP/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_300
  gate_result: null
YAML

    run bash "$TEST_TMP/scripts/gunshi_gate_reflux.sh" cmd_300 "CLEAR # injected"

    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid gate_result"* ]]
    [ "$(grep -c 'gate_result: null' "$TEST_TMP/logs/gunshi_review_log.yaml")" -eq 1 ]
}
