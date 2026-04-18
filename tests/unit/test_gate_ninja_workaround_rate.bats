#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMP
    TEST_TMP="$(mktemp -d)"
    mkdir -p "${TEST_TMP}/scripts/gates" "${TEST_TMP}/logs"
    cp "$PROJECT_ROOT/scripts/gates/gate_ninja_workaround_rate.sh" "${TEST_TMP}/scripts/gates/"
    chmod +x "${TEST_TMP}/scripts/gates/gate_ninja_workaround_rate.sh"
    rm -f /tmp/shogun_wa_rate_cache_*
}

teardown() {
    rm -rf "$TEST_TMP"
    rm -f /tmp/shogun_wa_rate_cache_*
}

@test "gate_ninja_workaround_rate: quiet summaryとALERTを出す" {
    cat > "${TEST_TMP}/logs/karo_workarounds.yaml" <<'YAML'
- category: clean
  cmd_id: cmd_1
  ninja: saizo
  workaround: false
- category: report_yaml_format
  cmd_id: cmd_2
  ninja: saizo
  workaround: true
- category: clean
  cmd_id: cmd_3
  ninja: hayate
  workaround: false
- category: ci_gate_mismatch
  cmd_id: cmd_4
  ninja: hayate
  workaround: true
- category: ci_gate_mismatch
  cmd_id: cmd_5
  ninja: hayate
  workaround: true
YAML

    run bash "${TEST_TMP}/scripts/gates/gate_ninja_workaround_rate.sh" --quiet --last 5
    [ "$status" -eq 0 ]
    [[ "$output" == *"忍者別workaround(直近5件): hayate:2/3, saizo:1/2"* ]]
    [[ "$output" == *"ALERT: WA率50%超 — hayate(67%)"* ]]
}

@test "gate_ninja_workaround_rate: nested formatでも忍者別詳細を出す" {
    cat > "${TEST_TMP}/logs/karo_workarounds.yaml" <<'YAML'
workarounds:
  - category: report_yaml_format
    cmd_id: cmd_10
    detail: 才蔵報告を家老が補正
    workaround: true
  - category: clean
    cmd_id: cmd_11
    root_cause: 才蔵は問題なし
    workaround: false
YAML

    run bash "${TEST_TMP}/scripts/gates/gate_ninja_workaround_rate.sh" --ninja saizo --last 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"=== saizo workaround履歴 (直近2件中) ==="* ]]
    [[ "$output" == *"担当件数: 2  WA件数: 1  WA率: 50.0%"* ]]
    [[ "$output" == *"- cmd_10: report_yaml_format"* ]]
}
