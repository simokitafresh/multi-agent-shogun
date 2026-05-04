#!/usr/bin/env bats
# test_cmd_save_dm_signal_bare_layer_reference.bats — dm-signal raw L0-L4 notation WARN tests

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_save_bare_layer.XXXXXX")"

    cat > "$TEST_TMPDIR/test_func.sh" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
CMD_BLOCK="$1"
CMD_BLOCK_NC=$(echo "$CMD_BLOCK" | grep -v '^\s*#' || true)
CMD_BLOCK_FOUND=1
CMD_BLOCK_CACHE_LOADED=0
declare -A CMD_BLOCK_CACHE=()
WARN_COUNT=0
declare -a WARN_REASONS=()
count_same_warn_pattern() { echo 0; }
WRAPPER

    sed -n '/^trim_inline_yaml_scalar()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^load_cmd_block_cache()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^cmd_block_get_field()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^build_warn_note()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^warn_note_key()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^warn_note_message()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^record_warn_reason()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^check_dm_signal_bare_layer_reference()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    cat >> "$TEST_TMPDIR/test_func.sh" <<'CALL'
check_dm_signal_bare_layer_reference 2>&1
CALL
    chmod +x "$TEST_TMPDIR/test_func.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "BLR-T001: dm-signal cmd with bare L0 emits WARNING" {
    local CMD_BLOCK='    project: dm-signal
    title: "L0表記の確認"
    command: |
      L0を四神として扱う注釈を追加する
    acceptance_criteria:
      - id: AC1
        description: "L0の対応を確認する"'

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"文脈なし生L0-L4"* ]]
    [[ "$output" == *"canonical名"* ]]
}

@test "BLR-T002: canonical names are excluded" {
    local CMD_BLOCK='    project: dm-signal
    title: "canonical表記の確認"
    command: |
      pf_L0/pf_L1/pf_L2 と calc_L1/calc_L2/calc_L3 を明記する
    acceptance_criteria:
      - id: AC1
        description: "canonical名だけを使う"'

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"文脈なし生L0-L4"* ]]
}

@test "BLR-T003: backticks, file paths, and math context are excluded" {
    local CMD_BLOCK='    project: dm-signal
    title: "除外条件の確認"
    command: |
      `L0` はコードスパンなので除外
      context/dm-signal-core.md の L2 はファイルパス同一行なので除外
      L1正則化 と L2 norm は数学文脈なので除外
    acceptance_criteria:
      - id: AC1
        description: "除外条件がWARNしない"'

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"文脈なし生L0-L4"* ]]
}

@test "BLR-T004: non dm-signal project is skipped" {
    local CMD_BLOCK='    project: infra
    title: "infra L0"
    command: |
      L0表記を含むinfra cmd
    acceptance_criteria:
      - id: AC1
        description: "infraは対象外"'

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"文脈なし生L0-L4"* ]]
}
