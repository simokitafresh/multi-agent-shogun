#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMP
    TEST_TMP="$(mktemp -d)"
    mkdir -p "$TEST_TMP/scripts/gates" "$TEST_TMP/logs"
    cp "$PROJECT_ROOT/scripts/gates/gate_workaround_rate.sh" "$TEST_TMP/scripts/gates/"
    chmod +x "$TEST_TMP/scripts/gates/gate_workaround_rate.sh"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "gate_workaround_rate: gate_metrics denominator is explicit in header" {
    cat > "$TEST_TMP/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_1
  category: report_yaml_format
  workaround: true
- cmd_id: cmd_2
  category: clean
  workaround: false
YAML
    cat > "$TEST_TMP/logs/gate_metrics.log" <<'LOG'
2026-07-05T10:00:00	cmd_1	CLEAR	all_gates_passed	full	unknown	unknown	none
2026-07-05T10:01:00	cmd_2	CLEAR	all_gates_passed	full	unknown	unknown	none
LOG

    run bash "$TEST_TMP/scripts/gates/gate_workaround_rate.sh" --last 2

    [ "$status" -eq 0 ]
    [[ "$output" == *"■ Workaround率 (GATE CLEAR直近2cmd)"* ]]
    [[ "$output" == *"WA率: 50% (1/2件) — ALERT"* ]]
}

@test "gate_workaround_rate: fallback denominator is explicit in header" {
    cat > "$TEST_TMP/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_1
  category: report_yaml_format
  workaround: true
- cmd_id: cmd_2
  category: clean
  workaround: false
YAML

    run bash "$TEST_TMP/scripts/gates/gate_workaround_rate.sh" --last 2

    [ "$status" -eq 0 ]
    [[ "$output" == *"■ Workaround率 (WAログ直近2件)"* ]]
    [[ "$output" == *"gate_metrics.log不在のためkaro_workaroundsエントリ数をフォールバック分母に使用"* ]]
}
