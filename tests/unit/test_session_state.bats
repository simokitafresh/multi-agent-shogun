#!/usr/bin/env bats
# test_session_state.bats — GP-198: session_state記録+previous_failures注入テスト
# AC1: gate FAIL時にtask YAMLのsession_stateに失敗情報を記録
# AC2: 再配備時にsession_stateからprevious_failuresを自動注入

GATE="scripts/gates/gate_report_format.sh"
REPO_TMPDIR=""
TASK_TMPDIR=""

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/deploy_task.sh"
    [ -f "$SRC_DEPLOY_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    export SESSION_STATE_HELPERS="$BATS_FILE_TMPDIR/session_state_helpers.bash"
    sed -n '/^inject_session_state_hints()/,/^}/p' "$SRC_DEPLOY_SCRIPT" > "$SESSION_STATE_HELPERS"
}

setup() {
    source "$SESSION_STATE_HELPERS"
    # /tmp/回避: gate_report_format.shの/tmp/早期exitガードを避けるためtests/配下に作成
    REPO_TMPDIR="$(mktemp -d "tests/.tmp_session_state.XXXXXX")"
    TASK_TMPDIR="$(mktemp -d "tests/.tmp_session_state_task.XXXXXX")"
    export GATE_PASS_CACHE_FILE="$REPO_TMPDIR/.gate_pass_cache"
    export GATE_FIRE_LOG_FILE="$REPO_TMPDIR/gate_fire_log.yaml"
    export GATE_SESSION_STATE_TASK_DIR="$TASK_TMPDIR"
    export GATE_SESSION_STATE_TEST=1
    export SKILL_GATE_FEEDBACK_DISABLE=1
    export GATE_CLARITY_WARN_DISABLE=1
}

teardown() {
    rm -rf "$REPO_TMPDIR" "$TASK_TMPDIR"
    unset GATE_PASS_CACHE_FILE GATE_FIRE_LOG_FILE GATE_SESSION_STATE_TASK_DIR
    unset GATE_SESSION_STATE_TEST SKILL_GATE_FEEDBACK_DISABLE GATE_CLARITY_WARN_DISABLE
    unset _DEPLOY_PREV_SESSION_STATE
}

# ─── ヘルパー ───

# 最小限のFAILレポートを作成（verdict空 + binary_checks未記入）
create_fail_report() {
    local path="$1"
    cat > "$path" << 'YAML'
worker_id: kagemaru
parent_cmd: cmd_test
result:
  summary: "report summary text"
diagnose_reason: "report diagnose text"
ac_version_read: abc12345
status: pending
binary_checks:
  AC1:
  - check: "テスト確認"
    result: ""
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: ""
lessons_useful: []
verdict: ""
YAML
}

# 最小限のtask YAMLを作成
create_task_yaml() {
    local path="$1"
    cat > "$path" << 'YAML'
task:
  parent_cmd: cmd_test
  task_id: cmd_test_impl
  status: assigned
  worker_id: kagemaru
YAML
}

# ─── AC1: gate FAIL → session_state記録 ───

@test "T-SS-001: gate FAIL時にtask YAMLのsession_stateが記録される" {
    local task_yaml="$TASK_TMPDIR/kagemaru.yaml"
    create_task_yaml "$task_yaml"

    # report pathはtests/.tmp*配下(非/tmp/)でkagemaru_report_{cmd}.yaml形式
    local report="$REPO_TMPDIR/kagemaru_report_cmd_test.yaml"
    create_fail_report "$report"

    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]

    # session_stateが書き込まれたことを確認
    run grep -q "session_state" "$task_yaml"
    [ "$status" -eq 0 ]

    # last_block_reasonが存在することを確認
    run grep -q "last_block_reason" "$task_yaml"
    [ "$status" -eq 0 ]

    # attempt: 1 であることを確認
    run grep -q "attempt: 1" "$task_yaml"
    [ "$status" -eq 0 ]
}

@test "T-SS-002: 2回目のFAIL時にattemptがインクリメントされる" {
    local task_yaml="$TASK_TMPDIR/kagemaru.yaml"
    # 既存のsession_state(attempt: 1)を持つtask YAMLを作成
    cat > "$task_yaml" << 'YAML'
task:
  parent_cmd: cmd_test
  task_id: cmd_test_impl
  status: assigned
  worker_id: kagemaru
  session_state:
    attempt: 1
    last_block_reason: 'previous error'
    tried_approaches:
    - 'previous error'
YAML

    local report="$REPO_TMPDIR/kagemaru_report_cmd_test.yaml"
    create_fail_report "$report"

    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]

    # attempt: 2 になっていることを確認
    run grep -q "attempt: 2" "$task_yaml"
    [ "$status" -eq 0 ]
}

@test "T-SS-002b: diagnose_reason, approach_summary, prior_attempts[] が記録される" {
    local task_yaml="$TASK_TMPDIR/kagemaru.yaml"
    create_task_yaml "$task_yaml"

    local report="$REPO_TMPDIR/kagemaru_report_cmd_test.yaml"
    create_fail_report "$report"

    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]

    run grep -q "diagnose_reason: 'report diagnose text'" "$task_yaml"
    [ "$status" -eq 0 ]

    run grep -q "approach_summary: 'report summary text'" "$task_yaml"
    [ "$status" -eq 0 ]

    run grep -q "prior_attempts:" "$task_yaml"
    [ "$status" -eq 0 ]
}

@test "T-SS-002c: prior_attempts は最大3件保持" {
    local task_yaml="$TASK_TMPDIR/kagemaru.yaml"
    cat > "$task_yaml" << 'YAML'
task:
  parent_cmd: cmd_test
  task_id: cmd_test_impl
  status: assigned
  worker_id: kagemaru
  session_state:
    attempt: 3
    last_block_reason: 'reason3'
    tried_approaches:
    - 'reason1'
    - 'reason2'
    - 'reason3'
    prior_attempts:
    - attempt: 1
      block_reason: 'reason1'
      diagnose_reason: 'diag1'
      approach_summary: 'sum1'
    - attempt: 2
      block_reason: 'reason2'
      diagnose_reason: 'diag2'
      approach_summary: 'sum2'
    - attempt: 3
      block_reason: 'reason3'
      diagnose_reason: 'diag3'
      approach_summary: 'sum3'
YAML

    local report="$REPO_TMPDIR/kagemaru_report_cmd_test.yaml"
    create_fail_report "$report"

    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]

    run grep -c "block_reason:" "$task_yaml"
    # last_block_reason + prior_attempts 3 entries = 4
    [ "$status" -eq 0 ]
    [ "$output" -eq 4 ]
    run grep -q "block_reason: 'reason1'" "$task_yaml"
    [ "$status" -eq 1 ]
}

@test "T-SS-003: 有効な忍者名でないreportはtask YAMLを変更しない" {
    local task_yaml="$TASK_TMPDIR/invalid.yaml"
    create_task_yaml "$task_yaml"

    # 有効でない名前のreport
    local report="$REPO_TMPDIR/unknown_report_cmd_test.yaml"
    create_fail_report "$report"

    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]

    # task YAMLが変更されていないことを確認（session_stateなし）
    run grep -q "session_state" "$task_yaml"
    [ "$status" -eq 1 ]
}

# ─── AC2: deploy時にsession_stateからprevious_failuresを注入 ───

@test "T-SS-004: inject_session_state_hints がprevious_failuresを注入する" {
    local task_yaml="$TASK_TMPDIR/sasuke.yaml"

    # 簡単なtask YAMLを作成
    cat > "$task_yaml" << 'YAML'
task:
  parent_cmd: cmd_test
  task_id: cmd_test_impl
  status: assigned
  worker_id: sasuke
YAML

    # _DEPLOY_PREV_SESSION_STATEをセットしてinject_session_state_hintsを呼ぶ
    (
        export _DEPLOY_PREV_SESSION_STATE='{"attempt": 2, "last_block_reason": "binary_checks FAIL", "tried_approaches": ["binary_checks FAIL"], "diagnose_reason": "diag text", "approach_summary": "summary text", "prior_attempts": [{"attempt": 1, "block_reason": "older fail", "diagnose_reason": "older diag", "approach_summary": "older summary"}, {"attempt": 2, "block_reason": "binary_checks FAIL", "diagnose_reason": "diag text", "approach_summary": "summary text"}]}'
        inject_session_state_hints "$task_yaml"
    )

    # previous_failuresが書き込まれたことを確認
    run grep -q "previous_failures" "$task_yaml"
    [ "$status" -eq 0 ]

    run grep -q "attempt: 2" "$task_yaml"
    [ "$status" -eq 0 ]

    run grep -q "last_block_reason" "$task_yaml"
    [ "$status" -eq 0 ]

    run grep -q "diagnose_reason: 'diag text'" "$task_yaml"
    [ "$status" -eq 0 ]

    run grep -q "approach_summary: 'summary text'" "$task_yaml"
    [ "$status" -eq 0 ]

    run grep -q "prior_attempts:" "$task_yaml"
    [ "$status" -eq 0 ]
}

@test "T-SS-004b: inject_session_state_hints は multiline の diagnose/summary を1行へ構造化する" {
    local task_yaml="$TASK_TMPDIR/sasuke_multiline.yaml"
    cat > "$task_yaml" << 'YAML'
task:
  parent_cmd: cmd_test
  task_id: cmd_test_impl
  status: assigned
  worker_id: sasuke
YAML

    (
        export _DEPLOY_PREV_SESSION_STATE='{"attempt": 2, "last_block_reason": "binary_checks FAIL\nsame failure", "tried_approaches": ["binary_checks FAIL\nsame failure"], "diagnose_reason": "diag line1\nline2", "approach_summary": "summary line1\nline2", "prior_attempts": [{"attempt": 1, "block_reason": "older fail\nagain", "diagnose_reason": "older diag\nmore", "approach_summary": "older summary\nmore"}]}'
        inject_session_state_hints "$task_yaml"
    )

    run grep -q "last_block_reason: 'binary_checks FAIL same failure'" "$task_yaml"
    [ "$status" -eq 0 ]

    run grep -q "diagnose_reason: 'diag line1 line2'" "$task_yaml"
    [ "$status" -eq 0 ]

    run grep -q "approach_summary: 'summary line1 line2'" "$task_yaml"
    [ "$status" -eq 0 ]

    run grep -q "block_reason: 'older fail again'" "$task_yaml"
    [ "$status" -eq 0 ]

    run grep -q "diagnose_reason: 'older diag more'" "$task_yaml"
    [ "$status" -eq 0 ]
}

@test "T-SS-005: _DEPLOY_PREV_SESSION_STATEが空の場合はprevious_failuresを注入しない" {
    local task_yaml="$TASK_TMPDIR/sasuke.yaml"
    cat > "$task_yaml" << 'YAML'
task:
  parent_cmd: cmd_test
  task_id: cmd_test_impl
  status: assigned
  worker_id: sasuke
YAML

    (
        export _DEPLOY_PREV_SESSION_STATE=""
        inject_session_state_hints "$task_yaml"
    )

    # previous_failuresが存在しないことを確認
    run grep -q "previous_failures" "$task_yaml"
    [ "$status" -eq 1 ]
}
