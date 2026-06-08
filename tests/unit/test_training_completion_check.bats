#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TMP_ROOT="$(mktemp -d)"
    mkdir -p "$TMP_ROOT/logs" "$TMP_ROOT/scripts" "$TMP_ROOT/skills/report-write"

    # Stub skill_auto_improve.sh
    cat > "$TMP_ROOT/scripts/skill_auto_improve.sh" <<'SH'
#!/usr/bin/env bash
echo "STUB_SKILL_AUTO_IMPROVE: $*"
SH
    chmod +x "$TMP_ROOT/scripts/skill_auto_improve.sh"

    # Stub SKILL.md for report-write
    echo "# report-write" > "$TMP_ROOT/skills/report-write/SKILL.md"
}

teardown() {
    rm -rf "$TMP_ROOT"
}

@test "training_completion_check requires --cmd-id" {
    run bash "$PROJECT_ROOT/scripts/training_completion_check.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"--cmd-id is required"* ]]
}

@test "training_completion_check exits 0 when gate_fire_log missing" {
    run bash "$PROJECT_ROOT/scripts/training_completion_check.sh" \
        --cmd-id "cmd_training_L4_auto_2026060416_hayate" \
        --gate-log "$TMP_ROOT/nonexistent.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TRAINING_COMPLETION_SKIP"* ]]
}

@test "training_completion_check detects TRAINING_INCOMPLETE when first-pass < threshold" {
    cat > "$TMP_ROOT/logs/gate_fire_log.yaml" <<'LOG'
- ts: "2026-06-04T16:43:00+09:00", file: "queue/reports/hayate_report_cmd_training_L4_auto_2026060416_hayate.yaml", gate: "gate_report_format", result: FAIL, reasons: "worker_id: MISSING"
- ts: "2026-06-04T16:44:00+09:00", file: "queue/reports/hayate_report_cmd_training_L4_auto_2026060416_hayate.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-04T16:45:00+09:00", file: "queue/reports/saizo_report_cmd_training_L4_auto_2026060416_saizo.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-04T16:46:00+09:00", file: "queue/reports/kotaro_report_cmd_training_L4_auto_2026060416_kotaro.yaml", gate: "gate_report_format", result: FAIL, reasons: "lessons_useful: MISSING"
- ts: "2026-06-04T16:47:00+09:00", file: "queue/reports/kotaro_report_cmd_training_L4_auto_2026060416_kotaro.yaml", gate: "gate_report_format", result: PASS
LOG

    run bash "$PROJECT_ROOT/scripts/training_completion_check.sh" \
        --cmd-id "cmd_training_L4_auto_2026060416_hayate" \
        --gate-log "$TMP_ROOT/logs/gate_fire_log.yaml" \
        --pass-count 3

    [ "$status" -eq 0 ]
    [[ "$output" == *"first_pass=1/3"* ]]
    [[ "$output" == *"TRAINING_INCOMPLETE"* ]]
}

@test "training_completion_check detects TRAINING_COMPLETE when first-pass >= threshold" {
    cat > "$TMP_ROOT/logs/gate_fire_log.yaml" <<'LOG'
- ts: "2026-06-04T16:43:00+09:00", file: "queue/reports/hayate_report_cmd_training_L4_auto_2026060416_hayate.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-04T16:44:00+09:00", file: "queue/reports/saizo_report_cmd_training_L4_auto_2026060416_saizo.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-04T16:45:00+09:00", file: "queue/reports/kotaro_report_cmd_training_L4_auto_2026060416_kotaro.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-04T16:46:00+09:00", file: "queue/reports/tobisaru_report_cmd_training_L4_auto_2026060416_tobisaru.yaml", gate: "gate_report_format", result: FAIL, reasons: "verdict: MISSING"
- ts: "2026-06-04T16:47:00+09:00", file: "queue/reports/tobisaru_report_cmd_training_L4_auto_2026060416_tobisaru.yaml", gate: "gate_report_format", result: PASS
LOG

    run bash "$PROJECT_ROOT/scripts/training_completion_check.sh" \
        --cmd-id "cmd_training_L4_auto_2026060416_hayate" \
        --gate-log "$TMP_ROOT/logs/gate_fire_log.yaml" \
        --improve-script "$TMP_ROOT/scripts/skill_auto_improve.sh" \
        --pass-count 3

    [ "$status" -eq 0 ]
    [[ "$output" == *"first_pass=3/4"* ]]
    [[ "$output" == *"TRAINING_COMPLETE"* ]]
    [[ "$output" == *"STUB_SKILL_AUTO_IMPROVE: --apply"* ]]
}

@test "training_completion_check calls skill_auto_improve with --skill when detected" {
    cat > "$TMP_ROOT/logs/gate_fire_log.yaml" <<'LOG'
- ts: "2026-06-04T16:43:00+09:00", file: "queue/reports/hayate_report_cmd_training_L2_report-write_2026060416_hayate.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-04T16:44:00+09:00", file: "queue/reports/saizo_report_cmd_training_L2_report-write_2026060416_saizo.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-04T16:45:00+09:00", file: "queue/reports/kotaro_report_cmd_training_L2_report-write_2026060416_kotaro.yaml", gate: "gate_report_format", result: PASS
LOG

    run bash "$PROJECT_ROOT/scripts/training_completion_check.sh" \
        --cmd-id "cmd_training_L2_report-write_2026060416_hayate" \
        --gate-log "$TMP_ROOT/logs/gate_fire_log.yaml" \
        --improve-script "$TMP_ROOT/scripts/skill_auto_improve.sh" \
        --pass-count 3

    [ "$status" -eq 0 ]
    [[ "$output" == *"TRAINING_COMPLETE"* ]]
    [[ "$output" == *"STUB_SKILL_AUTO_IMPROVE: --apply --skill report-write"* ]]
}

@test "training_completion_check handles absolute and relative file paths in gate_fire_log" {
    cat > "$TMP_ROOT/logs/gate_fire_log.yaml" <<'LOG'
- ts: "2026-06-04T16:43:00+09:00", file: "/mnt/c/tools/multi-agent-shogun/queue/reports/hayate_report_cmd_training_L4_auto_2026060416_hayate.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-04T16:44:00+09:00", file: "queue/reports/saizo_report_cmd_training_L4_auto_2026060416_saizo.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-04T16:45:00+09:00", file: "queue/reports/kotaro_report_cmd_training_L4_auto_2026060416_kotaro.yaml", gate: "gate_report_format", result: PASS
LOG

    run bash "$PROJECT_ROOT/scripts/training_completion_check.sh" \
        --cmd-id "cmd_training_L4_auto_2026060416_hayate" \
        --gate-log "$TMP_ROOT/logs/gate_fire_log.yaml" \
        --improve-script "$TMP_ROOT/scripts/skill_auto_improve.sh" \
        --pass-count 3

    [ "$status" -eq 0 ]
    [[ "$output" == *"first_pass=3/3"* ]]
    [[ "$output" == *"TRAINING_COMPLETE"* ]]
}

@test "training_completion_check ignores non-gate_report_format entries" {
    cat > "$TMP_ROOT/logs/gate_fire_log.yaml" <<'LOG'
- ts: "2026-06-04T16:43:00+09:00", file: "queue/reports/hayate_report_cmd_training_L4_auto_2026060416_hayate.yaml", gate: "gate_report_format", result: PASS
2026-06-04T16:44:00 [WARN] cmd_training_L4_auto_2026060416_hayate gate: "skill_script_refs" stale_or_missing_refs
- ts: "2026-06-04T16:45:00+09:00", file: "queue/reports/saizo_report_cmd_training_L4_auto_2026060416_saizo.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-04T16:46:00+09:00", file: "queue/reports/kotaro_report_cmd_training_L4_auto_2026060416_kotaro.yaml", gate: "gate_report_format", result: PASS
LOG

    run bash "$PROJECT_ROOT/scripts/training_completion_check.sh" \
        --cmd-id "cmd_training_L4_auto_2026060416_hayate" \
        --gate-log "$TMP_ROOT/logs/gate_fire_log.yaml" \
        --improve-script "$TMP_ROOT/scripts/skill_auto_improve.sh" \
        --pass-count 3

    [ "$status" -eq 0 ]
    [[ "$output" == *"first_pass=3/3"* ]]
    [[ "$output" == *"TRAINING_COMPLETE"* ]]
}

@test "training_completion_check handles speed training cmd pattern" {
    cat > "$TMP_ROOT/logs/gate_fire_log.yaml" <<'LOG'
- ts: "2026-06-07T20:33:00+09:00", file: "queue/reports/hayate_report_cmd_training_speed_topic_2026060720_hayate.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-07T20:34:00+09:00", file: "queue/reports/saizo_report_cmd_training_speed_topic_2026060720_saizo.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-07T20:35:00+09:00", file: "queue/reports/kotaro_report_cmd_training_speed_topic_2026060720_kotaro.yaml", gate: "gate_report_format", result: PASS
LOG

    run bash "$PROJECT_ROOT/scripts/training_completion_check.sh" \
        --cmd-id "cmd_training_speed_topic_2026060720_hayate" \
        --gate-log "$TMP_ROOT/logs/gate_fire_log.yaml" \
        --improve-script "$TMP_ROOT/scripts/skill_auto_improve.sh" \
        --pass-count 3

    [ "$status" -eq 0 ]
    [[ "$output" == *"TRAINING_COMPLETE"* ]]
}

@test "ninja_monitor _trigger_training_completion_check calls check script for completed training" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs"

# Create training task YAML
cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  task_type: training
  task_id: cmd_training_L4_auto_2026060416_hayate
  status: done
YAML

# Create gate_fire_log with 3+ first-pass PASS
cat > "$SCRIPT_DIR/logs/gate_fire_log.yaml" <<LOG
- ts: "2026-06-04T16:43:00+09:00", file: "queue/reports/hayate_report_cmd_training_L4_auto_2026060416_hayate.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-04T16:44:00+09:00", file: "queue/reports/saizo_report_cmd_training_L4_auto_2026060416_saizo.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-04T16:45:00+09:00", file: "queue/reports/kotaro_report_cmd_training_L4_auto_2026060416_kotaro.yaml", gate: "gate_report_format", result: PASS
LOG

# Stub skill_auto_improve.sh
cat > "$SCRIPT_DIR/scripts/skill_auto_improve.sh" <<SH
#!/usr/bin/env bash
echo "STUB_SKILL_AUTO_IMPROVE: \$*"
SH
chmod +x "$SCRIPT_DIR/scripts/skill_auto_improve.sh"

# Stub training_completion_check.sh (use the real one)
cp "$PROJECT_ROOT/scripts/training_completion_check.sh" "$SCRIPT_DIR/scripts/"
chmod +x "$SCRIPT_DIR/scripts/training_completion_check.sh"

log() { echo "$1"; }

_trigger_training_completion_check hayate
echo "CHECKED=${TRAINING_COMPLETION_CHECKED[hayate:cmd_training_L4_auto_2026060416_hayate]:-unset}"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"TRAINING_COMPLETION_DONE"* ]]
    [[ "$output" == *"CHECKED=1"* ]]
}

@test "ninja_monitor _trigger_training_completion_check skips non-training tasks" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks"

# Non-training task
cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  task_type: focused
  task_id: cmd_3230_focused
  status: done
YAML

log() { echo "$1"; }

_trigger_training_completion_check hayate
echo "SKIPPED_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIPPED_OK"* ]]
    [[ "$output" != *"TRAINING_COMPLETE"* ]]
}

@test "ninja_monitor _trigger_training_completion_check dedup prevents double check" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs"

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  task_type: training
  task_id: cmd_training_L4_auto_2026060416_hayate
  status: done
YAML

cat > "$SCRIPT_DIR/logs/gate_fire_log.yaml" <<LOG
- ts: "2026-06-04T16:43:00+09:00", file: "queue/reports/hayate_report_cmd_training_L4_auto_2026060416_hayate.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-04T16:44:00+09:00", file: "queue/reports/saizo_report_cmd_training_L4_auto_2026060416_saizo.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-06-04T16:45:00+09:00", file: "queue/reports/kotaro_report_cmd_training_L4_auto_2026060416_kotaro.yaml", gate: "gate_report_format", result: PASS
LOG

cat > "$SCRIPT_DIR/scripts/skill_auto_improve.sh" <<SH
#!/usr/bin/env bash
echo "STUB_IMPROVE"
SH
chmod +x "$SCRIPT_DIR/scripts/skill_auto_improve.sh"
cp "$PROJECT_ROOT/scripts/training_completion_check.sh" "$SCRIPT_DIR/scripts/"
chmod +x "$SCRIPT_DIR/scripts/training_completion_check.sh"

log() { echo "$1"; }
count=0
_trigger_training_completion_check hayate; count=$((count+1))
_trigger_training_completion_check hayate; count=$((count+1))
echo "CALL_COUNT=$count"
'
    [ "$status" -eq 0 ]
    # TRAINING_COMPLETION_DONE should appear only once (second call is deduped)
    local complete_count
    complete_count=$(echo "$output" | grep -c "TRAINING_COMPLETION_DONE" || true)
    [ "$complete_count" -eq 1 ]
}
