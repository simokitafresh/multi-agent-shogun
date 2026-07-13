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
    [[ "$output" == *"target=scripts/throughput_scan.sh"* ]]
    [[ "$output" == *"stage_medians=deploy:70.0s,work:120.0s,finalize:60.0s,e2e:250.0s,overhead:30.0%"* ]]
    [[ "$output" == *"yaml.safe_load(open('$TEST_TMPDIR/logs/loop_ledger.yaml'))"* ]]
    [[ "$output" != *"target=scripts/cmd_complete_gate.sh"* ]]
    [[ "$output" != *"test -f logs/loop_ledger.yaml && test -f scripts/cmd_complete_gate.sh"* ]]
}
