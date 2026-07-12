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

@test "gate_workaround_rate: reports rework capture separately from manual WA rate" {
    cat > "$TEST_TMP/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_karo_hotfix_a
  timestamp: '2026-07-12T00:01:00Z'
  category: rework_auto_capture
  workaround: false
  event_kind: hotfix
  auto_captured: true
- cmd_id: cmd_manual
  category: report_yaml_format
  workaround: true
  event_kind: manual_wa
  auto_captured: false
YAML
    git -C "$TEST_TMP" init -q
    git -C "$TEST_TMP" config user.email test@example.com
    git -C "$TEST_TMP" config user.name test
    touch "$TEST_TMP/fixture"
    git -C "$TEST_TMP" add fixture
    git -C "$TEST_TMP" commit -qm "cmd_karo_hotfix_a"

    run env REWORK_CAPTURE_GIT_DIR="$TEST_TMP" REWORK_CAPTURE_SINCE="2000-01-01" \
        bash "$TEST_TMP/scripts/gates/gate_workaround_rate.sh" --last 2

    [ "$status" -eq 0 ]
    [[ "$output" == *"WA率: 50% (1/2件)"* ]]
    [[ "$output" == *"手戻り捕捉率: 100% (1/1件; auto_captured/eligible_rework_commits)"* ]]
}

@test "gate_workaround_rate: capture numerator uses the same since window as eligible commits" {
    cat > "$TEST_TMP/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_karo_hotfix_previous_day
  timestamp: '2026-07-11T23:59:59Z'
  category: rework_auto_capture
  workaround: false
  event_kind: hotfix
  auto_captured: true
- cmd_id: cmd_karo_hotfix_today
  timestamp: '2026-07-12T00:01:00Z'
  category: rework_auto_capture
  workaround: false
  event_kind: hotfix
  auto_captured: true
YAML
    git -C "$TEST_TMP" init -q
    git -C "$TEST_TMP" config user.email test@example.com
    git -C "$TEST_TMP" config user.name test
    touch "$TEST_TMP/fixture"
    git -C "$TEST_TMP" add fixture
    git -C "$TEST_TMP" commit -qm "cmd_karo_hotfix_today"

    run env REWORK_CAPTURE_GIT_DIR="$TEST_TMP" REWORK_CAPTURE_SINCE="2026-07-12T00:00:00Z" \
        bash "$TEST_TMP/scripts/gates/gate_workaround_rate.sh" --last 2

    [ "$status" -eq 0 ]
    [[ "$output" == *"手戻り捕捉率: 100% (1/1件; auto_captured/eligible_rework_commits)"* ]]
    [[ "$output" != *"200%"* ]]
}
