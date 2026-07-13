#!/usr/bin/env bats
# cmd_karo_hotfix_ninja_wa_denominator_root_202607131915
# 忍者別WA率の分母(一次ソース=terminal task/report)修正の8パターンfixture。
# AC1: 分母消失(clean→ninja:system偏在)の再現+修正確認
# AC2: 一次分母(report_ninja)取得+同一cmd重複WA排除+report/task不在の active未解消WAはfail-closed算入
# AC3: 配備前BLOCK等worker未着手WAはexecutor exposureとして分離、責任率へ算入しない
# AC4: 8パターンを表形式fixtureで固定

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMP
    TEST_TMP="$(mktemp -d)"
    mkdir -p "$TEST_TMP/scripts/gates" "$TEST_TMP/logs" "$TEST_TMP/queue/reports/archive"
    cp "$PROJECT_ROOT/scripts/gates/gate_ninja_workaround_rate.sh" "$TEST_TMP/scripts/gates/"
    chmod +x "$TEST_TMP/scripts/gates/gate_ninja_workaround_rate.sh"
    rm -f /tmp/shogun_wa_rate_cache_* /tmp/shogun_wa_report_index_*
}

teardown() {
    rm -rf "$TEST_TMP"
    rm -f /tmp/shogun_wa_rate_cache_* /tmp/shogun_wa_report_index_*
}

mk_report() {
    local dir="$1" worker="$2" cmd="$3" status="${4:-completed}"
    cat > "$dir/${worker}_report_${cmd}.yaml" <<EOF
worker_id: ${worker}
parent_cmd: ${cmd}
status: ${status}
EOF
}

@test "P1: AC1 denominator-vanishing repro - 10 clean(system-attributed)+2 WA now rates 2/12 not 3/3=100%" {
    {
        for i in $(seq 1 10); do
            cat <<YAML
- cmd_id: cmd_p1_${i}
  timestamp: '2026-07-13T09:00:0${i}Z'
  ninja: system
  workaround: false
  event_kind: hotfix
  auto_captured: true
  category: rework_auto_capture
  detail: 'cmd_complete_gate completed rework event'
  root_cause: 'automatic completion observation'
  resolved_by_cmd: ''
YAML
        done
        cat <<'YAML'
- cmd_id: cmd_p1_wa1
  timestamp: '2026-07-13T09:20:00Z'
  ninja: hanzo
  workaround: true
  category: gate_logic_gap
  detail: 'gate logic gap fixture'
  root_cause: 'fixture'
  resolved_by_cmd: ''
- cmd_id: cmd_p1_wa2
  timestamp: '2026-07-13T09:21:00Z'
  ninja: hanzo
  workaround: true
  category: gate_logic_gap
  detail: 'gate logic gap fixture2'
  root_cause: 'fixture'
  resolved_by_cmd: ''
YAML
    } > "$TEST_TMP/logs/karo_workarounds.yaml"

    for i in $(seq 1 10); do
        mk_report "$TEST_TMP/queue/reports" hanzo "cmd_p1_${i}" completed
    done
    mk_report "$TEST_TMP/queue/reports" hanzo cmd_p1_wa1 completed
    mk_report "$TEST_TMP/queue/reports" hanzo cmd_p1_wa2 completed

    run bash "$TEST_TMP/scripts/gates/gate_ninja_workaround_rate.sh" --ninja hanzo --last 30

    [ "$status" -eq 0 ]
    [[ "$output" == *"担当件数: 12  WA件数: 2  WA率: 16.7%"* ]]
    [[ "$output" != *"WA率: 100"* ]]
}

@test "P2: system-attributed clean entries never leak as a nameable 'system'/'unknown' row" {
    cat > "$TEST_TMP/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_p2_1
  ninja: system
  workaround: false
  event_kind: hotfix
  auto_captured: true
  category: rework_auto_capture
  detail: 'cmd_complete_gate completed rework event'
  root_cause: 'automatic completion observation'
- cmd_id: cmd_p2_2
  ninja: system
  workaround: false
  event_kind: hotfix
  auto_captured: true
  category: rework_auto_capture
  detail: 'cmd_complete_gate completed rework event'
  root_cause: 'automatic completion observation'
YAML
    # このPJに人間の報告が一切無い(真にシステム専用cmd) -> 誰の分母にも算入されない

    run bash "$TEST_TMP/scripts/gates/gate_ninja_workaround_rate.sh" --quiet --last 30

    [ "$status" -eq 0 ]
    [[ "$output" == *"忍者別workaround(WAログ直近2件): 全員clean"* ]]
    [[ "$output" != *"system"* ]]
    [[ "$output" != *"unknown"* ]]
}

@test "P3: duplicate WA log entries for the same cmd_id dedupe to 1 in the numerator" {
    cat > "$TEST_TMP/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_p3_dup
  timestamp: '2026-07-13T09:00:00Z'
  ninja: kotaro
  workaround: true
  category: commit_missing
  detail: 'dup entry 1'
  root_cause: 'fixture'
  resolved_by_cmd: ''
- cmd_id: cmd_p3_dup
  timestamp: '2026-07-13T09:05:00Z'
  ninja: kotaro
  workaround: true
  category: commit_missing
  detail: 'dup entry 2 (same cmd, logged twice)'
  root_cause: 'fixture'
  resolved_by_cmd: ''
YAML
    mk_report "$TEST_TMP/queue/reports" kotaro cmd_p3_dup completed
    mk_report "$TEST_TMP/queue/reports" kotaro cmd_p3_clean_a completed
    mk_report "$TEST_TMP/queue/reports" kotaro cmd_p3_clean_b completed

    run bash "$TEST_TMP/scripts/gates/gate_ninja_workaround_rate.sh" --ninja kotaro --last 30

    [ "$status" -eq 0 ]
    [[ "$output" == *"担当件数: 3  WA件数: 1  WA率: 33.3%"* ]]
}

@test "P4: report archive move / duplicate main+archive copies do not inflate the denominator" {
    mk_report "$TEST_TMP/queue/reports/archive" saizo cmd_p4_archived_only completed
    mk_report "$TEST_TMP/queue/reports" saizo cmd_p4_both_copies completed
    mk_report "$TEST_TMP/queue/reports/archive" saizo cmd_p4_both_copies completed
    cat > "$TEST_TMP/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_p4_wa
  timestamp: '2026-07-13T09:00:00Z'
  ninja: saizo
  workaround: true
  category: gate_logic_gap
  detail: 'fixture wa'
  root_cause: 'fixture'
  resolved_by_cmd: ''
YAML

    run bash "$TEST_TMP/scripts/gates/gate_ninja_workaround_rate.sh" --ninja saizo --last 30

    [ "$status" -eq 0 ]
    [[ "$output" == *"担当件数: 3  WA件数: 1  WA率: 33.3%"* ]]
}

@test "P5: resolved WA (failed then RC-fixed, same cmd terminal report) counts as clean, not WA" {
    mk_report "$TEST_TMP/queue/reports" hayate cmd_p5_rc_final completed
    cat > "$TEST_TMP/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_p5_rc_final
  timestamp: '2026-07-13T09:00:00Z'
  ninja: hayate
  workaround: true
  category: report_yaml_format
  detail: 'initial failure, later fixed'
  root_cause: 'fixture'
  resolved_by_cmd: cmd_p5_fix
YAML

    run bash "$TEST_TMP/scripts/gates/gate_ninja_workaround_rate.sh" --ninja hayate --last 30

    [ "$status" -eq 0 ]
    [[ "$output" == *"担当件数: 1  WA件数: 0  WA率: 0.0%"* ]]
    [[ "$output" == *"workaroundなし: clean"* ]]
}

@test "P6: active unresolved WA with no matching report is fail-closed counted into both numerator and denominator" {
    mk_report "$TEST_TMP/queue/reports" kotaro cmd_p6_ok_1 completed
    mk_report "$TEST_TMP/queue/reports" kotaro cmd_p6_ok_2 completed
    cat > "$TEST_TMP/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_p6_inflight
  timestamp: '2026-07-13T09:00:00Z'
  ninja: kotaro
  workaround: true
  category: agent_stall_recovery
  detail: 'still in progress, no report filed yet'
  root_cause: 'fixture'
  resolved_by_cmd: ''
YAML

    run bash "$TEST_TMP/scripts/gates/gate_ninja_workaround_rate.sh" --ninja kotaro --last 30

    [ "$status" -eq 0 ]
    [[ "$output" == *"担当件数: 3  WA件数: 1  WA率: 33.3%"* ]]
}

@test "P7: AC3 pre-execution BLOCK with no backing report is excluded as executor exposure, not counted in rate" {
    mk_report "$TEST_TMP/queue/reports" hanzo cmd_p7_ok_1 completed
    mk_report "$TEST_TMP/queue/reports" hanzo cmd_p7_ok_2 completed
    cat > "$TEST_TMP/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_p7_never_started
  timestamp: '2026-07-13T09:00:00Z'
  ninja: hanzo
  workaround: true
  category: deploy_contract
  detail: 'karo_direct配備YAMLの自然境界契約不足で初回BLOCK、workerは未着手'
  root_cause: 'estimated_minutesと構造化split_decisionを追加し再配備'
  resolved_by_cmd: ''
YAML

    run bash "$TEST_TMP/scripts/gates/gate_ninja_workaround_rate.sh" --ninja hanzo --last 30

    [ "$status" -eq 0 ]
    [[ "$output" == *"担当件数: 2  WA件数: 0  WA率: 0.0%"* ]]
    [[ "$output" == *"除外(pre-execution/未着手, 忍者責任率対象外): 1件"* ]]
}

@test "P8: exposure-only ninja is excluded from ALERT ranking while a genuine high-rate ninja still ALERTs" {
    mk_report "$TEST_TMP/queue/reports" saizo cmd_p8_saizo_ok_1 completed
    mk_report "$TEST_TMP/queue/reports" saizo cmd_p8_saizo_ok_2 completed
    mk_report "$TEST_TMP/queue/reports" hanzo cmd_p8_hanzo_clean_1 completed
    cat > "$TEST_TMP/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_p8_saizo_never_started
  timestamp: '2026-07-13T09:00:00Z'
  ninja: saizo
  workaround: true
  category: deploy_contract
  detail: '配備前BLOCKでworker未着手'
  root_cause: 'fixture'
  resolved_by_cmd: ''
- cmd_id: cmd_p8_hanzo_wa1
  timestamp: '2026-07-13T09:10:00Z'
  ninja: hanzo
  workaround: true
  category: gate_logic_gap
  detail: 'real wa 1'
  root_cause: 'fixture'
  resolved_by_cmd: ''
- cmd_id: cmd_p8_hanzo_wa2
  timestamp: '2026-07-13T09:11:00Z'
  ninja: hanzo
  workaround: true
  category: gate_logic_gap
  detail: 'real wa 2'
  root_cause: 'fixture'
  resolved_by_cmd: ''
YAML

    run bash "$TEST_TMP/scripts/gates/gate_ninja_workaround_rate.sh" --quiet --last 30

    [ "$status" -eq 0 ]
    [[ "$output" == *"忍者別workaround(WAログ直近3件): hanzo:2/3"* ]]
    [[ "$output" == *"ALERT: WA率50%超 — hanzo(67%)"* ]]
    [[ "$output" == *"除外(pre-execution/未着手, 忍者責任率対象外) — saizo(1)"* ]]
}
