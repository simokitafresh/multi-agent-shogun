#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/throughput_scan.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
    python3 -c "import yaml" >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/throughput_scan.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/logs" "$TEST_TMPDIR/queue" "$TEST_TMPDIR/scripts/lib"
    echo "insights: []" > "$TEST_TMPDIR/queue/insights.yaml"
    cp "$SRC_SCRIPT" "$TEST_TMPDIR/scripts/throughput_scan.sh"
    chmod +x "$TEST_TMPDIR/scripts/throughput_scan.sh"
    cp "$PROJECT_ROOT/scripts/insight_write.sh" "$TEST_TMPDIR/scripts/insight_write.sh"
    cp "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$TEST_TMPDIR/scripts/lib/yaml_field_set.sh"
    chmod +x "$TEST_TMPDIR/scripts/insight_write.sh"
    export THROUGHPUT_SCAN_ROOT="$TEST_TMPDIR"
}

write_ratchet_baseline() {
    cat > "$TEST_TMPDIR/logs/loop_ledger.yaml" <<'EOF'
snapshots:
- generated_at: "2026-07-16T14:32:11Z"
  loops:
    throughput:
      e2e_median_sec: "3213.5"
EOF
    echo 'detectors: []' > "$TEST_TMPDIR/logs/detector_fp_rate.yaml"
}

append_ratchet_row() {
    local ts="$1" cmd="$2" deploy="$3" work="$4" finalize="$5" e2e="$6" missing="${7:-none}" extra="${8:-}"
    printf '%s\t%s\tCLEAR\tall_gates_passed\tx\tx\tx\tx\tduration_sec=1\tdeploy_sec=%s work_sec=%s finalize_sec=%s e2e_sec=%s missing=%s %s\n' \
        "$ts" "$cmd" "$deploy" "$work" "$finalize" "$e2e" "$missing" "$extra" >> "$TEST_TMPDIR/logs/gate_metrics.log"
}

teardown() {
    unset THROUGHPUT_SCAN_ROOT
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "throughput_scan queues fix_known insight for worsening throughput and high FP detector" {
    cat > "$TEST_TMPDIR/logs/loop_ledger.yaml" <<'EOF'
snapshots:
- generated_at: "2026-07-08T09:00:00Z"
  loops:
    throughput:
      e2e_median_sec: 100.0
      overhead_rate_median_pct: 10.0
- generated_at: "2026-07-08T10:00:00Z"
  loops:
    throughput:
      e2e_median_sec: 190.0
      overhead_rate_median_pct: 21.0
EOF
    cat > "$TEST_TMPDIR/logs/detector_fp_rate.yaml" <<'EOF'
detectors:
- detector: "cmd_save:check_ac_must_should_mix"
  fires: 2
  false_positive: 2
  true_positive: 0
  unknown: 0
  fp_rate: 100.0
EOF

    run bash "$TEST_TMPDIR/scripts/throughput_scan.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"THROUGHPUT_SCAN_QUEUED"* ]]
    [[ "$output" == *"THROUGHPUT_SCAN_SUMMARY: candidates=3 queued=3 duplicates=0"* ]]

    python3 - "$TEST_TMPDIR/queue/insights.yaml" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1]))
items = data["insights"]
assert len(items) == 3
assert all(item["fix_known"] is True for item in items)
assert any("overhead median worsened" in item["insight"] for item in items)
assert any("e2e median worsened" in item["insight"] for item in items)
assert any("detector=cmd_save:check_ac_must_should_mix" in item["insight"] for item in items)
assert any(item["target_file"] == "scripts/cmd_save.sh" for item in items)
assert sum(item["target_file"] == "scripts/loop_ledger_update.sh" for item in items) == 2
PY
}

@test "throughput_scan emits none when ledgers are below thresholds" {
    cat > "$TEST_TMPDIR/logs/loop_ledger.yaml" <<'EOF'
snapshots:
- generated_at: "2026-07-08T09:00:00Z"
  loops:
    throughput:
      e2e_median_sec: 100.0
      overhead_rate_median_pct: 10.0
- generated_at: "2026-07-08T10:00:00Z"
  loops:
    throughput:
      e2e_median_sec: 120.0
      overhead_rate_median_pct: 11.0
EOF
    cat > "$TEST_TMPDIR/logs/detector_fp_rate.yaml" <<'EOF'
detectors:
- detector: "cmd_save:check_ac_test_scope"
  fires: 5
  false_positive: 1
  true_positive: 0
  unknown: 4
  fp_rate: 20.0
EOF

    run bash "$TEST_TMPDIR/scripts/throughput_scan.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"THROUGHPUT_SCAN_NONE"* ]]
    python3 - "$TEST_TMPDIR/queue/insights.yaml" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1]))
assert data["insights"] == []
PY
}

@test "throughput_scan suppresses duplicate pending insight" {
    cat > "$TEST_TMPDIR/logs/loop_ledger.yaml" <<'EOF'
snapshots: []
EOF
    cat > "$TEST_TMPDIR/logs/detector_fp_rate.yaml" <<'EOF'
detectors:
- detector: "cmd_save:cmd_text_deferral_language"
  fires: 13
  false_positive: 13
  true_positive: 0
  unknown: 0
  fp_rate: 100.0
EOF

    run bash "$TEST_TMPDIR/scripts/throughput_scan.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"queued=1 duplicates=0"* ]]
    run bash "$TEST_TMPDIR/scripts/throughput_scan.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"queued=0 duplicates=1"* ]]

    python3 - "$TEST_TMPDIR/queue/insights.yaml" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1]))
assert len(data["insights"]) == 1
PY
}

@test "ninja_monitor check_throughput_scan runs scan script on interval" {
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="'"$TEST_TMPDIR"'"
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs"
cat > "$SCRIPT_DIR/scripts/throughput_scan.sh" <<SH
#!/usr/bin/env bash
echo "stub throughput scan"
SH
chmod +x "$SCRIPT_DIR/scripts/throughput_scan.sh"
log() { echo "$1"; }
LAST_THROUGHPUT_SCAN=0
THROUGHPUT_SCAN_INTERVAL=1
check_throughput_scan
cat "$SCRIPT_DIR/logs/throughput_scan.log"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"stub throughput scan"* ]]
}

@test "throughput S1 candidates include stage attribution and numeric verify" {
    cat > "$TEST_TMPDIR/logs/loop_ledger.yaml" <<'EOF'
snapshots:
- generated_at: "2026-07-08T09:00:00Z"
  loops:
    throughput:
      e2e_median_sec: 100.0
      overhead_rate_median_pct: 10.0
      deploy_median_sec: 10.0
      work_median_sec: 80.0
      finalize_median_sec: 10.0
- generated_at: "2026-07-08T10:00:00Z"
  loops:
    throughput:
      e2e_median_sec: 250.0
      overhead_rate_median_pct: 30.0
      deploy_median_sec: 70.0
      work_median_sec: 120.0
      finalize_median_sec: 60.0
EOF
    cat > "$TEST_TMPDIR/logs/detector_fp_rate.yaml" <<'EOF'
detectors: []
EOF

    run bash "$TEST_TMPDIR/scripts/throughput_scan.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"THROUGHPUT_SCAN_DRY_RUN"* ]]
    [[ "$output" == *"largest_stage=work target=scripts/loop_ledger_update.sh measurement_target=work_median_sec"* ]]
    [[ "$output" == *"stage_medians=deploy:70.0s,work:120.0s,finalize:60.0s,e2e:250.0s,overhead:30.0%,measured:250.0s,unmeasured_wait:0.0s"* ]]
    [[ "$output" == *"yaml.safe_load(open('$TEST_TMPDIR/logs/loop_ledger.yaml'))"* ]]
    [[ "$output" != *"target=scripts/throughput_scan.sh"* ]]
    [[ "$output" != *"target=scripts/cmd_complete_gate.sh"* ]]
    [[ "$output" != *"target=scripts/deploy_task.sh"* ]]
}

@test "throughput scan attributes the production 3213.5s measurement gap" {
    cat > "$TEST_TMPDIR/logs/loop_ledger.yaml" <<'EOF'
snapshots:
- loops: {throughput: {e2e_median_sec: 3054.0, overhead_rate_median_pct: 70.0}}
- loops:
    throughput: {deploy_median_sec: 256.0, work_median_sec: 448.0, finalize_median_sec: 235.0, e2e_median_sec: 3213.5, overhead_rate_median_pct: 74.1}
EOF
    echo 'detectors: []' > "$TEST_TMPDIR/logs/detector_fp_rate.yaml"
    run bash "$TEST_TMPDIR/scripts/throughput_scan.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"measured:939.0s,unmeasured_wait:2274.5s"* ]]
    [[ "$output" == *"largest_stage=unmeasured_wait target=scripts/loop_ledger_update.sh measurement_target=unmeasured_wait"* ]]
}

@test "throughput scan handles missing and outlier stage data without false attribution" {
    cat > "$TEST_TMPDIR/logs/loop_ledger.yaml" <<'EOF'
snapshots:
- loops: {throughput: {e2e_median_sec: 100.0}}
- loops: {throughput: {e2e_median_sec: 10000.0, deploy_median_sec: null, work_median_sec: 1.0, finalize_median_sec: 1.0}}
EOF
    echo 'detectors: []' > "$TEST_TMPDIR/logs/detector_fp_rate.yaml"
    run bash "$TEST_TMPDIR/scripts/throughput_scan.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"measured:na,unmeasured_wait:na"* ]]
    [[ "$output" == *"largest_stage=unmeasured target=scripts/loop_ledger_update.sh measurement_target=missing:deploy_median_sec"* ]]
}

@test "throughput scan attributes deploy-largest candidates to deploy_task" {
    cat > "$TEST_TMPDIR/logs/loop_ledger.yaml" <<'EOF'
snapshots:
- loops: {throughput: {e2e_median_sec: 100.0, overhead_rate_median_pct: 10.0}}
- loops:
    throughput: {deploy_median_sec: 140.0, work_median_sec: 80.0, finalize_median_sec: 30.0, e2e_median_sec: 250.0, overhead_rate_median_pct: 30.0}
EOF
    echo 'detectors: []' > "$TEST_TMPDIR/logs/detector_fp_rate.yaml"

    run bash "$TEST_TMPDIR/scripts/throughput_scan.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"largest_stage=deploy target=scripts/deploy_task.sh measurement_target=deploy_median_sec"* ]]
    [[ "$output" != *"target=scripts/cmd_complete_gate.sh"* ]]
}

@test "throughput scan attributes finalize-largest candidates to cmd_complete_gate" {
    cat > "$TEST_TMPDIR/logs/loop_ledger.yaml" <<'EOF'
snapshots:
- loops: {throughput: {e2e_median_sec: 100.0, overhead_rate_median_pct: 10.0}}
- loops:
    throughput: {deploy_median_sec: 40.0, work_median_sec: 60.0, finalize_median_sec: 150.0, e2e_median_sec: 250.0, overhead_rate_median_pct: 30.0}
EOF
    echo 'detectors: []' > "$TEST_TMPDIR/logs/detector_fp_rate.yaml"

    run bash "$TEST_TMPDIR/scripts/throughput_scan.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"largest_stage=finalize target=scripts/cmd_complete_gate.sh measurement_target=finalize_median_sec"* ]]
    [[ "$output" != *"target=scripts/deploy_task.sh"* ]]
}

@test "throughput scan routes tied largest stages to measurement instead of guessing" {
    cat > "$TEST_TMPDIR/logs/loop_ledger.yaml" <<'EOF'
snapshots:
- loops: {throughput: {e2e_median_sec: 100.0, overhead_rate_median_pct: 10.0}}
- loops:
    throughput: {deploy_median_sec: 100.0, work_median_sec: 20.0, finalize_median_sec: 100.0, e2e_median_sec: 220.0, overhead_rate_median_pct: 30.0}
EOF
    echo 'detectors: []' > "$TEST_TMPDIR/logs/detector_fp_rate.yaml"

    run bash "$TEST_TMPDIR/scripts/throughput_scan.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"largest_stage=ambiguous target=scripts/loop_ledger_update.sh measurement_target=tie:deploy,finalize"* ]]
}

@test "2x ratchet stays WARMUP with four valid post-telemetry commands" {
    write_ratchet_baseline
    for n in 1 2 3 4; do append_ratchet_row "2026-07-17T02:0${n}:00" "cmd_$n" 100 500 100 1600; done
    run bash "$TEST_TMPDIR/scripts/throughput_scan.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"status=WARMUP"*"target_e2e_sec=1606.75"*"valid_samples=4"* ]]
}

@test "2x ratchet accepts five samples at the exact 2.0 boundary including an outlier" {
    write_ratchet_baseline
    for spec in '1 1500' '2 1606.75' '3 1606.75' '4 1606.75' '5 9999'; do set -- $spec; append_ratchet_row "2026-07-17T02:0$1:00" "cmd_$1" 100 500 100 "$2"; done
    run bash "$TEST_TMPDIR/scripts/throughput_scan.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"status=PASS"*"median_e2e_sec=1606.75"*"improvement_ratio=2.0"* ]]
}

@test "2x ratchet fails five samples above boundary and attributes numeric largest stage" {
    write_ratchet_baseline
    for n in 1 2 3 4 5; do append_ratchet_row "2026-07-17T02:0${n}:00" "cmd_$n" 100 1200 300 1607; done
    run bash "$TEST_TMPDIR/scripts/throughput_scan.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"status=FAIL"*"median_e2e_sec=1607.0"*"largest_stage=work"* ]]
}

@test "2x ratchet excludes invalid duplicate legacy and backfill rows with reason counts" {
    write_ratchet_baseline
    append_ratchet_row "2026-07-17T02:01:00" cmd_zero 0 500 100 700
    append_ratchet_row "2026-07-17T02:01:30" cmd_zero_unproved 0 500 100 na missing_issue_ts
    append_ratchet_row "2026-07-17T02:02:00" cmd_na na 5 5 na missing_issue_ts
    append_ratchet_row "2026-07-17T02:03:00" cmd_neg -1 5 5 9
    append_ratchet_row "2026-07-17T02:04:00" cmd_backfill 1 5 5 9 none estimated_backfill=true
    append_ratchet_row "2026-07-17T01:40:00" cmd_old 1 5 5 9
    append_ratchet_row "2026-07-17T02:05:00" cmd_dup 1 5 5 9
    append_ratchet_row "2026-07-17T02:06:00" cmd_dup 1 5 5 10
    run bash "$TEST_TMPDIR/scripts/throughput_scan.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"valid_samples=2"*"excluded=na:2,negative:1,estimated_backfill:1,old_schema:1,duplicate_old_revision:1"* ]]
}
