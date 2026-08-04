#!/usr/bin/env bats

# test_necessity: an impl task may reuse only explicitly named, distinct,
# completed PASS-family scout reports whose commands are both Gunshi-LGTM and
# latest-state GATE CLEAR; every incomplete or out-of-scope variant must block.

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FIXTURE_ROOT="$BATS_TEST_TMPDIR/repo"
  TASK_FILE="$FIXTURE_ROOT/task.yaml"
  mkdir -p "$FIXTURE_ROOT/queue/reports" "$FIXTURE_ROOT/queue/archive/reports" "$FIXTURE_ROOT/logs"
  write_valid_fixture
}

write_valid_fixture() {
  cat > "$TASK_FILE" <<'EOF'
task:
  task_type: impl
  parent_cmd: cmd_impl
  status: assigned
  scout_reports:
    - queue/reports/track_a.yaml
    - queue/reports/track_b.yaml
EOF
  cat > "$FIXTURE_ROOT/queue/reports/track_a.yaml" <<'EOF'
report_id: rpt-track-a
parent_cmd: cmd_track_a
task_type: scout
status: completed
verdict: PASS
EOF
  cat > "$FIXTURE_ROOT/queue/reports/track_b.yaml" <<'EOF'
report_id: rpt-track-b
parent_cmd: cmd_track_b
task_type: recon
status: completed
verdict: PASS_NO_IMPROVEMENT
EOF
  cat > "$FIXTURE_ROOT/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_track_a
  review_type: report
  verdict: LGTM
- review:
    cmd_id: cmd_track_b
    review_type: report
    verdict: LGTM
EOF
  printf '%s\n' \
    $'2026-08-04T22:35:52\tcmd_track_a\tCLEAR\tall_gates_passed' \
    $'2026-08-04T22:40:59\tcmd_track_b\tCLEAR\tall_gates_passed' \
    > "$FIXTURE_ROOT/logs/gate_metrics.log"
}

run_scout_gate() {
  run bash -lc '
    set -euo pipefail
    export DEPLOY_TASK_LIB_ONLY=1
    source "$1/scripts/deploy_task.sh"
    SCRIPT_DIR="$2"
    log() { printf "%s\n" "$*"; }
    check_scout_gate "$3"
  ' -- "$PROJECT_ROOT" "$FIXTURE_ROOT" "$TASK_FILE"
}

@test "explicit two-report hand-off passes only after completed PASS, LGTM, and CLEAR" {
  run_scout_gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"explicit scout_reports=2 distinct_report_ids=2"* ]]
}

@test "one explicit report blocks" {
  python3 - "$TASK_FILE" <<'PY'
import pathlib, yaml, sys
p=pathlib.Path(sys.argv[1]); d=yaml.safe_load(p.read_text()); d['task']['scout_reports']=d['task']['scout_reports'][:1]; p.write_text(yaml.safe_dump(d, sort_keys=False))
PY
  run_scout_gate
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least two explicit report paths are required"* ]]
}

@test "duplicate report_id blocks" {
  sed -i 's/rpt-track-b/rpt-track-a/' "$FIXTURE_ROOT/queue/reports/track_b.yaml"
  run_scout_gate
  [ "$status" -ne 0 ]
  [[ "$output" == *"duplicate report_id"* ]]
}

@test "out-of-scope report path blocks" {
  cp "$FIXTURE_ROOT/queue/reports/track_b.yaml" "$FIXTURE_ROOT/outside.yaml"
  sed -i 's#queue/reports/track_b.yaml#outside.yaml#' "$TASK_FILE"
  run_scout_gate
  [ "$status" -ne 0 ]
  [[ "$output" == *"not under an approved report directory"* ]]
}

@test "non-completed report blocks" {
  sed -i 's/status: completed/status: in_progress/' "$FIXTURE_ROOT/queue/reports/track_b.yaml"
  run_scout_gate
  [ "$status" -ne 0 ]
  [[ "$output" == *"status is not completed"* ]]
}

@test "report without Gunshi LGTM blocks" {
  sed -i '/cmd_id: cmd_track_b/{n;n;s/verdict: LGTM/verdict: REQUEST_CHANGES/;}' "$FIXTURE_ROOT/logs/gunshi_review_log.yaml"
  run_scout_gate
  [ "$status" -ne 0 ]
  [[ "$output" == *"latest gunshi report review is not LGTM"* ]]
}

@test "report whose latest gate is not CLEAR blocks" {
  printf '%s\n' $'2026-08-04T22:41:59\tcmd_track_b\tBLOCK\treopened' >> "$FIXTURE_ROOT/logs/gate_metrics.log"
  run_scout_gate
  [ "$status" -ne 0 ]
  [[ "$output" == *"latest gate is not CLEAR"* ]]
}

@test "legacy same-parent done counting remains available without scout_reports" {
  sed -i '/  scout_reports:/,+2d' "$TASK_FILE"
  mkdir -p "$FIXTURE_ROOT/queue/tasks"
  cat > "$FIXTURE_ROOT/queue/tasks/track_a.yaml" <<'EOF'
task:
  parent_cmd: cmd_impl
  task_id: cmd_impl_scout_a
  status: done
EOF
  cat > "$FIXTURE_ROOT/queue/tasks/track_b.yaml" <<'EOF'
task:
  parent_cmd: cmd_impl
  task_id: cmd_impl_recon_b
  status: done
EOF
  run_scout_gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 scout/recon tasks done"* ]]
}

@test "legacy scout_exempt still bypasses report validation" {
  sed -i '/  scout_reports:/,+2d' "$TASK_FILE"
  sed -i '/  status:/a\  scout_exempt: true' "$TASK_FILE"
  run_scout_gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"scout_exempt=true in task YAML"* ]]
}
