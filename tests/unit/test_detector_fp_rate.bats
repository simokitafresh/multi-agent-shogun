#!/usr/bin/env bats
# test_detector_fp_rate.bats — detector FP rate ledger generation

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d)"
    mkdir -p "$TEST_TMPDIR/logs"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "detector_fp_rate counts cmd_save WARN followed by PASS as false_positive" {
    cat > "$TEST_TMPDIR/logs/gate_fire_log.yaml" <<'EOF'
- ts: "2026-07-08T08:49:47", file: "cmd_3757", gate: "cmd_save", result: WARN, checks: "check_ac_param_sufficiency", reasons: "ac_param_sufficiency|check=check_ac_param_sufficiency"
- ts: "2026-07-08T09:00:00", file: "cmd_3757", gate: "cmd_save", result: PASS, checks: "", reasons: ""
EOF
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries: []
EOF
    cat > "$TEST_TMPDIR/logs/gate_alerts.yaml" <<'EOF'
alerts: []
EOF

    run env DETECTOR_FP_ROOT="$TEST_TMPDIR" bash "$PROJECT_ROOT/scripts/detector_fp_rate.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cmd_save:check_ac_param_sufficiency: fp_rate=100.0% fp=1/1"* ]]
    grep -q 'detector: "cmd_save:check_ac_param_sufficiency"' "$TEST_TMPDIR/logs/detector_fp_rate.yaml"
    grep -q 'outcome: "false_positive"' "$TEST_TMPDIR/logs/detector_fp_rate.yaml"
}

@test "detector_fp_rate keeps unresolved escalation alerts as unknown" {
    cat > "$TEST_TMPDIR/logs/gate_fire_log.yaml" <<'EOF'
EOF
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries: []
EOF
    cat > "$TEST_TMPDIR/logs/gate_alerts.yaml" <<'EOF'
alerts:
  - alert_id: GA-001
    gate: ci_red
    detected_at: "2026-07-08T10:00:00+0900"
    alert_detail: "ALERT: CI赤"
    three_questions_sent: true
    investigation_cmd: null
    improvement_done: false
EOF

    run env DETECTOR_FP_ROOT="$TEST_TMPDIR" bash "$PROJECT_ROOT/scripts/detector_fp_rate.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"escalation:ci_red: fp_rate=0.0% fp=0/1"* ]]
    grep -q 'outcome: "unknown"' "$TEST_TMPDIR/logs/detector_fp_rate.yaml"
}

@test "detector_fp_rate connects Guard19 scripts_same_day_history fires as an unknown-outcome detector" {
    cat > "$TEST_TMPDIR/logs/gate_fire_log.yaml" <<'EOF'
- ts: "2026-07-12T15:46:44", file: "scripts/foo.sh", gate: "scripts_same_day_history", result: WARN, reasons: "commits_today=1; uncommitted=no"
- ts: "2026-07-12T15:50:00", file: "scripts/bar.sh", gate: "scripts_same_day_history", result: WARN, reasons: "commits_today=0; uncommitted=yes"
EOF
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries: []
EOF
    cat > "$TEST_TMPDIR/logs/gate_alerts.yaml" <<'EOF'
alerts: []
EOF

    run env DETECTOR_FP_ROOT="$TEST_TMPDIR" bash "$PROJECT_ROOT/scripts/detector_fp_rate.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"scripts_same_day_history: fp_rate=0.0% fp=0/2"* ]]
    grep -q 'detector: "scripts_same_day_history"' "$TEST_TMPDIR/logs/detector_fp_rate.yaml"
    grep -q 'fires: 2' "$TEST_TMPDIR/logs/detector_fp_rate.yaml"
    grep -q 'outcome: "unknown"' "$TEST_TMPDIR/logs/detector_fp_rate.yaml"
}

@test "detector_fp_rate does not reintroduce direct yaml dump writes" {
    run python3 - "$PROJECT_ROOT/scripts/detector_fp_rate.sh" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
hits = []
for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    if re.search(r"\byaml\.(safe_dump|dump)\s*\(", line):
        hits.append(f"{path}:{lineno}:{line.strip()}")

if hits:
    print("\n".join(hits))
    sys.exit(1)
PY
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}
