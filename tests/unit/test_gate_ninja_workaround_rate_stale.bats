#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMP
    TEST_TMP="$(mktemp -d)"
    mkdir -p "$TEST_TMP/scripts/gates" "$TEST_TMP/logs"
    cp "$PROJECT_ROOT/scripts/gates/gate_ninja_workaround_rate.sh" "$TEST_TMP/scripts/gates/"
    chmod +x "$TEST_TMP/scripts/gates/gate_ninja_workaround_rate.sh"
    rm -f /tmp/shogun_wa_rate_cache_*
}

teardown() {
    rm -rf "$TEST_TMP"
    rm -f /tmp/shogun_wa_rate_cache_*
}

@test "gate_ninja_workaround_rate: stale ninja WA is excluded from threshold warning when recent window is clean" {
    cat > "$TEST_TMP/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_1
  ninja: hanzo
  category: report_yaml_format
  workaround: true
- cmd_id: cmd_2
  ninja: hanzo
  category: report_yaml_format
  workaround: true
- cmd_id: cmd_3
  ninja: hanzo
  category: clean
  workaround: false
- cmd_id: cmd_4
  ninja: hanzo
  category: clean
  workaround: false
- cmd_id: cmd_5
  ninja: hanzo
  category: clean
  workaround: false
- cmd_id: cmd_6
  ninja: hanzo
  category: clean
  workaround: false
- cmd_id: cmd_7
  ninja: saizo
  category: clean
  workaround: false
- cmd_id: cmd_8
  ninja: saizo
  category: clean
  workaround: false
- cmd_id: cmd_9
  ninja: kotaro
  category: clean
  workaround: false
- cmd_id: cmd_10
  ninja: kotaro
  category: clean
  workaround: false
- cmd_id: cmd_11
  ninja: tobisaru
  category: clean
  workaround: false
- cmd_id: cmd_12
  ninja: tobisaru
  category: clean
  workaround: false
- cmd_id: cmd_13
  ninja: hayate
  category: clean
  workaround: false
- cmd_id: cmd_14
  ninja: hayate
  category: clean
  workaround: false
- cmd_id: cmd_15
  ninja: kagemaru
  category: clean
  workaround: false
- cmd_id: cmd_16
  ninja: kagemaru
  category: clean
  workaround: false
YAML

    run bash "$TEST_TMP/scripts/gates/gate_ninja_workaround_rate.sh" --quiet --last 16

    [ "$status" -eq 0 ]
    [[ "$output" == *"忍者別workaround(直近16件): hanzo:2/6"* ]]
    [[ "$output" != *"WARN: WA率30%超"* ]]
    [[ "$output" == *"OK: stale WA履歴は閾値判定外(直近10件clean) — hanzo(2/6)"* ]]
}

@test "gate_ninja_workaround_rate: recent ninja WA still warns" {
    cat > "$TEST_TMP/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_1
  ninja: hanzo
  category: clean
  workaround: false
- cmd_id: cmd_2
  ninja: hanzo
  category: clean
  workaround: false
- cmd_id: cmd_3
  ninja: hanzo
  category: clean
  workaround: false
- cmd_id: cmd_4
  ninja: hanzo
  category: report_yaml_format
  workaround: true
- cmd_id: cmd_5
  ninja: hanzo
  category: report_yaml_format
  workaround: true
YAML

    run bash "$TEST_TMP/scripts/gates/gate_ninja_workaround_rate.sh" --quiet --last 5

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: WA率30%超 — hanzo(40%)"* ]]
    [[ "$output" != *"stale WA履歴"* ]]
}

@test "gate_ninja_workaround_rate: gate_metrics CLEAR window does not hide recent workaround log entries" {
    cat > "$TEST_TMP/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_old_1
  ninja: hanzo
  category: report_yaml_format
  workaround: true
- cmd_id: cmd_old_2
  ninja: hanzo
  category: report_yaml_format
  workaround: true
- cmd_id: cmd_recent_1
  ninja: hanzo
  category: clean
  workaround: false
- cmd_id: cmd_recent_wa
  ninja: kagemaru
  category: report_yaml_format
  workaround: true
YAML
    cat > "$TEST_TMP/logs/gate_metrics.log" <<'LOG'
2026-06-30T09:00:00	cmd_old_1	CLEAR	all_gates_passed	full	unknown	unknown	none
2026-06-30T09:10:00	cmd_old_2	CLEAR	all_gates_passed	full	unknown	unknown	none
2026-06-30T09:20:00	cmd_recent_1	CLEAR	all_gates_passed	full	unknown	unknown	none
2026-06-30T09:30:00	cmd_recent_2	CLEAR	all_gates_passed	full	unknown	unknown	none
LOG

    run bash "$TEST_TMP/scripts/gates/gate_ninja_workaround_rate.sh" --quiet --last 2

    [ "$status" -eq 0 ]
    [[ "$output" == *"忍者別workaround(直近2件): kagemaru:1/1"* ]]
    [[ "$output" != *"全員clean"* ]]
}

@test "gate_ninja_workaround_rate: --ninja reports direct ninja-field workaround even when cmd is not CLEARed" {
    cat > "$TEST_TMP/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_clean
  ninja: kagemaru
  category: clean
  workaround: false
- cmd_id: cmd_open_wa
  ninja: kagemaru
  category: report_yaml_format
  workaround: true
YAML
    cat > "$TEST_TMP/logs/gate_metrics.log" <<'LOG'
2026-06-30T09:00:00	cmd_clean	CLEAR	all_gates_passed	full	unknown	unknown	none
LOG

    run bash "$TEST_TMP/scripts/gates/gate_ninja_workaround_rate.sh" --ninja kagemaru --last 2

    [ "$status" -eq 0 ]
    [[ "$output" == *"担当件数: 2  WA件数: 1  WA率: 50.0%"* ]]
    [[ "$output" == *"- cmd_open_wa: report_yaml_format"* ]]
    [[ "$output" != *"担当件数: 0"* ]]
    [[ "$output" != *"WARN: WA率30%超"* ]]
}
