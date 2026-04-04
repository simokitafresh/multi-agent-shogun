#!/usr/bin/env bats
# test_cmd_save_param_space_against_results.bats
# cmd_1738: 前段results.yaml config と後段command記載値の突合

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    local _start _call _end
    _start=$(grep -n '^check_param_space_against_results() {' "$SRC_SAVE_SCRIPT" | head -1 | cut -d: -f1)
    _call=$(grep -n '^check_param_space_against_results$' "$SRC_SAVE_SCRIPT" | head -1 | cut -d: -f1)
    _end=$((_call - 1))
    eval "$(sed -n "${_start},${_end}p" "$SRC_SAVE_SCRIPT")"
    export -f check_param_space_against_results
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d)"
    export PROJECT_DIR="${TEST_TMPDIR}/repo"
    export TEST_PROJECT_PATH="${TEST_TMPDIR}/dm-signal"
    mkdir -p "${PROJECT_DIR}/projects" "${TEST_PROJECT_PATH}/outputs/analysis/alm_research"

    cat > "${PROJECT_DIR}/projects/dm-signal.yaml" <<YAML
project:
  id: dm-signal
  path: "${TEST_PROJECT_PATH}"
YAML

    cat > "${TEST_PROJECT_PATH}/outputs/analysis/alm_research/cmd_1736_results.yaml" <<'YAML'
cmd_id: cmd_1736
config:
  lookbacks:
  - 1
  - 2
  - 3
  - 4
  - 5
  - 6
  top_ns:
  - 1
  - 2
  - 3
  rolling_windows:
  - 12
  - 24
  - 36
YAML

    export CMD_ID="cmd_1738"
    export CMD_BLOCK=""
    export CMD_BLOCK_NC=""
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

_set_cmd_block() {
    CMD_BLOCK="$1"
    CMD_BLOCK_NC="$1"
    export CMD_BLOCK CMD_BLOCK_NC
}

@test "subset: lookbacks が前段より狭い → BLOCK" {
    _set_cmd_block $'    project: dm-signal\n    command: |\n      cmd_1736を参照し、lookbacks=[1,3,6] で再検証する'
    run check_param_space_against_results
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK: 前段cmdのパラメータ空間を縮小しています"* ]]
    [[ "$output" == *"lookbacks"* ]]
}

@test "equal: top_n が前段と同一範囲 → PASS" {
    _set_cmd_block $'    project: dm-signal\n    command: |\n      cmd_1736を参照し、top_n=1-3 で全件再確認する'
    run check_param_space_against_results
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK"* ]]
}

@test "superset: rolling_window を拡張 → PASS" {
    _set_cmd_block $'    project: dm-signal\n    command: |\n      cmd_1736を参照し、rolling_window=[12,24,36,48] で比較する'
    run check_param_space_against_results
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK"* ]]
}

@test "missing results: 前段results.yaml不在 → SKIP" {
    _set_cmd_block $'    project: dm-signal\n    command: |\n      cmd_1999を参照し、lookbacks=[1,3,6] で再検証する'
    run check_param_space_against_results
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK"* ]]
}
