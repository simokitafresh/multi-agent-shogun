#!/usr/bin/env bats
# test_cmd_save_prev_cmd_gate.bats — Check 1.6: 前回PASS済みcmd pending昇格チェック
# AC2: 前回cmdがpending未昇格ならBLOCK
# AC3: 前回cmdがpending昇格済みなら正常PASS

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    # helper関数を抽出
    eval "$(sed -n '/^record_block_reason()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^abort_if_block_immediate()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f record_block_reason abort_if_block_immediate

    # check_prev_cmd_pending: Check 1.6インラインセクションを関数化
    eval "check_prev_cmd_pending() {
$(sed -n '/^# --- Check 1.6:/,/^# --- Check 2:/{/^# --- Check 2:/d;p}' "$SRC_SAVE_SCRIPT")
}"
    export -f check_prev_cmd_pending
}

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
    export QUEUE_FILE="$TEST_TMPDIR/shogun_to_karo.yaml"
    export CMD_SAVE_LAST_CMD_FILE="$TEST_TMPDIR/cmd_save_last_cmd.txt"
    export CMD_SAVE_ACCUMULATE_BLOCKS=0
    export BLOCK_COUNT=0
    declare -ga BLOCK_REASONS=()
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ヘルパー: QUEUE_FILEに前回cmdと新cmdを作成
write_queue_with_prev() {
    local prev_status="${1:-pending}"
    cat > "$QUEUE_FILE" <<YAML
commands:
  cmd_prev:
    status: ${prev_status}
  cmd_new:
    status: pending
YAML
}

# --- AC2: 前回cmdがpendingのままBLOCK ---

@test "AC2: 前回cmdがpendingのままBLOCK" {
    write_queue_with_prev "pending"
    echo "cmd_prev" > "$CMD_SAVE_LAST_CMD_FILE"
    CMD_ID="cmd_new"
    export CMD_ID BLOCK_COUNT

    run check_prev_cmd_pending
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"前回PASS済み cmd_prev"* ]]
    [[ "$output" == *"pending"* ]]
}

# --- AC3: 前回cmdがdelegated昇格済みならPASS ---

@test "AC3: 前回cmdがdelegated済みならPASS" {
    write_queue_with_prev "delegated"
    echo "cmd_prev" > "$CMD_SAVE_LAST_CMD_FILE"
    CMD_ID="cmd_new"
    export CMD_ID BLOCK_COUNT

    run check_prev_cmd_pending
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK"* ]]
}

@test "AC3補: 前回cmdがin_progress昇格済みならPASS" {
    write_queue_with_prev "in_progress"
    echo "cmd_prev" > "$CMD_SAVE_LAST_CMD_FILE"
    CMD_ID="cmd_new"
    export CMD_ID BLOCK_COUNT

    run check_prev_cmd_pending
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK"* ]]
}

# --- 追加ケース ---

@test "状態ファイルなし: 初回実行はスキップ" {
    write_queue_with_prev "pending"
    # CMD_SAVE_LAST_CMD_FILEを作成しない
    CMD_ID="cmd_new"
    export CMD_ID BLOCK_COUNT

    run check_prev_cmd_pending
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK"* ]]
}

@test "同じcmd_idの再保存は許可" {
    write_queue_with_prev "pending"
    echo "cmd_prev" > "$CMD_SAVE_LAST_CMD_FILE"
    # 前回と同じcmd_idを保存しようとする場合はスキップ
    CMD_ID="cmd_prev"
    export CMD_ID BLOCK_COUNT

    run check_prev_cmd_pending
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK"* ]]
}

@test "前回cmdがQUEUEにない(archive済み)はPASS" {
    # cmd_prev がQUEUEに存在しない場合 = archive済み = 昇格済みとみなす
    cat > "$QUEUE_FILE" <<YAML
commands:
  cmd_new:
    status: pending
YAML
    echo "cmd_prev" > "$CMD_SAVE_LAST_CMD_FILE"
    CMD_ID="cmd_new"
    export CMD_ID BLOCK_COUNT

    run check_prev_cmd_pending
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK"* ]]
}

@test "非数字cmd境界: 次cmdのstatusを誤読せずPASS" {
    cat > "$QUEUE_FILE" <<YAML
commands:
  cmd_prev:
    title: "status未記入の前回cmd"
  cmd_training_next:
    status: pending
YAML
    echo "cmd_prev" > "$CMD_SAVE_LAST_CMD_FILE"
    CMD_ID="cmd_new"
    export CMD_ID BLOCK_COUNT

    run check_prev_cmd_pending
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK"* ]]
}
