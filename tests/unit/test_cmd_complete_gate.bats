#!/usr/bin/env bats
# test_necessity: CI readiness applies only to remote-contained report commits, never free text, and fails closed when commit or remote identity is unknowable; violation is BLOCK.
# regression_justification: The existing completion-gate suite did not cover a dirty shared worktree whose local HEAD diverged from the pushed origin/main boundary.
# test_cmd_complete_gate.bats - cmd_complete_gate.sh partial unit tests
# test_necessity: dm-signal production-deploy completion must bind origin/live identity and API 2xx responses; this is a permanent contract gate.
# regression_justification: test coverage previously allowed test+GATE CLEAR while the deployed Render revision still served an error response.
# Optimized: gate全体実行をやめ、重い責務を関数/局所フェーズ単位で直接検証する

load '../helpers/cmd_gate_scaffold'

setup_file() {
    cmd_gate_setup_file
    export SRC_NORMALIZE_SCRIPT="$PROJECT_ROOT/scripts/lib/normalize_report.sh"
    [ -f "$SRC_NORMALIZE_SCRIPT" ] || return 1

    # Extract function bodies once to $BATS_FILE_TMPDIR (avoids per-test sed overhead)
    export GATE_HELPERS_FILE="$BATS_FILE_TMPDIR/gate_helpers.sh"
    python3 - "$SRC_GATE_SCRIPT" > "$GATE_HELPERS_FILE" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
names = """record_block_reason append_line_locked dispatch_gate_notification_async send_high_notification send_info_cmd_notification log_gate_stderr_file lesson_done_satisfies_lesson_candidate_registration cmd_status_is_canceled level_heading check_context_update resolve_report_file update_lesson_impact_tsv append_lesson_tracking build_clear_duration_metric build_clear_throughput_metric binary_checks_warn_reason report_has_commit_binary_check_yes collect_report_files_modified discover_reports_for_cmd collect_parent_cmd_report_files_modified has_parent_cmd_report collect_git_show_w_files collect_report_commit_hash collect_cmd_phase_git_files check_self_grade_commit_file_coverage is_lessons_useful_empty_warn_task_type handle_empty_lessons_useful_check validate_lesson_feedback_set detect_task_types _check_lc_found lesson_candidate_status preflight_gate_flags collect_report_modified_files load_validated_sg7_context collect_cmd_command_file_refs collect_report_verified_existing_deps collect_task_readonly_refs check_command_files_modified_coverage check_scope_drift check_wtf_likelihood check_script_wiring resolve_task_repo_dir cmd_requires_cdp_production_check run_cdp_production_check cmd_requires_dm_signal_production_smoke dm_signal_report_deploy_sha resolve_dm_signal_render_live_sha run_dm_signal_production_smoke_check append_codd_registry_entry run_codd_propagate_update normalize_block_reason_to_workaround_categories update_karo_workaround_resolutions classify_completed_rework_event_kind capture_completed_rework_event""".split()
for name in names:
    match = re.search(rf"(?m)^{re.escape(name)}\(\) \{{.*?^\}}", source, re.DOTALL)
    if match is None:
        raise SystemExit(f"missing helper: {name}")
    print(match.group(0), end="\n\n")
start = source.index("write_l6_horizontal_level5_insights()")
end = source.index("\n# ─── changelog自動記録関数", start)
print(source[start:end])
PY

    # Build the invariant scaffold once on ext4. Each test still receives an
    # isolated copy, but avoids repeating mkdir/symlink/stub process setup.
    cmd_gate_scaffold "cmd_gate_master"
    ln -s "$PROJECT_ROOT/scripts/gates/gate_dm_signal_production_smoke.sh" \
        "$TEST_PROJECT/scripts/gates/gate_dm_signal_production_smoke.sh"
    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: infra
    path: __TEST_PROJECT__
EOF
    cat > "$TEST_PROJECT/tasks/lessons.md" <<'EOF'
# Lessons
- **status**: confirmed
EOF
    cat > "$TEST_PROJECT/queue/inbox/karo.yaml" <<'EOF'
messages:
  - id: msg_test
    read: false
EOF
    write_task_fixture "sasuke_report_${TEST_CMD_ID}.yaml"
    export CMD_GATE_MASTER_PROJECT="$TEST_PROJECT"
    export CMD_GATE_MASTER_TMPDIR="$TEST_TMPDIR"
}

# test_necessity: completion must accept every YAML spelling that
# gate_report_format normalizes to boolean and reject non-booleans.
# regression_justification: the old awk parser stripped double quotes but not
# single quotes, so found: 'true' passed report validation and then BLOCKed here.
@test "lesson_candidate parser normalizes six YAML booleans and blocks two invalid values" {
    source "$GATE_HELPERS_FILE"
    local fixture="$BATS_TEST_TMPDIR/lesson-candidate.yaml"
    local value expected
    local -a cases=(
        "true|found_true"
        "'true'|found_true"
        '"true"|found_true'
        "false|ok_false"
        "'false'|ok_false"
        '"false"|ok_false'
        "truthy|malformed"
        "1|malformed"
    )

    for case_entry in "${cases[@]}"; do
        value="${case_entry%%|*}"
        expected="${case_entry#*|}"
        cat > "$fixture" <<EOF
lesson_candidate:
  found: $value
  title: contract title
  detail: contract detail
  no_lesson_reason: contract reason
EOF
        run lesson_candidate_status "$fixture"
        [ "$status" -eq 0 ]
        [ "$output" = "$expected" ]
    done
}

@test "build_clear_throughput_metric records stage durations for nested and flat task YAML" {
    source "$GATE_HELPERS_FILE"
    export CMD_ID="$TEST_CMD_ID"
    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml" "$TEST_PROJECT/queue/tasks/hanzo.yaml")
    mkdir -p "$TEST_PROJECT/queue/tasks"

    cat > "$YAML_FILE" <<EOF
commands:
  $TEST_CMD_ID:
    id: $TEST_CMD_ID
    delegated_at: "2026-07-08T09:00:00"
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_999
  deployed_at: '2026-07-08T09:01:00'
  acknowledged_at: '2026-07-08T09:02:00'
  done_at: '2026-07-08T09:07:00'
EOF
    cat > "$TEST_PROJECT/queue/tasks/hanzo.yaml" <<'EOF'
parent_cmd: cmd_999
deployed_at: '2026-07-08T09:03:00'
acknowledged_at: '2026-07-08T09:04:00'
done_at: '2026-07-08T09:09:00'
EOF

    run build_clear_throughput_metric "2026-07-08T09:10:00"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deploy_sec=180"* ]]
    [[ "$output" == *"work_sec=420"* ]]
    [[ "$output" == *"finalize_sec=60"* ]]
    [[ "$output" == *"e2e_sec=600"* ]]
    [[ "$output" == *"missing=none"* ]]
}

@test "build_clear_throughput_metric emits missing reason codes instead of unknown" {
    source "$GATE_HELPERS_FILE"
    export CMD_ID="$TEST_CMD_ID"
    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    mkdir -p "$TEST_PROJECT/queue/tasks"

    cat > "$YAML_FILE" <<EOF
commands:
  $TEST_CMD_ID:
    id: $TEST_CMD_ID
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_999
  deployed_at: '2026-07-08T09:01:00'
EOF

    run build_clear_throughput_metric "2026-07-08T09:10:00"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deploy_sec=na"* ]]
    [[ "$output" == *"work_sec=na"* ]]
    [[ "$output" == *"e2e_sec=na"* ]]
    [[ "$output" == *"missing=missing_issue_ts,missing_ack_ts,missing_done_ts,invalid_deploy_sec,invalid_work_sec,invalid_finalize_sec,invalid_e2e_sec"* ]]
    [[ "$output" != *"unknown"* ]]
}

@test "build_clear_throughput_metric falls back to cmd_design_quality timestamp when cmd has no delegated_at" {
    source "$GATE_HELPERS_FILE"
    export CMD_ID="$TEST_CMD_ID"
    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/logs"

    cat > "$YAML_FILE" <<EOF
commands:
  $TEST_CMD_ID:
    status: pending
EOF
    cat > "$TEST_PROJECT/logs/cmd_design_quality.yaml" <<EOF
- cmd_id: "$TEST_CMD_ID"
  timestamp: "2026-07-08T09:00:00Z"
  source: cmd_save_warn
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_999
  deployed_at: '2026-07-08T09:01:00'
  acknowledged_at: '2026-07-08T09:02:00'
  done_at: '2026-07-08T09:06:00'
EOF

    run build_clear_throughput_metric "2026-07-08T09:10:00"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deploy_sec=60"* ]]
    [[ "$output" == *"e2e_sec=600"* ]]
    [[ "$output" == *"missing=none"* ]]
}

@test "build_clear_throughput_metric resolves direct cmd from issued task deploy ack and report done" {
    source "$GATE_HELPERS_FILE"
    export CMD_ID="$TEST_CMD_ID"
    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/queue/reports"
    printf 'commands: {}\n' > "$YAML_FILE"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  issued_at: '2026-07-08T09:00:00'
  deployed_at: '2026-07-08T09:01:00'
  acknowledged_at: '2026-07-08T09:02:00'
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
parent_cmd: $TEST_CMD_ID
status: completed
timestamp: '2026-07-08T09:07:00'
EOF

    run build_clear_throughput_metric "2026-07-08T09:10:00"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deploy_sec=60 work_sec=300 finalize_sec=180 e2e_sec=600 missing=none"* ]]
}

@test "build_clear_throughput_metric permits zero deploy only for identical direct issue and deploy events" {
    source "$GATE_HELPERS_FILE"
    export CMD_ID="$TEST_CMD_ID"
    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/queue/reports"
    printf 'commands: {}\n' > "$YAML_FILE"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  issued_at: '2026-07-08T09:01:00'
  deployed_at: '2026-07-08T09:01:00'
  acknowledged_at: '2026-07-08T09:02:00'
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
parent_cmd: $TEST_CMD_ID
status: completed
timestamp: '2026-07-08T09:07:00'
EOF

    run build_clear_throughput_metric "2026-07-08T09:10:00"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deploy_sec=0 work_sec=300 finalize_sec=180 e2e_sec=540 missing=none"* ]]
}

@test "build_clear_throughput_metric preserves first issue across blocked retry and parallel deploy completion" {
    source "$GATE_HELPERS_FILE"
    export CMD_ID="$TEST_CMD_ID"
    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml" "$TEST_PROJECT/queue/tasks/hanzo.yaml")
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/queue/reports"
    printf 'commands: {}\n' > "$YAML_FILE"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  issued_at: '2026-07-08T09:00:00'
  deployed_at: '2026-07-08T09:04:00'
  acknowledged_at: '2026-07-08T09:05:00'
EOF
    cat > "$TEST_PROJECT/queue/tasks/hanzo.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  issued_at: '2026-07-08T09:00:30'
  deployed_at: '2026-07-08T09:03:00'
  acknowledged_at: '2026-07-08T09:05:00'
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
parent_cmd: $TEST_CMD_ID
status: completed
timestamp: '2026-07-08T09:08:00'
EOF

    run build_clear_throughput_metric "2026-07-08T09:10:00"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deploy_sec=240 work_sec=180 finalize_sec=120 e2e_sec=600 missing=none"* ]]
}

# test_necessity: retry時のdeploy/work/e2eを同一attempt境界へ揃え、負残差とworkリセット誤差を防ぐ。
@test "build_clear_throughput_metric resets all intervals to latest successful retry attempt" {
    source "$GATE_HELPERS_FILE"
    export CMD_ID="$TEST_CMD_ID"
    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/queue/reports" "$TEST_PROJECT/logs"
    printf 'commands: {}\n' > "$YAML_FILE"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  issued_at: '2026-07-08T09:00:00'
  deployed_at: '2026-07-08T09:56:00'
  acknowledged_at: '2026-07-08T09:03:00'
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
parent_cmd: $TEST_CMD_ID
status: completed
timestamp: '2026-07-08T09:58:00'
EOF
    cat > "$TEST_PROJECT/logs/deploy_issue_log.yaml" <<EOF
- attempt_id: "$TEST_CMD_ID:sasuke:first"
  cmd_id: "$TEST_CMD_ID"
  ninja: "sasuke"
  result: "issued"
  reason: "entry"
  timestamp: "2026-07-08T09:00:00"
- attempt_id: "$TEST_CMD_ID:sasuke:first"
  cmd_id: "$TEST_CMD_ID"
  ninja: "sasuke"
  result: "deployed"
  reason: "exit_0"
  timestamp: "2026-07-08T09:02:00"
- attempt_id: "$TEST_CMD_ID:sasuke:retry"
  cmd_id: "$TEST_CMD_ID"
  ninja: "sasuke"
  result: "issued"
  reason: "entry"
  timestamp: "2026-07-08T09:55:00"
- attempt_id: "$TEST_CMD_ID:sasuke:retry"
  cmd_id: "$TEST_CMD_ID"
  ninja: "sasuke"
  result: "deployed"
  reason: "exit_0"
  timestamp: "2026-07-08T09:56:00"
EOF

    run build_clear_throughput_metric "2026-07-08T10:00:00"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deploy_sec=60"* ]]
    [[ "$output" == *"work_sec=120"* ]]
    [[ "$output" == *"finalize_sec=120"* ]]
    [[ "$output" == *"e2e_sec=300"* ]]
    [[ "$output" == *"missing=none"* ]]
}

@test "build_clear_throughput_metric preserves reversed timestamp reasons without clamping" {
    source "$GATE_HELPERS_FILE"
    export CMD_ID="$TEST_CMD_ID"
    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/queue/reports"
    cat > "$YAML_FILE" <<EOF
commands:
  $TEST_CMD_ID:
    delegated_at: '2026-07-08T09:05:00'
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  deployed_at: '2026-07-08T09:01:00'
  acknowledged_at: '2026-07-08T09:02:00'
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
parent_cmd: $TEST_CMD_ID
status: completed
timestamp: '2026-07-08T09:07:00'
EOF

    run build_clear_throughput_metric "2026-07-08T09:10:00"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deploy_sec=na"* ]]
    [[ "$output" == *"invalid_deploy_sec"* ]]
    [[ "$output" != *"deploy_sec=0"* ]]
}

@test "build_clear_throughput_metric selects latest duplicate report done event" {
    source "$GATE_HELPERS_FILE"
    export CMD_ID="$TEST_CMD_ID"
    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/queue/reports"
    cat > "$YAML_FILE" <<EOF
commands:
  $TEST_CMD_ID:
    delegated_at: '2026-07-08T09:00:00'
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  deployed_at: '2026-07-08T09:01:00'
  acknowledged_at: '2026-07-08T09:02:00'
EOF
    for pair in early:06 late:08; do
        name="${pair%%:*}"; minute="${pair##*:}"
        cat > "$TEST_PROJECT/queue/reports/${name}_${TEST_CMD_ID}.yaml" <<EOF
parent_cmd: $TEST_CMD_ID
status: completed
timestamp: '2026-07-08T09:${minute}:00'
EOF
    done

    run build_clear_throughput_metric "2026-07-08T09:10:00"
    [ "$status" -eq 0 ]
    [[ "$output" == *"work_sec=360 finalize_sec=120 e2e_sec=600 missing=none"* ]]
}

@test "build_clear_duration_metric uses acknowledged_at and done_at for nested and flat task YAML" {
    source "$GATE_HELPERS_FILE"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml" "$TEST_PROJECT/queue/tasks/hanzo.yaml")
    MATCHING_TASK_FILES_PROCESSED_COUNT=0
    MATCHING_TASK_FILES_SKIPPED_COUNT=0
    mkdir -p "$TEST_PROJECT/queue/tasks"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_999
  acknowledged_at: '2026-07-08T09:00:00'
  done_at: '2026-07-08T09:03:00'
  deployed_at: '2026-07-01T00:00:00'
  completed_at: '2026-07-01T00:00:01'
EOF
    cat > "$TEST_PROJECT/queue/tasks/hanzo.yaml" <<'EOF'
parent_cmd: cmd_999
acknowledged_at: '2026-07-08T09:00:00'
done_at: '2026-07-08T09:05:00'
EOF

    run build_clear_duration_metric
    [ "$status" -eq 0 ]
    [ "$output" = "duration_sec=300" ]
}

@test "build_clear_duration_metric ignores stale fallback timestamps when acknowledged_at/done_at are present" {
    source "$GATE_HELPERS_FILE"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    MATCHING_TASK_FILES_PROCESSED_COUNT=0
    MATCHING_TASK_FILES_SKIPPED_COUNT=0
    mkdir -p "$TEST_PROJECT/queue/tasks"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_999
  acknowledged_at: '2026-07-08T09:00:00'
  done_at: '2026-07-08T09:02:00'
  deployed_at: '2026-01-01T00:00:00'
  completed_at: '2026-01-02T00:00:00'
EOF

    run build_clear_duration_metric
    [ "$status" -eq 0 ]
    [ "$output" = "duration_sec=120" ]
}

@test "build_clear_duration_metric falls back to dispatch marker and report timestamp when acknowledged_at/done_at/deployed_at/completed_at are all empty" {
    source "$GATE_HELPERS_FILE"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    MATCHING_TASK_FILES_PROCESSED_COUNT=0
    MATCHING_TASK_FILES_SKIPPED_COUNT=0
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/queue/dispatch_ntfy_started" "$TEST_PROJECT/queue/reports"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  acknowledged_at: ''
  done_at: ''
  deployed_at: ''
  completed_at: ''
EOF
    cat > "$TEST_PROJECT/queue/dispatch_ntfy_started/${TEST_CMD_ID}.started" <<'EOF'
timestamp: 2026-07-08T09:00:00
cmd_id: cmd_999
ninja: sasuke
title: test
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_999
timestamp: '2026-07-08T09:05:00'
EOF

    run build_clear_duration_metric
    [ "$status" -eq 0 ]
    [ "$output" = "duration_sec=300" ]
}

@test "build_clear_duration_metric ignores stale task file overwritten by next deployment and uses per-cmd fallback instead" {
    source "$GATE_HELPERS_FILE"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    MATCHING_TASK_FILES_PROCESSED_COUNT=0
    MATCHING_TASK_FILES_SKIPPED_COUNT=0
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/queue/dispatch_ntfy_started" "$TEST_PROJECT/queue/reports"

    # sasuke.yaml already overwritten by the NEXT cmd deployed to sasuke (parent_cmd differs,
    # deployed_at is later than the original cmd's own completion — would produce a bogus
    # negative duration if trusted instead of being ignored).
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_1000
  acknowledged_at: ''
  done_at: ''
  deployed_at: '2026-07-08T09:10:00'
  completed_at: ''
EOF
    cat > "$TEST_PROJECT/queue/dispatch_ntfy_started/${TEST_CMD_ID}.started" <<'EOF'
timestamp: 2026-07-08T09:00:00
cmd_id: cmd_999
ninja: sasuke
title: test
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_999
timestamp: '2026-07-08T09:05:00'
EOF

    run build_clear_duration_metric
    [ "$status" -eq 0 ]
    [ "$output" = "duration_sec=300" ]
}

@test "build_clear_duration_metric does not crash on offset-naive/aware mismatch (karo-direct cmd absent from shogun_to_karo.yaml) AC2" {
    source "$GATE_HELPERS_FILE"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    MATCHING_TASK_FILES_PROCESSED_COUNT=0
    MATCHING_TASK_FILES_SKIPPED_COUNT=0
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/queue/dispatch_ntfy_started" "$TEST_PROJECT/queue/reports"

    # Karo-direct hotfix cmds rotate task files fast enough that the task no
    # longer matches this cmd by the time GATE CLEAR runs, forcing the
    # fallback path: dispatch marker timestamp (naive, `date "+%Y-%m-%dT%H:%M:%S"`)
    # vs. report top-level timestamp (offset-aware, `date -Iseconds`). Mixing
    # naive and aware datetimes previously raised an uncaught TypeError that
    # killed the whole cmd_complete_gate.sh process under `set -e`.
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_1000
  acknowledged_at: ''
  done_at: ''
  deployed_at: '2026-07-08T09:10:00'
  completed_at: ''
EOF
    cat > "$TEST_PROJECT/queue/dispatch_ntfy_started/${TEST_CMD_ID}.started" <<'EOF'
timestamp: 2026-07-08T09:00:00
cmd_id: cmd_999
ninja: sasuke
title: test
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_999
timestamp: '2026-07-08T09:05:00+09:00'
EOF

    run build_clear_duration_metric
    [ "$status" -eq 0 ]
    [ "$output" = "duration_sec=300" ]
}

@test "canceled cmd excludes matching task files from completion tracking" {
    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"
    export CMD_ID="$TEST_CMD_ID"
    declare -A _CMD_TASK_MAP
    MATCHING_TASK_FILES=()

    cat > "$YAML_FILE" <<EOF
commands:
  $TEST_CMD_ID:
    id: $TEST_CMD_ID
    status: canceled
EOF
    cat > "$TASKS_DIR/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  status: assigned
EOF

    while IFS= read -r _cache_tf; do
        [ -f "$_cache_tf" ] || continue
        _CMD_TASK_MAP["$_cache_tf"]=1
        MATCHING_TASK_FILES+=("$_cache_tf")
    done < <({ grep -l "parent_cmd: ${CMD_ID}" "$TASKS_DIR"/*.yaml 2>/dev/null; grep -l "cmd_id: ${CMD_ID}" "$TASKS_DIR"/*.yaml 2>/dev/null; } | sort -u || true)

    [ "${#MATCHING_TASK_FILES[@]}" -eq 1 ]
    if cmd_status_is_canceled "$CMD_ID"; then
        MATCHING_TASK_FILES=()
        _CMD_TASK_MAP=()
    fi

    [ "${#MATCHING_TASK_FILES[@]}" -eq 0 ]
    run bash -c '[[ -z "${_CMD_TASK_MAP[*]}" ]]'
    [ "$status" -eq 0 ]
}

@test "task cmd matcher ignores stale cmd_id after current-format parent_cmd is cleared" {
    local matcher="$PROJECT_ROOT/scripts/lib/task_cmd_match.sh"
    local current="$TEST_PROJECT/queue/tasks/current_idle.yaml"
    local legacy="$TEST_PROJECT/queue/tasks/legacy.yaml"
    local active="$TEST_PROJECT/queue/tasks/active.yaml"

    cat > "$current" <<EOF
task:
  parent_cmd:
  cmd_id: $TEST_CMD_ID
  status: idle
EOF
    cat > "$legacy" <<EOF
task:
  cmd_id: $TEST_CMD_ID
  status: done
EOF
    cat > "$active" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  cmd_id: cmd_stale
  status: done
EOF

    run bash -c 'source "$1"; task_file_matches_cmd "$2" "$3"' _ "$matcher" "$current" "$TEST_CMD_ID"
    [ "$status" -ne 0 ]
    run bash -c 'source "$1"; task_file_matches_cmd "$2" "$3"' _ "$matcher" "$legacy" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    run bash -c 'source "$1"; task_file_matches_cmd "$2" "$3"' _ "$matcher" "$active" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
}

# test_necessity: 同一task_idを別忍者へ再配備した時、完了ゲートが旧担当の
# 未着reportを必須母数へ残して180秒待機する回帰を防ぐ。異なるtask_idの
# 正当な並列shardは同時に保持されることも同じ境界で保証する。
@test "task cmd matcher keeps newest reassignment generation but preserves distinct shards" {
    local matcher="$PROJECT_ROOT/scripts/lib/task_cmd_match.sh"
    local old_worker="$TEST_PROJECT/queue/tasks/hayate.yaml"
    local new_worker="$TEST_PROJECT/queue/tasks/hanzo.yaml"
    local shard="$TEST_PROJECT/queue/tasks/saizo.yaml"

    cat > "$old_worker" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_id: ${TEST_CMD_ID}_full
  deployed_at: '2026-08-03T03:04:56+09:00'
  status: acknowledged
EOF
    cat > "$new_worker" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_id: ${TEST_CMD_ID}_full
  deployed_at: '2026-08-03T03:06:08+09:00'
  status: done
EOF
    cat > "$shard" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_id: ${TEST_CMD_ID}_shard_b
  deployed_at: '2026-08-03T03:05:00+09:00'
  status: done
EOF

    run bash -c 'source "$1"; list_current_task_files_for_cmd "$2" "$3"' \
        _ "$matcher" "$TEST_PROJECT/queue/tasks" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" != *"$old_worker"* ]]
    [[ "$output" == *"$new_worker"* ]]
    [[ "$output" == *"$shard"* ]]
}

@test "auto_resolve_cmd_related_insights resolves pending insights that mention cmd_id" {
    export INSIGHTS_FILE="$TEST_PROJECT/queue/insights.yaml"
    cat > "$INSIGHTS_FILE" <<EOF
insights:
- id: INS-CMD-MATCH
  ts: "2026-05-15T00:00:00+09:00"
  insight: "source_cmd=$TEST_CMD_ID のLevel5候補"
  priority: "medium"
  source: "cmd_complete_gate:l6_horizontal:$TEST_CMD_ID"
  status: pending
- id: INS-OTHER
  ts: "2026-05-15T00:00:01+09:00"
  insight: "別cmd"
  priority: "medium"
  source: "manual"
  status: pending
EOF
    cat > "$TEST_PROJECT/queue/tasks/insight-owner.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  origin_insight_ids: [INS-CMD-MATCH]
EOF
    cp "$PROJECT_ROOT/scripts/insight_write.sh" "$TEST_PROJECT/scripts/insight_write.sh"
    cp "$PROJECT_ROOT/scripts/insight_resolve.sh" "$TEST_PROJECT/scripts/insight_resolve.sh"
    chmod +x "$TEST_PROJECT/scripts/insight_write.sh"
    chmod +x "$TEST_PROJECT/scripts/insight_resolve.sh"

    run auto_resolve_cmd_related_insights "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"resolved: 1 cmd-related insight(s)"* ]]

    python3 - <<PY
import yaml
data = yaml.safe_load(open("$INSIGHTS_FILE"))
rows = {e["id"]: e for e in data["insights"]}
assert rows["INS-CMD-MATCH"]["status"] == "resolved"
assert rows["INS-CMD-MATCH"]["resolved_reason"]
assert rows["INS-CMD-MATCH"]["action_artifact"]
assert rows["INS-OTHER"]["status"] == "pending"
PY
}

@test "auto_resolve_cmd_related_insights logs parser stderr for unreadable insights path" {
    export INSIGHTS_FILE="$TEST_PROJECT/queue/insights_as_dir.yaml"
    mkdir -p "$INSIGHTS_FILE"
    cp "$PROJECT_ROOT/scripts/insight_write.sh" "$TEST_PROJECT/scripts/insight_write.sh"
    cp "$PROJECT_ROOT/scripts/insight_resolve.sh" "$TEST_PROJECT/scripts/insight_resolve.sh"
    chmod +x "$TEST_PROJECT/scripts/insight_write.sh"
    chmod +x "$TEST_PROJECT/scripts/insight_resolve.sh"

    run auto_resolve_cmd_related_insights "$TEST_CMD_ID"
    [ "$status" -eq 1 ]
    # cmd_karo_hotfix_post_clear_fail_open_20260725 (AC1): この失敗はもうGATE CLEARを
    # 止めない(呼出し元がfail-open化)ため、メッセージも実態に合わせWARNへ変更した。
    [[ "$output" == *"[WARN] insight declaration selection failed (non-blocking)"* ]]
    grep -F "auto_resolve_cmd_related_insights parse:" "$TEST_PROJECT/logs/cmd_complete_gate_stderr.log"
}

@test "cmd_complete_gate protects shared file writes with lock_path flock" {
    run grep -F 'append_line_locked "$GATE_METRICS_LOG"' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]

    run grep -F '200>"$(lock_path "$tracking_file")"' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]

    run grep -F '200>"$(lock_path "$impact_file")"' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]

    run grep -F '200>"$(lock_path "$DASHBOARD")"' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]

    run grep -F '200>"$(lock_path "$_GV_DQ_FILE")"' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]

    run grep -F 'END_VERDICT_PY' "$SRC_GATE_SCRIPT"
    [ "$status" -ne 0 ]

    run grep -F 'handled by Gunshi verdict update to cmd_design_quality' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_gate_ctx.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export TEST_CMD_ID="cmd_999"
    mkdir -p "$TEST_PROJECT"
    cp -a --reflink=auto "$CMD_GATE_MASTER_PROJECT/." "$TEST_PROJECT/"
    export SCRIPT_DIR="$TEST_PROJECT"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"
    export LOG_DIR="$TEST_PROJECT/logs"
    export CMD_ID="$TEST_CMD_ID"

    sed -i "s|__TEST_PROJECT__|$TEST_PROJECT|" "$TEST_PROJECT/config/projects.yaml"

    source "$SRC_FIELD_GET_SCRIPT"
    source "$SRC_LOCK_PATH_SCRIPT"
    # shellcheck source=/dev/null
    source "$GATE_HELPERS_FILE"

    ALL_CLEAR=true
    BLOCK_REASONS=()

}

_run_command_files_modified_coverage_with_state() {
    check_command_files_modified_coverage
    echo "ALL_CLEAR=$ALL_CLEAR"
    echo "BLOCK_REASONS=${BLOCK_REASONS[*]}"
}

_run_self_grade_commit_file_coverage_with_state() {
    check_self_grade_commit_file_coverage
    echo "ALL_CLEAR=$ALL_CLEAR"
    echo "BLOCK_REASONS=${BLOCK_REASONS[*]}"
}

_write_command_coverage_fixture() {
    local command_text="$1"
    local files_modified_block="$2"
    local target_path="${3:-}"

    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    export MATCHING_TASK_FILES_PROCESSED_COUNT=0
    export MATCHING_TASK_FILES_SKIPPED_COUNT=0
    export ALL_CLEAR=true
    BLOCK_REASONS=()

    cat > "$YAML_FILE" <<EOF
commands:
  $TEST_CMD_ID:
    command: "$command_text"
    target_path: "$target_path"
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
files_modified:
$files_modified_block
EOF
}

_write_self_grade_fixture() {
    local files_modified_block="$1"
    local commit_hash
    commit_hash=$(git -C "$TEST_PROJECT" rev-parse HEAD)

    export SCRIPT_DIR="$TEST_PROJECT"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    export MATCHING_TASK_FILES_PROCESSED_COUNT=0
    export MATCHING_TASK_FILES_SKIPPED_COUNT=0
    export ALL_CLEAR=true
    BLOCK_REASONS=()

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
files_modified:
$files_modified_block
binary_checks:
  commit:
    - check: git commitが完了したか
      result: yes
commit_hash: $commit_hash
EOF
}

_init_self_grade_git_repo() {
    git -C "$TEST_PROJECT" init >/dev/null
    git -C "$TEST_PROJECT" config user.email test@example.com
    git -C "$TEST_PROJECT" config user.name Test
    mkdir -p "$TEST_PROJECT/scripts"
    printf 'before\n' > "$TEST_PROJECT/scripts/touched.sh"
    git -C "$TEST_PROJECT" add scripts/touched.sh
    git -C "$TEST_PROJECT" commit -m initial >/dev/null
    printf 'after\n' > "$TEST_PROJECT/scripts/touched.sh"
    git -C "$TEST_PROJECT" add scripts/touched.sh
    git -C "$TEST_PROJECT" commit -m "touch script" >/dev/null
}

@test "self-grade commit/files verification warns when files_modified is absent from git show -w" {
    _init_self_grade_git_repo
    _write_self_grade_fixture "  - path: scripts/reported_only.sh
    change: modified"

    run _run_self_grade_commit_file_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"SELF_GRADE_COMMIT_FILES files_modified not in report commit phase union"* ]]
    [[ "$output" == *"scripts/reported_only.sh"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
    [[ "$output" == *"BLOCK_REASONS="* ]]
}

@test "self-grade commit/files verification accepts files_modified covered by git show -w" {
    _init_self_grade_git_repo
    _write_self_grade_fixture "  - path: scripts/touched.sh
    change: modified"

    run _run_self_grade_commit_file_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (files_modified covered by report commit phase union"* ]]
    [[ "$output" == *"OK (self-grade commit file coverage)"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
    [[ "$output" == *"BLOCK_REASONS="* ]]
}

@test "self-grade commit/files verification merges files_modified from same parent_cmd phase reports" {
    _init_self_grade_git_repo
    printf 'phase1\n' > "$TEST_PROJECT/scripts/phase1.sh"
    printf 'phase2\n' > "$TEST_PROJECT/scripts/phase2.sh"
    git -C "$TEST_PROJECT" add scripts/phase1.sh scripts/phase2.sh
    git -C "$TEST_PROJECT" commit -m "multi phase files" >/dev/null

    _write_self_grade_fixture "  - path: scripts/phase2.sh
    change: modified"
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}_l0.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
files_modified:
  - path: scripts/phase1.sh
    change: modified
EOF

    run _run_self_grade_commit_file_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (files_modified covered by report commit phase union"* ]]
    [[ "$output" == *"OK (self-grade commit file coverage)"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "self-grade commit/files verification keeps single phase behavior" {
    _init_self_grade_git_repo
    _write_self_grade_fixture "  - path: scripts/touched.sh
    change: modified"

    run _run_self_grade_commit_file_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (files_modified covered by report commit phase union"* ]]
    [[ "$output" == *"OK (self-grade commit file coverage)"* ]]
}

@test "self-grade commit/files verification deduplicates files_modified across phase reports" {
    _init_self_grade_git_repo
    _write_self_grade_fixture "  - path: scripts/touched.sh
    change: modified"
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}_l0.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
files_modified:
  - path: scripts/touched.sh
    change: modified
EOF

    run collect_parent_cmd_report_files_modified "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c '^scripts/touched.sh$')" -eq 1 ]
}

@test "self-grade commit/files verification ignores unrelated newer HEAD and uses report commit_hash" {
    _init_self_grade_git_repo
    _write_self_grade_fixture "  - path: scripts/touched.sh
    change: modified"

    printf 'unrelated\n' > "$TEST_PROJECT/unrelated.txt"
    git -C "$TEST_PROJECT" add unrelated.txt
    git -C "$TEST_PROJECT" commit -m "unrelated newer head" >/dev/null

    run _run_self_grade_commit_file_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (files_modified covered by report commit phase union"* ]]
    [[ "$output" != *"unrelated.txt"* ]]
}

@test "validated direct SG7 context supplies project and exact report scope" {
    local bundle="$TEST_PROJECT/queue/gates/$TEST_CMD_ID/sg7_bundle.json"
    mkdir -p "$(dirname "$bundle")"
    cat > "$bundle" <<EOF
{"review":{"cmd_spec_source":"queue/reports/sasuke_report_${TEST_CMD_ID}.yaml"}}
EOF

    load_validated_sg7_context "$bundle" '{"project":"infra","scope":["scripts/a.sh","tests/a.bats"]}'

    [ "$CMD_PROJECT" = "infra" ]
    [ "$SG7_DIRECT_REPORT_SPEC" = "true" ]
    [ "$SG7_SPEC_SCOPE" = $'scripts/a.sh\ntests/a.bats' ]
    run collect_cmd_command_file_refs "$TEST_CMD_ID" ""
    [ "$status" -eq 0 ]
    [ "$output" = $'scripts/a.sh\ntests/a.bats' ]
}

@test "scope drift and WTF parse standard files_modified dash-path entries from direct SG7 scope" {
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    export MATCHING_TASK_FILES_PROCESSED_COUNT=0
    export MATCHING_TASK_FILES_SKIPPED_COUNT=0
    export SG7_DIRECT_REPORT_SPEC=true
    export SG7_SPEC_SCOPE=$'scripts/a.sh\ntests/a.bats'
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  target_path: scripts/a.sh
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
files_modified:
  - path: scripts/a.sh
    change: modified
  - path: tests/a.bats
    change: added
EOF
    get_cmd_head_hashes() { :; }

    run check_scope_drift
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (全2件 target_path内)"* ]]
    [[ "$output" != *"files_modified empty"* ]]

    run check_wtf_likelihood
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (files=2, revert=0)"* ]]
}

@test "script wiring scans tracked nested instructions and ignores ambient untracked docs" {
    git -C "$TEST_PROJECT" init -q
    git -C "$TEST_PROJECT" config user.email test@example.com
    git -C "$TEST_PROJECT" config user.name Test
    mkdir -p "$TEST_PROJECT/instructions/generated" "$TEST_PROJECT/scripts"
    printf '# tracked\n`scripts/existing.sh`\n' > "$TEST_PROJECT/instructions/generated/codex-karo.md"
    printf '# ambient\n`scripts/ambient-missing.sh`\n' > "$TEST_PROJECT/instructions/ambient.md"
    printf '#!/bin/bash\n' > "$TEST_PROJECT/scripts/existing.sh"
    git -C "$TEST_PROJECT" add instructions/generated/codex-karo.md scripts/existing.sh
    git -C "$TEST_PROJECT" commit -q -m initial

    run check_script_wiring cmd_no_matching_commit
    [ "$status" -eq 0 ]
    [[ "$output" == *$'CHECK\tREVERSE\tOK\tall 1 referenced scripts/*.sh path(s) exist'* ]]
    [[ "$output" != *"ambient-missing.sh"* ]]

    printf '# tracked\n`scripts/tracked-missing.sh`\n' > "$TEST_PROJECT/instructions/generated/codex-karo.md"
    git -C "$TEST_PROJECT" add instructions/generated/codex-karo.md
    git -C "$TEST_PROJECT" commit -q -m tracked-missing

    run check_script_wiring cmd_no_matching_commit
    [ "$status" -eq 0 ]
    [[ "$output" == *$'CHECK\tREVERSE\tWARN\t1 referenced scripts/*.sh path(s) do not exist'* ]]
    [[ "$output" == *"tracked-missing.sh <- instructions/generated/codex-karo.md"* ]]
    [[ "$output" != *"ambient-missing.sh"* ]]
}

@test "karo procedures document is tracked so clean clones retain referenced runbook" {
    run git -C "$PROJECT_ROOT" ls-files --error-unmatch instructions/karo-procedures.md
    [ "$status" -eq 0 ]
}

# ─── cmd_karo_hotfix_gate_report_discovery_after_redeploy: task snapshot=0でも
#     report自身のparent_cmd/task_idからcmd Aのreportを発見する(cmd_3844型偽BLOCK根治) ───

@test "discover_reports_for_cmd finds cmd A report/files_modified/binary_checks after worker task YAML is overwritten by cmd B AC1" {
    export SCRIPT_DIR="$TEST_PROJECT"
    export CMD_ID="$TEST_CMD_ID"

    # sasuke was redeployed to the NEXT cmd before this gate ran: sasuke.yaml
    # no longer references $TEST_CMD_ID at all (task snapshot=0 for cmd A).
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: cmd_next_9999
  report_filename: sasuke_report_cmd_next_9999.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: ${TEST_CMD_ID}_normal
parent_cmd: $TEST_CMD_ID
files_modified:
  - path: scripts/cmd_complete_gate.sh
    change: modified
binary_checks:
  AC1:
    - check: xxx
      result: yes
EOF

    run discover_reports_for_cmd "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke_report_${TEST_CMD_ID}.yaml"* ]]

    unset MATCHING_TASK_FILES
    run collect_report_modified_files
    [ "$status" -eq 0 ]
    [[ "$output" == *"scripts/cmd_complete_gate.sh"* ]]

    run python3 -c "
import yaml
with open('$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml') as f:
    data = yaml.safe_load(f)
# YAML 1.1 resolves unquoted 'yes' to boolean True (PyYAML safe_load).
result = data['binary_checks']['AC1'][0]['result']
assert result is True or str(result).strip().lower() == 'yes'
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == "ok" ]]
}

@test "discover_reports_for_cmd rejects prefix-collision cmd_ids (AC2 strict equality)" {
    export SCRIPT_DIR="$TEST_PROJECT"
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_cmd_100.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_100
files_modified:
  - path: scripts/exact.sh
    change: modified
EOF
    cat > "$TEST_PROJECT/queue/reports/hanzo_report_cmd_1000.yaml" <<'EOF'
worker_id: hanzo
parent_cmd: cmd_1000
files_modified:
  - path: scripts/prefix_collision.sh
    change: modified
EOF

    run discover_reports_for_cmd "cmd_100"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke_report_cmd_100.yaml"* ]]
    [[ "$output" != *"hanzo_report_cmd_1000.yaml"* ]]
}

@test "collect_report_modified_files merges task-snapshot reports with parent_cmd-discovered reports and excludes other cmds AC1 AC2" {
    export SCRIPT_DIR="$TEST_PROJECT"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"
    export CMD_ID="$TEST_CMD_ID"

    # hanzo: still tracked live via MATCHING_TASK_FILES (normal path).
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/hanzo.yaml")
    cat > "$TEST_PROJECT/queue/tasks/hanzo.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: hanzo_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/hanzo_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: hanzo
parent_cmd: $TEST_CMD_ID
files_modified:
  - path: scripts/live_task.sh
    change: modified
EOF

    # sasuke: task YAML already overwritten by the next cmd — only discoverable
    # via report parent_cmd match, not via MATCHING_TASK_FILES.
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: cmd_next_9999
  report_filename: sasuke_report_cmd_next_9999.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
files_modified:
  - path: scripts/stale_task.sh
    change: modified
EOF

    # A report for a completely different cmd must never be mixed in.
    cat > "$TEST_PROJECT/queue/reports/kotaro_report_cmd_other_9999.yaml" <<'EOF'
worker_id: kotaro
parent_cmd: cmd_other_9999
files_modified:
  - path: scripts/unrelated.sh
    change: modified
EOF

    run collect_report_modified_files
    [ "$status" -eq 0 ]
    [[ "$output" == *"scripts/live_task.sh"* ]]
    [[ "$output" == *"scripts/stale_task.sh"* ]]
    [[ "$output" != *"scripts/unrelated.sh"* ]]
}

@test "command/files_modified coverage does not false-BLOCK when task snapshot is 0 (cmd_3844 pattern) AC1 AC3" {
    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=()
    export MATCHING_TASK_FILES_PROCESSED_COUNT=0
    export MATCHING_TASK_FILES_SKIPPED_COUNT=0
    export ALL_CLEAR=true
    BLOCK_REASONS=()

    cat > "$YAML_FILE" <<EOF
commands:
  $TEST_CMD_ID:
    command: "scripts/cmd_complete_gate.sh を修正"
    target_path: ""
EOF

    # sasuke was redeployed to the NEXT cmd before this gate ran: sasuke.yaml
    # no longer references $TEST_CMD_ID at all (MATCHING_TASK_FILES snapshot=0),
    # but the completed report for cmd A still exists on disk (cmd_3844).
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: cmd_next_9999
  report_filename: sasuke_report_cmd_next_9999.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
files_modified:
  - path: scripts/cmd_complete_gate.sh
    change: modified
EOF

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (command欄ファイル参照 全1件がfiles_modifiedに記載済み)"* ]]
    [[ "$output" != *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
    [[ "$output" == *"BLOCK_REASONS="* ]]
    [[ "$output" != *"command_files_modified_mismatch"* ]]
}

@test "command/files_modified coverage reads archived command instead of false-SKIP after BLOCK archival" {
    _write_command_coverage_fixture \
        "scripts/cmd_complete_gate.sh と scripts/archived_missing.sh を修正" \
        "  - path: scripts/cmd_complete_gate.sh
    change: modified"

    mkdir -p "$TEST_PROJECT/queue/archive/cmds"
    mv "$YAML_FILE" "$TEST_PROJECT/queue/archive/cmds/${TEST_CMD_ID}_done.yaml"
    printf 'commands: {}\n' > "$YAML_FILE"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" == *"missing: scripts/archived_missing.sh"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
}

@test "command/files_modified coverage blocks when command target is missing from report" {
    _write_command_coverage_fixture \
        "scripts/cmd_complete_gate.sh と scripts/stop_check_inbox.sh を修正" \
        "  - path: tests/unit/test_cmd_complete_gate.bats
    change: modified"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" != *"missing: scripts/cmd_complete_gate.sh"* ]]
    [[ "$output" == *"missing: scripts/stop_check_inbox.sh"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
}

@test "command/files_modified coverage accepts full path and basename matches" {
    _write_command_coverage_fixture \
        "cmd_complete_gate.sh と scripts/stop_check_inbox.sh を修正" \
        "  - path: scripts/cmd_complete_gate.sh
    change: modified
  - path: hooks/stop_check_inbox.sh
    change: modified"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (command欄ファイル参照 全2件がfiles_modifiedに記載済み)"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
    [[ "$output" == *"BLOCK_REASONS="* ]]
}

@test "command/files_modified coverage ignores cmd_4250 bareword session_alerts false positive" {
    # test_necessity: command_refs must contain only explicit paths; a common
    # noun that happens to resemble a file stem must not BLOCK completion.
    mkdir -p "$TEST_PROJECT/queue"
    touch "$TEST_PROJECT/queue/session_alerts_shogun.txt"
    _write_command_coverage_fixture \
        "session_alertsを処理" \
        "  - path: scripts/gates/gate_shogun_startup.sh
    change: modified
  - path: scripts/gates/gate_karo_startup.sh
    change: modified
  - path: scripts/gates/gate_gunshi_startup.sh
    change: modified
  - path: tests/unit/test_gate_shogun_startup.bats
    change: modified
  - path: context/infrastructure.md
    change: modified" \
        "queue"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP (command欄に拡張子付きファイル参照なし)"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
    [[ "$output" == *"BLOCK_REASONS="* ]]
}

@test "command/files_modified coverage ignores slash-delimited domain alternatives but keeps real paths" {
    # test_necessity: slash-delimited enum values must not BLOCK completion,
    # while an explicit repository path in the same command remains enforced.
    _write_command_coverage_fixture \
        "full/tickerの挙動を維持し scripts/cmd_complete_gate.sh を修正" \
        "  - path: scripts/cmd_complete_gate.sh
    change: modified"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (command欄ファイル参照 全1件がfiles_modifiedに記載済み)"* ]]
    [[ "$output" != *"missing: full/ticker"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
    [[ "$output" == *"BLOCK_REASONS="* ]]
}

@test "command/files_modified coverage keeps explicit relative and absolute paths strict" {
    local absolute_target="$TEST_PROJECT/scripts/absolute_target"
    mkdir -p "$(dirname "$absolute_target")"
    touch "$absolute_target"

    _write_command_coverage_fixture \
        "$absolute_target と scripts/cmd_complete_gate.sh を修正" \
        "  - path: scripts/absolute_target
    change: modified
  - path: scripts/cmd_complete_gate.sh
    change: modified"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (command欄ファイル参照 全2件がfiles_modifiedに記載済み)"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
    [[ "$output" == *"BLOCK_REASONS="* ]]
}

@test "command/files_modified coverage blocks unrelated explicit path" {
    mkdir -p "$TEST_PROJECT/tests/unit"
    touch "$TEST_PROJECT/tests/unit/test_semantic_index_update.bats"

    _write_command_coverage_fixture \
        "tests/unit/test_semantic_index_update.batsを高速化" \
        "  - file: tests/unit/test_unrelated.bats
    change: modified" \
        "tests/unit"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" == *"missing: tests/unit/test_semantic_index_update.bats"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
}

@test "command/files_modified coverage ignores read-only command refs when write target is reported" {
    _write_command_coverage_fixture \
        "scripts/build_instructions.sh を読んで skills/reset-layout/SKILL.md を更新" \
        "  - path: skills/reset-layout/SKILL.md
    change: modified" \
        "skills/reset-layout/SKILL.md"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (command欄ファイル参照 全1件がfiles_modifiedに記載済み)"* ]]
    [[ "$output" != *"missing: scripts/build_instructions.sh"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
    [[ "$output" == *"BLOCK_REASONS="* ]]
}

@test "command/files_modified coverage still blocks when write target is missing after read-only refs" {
    _write_command_coverage_fixture \
        "scripts/build_instructions.sh を読んで skills/reset-layout/SKILL.md を更新" \
        "  - path: scripts/build_instructions.sh
    change: read" \
        "skills/reset-layout/SKILL.md"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" == *"missing: skills/reset-layout/SKILL.md"* ]]
    [[ "$output" != *"missing: scripts/build_instructions.sh"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
}

@test "command/files_modified coverage skips for recon sentinel (no code change)" {
    _write_command_coverage_fixture \
        "memory_db_import.pyのsummary/detail書込み処理を特定する" \
        "  - path: 偵察のみ（コード変更なし）
    change: none"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP (files_modified=no-code-change sentinel"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "command/files_modified coverage skips product refs for recon-only cmd with research artifacts" {
    _write_command_coverage_fixture \
        "backend/app/api/signals.py と frontend/app/admin/visibility/page.tsx を精読して原因を特定" \
        "  - path: docs/research/cmd_999_visibility_recon.md
    change: added
  - path: context/dm-signal-ops.md
    change: modified"
    export HAS_RECON=true
    export HAS_IMPLEMENT=false

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP (recon/scout-only cmd: command file refs are investigation inputs)"* ]]
    [[ "$output" != *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "task type detection classifies scout as recon-only" {
    _write_command_coverage_fixture \
        "backend/app/api/signals.py を精読" \
        "  - path: docs/research/cmd_999_visibility_recon.md
    change: added"
    cat >> "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
  task_type: scout
EOF
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"

    run detect_task_types "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [ "$output" = "true false" ]
}

# test_necessity: cmd_complete_gate must classify every deployed recon2 task as
# recon-only so investigation commands never acquire implementation-only gates.
@test "task type detection classifies recon2 as recon-only" {
    _write_command_coverage_fixture \
        "SIGNAL変更を二名で調査" \
        "  - path: docs/research/cmd_999_signal_change_recon.md
    change: added"
    cat >> "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
  task_type: recon2
EOF
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"

    run detect_task_types "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [ "$output" = "true false" ]
}

@test "task type detection classifies full as implementation" {
    _write_command_coverage_fixture \
        "backend/app/api/signals.py を修正" \
        "  - path: backend/app/api/signals.py
    change: modified"
    cat >> "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
  task_type: full
EOF
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"

    run detect_task_types "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [ "$output" = "false true" ]
}

@test "task type detection fail-closes unknown type as implementation" {
    _write_command_coverage_fixture \
        "scripts/tool.sh を修正" \
        "  - path: scripts/tool.sh
    change: modified"
    cat >> "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
  task_type: future_type
EOF
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"

    run detect_task_types "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unknown task_type: 'future_type'; fail-closed as implementation"* ]]
    [[ "$output" == *"false true"* ]]
}

@test "task type detection fail-closes missing type as implementation" {
    _write_command_coverage_fixture \
        "scripts/tool.sh を修正" \
        "  - path: scripts/tool.sh
    change: modified"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"

    run detect_task_types "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Missing task_type; fail-closed as implementation"* ]]
    [[ "$output" == *"false true"* ]]
}

# test_necessity: a command containing both investigation and implementation
# tasks must retain both conditional gate families.
@test "task type detection classifies mixed recon2 and implementation as both" {
    _write_command_coverage_fixture \
        "SIGNAL変更を調査して修正" \
        "  - path: scripts/cmd_complete_gate.sh
    change: modified"
    cat >> "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
  task_type: recon2
EOF
    cat > "$TEST_PROJECT/queue/tasks/hanzo.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: hotfix
EOF
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"
    unset MATCHING_TASK_FILES

    run detect_task_types "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [ "$output" = "true true" ]
}

@test "command/files_modified coverage remains strict for mixed recon and implementation cmd" {
    _write_command_coverage_fixture \
        "backend/app/api/signals.py を調査して修正" \
        "  - path: docs/research/cmd_999_visibility_recon.md
    change: added"
    export HAS_RECON=true
    export HAS_IMPLEMENT=true

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" == *"missing: backend/app/api/signals.py"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
}

@test "command/files_modified coverage blocks typo path even when file does not exist" {
    _write_command_coverage_fixture \
        "scripts/cmd_complete_gate.sh を修正" \
        "  - path: scripts/typo_nonexistent_file.sh
    change: modified"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
}

@test "command/files_modified coverage ignores product names that look like file paths" {
    _write_command_coverage_fixture \
        "Next.js標準のESLint設定ファイルを追加しnpm run lintの非対話実行を確認" \
        "  - path: frontend/.eslintrc.json
    change: added
  - path: frontend/package.json
    change: modified" \
        "frontend"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP (command欄に拡張子付きファイル参照なし)"* ]]
    [[ "$output" != *"missing: Next.js"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
    [[ "$output" == *"BLOCK_REASONS="* ]]
}

@test "command/files_modified coverage still checks real uppercase files" {
    touch "$TEST_PROJECT/README.md"

    _write_command_coverage_fixture \
        "README.mdを更新" \
        "  - path: docs/other.md
    change: modified"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" == *"missing: README.md"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
}

@test "command/files_modified coverage excludes execution-only refs (LG037 FP fix)" {
    _write_command_coverage_fixture \
        "SKILL.md 8件のスクリプト参照陳腐化を修正。note_draft.shを実行して確認。report_field_set.shを実行。gate_skill_script_refs.shで検証。" \
        "  - path: skills/reset-layout/SKILL.md
    change: modified"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    [[ "$output" != *"missing: note_draft.sh"* ]]
    [[ "$output" != *"missing: report_field_set.sh"* ]]
    [[ "$output" != *"missing: gate_skill_script_refs.sh"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "command/files_modified coverage excludes exec_prefix refs (bash/python3 直前)" {
    _write_command_coverage_fixture \
        "scripts/target.sh を修正し bash scripts/verify.sh で検証。python3 scripts/check.py で確認。" \
        "  - path: scripts/target.sh
    change: modified"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    [[ "$output" != *"missing: scripts/verify.sh"* ]]
    [[ "$output" != *"missing: scripts/check.py"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "command/files_modified coverage excludes clause_boundary refs (読点で別節のwrite_marker)" {
    _write_command_coverage_fixture \
        "scripts/target.sh を修正。scripts/semantic_search.sh を呼び出し、チェックを追加。" \
        "  - path: scripts/target.sh
    change: modified"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    [[ "$output" != *"missing: scripts/semantic_search.sh"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "command/files_modified coverage excludes extended read_markers (分析/呼び出/出力)" {
    _write_command_coverage_fixture \
        "scripts/target.sh を修正。scripts/analysis.sh で分析。scripts/call.sh を呼び出して出力確認。" \
        "  - path: scripts/target.sh
    change: modified"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    [[ "$output" != *"missing: scripts/analysis.sh"* ]]
    [[ "$output" != *"missing: scripts/call.sh"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "command/files_modified coverage treats csv input 'から' as read-only" {
    _write_command_coverage_fixture \
        "AC1: grid_monthly_fast.csv全ファイルからrolling_1y_low算出→14指標テーブル。AC3: docs/research/gs_3objective_correlation_analysis_20260707.mdを更新" \
        "  - path: docs/research/gs_3objective_correlation_analysis_20260707.md
    change: modified"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    [[ "$output" != *"missing: grid_monthly_fast.csv"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "command/files_modified coverage excludes verified_existing_dependency refs (LG037)" {
    _write_command_coverage_fixture \
        "scripts/cmd_complete_gate.sh と scripts/deploy_task.sh を修正" \
        "  - path: scripts/cmd_complete_gate.sh
    change: modified"

    # Add verified_existing_dependency to report
    cat >> "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
verified_existing_dependency:
  - path: scripts/deploy_task.sh
    reason: "実行のみ参照"
EOF

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" != *"missing: scripts/deploy_task.sh"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "command/files_modified coverage excludes files_modified verified_existing_dependency refs" {
    _write_command_coverage_fixture \
        "scripts/cmd_complete_gate.sh と CLAUDE.md を修正" \
        "  - path: scripts/cmd_complete_gate.sh
    change: modified
  - path: CLAUDE.md
    change: verified_existing_dependency
    reason: 変更不要と確認済み"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" != *"missing: CLAUDE.md"* ]]
    [[ "$output" == *"OK (command欄ファイル参照 全1件がfiles_modifiedに記載済み)"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "command/files_modified coverage excludes checked_not_modified refs" {
    _write_command_coverage_fixture \
        "scripts/cmd_complete_gate.sh と CLAUDE.md を修正" \
        "  - path: scripts/cmd_complete_gate.sh
    change: modified"

    cat >> "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
checked_not_modified:
  - path: CLAUDE.md
    reason: 正本再生成後に差分不要と確認
EOF

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" != *"missing: CLAUDE.md"* ]]
    [[ "$output" == *"OK (command欄ファイル参照 全1件がfiles_modifiedに記載済み)"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "command/files_modified coverage excludes verified_existing_dependency before target_path selection" {
    _write_command_coverage_fixture \
        "refactor-workorder-20260611.md を必読参照し、backend/app/api/main.py を修正" \
        "  - path: backend/app/api/main.py
    change: modified" \
        "refactor-workorder-20260611.md"

    cat >> "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
verified_existing_dependency:
  - path: /mnt/c/Python_app/DM-signal/.agent/task-force/refactor-workorder-20260611.md
    reason: "必読の権威文書。参照のみで変更対象ではない"
EOF

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (command欄ファイル参照 全1件がfiles_modifiedに記載済み)"* ]]
    [[ "$output" != *"missing: refactor-workorder-20260611.md"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "command/files_modified coverage excludes task readonly_ref before target_path selection" {
    _write_command_coverage_fixture \
        "refactor-workorder-20260611.md を必読参照し、backend/app/api/main.py を修正" \
        "  - path: backend/app/api/main.py
    change: modified" \
        "refactor-workorder-20260611.md"

    cat >> "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
  readonly_ref:
  - path: /mnt/c/Python_app/DM-signal/.agent/task-force/refactor-workorder-20260611.md
    reason: command欄の必読/参照専用ファイル
EOF

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (command欄ファイル参照 全1件がfiles_modifiedに記載済み)"* ]]
    [[ "$output" != *"missing: refactor-workorder-20260611.md"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "command/files_modified coverage preserves true positive after verified_existing_dependency filtering" {
    _write_command_coverage_fixture \
        "refactor-workorder-20260611.md を必読参照し、backend/app/api/main.py と backend/app/api/portfolios.py を修正" \
        "  - path: backend/app/api/main.py
    change: modified" \
        "refactor-workorder-20260611.md"

    cat >> "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
verified_existing_dependency:
  - path: /mnt/c/Python_app/DM-signal/.agent/task-force/refactor-workorder-20260611.md
    reason: "必読の権威文書。参照のみで変更対象ではない"
EOF

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" == *"missing: backend/app/api/portfolios.py"* ]]
    [[ "$output" != *"missing: refactor-workorder-20260611.md"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
}

@test "command/files_modified coverage preserves true positive after task readonly_ref filtering" {
    _write_command_coverage_fixture \
        "refactor-workorder-20260611.md を必読参照し、backend/app/api/main.py と backend/app/api/portfolios.py を修正" \
        "  - path: backend/app/api/main.py
    change: modified" \
        "refactor-workorder-20260611.md"

    cat >> "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
  readonly_ref:
  - path: /mnt/c/Python_app/DM-signal/.agent/task-force/refactor-workorder-20260611.md
    reason: command欄の必読/参照専用ファイル
EOF

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" == *"missing: backend/app/api/portfolios.py"* ]]
    [[ "$output" != *"missing: refactor-workorder-20260611.md"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
}

@test "command/files_modified coverage accepts archived cmd_3289 through cmd_3293 readonly refs" {
    local cmd report_name
    for cmd in cmd_3289 cmd_3290 cmd_3291 cmd_3292 cmd_3293; do
        report_name="kagemaru_report_${cmd}.yaml"
        cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  $cmd:
    command: "refactor-workorder-20260611.md と approval-20260611-wp1f-wp4-tz.md を必読参照し、backend/app/api/main.py を修正"
    target_path: "refactor-workorder-20260611.md"
EOF
        cat > "$TEST_PROJECT/queue/reports/$report_name" <<EOF
worker_id: kagemaru
parent_cmd: $cmd
files_modified:
  - path: backend/app/api/main.py
    change: modified
EOF
        cat > "$TEST_PROJECT/queue/tasks/kagemaru.yaml" <<EOF
task:
  parent_cmd: $cmd
  report_filename: $report_name
  readonly_ref:
  - path: refactor-workorder-20260611.md
    reason: command欄の必読/参照専用ファイル
  - path: approval-20260611-wp1f-wp4-tz.md
    reason: command欄の必読/参照専用ファイル
EOF

        export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
        export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/kagemaru.yaml")
        export CMD_ID="$cmd"
        export ALL_CLEAR=true
        BLOCK_REASONS=()

        run _run_command_files_modified_coverage_with_state
        [ "$status" -eq 0 ]
        [[ "$output" != *"COMMAND_SCOPE_MISSING"* ]]
        [[ "$output" != *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
    done
}

@test "command/files_modified coverage accepts archived cmd_3297 through cmd_3299 with task readonly_ref" {
    local cmd
    for cmd in cmd_3297 cmd_3298 cmd_3299; do
        case "$cmd" in
            cmd_3297)
                cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  $cmd:
    command: ".agent/task-force/refactor-workorder-20260611.md と .agent/task-force/approval-20260611-wp1f-wp4-tz.md を参照し、frontend/package.json を修正"
EOF
                cat > "$TEST_PROJECT/queue/reports/hayate_report_${cmd}.yaml" <<EOF
worker_id: hayate
parent_cmd: $cmd
files_modified:
  - path: frontend/package.json
    change: modified
EOF
                cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<EOF
task:
  parent_cmd: $cmd
  report_filename: hayate_report_${cmd}.yaml
  readonly_ref:
  - path: .agent/task-force/refactor-workorder-20260611.md
    reason: command欄の必読/参照専用ファイル
  - path: .agent/task-force/approval-20260611-wp1f-wp4-tz.md
    reason: command欄の必読/参照専用ファイル
EOF
                export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/hayate.yaml")
                ;;
            cmd_3298)
                cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  $cmd:
    command: ".agent/task-force/approval-20260611-wp1f-wp4-tz.md を参照し、backend/app/api/portfolios.py を修正"
EOF
                cat > "$TEST_PROJECT/queue/reports/kagemaru_report_${cmd}.yaml" <<EOF
worker_id: kagemaru
parent_cmd: $cmd
files_modified:
  - path: backend/app/api/portfolios.py
    change: modified
EOF
                cat > "$TEST_PROJECT/queue/tasks/kagemaru.yaml" <<EOF
task:
  parent_cmd: $cmd
  report_filename: kagemaru_report_${cmd}.yaml
  readonly_ref:
  - path: .agent/task-force/approval-20260611-wp1f-wp4-tz.md
    reason: command欄の必読/参照専用ファイル
EOF
                export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/kagemaru.yaml")
                ;;
            cmd_3299)
                cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  $cmd:
    command: "refactor-workorder-20260611.md / summary.md / manifest-frontend.md / manifest-backend.md を参照し、frontend/package.json と backend/app/api/main.py を修正"
EOF
                for ninja in hanzo hayate tobisaru; do
                    cat > "$TEST_PROJECT/queue/reports/${ninja}_report_${cmd}.yaml" <<EOF
worker_id: $ninja
parent_cmd: $cmd
files_modified:
  - path: frontend/package.json
    change: modified
  - path: backend/app/api/main.py
    change: modified
EOF
                    cat > "$TEST_PROJECT/queue/tasks/${ninja}.yaml" <<EOF
task:
  parent_cmd: $cmd
  report_filename: ${ninja}_report_${cmd}.yaml
  readonly_ref:
  - path: refactor-workorder-20260611.md
    reason: command欄の必読/参照専用ファイル
  - path: summary.md
    reason: command欄の必読/参照専用ファイル
  - path: manifest-frontend.md
    reason: command欄の必読/参照専用ファイル
  - path: manifest-backend.md
    reason: command欄の必読/参照専用ファイル
EOF
                done
                export MATCHING_TASK_FILES=(
                    "$TEST_PROJECT/queue/tasks/hanzo.yaml"
                    "$TEST_PROJECT/queue/tasks/hayate.yaml"
                    "$TEST_PROJECT/queue/tasks/tobisaru.yaml"
                )
                ;;
        esac

        export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
        export CMD_ID="$cmd"
        export ALL_CLEAR=true
        BLOCK_REASONS=()

        run _run_command_files_modified_coverage_with_state
        [ "$status" -eq 0 ]
        [[ "$output" != *"COMMAND_SCOPE_MISSING"* ]]
        [[ "$output" != *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
        [[ "$output" == *"ALL_CLEAR=true"* ]]
    done
}

@test "preflight auto-registers found:true lesson candidate when lesson.done is missing" {
    rm -f "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done"
    export ALL_GATES=()
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    export MATCHING_TASK_FILES_PROCESSED_COUNT=0
    export MATCHING_TASK_FILES_SKIPPED_COUNT=0

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
lesson_candidate:
  found: true
  project: infra
  title: 自動登録テスト
  detail: preflight should auto-register this candidate.
EOF
    cat > "$TEST_PROJECT/scripts/auto_draft_lesson.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$TEST_PROJECT/auto_draft_calls.log"
mkdir -p "$TEST_PROJECT/queue/gates/$TEST_CMD_ID"
{
  echo "timestamp: 2026-05-24T00:00:00"
  echo "source: lesson_write"
} > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done"
EOF
    chmod +x "$TEST_PROJECT/scripts/auto_draft_lesson.sh"

    run preflight_gate_flags "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lesson: auto-registering found:true candidate (sasuke)"* ]]
    [[ "$output" == *"lesson: preflight OK (via auto_draft_lesson/lesson_write)"* ]]
    grep -q "sasuke_report_${TEST_CMD_ID}.yaml" "$TEST_PROJECT/auto_draft_calls.log"
    grep -Fx "source: lesson_write" "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done"
}

@test "preflight skips lesson auto-register when lesson.done already exists" {
    export ALL_GATES=()
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    export MATCHING_TASK_FILES_PROCESSED_COUNT=0
    export MATCHING_TASK_FILES_SKIPPED_COUNT=0

    cat > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done" <<'EOF'
timestamp: 2026-05-24T00:00:00
source: lesson_write
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
lesson_candidate:
  found: true
  project: infra
  title: 冪等テスト
  detail: auto_draft must not run when lesson.done exists.
EOF
    cat > "$TEST_PROJECT/scripts/auto_draft_lesson.sh" <<'EOF'
#!/usr/bin/env bash
printf 'called\n' >> "$TEST_PROJECT/auto_draft_calls.log"
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/auto_draft_lesson.sh"

    run preflight_gate_flags "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lesson: already exists (skip)"* ]]
    [ ! -f "$TEST_PROJECT/auto_draft_calls.log" ]
    grep -Fx "source: lesson_write" "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done"
}

@test "preflight uses lesson_check for found:false lesson candidate" {
    rm -f "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done"
    export ALL_GATES=()
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    export MATCHING_TASK_FILES_PROCESSED_COUNT=0
    export MATCHING_TASK_FILES_SKIPPED_COUNT=0

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
lesson_candidate:
  found: false
EOF
    cat > "$TEST_PROJECT/scripts/auto_draft_lesson.sh" <<'EOF'
#!/usr/bin/env bash
printf 'called\n' >> "$TEST_PROJECT/auto_draft_calls.log"
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/lesson_check.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$1" "$2" >> "$TEST_PROJECT/lesson_check_calls.log"
mkdir -p "$TEST_PROJECT/queue/gates/$1"
{
  echo "timestamp: 2026-05-24T00:00:00"
  echo "source: lesson_check"
} > "$TEST_PROJECT/queue/gates/$1/lesson.done"
EOF
    chmod +x "$TEST_PROJECT/scripts/auto_draft_lesson.sh" "$TEST_PROJECT/scripts/lesson_check.sh"

    run preflight_gate_flags "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lesson: preflight OK (via lesson_check)"* ]]
    [ ! -f "$TEST_PROJECT/auto_draft_calls.log" ]
    grep -q "$TEST_CMD_ID|preflight: no found:true lesson_candidate" "$TEST_PROJECT/lesson_check_calls.log"
    grep -Fx "source: lesson_check" "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done"
}

@test "lesson_done_missing is WARN and does not force ALL_CLEAR false" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
needle = "lesson_candidate found:true but lesson.done not found"
idx = text.index(needle)
branch_start = text.rfind("else", 0, idx)
branch_end = text.index("\n            fi", idx)
branch = text[branch_start:branch_end]

assert "WARN:" in branch, branch
assert "notify_karo_lesson_registration_reminder" in branch, branch
assert "record_block_reason" not in branch, branch
assert "ALL_CLEAR=false" not in branch, branch
PY
    [ "$status" -eq 0 ]
}

@test "lesson_done_missing WARN sends karo reminder via inbox_write" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index("notify_karo_lesson_registration_reminder()")
end = text.index("\n}\n", start) + 3
func = text[start:end]

assert 'inbox_write.sh" karo' in func, func
assert "lesson_registration_reminder" in func, func
assert "lesson.done未生成" in func, func
assert "dedup" in func, func
PY
    [ "$status" -eq 0 ]
}

@test "lesson.done source=lesson_write satisfies GATE CLEAR lesson_candidate registration" {
    local done_file="$TEST_TMPDIR/lesson.done"
    cat > "$done_file" <<'EOF'
timestamp: 2026-07-02T04:55:00
source: lesson_write
EOF

    run lesson_done_satisfies_lesson_candidate_registration "$done_file"
    [ "$status" -eq 0 ]
}

@test "lesson.done note=duplicate_existing satisfies GATE CLEAR lesson_candidate registration" {
    local done_file="$TEST_TMPDIR/lesson.done"
    cat > "$done_file" <<'EOF'
timestamp: 2026-07-02T04:55:00
source: auto_draft
note: duplicate_existing (L922)
EOF

    run lesson_done_satisfies_lesson_candidate_registration "$done_file"
    [ "$status" -eq 0 ]
}

@test "GATE CLEAR lesson_candidate WARN branch checks lesson.done before warning" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index("Lesson candidate registration check (GATE CLEAR):")
end = text.index("Workaround rate (GATE CLEAR):", start)
branch = text[start:end]

assert "lesson_done_satisfies_lesson_candidate_registration" in branch, branch
assert branch.index("lesson_done_satisfies_lesson_candidate_registration") < branch.index("WARN: lesson_candidate未登録"), branch
PY
    [ "$status" -eq 0 ]
}

@test "missing lesson gate is WARN and sends karo reminder" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
needle = 'if [ "$gate" = "lesson" ]; then'
idx = text.index(needle)
branch_end = text.index("\n        else", idx)
branch = text[idx:branch_end]

assert "WARN:" in branch, branch
assert "notify_karo_lesson_registration_reminder" in branch, branch
assert "record_block_reason" not in branch, branch
assert "ALL_CLEAR=false" not in branch, branch
PY
    [ "$status" -eq 0 ]
}

@test "non-lesson missing gates remain blocking" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
needle = 'if [ "$gate" = "lesson" ]; then'
idx = text.index(needle)
else_start = text.index("\n        else", idx)
branch_end = text.index("\n        fi", else_start)
branch = text[else_start:branch_end]

assert "[CRITICAL]" in branch, branch
assert 'record_block_reason "missing_gate:${gate}"' in branch, branch
assert "ALL_CLEAR=false" in branch, branch
PY
    [ "$status" -eq 0 ]
}

@test "resolve_report_file warns when auto unwrap returns empty status after flock timeout" {
    local report_file="$TEST_PROJECT/queue/reports/hayate_report_${TEST_CMD_ID}.yaml"
    export SCRIPT_DIR="$TEST_PROJECT"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"
    export CMD_ID="$TEST_CMD_ID"

    cat > "$TASKS_DIR/hayate.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: hayate_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$report_file" <<'EOF'
report:
  worker_id: hayate
  status: completed
EOF

    # The boundary under test is flock failure handling, not flock's real
    # five-second clock.  Return the same failure deterministically.
    flock() {
        return 1
    }

    run resolve_report_file hayate "$TEST_CMD_ID"

    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto_unwrap] WARN: flock timeout on report YAML, skipping unwrap"* ]]
    [[ "$output" == *"[gate] WARN: report YAML unwrap returned unknown status '<empty>': $report_file"* ]]
    [[ "$output" == *"$report_file"* ]]
}

@test "resolve_report_file fast-paths flat report without unwrap warning" {
    local report_file="$TEST_PROJECT/queue/reports/hayate_report_${TEST_CMD_ID}.yaml"
    export SCRIPT_DIR="$TEST_PROJECT"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"
    export CMD_ID="$TEST_CMD_ID"

    cat > "$TASKS_DIR/hayate.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: hayate_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$report_file" <<'EOF'
# preserved comment

worker_id: hayate
status: completed
EOF

    run resolve_report_file hayate "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [ "$output" = "$report_file" ]
    [[ "$output" != *"unwrap returned unknown"* ]]
}

@test "resolve_report_file uses preloaded filename cache over repeated task scan" {
    local report_file="$TEST_PROJECT/queue/reports/hayate_cached_${TEST_CMD_ID}.yaml"
    export SCRIPT_DIR="$TEST_PROJECT"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"
    export CMD_ID="$TEST_CMD_ID"
    declare -gA REPORT_FILENAME_CACHE=([hayate]="hayate_cached_${TEST_CMD_ID}.yaml")
    export REPORT_FILENAME_CACHE_READY=true

    cat > "$TASKS_DIR/hayate.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: wrong_should_not_be_read.yaml
EOF
    printf 'worker_id: hayate\nstatus: completed\n' > "$report_file"

    run resolve_report_file hayate "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [ "$output" = "$report_file" ]
}

@test "resolve_report_file unwraps wrapped report once then uses flat fast path" {
    local report_file="$TEST_PROJECT/queue/reports/hayate_report_${TEST_CMD_ID}.yaml"
    export SCRIPT_DIR="$TEST_PROJECT"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"
    export CMD_ID="$TEST_CMD_ID"

    cat > "$TASKS_DIR/hayate.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: hayate_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$report_file" <<'EOF'
# preserved comment
report:
  worker_id: hayate
  status: completed
EOF

    run resolve_report_file hayate "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"report YAML auto-unwrapped"* ]]
    ! grep -q '^report:' "$report_file"
    grep -q '^worker_id: hayate' "$report_file"

    run resolve_report_file hayate "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [ "$output" = "$report_file" ]
}

@test "CoDD registry append extracts target and before/after from report and spec" {
    mkdir -p "$TEST_PROJECT/docs/research"
    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")

    cat > "$TEST_PROJECT/docs/research/codd_refactor_registry.md" <<'EOF'
# CoDD Refactor Registry

| 日付 | 実施者 | 対象スクリプト/領域 | Phase到達 | Before→After | spec/after設計書パス |
|------|--------|---------------------|-----------|--------------|----------------------|
EOF
    cat > "$YAML_FILE" <<EOF
commands:
  $TEST_CMD_ID:
    title: "CoDD improvement"
    command: "CoDDで scripts/demo_gate.sh を改善"
EOF
    cat > "$TEST_PROJECT/docs/research/codd_spec_demo_${TEST_CMD_ID}.md" <<'EOF'
# CoDD spec

Target: `scripts/demo_gate.sh`
before median: 120ms
after median: 30ms
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
status: done
result:
  summary: "CoDD spec docs/research/codd_spec_demo_${TEST_CMD_ID}.md に基づき before 120ms after 30ms"
files_modified:
  - path: scripts/demo_gate.sh
EOF

    run append_codd_registry_entry "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: appended $TEST_CMD_ID"* ]]
    grep -q "scripts/demo_gate.sh" "$TEST_PROJECT/docs/research/codd_refactor_registry.md"
    grep -q "120ms → 30ms" "$TEST_PROJECT/docs/research/codd_refactor_registry.md"
    grep -q "$TEST_CMD_ID" "$TEST_PROJECT/docs/research/codd_refactor_registry.md"
}

@test "CoDD registry append prefers report real runtime fields over summary timings" {
    mkdir -p "$TEST_PROJECT/docs/research"
    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")

    cat > "$TEST_PROJECT/docs/research/codd_refactor_registry.md" <<'EOF'
# CoDD Refactor Registry

| 日付 | 実施者 | 対象スクリプト/領域 | Phase到達 | Before→After | spec/after設計書パス |
|------|--------|---------------------|-----------|--------------|----------------------|
EOF
    cat > "$YAML_FILE" <<EOF
commands:
  $TEST_CMD_ID:
    title: "CoDD improvement"
    command: "CoDDで scripts/demo_gate.sh を改善"
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  assigned_to: sasuke
  target_path: scripts/demo_gate.sh
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
status: done
before_real_ms: 80
after_real_ms: 70
result:
  summary: "単発time表示では 0.08s -> 0.07s と見えるが、台帳用real msを正とする"
files_modified:
  - path: scripts/demo_gate.sh
EOF

    run append_codd_registry_entry "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: appended $TEST_CMD_ID"* ]]
    grep -q "80ms → 70ms" "$TEST_PROJECT/docs/research/codd_refactor_registry.md"
    ! grep -q "0.08s → 0.07s" "$TEST_PROJECT/docs/research/codd_refactor_registry.md"
}

@test "run_codd_propagate_update executes codd propagate update after gate clear" {
    local codd_log="$TEST_TMPDIR/codd_args.log"
    local stub_codd="$TEST_TMPDIR/codd"
    cat > "$stub_codd" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$TEST_CODD_LOG"
echo "propagate done"
EOF
    chmod +x "$stub_codd"

    export CODD_BIN="$stub_codd"
    export CODD_PROPAGATE_PATH="$TEST_PROJECT"
    export TEST_CODD_LOG="$codd_log"

    run run_codd_propagate_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"CoDD propagate update (GATE CLEAR):"* ]]
    [[ "$output" == *"OK: codd propagate --path $TEST_PROJECT --update"* ]]
    [[ "$output" == *"propagate done"* ]]
    [ "$(cat "$codd_log")" = "propagate --path $TEST_PROJECT --update" ]
}

@test "run_codd_propagate_update warns but does not block when codd is missing" {
    export CODD_BIN="$TEST_TMPDIR/missing-codd"

    run run_codd_propagate_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN] codd executable not found (skip)"* ]]
}

@test "normalize_block_reason_to_workaround_categories maps gate BLOCK reasons to WA categories" {
    run normalize_block_reason_to_workaround_categories "report_format:hayate.yaml|hayate:binary_checks_fail|missing_gate:review_gate|commit_missing"
    [ "$status" -eq 0 ]
    [[ "$output" == *"report_yaml_format"* ]]
    [[ "$output" == *"gate_missing"* ]]
    [[ "$output" == *"commit_missing"* ]]
}

@test "cmd_complete_gate appends first gate model profile metrics to gate_metrics rows" {
    grep -q 'build_first_gate_model_metric()' "$SRC_GATE_SCRIPT"
    grep -q 'first_gate=%s' "$SRC_GATE_SCRIPT"
    grep -q 'model_profile=%s' "$SRC_GATE_SCRIPT"
    python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
script = open(sys.argv[1], encoding='utf-8').read()
for marker in [
    'CLEAR\\tno_task_benchmark_fast_path',
    'OVERRIDE\\temergency_override',
    'BLOCK\\tcdp_production_check_failed',
    'CLEAR\\tall_gates_passed',
    # cmd_karo_hotfix_gate_metrics_literal_tab_20260725: the 5 early-exit
    # BLOCK writes were fixed to use printf '%s\t%s\tBLOCK\t%s' too, which
    # also contains the substring 'BLOCK\t%s'. Match the longer, still-unique
    # tail ('\t%s\t%s' continuing into task_type/model) so this keeps
    # targeting the generic block_reason row instead of the first early-exit
    # match found by str.index().
    # cmd_karo_impl_gate_metrics_record_split_20260725: 記録カテゴリの3分離により
    # 汎用block行の第3カラムは固定文字列'BLOCK'ではなく変数になった。同じ行を
    # category+reasonの引数対で指し、model_profile併記の不変量はそのまま検証する。
    '"$_gate_record_category" "$block_reason"',
]:
    idx = script.index(marker)
    window = script[idx:idx + 700]
    assert 'GATE_FIRST_MODEL_METRIC' in window, marker
PY
}

@test "cmd_complete_gate early-exit BLOCK rows use printf so tabs are real bytes" {
    # test_necessity: cmd_karo_hotfix_gate_metrics_literal_tab_20260725 found
    # 5 early-exit BLOCK append_line_locked calls interpolating "\t" inside a
    # plain double-quoted string (bash never expands \t there), producing a
    # literal backslash-t two-char sequence that breaks every downstream
    # awk -F'\t' consumer of gate_metrics.log. This guards the printf fix so
    # a future edit cannot silently reintroduce the naked-interpolation form.
    python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
script = open(sys.argv[1], encoding='utf-8').read()
reasons = [
    'parent_cmd_contract',
    'sg7_bundle_missing_or_invalid',
    'review_two_phase_pending',
    'review_fingerprint_changed_after_normalize',
    'context_freshness_own_commit_unreflected',
]
for reason in reasons:
    fixed = (
        'append_line_locked "$GATE_METRICS_LOG" "$(printf \'%s\\t%s\\tBLOCK\\t%s\' '
        '"$(date +%Y-%m-%dT%H:%M:%S)" "$CMD_ID" "' + reason + '")"'
    )
    assert fixed in script, 'missing printf fix for ' + reason
    broken = ')\\t${CMD_ID}\\tBLOCK\\t' + reason + '"'
    assert broken not in script, 'literal backslash-t regression for ' + reason
PY
}

@test "cmd_complete_gate honors GATE_METRICS_LOG override for no-task benchmark fast path" {
    local isolated_metrics="$TEST_TMPDIR/isolated/gate_metrics.log"
    mkdir -p "$(dirname "$isolated_metrics")"
    : > "$TEST_PROJECT/logs/gate_metrics.log"

    run env GATE_METRICS_LOG="$isolated_metrics" bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" cmd_nonexistent_benchmark

    [ "$status" -eq 0 ]
    [[ "$output" == *"No-task benchmark fast path"* ]]
    grep -Fq $'\tcmd_nonexistent_benchmark\tCLEAR\tno_task_benchmark_fast_path\t' "$isolated_metrics"
    ! grep -Fq "cmd_nonexistent_benchmark" "$TEST_PROJECT/logs/gate_metrics.log"
}

@test "cmd_complete real process blocks after normalize mutates approved report" {
    TEST_CMD_ID="cmd_fixture"
    local report="$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml"
    local metrics="$TEST_PROJECT/logs/gate_metrics.log"

    cp "$PROJECT_ROOT/scripts/bulletin_write.sh" "$TEST_PROJECT/scripts/bulletin_write.sh"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: implement
  status: done
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 2
  related_lessons: []
EOF
    cat > "$report" <<EOF
worker_id: sasuke
task_id: fixture
parent_cmd: $TEST_CMD_ID
status: completed
ac_version_read: 2
commit_hash: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
verdict: PASS
result:
  summary: approved before normalization
purpose_validation: {fit: true}
files_modified: [{path: scripts/fixture.sh}]
lesson_candidate: {found: false, no_lesson_reason: fixture}
lessons_useful: [{id: L625, useful: true, reason: fixture}]
binary_checks:
  AC1: [{check: fixture, result: yes}]
EOF
    cmd_gate_lib_override normalize_report.sh
    cat > "$TEST_PROJECT/scripts/lib/normalize_report.sh" <<'EOF'
#!/usr/bin/env bash
printf 'normalized_by_fixture: true\n' >> "$1"
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/lib/normalize_report.sh"
    rm -f "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/archive.done"
    : > "$metrics"
    : > "$TEST_PROJECT/notify.log"

    # cmd_karo_impl_approval_log_atomic_20260726: gunshi LGTM は台帳エントリ不在で fail-closed
    # になった。本testの対象は normalize 後の approved report 検査であり台帳契約ではないため、
    # fixture では検査だけ無効化する。
    REVIEW_APPROVAL_ROOT="$TEST_PROJECT" REVIEW_APPROVAL_NO_TRIGGER=1 REVIEW_APPROVAL_SKIP_LEDGER_CHECK=1 \
        bash "$PROJECT_ROOT/scripts/review_approval.sh" "$TEST_CMD_ID" gunshi LGTM "$report"
    REVIEW_APPROVAL_ROOT="$TEST_PROJECT" REVIEW_APPROVAL_NO_TRIGGER=1 \
        bash "$PROJECT_ROOT/scripts/review_approval.sh" "$TEST_CMD_ID" karo ACCEPT "$report"

    run env GATE_METRICS_LOG="$metrics" REVIEW_APPROVAL_ROOT="$TEST_PROJECT" \
        bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"

    [ "$status" -ne 0 ]
    [[ "$output" == *"review_fingerprint_changed_after_normalize"* ]]
    [ "$(grep -c $'\t'"$TEST_CMD_ID"$'\tCLEAR\t' "$metrics" || true)" -eq 0 ]
    # test_necessity: BLOCK rows must contain real tab bytes (not a literal
    # "\t" two-char sequence), or awk -F'\t' consumers (block_reasons lookup,
    # gate_fire dedupe) silently fail to parse the row.
    grep -Fq $'\t'"$TEST_CMD_ID"$'\tBLOCK\treview_fingerprint_changed_after_normalize' "$metrics"
    [ ! -e "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/archive.done" ]
    [ ! -s "$TEST_PROJECT/notify.log" ]
}

@test "gunshi verdict pre-check scans newest blocks first and stops at first success" {
    # test_necessity: pre-check must preserve chronological verdict semantics while
    # avoiding reads of older ~240KB logs after a resolving success is found.
    local fixture="$BATS_TEST_TMPDIR/verdict-tail"
    local py="$fixture/precheck.py"
    mkdir -p "$fixture/archive"
    awk '/^import sys, re, os, glob$/ {capture=1} capture {print} /^END_GV_PRECHECK_PY$/ {exit}' \
        "$PROJECT_ROOT/scripts/cmd_complete_gate.sh" | sed '$d' > "$py"

    cat > "$fixture/archive/gunshi_review_log_001_old.yaml" <<'EOF'
- cmd_id: cmd_fixture
  review_type: draft
  verdict: FAIL
  findings_summary: "old failure"
EOF
    cat > "$fixture/archive/gunshi_review_log_002_new.yaml" <<'EOF'
- cmd_id: cmd_fixture
  review_type: draft
  verdict: REQUEST_CHANGES
  findings_summary: "resolved request"
- cmd_id: cmd_fixture
  review_type: draft
  verdict: APPROVE
  findings_summary: "new success"
EOF
    cat > "$fixture/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_other
  review_type: draft
  verdict: FAIL
  findings_summary: "unrelated"
EOF

    run python3 "$py" cmd_fixture "$fixture/gunshi_review_log.yaml" "$fixture/archive"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]

    cat >> "$fixture/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_fixture
  review_type: draft
  verdict: FAIL
  findings_summary: "newest failure"
EOF
    run python3 "$py" cmd_fixture "$fixture/gunshi_review_log.yaml" "$fixture/archive"
    [ "$status" -eq 0 ]
    [[ "$output" == WARN* ]]
    [[ "$output" == *"newest failure"* ]]
    [[ "$output" != *"old failure"* ]]
    [[ "$output" != *"resolved request"* ]]
}

@test "update_karo_workaround_resolutions fills unresolved matching categories only" {
    export GATE_METRICS_LOG="$TEST_PROJECT/logs/gate_metrics.log"
    export KARO_WORKAROUNDS_FILE="$TEST_PROJECT/logs/karo_workarounds.yaml"
    export KARO_WORKAROUNDS_LOCK_FILE="$TEST_PROJECT/logs/karo_workarounds.lock"
    mkdir -p "$TEST_PROJECT/logs"

    cat > "$GATE_METRICS_LOG" <<EOF
2026-05-12T00:00:00	$TEST_CMD_ID	BLOCK	report_format:hayate_report.yaml	exact	unknown	unknown	none
2026-05-12T00:01:00	$TEST_CMD_ID	BLOCK	missing_gate:review_gate	exact	unknown	unknown	none
EOF
    cat > "$KARO_WORKAROUNDS_FILE" <<'EOF'
- cmd_id: cmd_old_report
  timestamp: '2026-05-12T00:00:00Z'
  ninja: hayate
  workaround: true
  category: report_yaml_format
  detail: 'report format workaround'
  root_cause: 'format gate failure'
  resolved_by_cmd: ''
- cmd_id: cmd_old_gate
  timestamp: '2026-05-12T00:00:00Z'
  ninja: kagemaru
  workaround: true
  category: gate_missing
  detail: 'review gate missing'
  root_cause: 'review gate not done'
  resolved_by_cmd: ''
- cmd_id: cmd_old_commit
  timestamp: '2026-05-12T00:00:00Z'
  ninja: saizo
  workaround: true
  category: commit_missing
  detail: 'commit missing'
  root_cause: 'commit not created'
  resolved_by_cmd: ''
- cmd_id: cmd_clean
  timestamp: '2026-05-12T00:00:00Z'
  ninja: kotaro
  workaround: false
  category: report_yaml_format
  detail: ''
  root_cause: ''
  resolved_by_cmd: ''
EOF

    run update_karo_workaround_resolutions "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Karo workaround resolution update (GATE CLEAR):"* ]]
    [[ "$output" == *"updated=2"* ]]
    grep -A7 "cmd_id: cmd_old_report" "$KARO_WORKAROUNDS_FILE" | grep -q "resolved_by_cmd: '$TEST_CMD_ID'"
    grep -A7 "cmd_id: cmd_old_gate" "$KARO_WORKAROUNDS_FILE" | grep -q "resolved_by_cmd: '$TEST_CMD_ID'"
    grep -A7 "cmd_id: cmd_old_commit" "$KARO_WORKAROUNDS_FILE" | grep -q "resolved_by_cmd: ''"
    grep -A7 "cmd_id: cmd_clean" "$KARO_WORKAROUNDS_FILE" | grep -q "resolved_by_cmd: ''"
}

@test "cmd_complete_gate wires workaround resolution update in normal and emergency CLEAR sections" {
    run bash -lc "grep -c 'update_karo_workaround_resolutions \"\\\$CMD_ID\"' '$SRC_GATE_SCRIPT'"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "completed rework kinds are auto-captured once without becoming manual workarounds" {
    export KARO_WORKAROUNDS_FILE="$TEST_PROJECT/logs/karo_workarounds.yaml"
    export KARO_WORKAROUNDS_LOCK_FILE="$TEST_PROJECT/logs/karo_workarounds.lock"
    source "$GATE_HELPERS_FILE"

    local cmd_id event_kind
    while IFS='|' read -r cmd_id event_kind; do
        run capture_completed_rework_event "$cmd_id"
        [ "$status" -eq 0 ]
        [[ "$output" == *"captured=1 event_kind=${event_kind}"* ]]
    done <<'CASES'
cmd_karo_hotfix_capture_test|hotfix
cmd_karo_rc_capture_test|rc
cmd_karo_direct_capture_test|karo_direct
CASES

    run capture_completed_rework_event "cmd_karo_hotfix_capture_test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"duplicate=1 event_kind=hotfix"* ]]
    run grep -c "event_kind: hotfix" "$KARO_WORKAROUNDS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
    run grep -A6 "cmd_id: cmd_karo_hotfix_capture_test" "$KARO_WORKAROUNDS_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"workaround: false"* ]]
    [[ "$output" == *"auto_captured: true"* ]]
    run grep -c '^  auto_captured: true$' "$KARO_WORKAROUNDS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" -eq 3 ]
    run grep -c '^  lesson_disposition: not_applicable$' "$KARO_WORKAROUNDS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" -eq 3 ]
    run grep -c "^  resolved_by_cmd: 'cmd_karo_" "$KARO_WORKAROUNDS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" -eq 3 ]
}

@test "rework capture fails closed when its ledger lock cannot be opened" {
    export KARO_WORKAROUNDS_FILE="$TEST_PROJECT/logs/karo_workarounds.yaml"
    export KARO_WORKAROUNDS_LOCK_FILE="$TEST_PROJECT/missing/ledger.lock"
    source "$GATE_HELPERS_FILE"

    run capture_completed_rework_event "cmd_karo_hotfix_capture_failure"
    [ "$status" -ne 0 ]
    [[ "$output" == *"rework event capture failed"* ]]
    [ ! -f "$KARO_WORKAROUNDS_FILE" ]
}

@test "normal CLEAR captures synchronously before sending its CLEAR notification" {
    run env SRC_GATE_SCRIPT="$SRC_GATE_SCRIPT" python3 - <<'PY'
from pathlib import Path
import os

text = Path(os.environ['SRC_GATE_SCRIPT']).read_text(encoding='utf-8')
start = text.index('if [ "$ALL_CLEAR" = true ]; then')
end = text.index('    (append_changelog', start)
branch = text[start:end]
capture = branch.index('if ! capture_completed_rework_event "$CMD_ID"; then')
notify = branch.index('send_clear_notifications_once "$CMD_ID" "GATE CLEAR immediate"')
assert capture < notify, branch
assert 'capture_completed_rework_event "$CMD_ID" >>' not in branch, branch
PY
    [ "$status" -eq 0 ]
}

@test "cmd_complete_gate wires rework event capture in normal and emergency CLEAR sections" {
    run bash -lc "grep -c 'capture_completed_rework_event \"\\\$CMD_ID\"' '$SRC_GATE_SCRIPT'"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "write_l6_horizontal_level5_insights saves matching defense_level_under_5 candidate" {
    local insight_log="$TEST_TMPDIR/insights.log"
    cat > "$TEST_PROJECT/scripts/insight_write.sh" <<EOF
#!/usr/bin/env bash
printf '%s|%s|%s\n' "\$1" "\$2" "\$3" >> "$insight_log"
echo INSIGHT_TEST
EOF
    chmod +x "$TEST_PROJECT/scripts/insight_write.sh"

    cat > "$TEST_PROJECT/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_2600
  findings_summary: "ac_param_sufficiency WARNをBLOCKで止めているが、候補値自動提案は未実装"
  proposal:
    defense_level: 4
  causal_chain: "ac_param_sufficiency 手動確認"
- cmd_id: cmd_2601
  findings_summary: "unrelated Level4"
  proposal:
    defense_level: 4
EOF

    export CMD_TITLE="強化 — ac_param_sufficiency候補値自動提案(Level5化)"
    export CMD_PURPOSE="ac_param_sufficiency WARN時にcontextから候補値を自動表示する"
    export CMD_CHANGED_FILES="scripts/cmd_save.sh"

    run write_l6_horizontal_level5_insights "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L6 horizontal Level5 candidate scan"* ]]
    [[ "$output" == *"saved: 1 horizontal candidate(s)"* ]]
    grep -q "同パターンLevel5未満候補: source_cmd=$TEST_CMD_ID" "$insight_log"
    grep -q "candidate_level=4" "$insight_log"
    grep -q "cmd_complete_gate:l6_horizontal:$TEST_CMD_ID" "$insight_log"
}

@test "write_l6_horizontal_level5_insights matches Japanese command tokens" {
    local insight_log="$TEST_TMPDIR/insights.log"
    cat > "$TEST_PROJECT/scripts/insight_write.sh" <<EOF
#!/usr/bin/env bash
printf '%s|%s|%s\n' "\$1" "\$2" "\$3" >> "$insight_log"
echo INSIGHT_TEST
EOF
    chmod +x "$TEST_PROJECT/scripts/insight_write.sh"

    cat > "$TEST_PROJECT/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_2602
  findings_summary: "横展開スキャンで日本語トークン抽出が弱く候補検出できない"
  proposal:
    defense_level: 4
  causal_chain: "日本語トークン分割不足"
EOF

    export CMD_TITLE="L6横展開候補検出の日本語トークン分割改善"
    export CMD_PURPOSE="長文フレーズを分割し日本語cmdでも候補検出を機能させる"
    export CMD_CHANGED_FILES="scripts/cmd_complete_gate.sh"

    run write_l6_horizontal_level5_insights "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L6 horizontal Level5 candidate scan"* ]]
    [[ "$output" == *"saved: 1 horizontal candidate(s)"* ]]
    grep -q "matched=.*日本語" "$insight_log"
    grep -q "candidate_level=4" "$insight_log"
    grep -q "cmd_complete_gate:l6_horizontal:$TEST_CMD_ID" "$insight_log"
}

# test_necessity: one Level5-under candidate may be emitted only once across command completions, including after resolution.
@test "write_l6_horizontal_level5_insights skips candidate already present in insight history" {
    local insight_log="$TEST_TMPDIR/insights.log"
    cat > "$TEST_PROJECT/scripts/insight_write.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$insight_log"
EOF
    chmod +x "$TEST_PROJECT/scripts/insight_write.sh"

    cat > "$TEST_PROJECT/logs/gunshi_gp_tracker.yaml" <<'EOF'
- id: GP-DUP
  description: "YAML parse prevention must be upgraded"
  defense_level: 4
EOF
    cat > "$TEST_PROJECT/queue/insights.yaml" <<'EOF'
- id: INS-OLD
  insight: "同パターンLevel5未満候補: source_cmd=cmd_old; matched=parse; current_pattern=old; candidate_level=4; candidate=YAML parse prevention must be upgraded; source=gunshi_gp_tracker.yaml"
  priority: medium
  source: cmd_complete_gate:l6_horizontal:cmd_old
  status: resolved
EOF

    export CMD_TITLE="YAML parse prevention Level5化"
    export CMD_PURPOSE="parse preventionを強化する"
    export CMD_CHANGED_FILES="scripts/cmd_complete_gate.sh"

    run write_l6_horizontal_level5_insights "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: no Level5-under horizontal candidates"* ]]
    [ ! -f "$insight_log" ]
}

@test "write_l6_horizontal_level5_insights skips commands without Level5 signal" {
    local insight_log="$TEST_TMPDIR/insights.log"
    cat > "$TEST_PROJECT/scripts/insight_write.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$insight_log"
EOF
    chmod +x "$TEST_PROJECT/scripts/insight_write.sh"

    cat > "$TEST_PROJECT/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_2600
  findings_summary: "ordinary candidate"
  proposal:
    defense_level: 4
EOF

    export CMD_TITLE="通常修正"
    export CMD_PURPOSE="typoを直す"
    export CMD_CHANGED_FILES="scripts/cmd_save.sh"

    run write_l6_horizontal_level5_insights "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: no Level5-under horizontal candidates"* ]]
    [ ! -f "$insight_log" ]
}

@test "append_lesson_tracking filters fallback reports to current worker_id" {
    rm -f "$TEST_PROJECT/queue/tasks/"*.yaml
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_id: ${TEST_CMD_ID}_exact
  worker_id: hayate
  related_lessons:
    - id: L001
EOF
    cat > "$TEST_PROJECT/queue/reports/hayate_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: hayate
task_id: ${TEST_CMD_ID}_exact
parent_cmd: $TEST_CMD_ID
lessons_useful:
  - id: L001
EOF
    cat > "$TEST_PROJECT/queue/reports/hanzo_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: hanzo
task_id: ${TEST_CMD_ID}_stale
lessons_useful:
  - id: L999
EOF

    run append_lesson_tracking "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]
    tail -1 "$TEST_PROJECT/logs/lesson_tracking.tsv" | grep -q $'\thayate\tCLEAR\tL001\tL001\texact$'
}

@test "append_lesson_tracking detects exact and normal task_id suffixes" {
    rm -f "$TEST_PROJECT/queue/tasks/"*.yaml
    cat > "$TEST_PROJECT/queue/reports/hayate_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: hayate
task_id: ${TEST_CMD_ID}_exact
parent_cmd: $TEST_CMD_ID
lessons_useful:
  - id: L001
EOF

    run append_lesson_tracking "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]
    tail -1 "$TEST_PROJECT/logs/lesson_tracking.tsv" | grep -q $'\thayate\tCLEAR\tnone\tL001\texact$'

    : > "$TEST_PROJECT/logs/lesson_tracking.tsv"
    rm -f "$TEST_PROJECT/queue/reports/"*.yaml
    cat > "$TEST_PROJECT/queue/reports/hayate_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: hayate
task_id: ${TEST_CMD_ID}_normal
parent_cmd: $TEST_CMD_ID
lessons_useful:
  - id: L002
EOF

    run append_lesson_tracking "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]
    tail -1 "$TEST_PROJECT/logs/lesson_tracking.tsv" | grep -q $'\thayate\tCLEAR\tnone\tL002\tnormal$'
}

@test "append_lesson_tracking allows parent_cmd match even when current assignee differs" {
    rm -f "$TEST_PROJECT/queue/tasks/"*.yaml
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_id: ${TEST_CMD_ID}_exact
  worker_id: hayate
  related_lessons:
    - id: L001
EOF
    cat > "$TEST_PROJECT/queue/reports/hanzo_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: hanzo
task_id: ${TEST_CMD_ID}_normal
parent_cmd: $TEST_CMD_ID
lessons_useful:
  - id: L002
EOF

    run append_lesson_tracking "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]
    tail -1 "$TEST_PROJECT/logs/lesson_tracking.tsv" | grep -q $'\thanzo\tCLEAR\tL001\tL002\texact$'
}

@test "append_lesson_tracking fallback ignores stale reports with mismatched parent_cmd" {
    rm -f "$TEST_PROJECT/queue/tasks/"*.yaml
    cat > "$TEST_PROJECT/queue/reports/hayate_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: hayate
task_id: ${TEST_CMD_ID}_exact
parent_cmd: cmd_other
lessons_useful:
  - id: L999
EOF

    run append_lesson_tracking "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]
    tail -1 "$TEST_PROJECT/logs/lesson_tracking.tsv" | grep -q $'\tnone\tCLEAR\tnone\tnone\tunknown$'
}

@test "lessons_useful empty is WARN for scout and verify task types" {
    reset_gate_state

    handle_empty_lessons_useful_check "sasuke" "scout" "L001" > "$TEST_TMPDIR/lessons_useful_output.txt"
    output="$(cat "$TEST_TMPDIR/lessons_useful_output.txt")"
    [[ "$output" == *"[WARN] sasuke: lessons_useful空。task_type=scout のためBLOCK対象外"* ]]
    [ "$ALL_CLEAR" = true ]
    [ "${#BLOCK_REASONS[@]}" -eq 0 ]

    handle_empty_lessons_useful_check "sasuke" "verify" "L002" > "$TEST_TMPDIR/lessons_useful_output.txt"
    output="$(cat "$TEST_TMPDIR/lessons_useful_output.txt")"
    [[ "$output" == *"[WARN] sasuke: lessons_useful空。task_type=verify のためBLOCK対象外"* ]]
    [ "$ALL_CLEAR" = true ]
    [ "${#BLOCK_REASONS[@]}" -eq 0 ]

    # recon (偵察) も教訓注入なし/少が一般的→WARN扱い
    handle_empty_lessons_useful_check "sasuke" "recon" "" > "$TEST_TMPDIR/lessons_useful_output.txt"
    output="$(cat "$TEST_TMPDIR/lessons_useful_output.txt")"
    [[ "$output" == *"[WARN] sasuke: lessons_useful空。task_type=recon のためBLOCK対象外"* ]]
    [ "$ALL_CLEAR" = true ]
    [ "${#BLOCK_REASONS[@]}" -eq 0 ]
}

@test "lessons_useful empty remains BLOCK for exact task type" {
    reset_gate_state

    handle_empty_lessons_useful_check "sasuke" "exact" "L001,L002" > "$TEST_TMPDIR/lessons_useful_output.txt"
    output="$(cat "$TEST_TMPDIR/lessons_useful_output.txt")"
    [[ "$output" == *"[CRITICAL] sasuke: NG ← lessons_useful空"* ]]
    [ "$ALL_CLEAR" = false ]
    [ "${BLOCK_REASONS[0]}" = "sasuke:empty_lessons_useful:related=[L001,L002]" ]
}

@test "lesson feedback set requires exact assigned IDs and rejects stale extras" {
    cat > "$TEST_TMPDIR/task.yaml" <<'EOF'
task:
  assigned_lesson_ids: [L100, L102]
  related_lessons:
    - id: L999
EOF
    cat > "$TEST_TMPDIR/report.yaml" <<'EOF'
lessons_useful:
  - id: L100
    useful: true
  - id: L999
    useful: false
EOF
    run validate_lesson_feedback_set "$TEST_TMPDIR/task.yaml" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"mode=strict"* ]]
    [[ "$output" == *"missing=L102"* ]]
    [[ "$output" == *"extra=L999"* ]]
}

@test "lesson feedback set allows ordinary related lesson subset but rejects extras" {
    cat > "$TEST_TMPDIR/task.yaml" <<'EOF'
task:
  related_lessons:
    - id: L100
    - id: L101
EOF
    cat > "$TEST_TMPDIR/report.yaml" <<'EOF'
lessons_useful:
  - id: L100
    useful: true
EOF
    run validate_lesson_feedback_set "$TEST_TMPDIR/task.yaml" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"mode=subset"* ]]

    cat > "$TEST_TMPDIR/report.yaml" <<'EOF'
lessons_useful:
  - id: L404
    useful: false
EOF
    run validate_lesson_feedback_set "$TEST_TMPDIR/task.yaml" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"extra=L404"* ]]
}

@test "null assigned lesson field falls back to ordinary related lesson subset" {
    cat > "$TEST_TMPDIR/task.yaml" <<'EOF'
task:
  assigned_lesson_ids: null
  related_lessons:
    - id: L100
EOF
    cat > "$TEST_TMPDIR/report.yaml" <<'EOF'
lessons_useful:
  - id: L100
    useful: true
EOF
    run validate_lesson_feedback_set "$TEST_TMPDIR/task.yaml" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"mode=subset"* ]]
}

# cmd_karo_impl_related_lessons_snapshot_20260727 AC4: deploy_task.shの再配備related_lessons
# preserve機構(実発生: kagemaru 08:21→09:03 related_lessons入替でGATE無過失BLOCK)を、
# GATE側(validate_lesson_feedback_set、本cmdでは無変更)から見て再現する。
# (1)配備時点の集合で報告した忍者はPASSする(検査を殺していないことをAC(3)と合わせて実証)。
@test "cmd_karo_impl_related_lessons_snapshot AC4(1): deploy-time related_lessons set matches report → PASS" {
    cat > "$TEST_TMPDIR/task.yaml" <<'EOF'
task:
  related_lessons:
    - id: L163
    - id: L161
    - id: L114
EOF
    cat > "$TEST_TMPDIR/report.yaml" <<'EOF'
lessons_useful:
  - id: L163
    useful: false
  - id: L161
    useful: false
EOF
    run validate_lesson_feedback_set "$TEST_TMPDIR/task.yaml" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"mode=subset"* ]]
}

# (2)再配備でrelated_lessonsが preserve される(deploy_task.shの是正が効いた)前提のtask.yamlは、
# 配備時点(08:21相当)の報告と★BLOCKしない。preserveせず入替わっていた場合(旧挙動)は
# extra=L161,L163でMISMATCHしていた実測(GATE出力[CRITICAL] ... MISMATCH mode=subset missing=none extra=L161,L163)。
@test "cmd_karo_impl_related_lessons_snapshot AC4(2): preserved related_lessons after redeploy does not false-positive BLOCK" {
    cat > "$TEST_TMPDIR/task.yaml" <<'EOF'
task:
  parent_cmd: cmd_karo_impl_commander_post_contract_20260727
  related_lessons:
    - id: L163
    - id: L161
    - id: L114
EOF
    cat > "$TEST_TMPDIR/report.yaml" <<'EOF'
worker_id: kagemaru
parent_cmd: cmd_karo_impl_commander_post_contract_20260727
lessons_useful:
  - id: L163
    useful: false
  - id: L161
    useful: false
EOF
    run validate_lesson_feedback_set "$TEST_TMPDIR/task.yaml" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *MISMATCH* ]]
}

# (3)注入集合に本当に無いidを報告した場合は従来どおりBLOCKする(検査を殺していないこと)。
@test "cmd_karo_impl_related_lessons_snapshot AC4(3): id outside the deployed set still triggers MISMATCH (検査は生きている)" {
    cat > "$TEST_TMPDIR/task.yaml" <<'EOF'
task:
  related_lessons:
    - id: L163
    - id: L161
    - id: L114
EOF
    cat > "$TEST_TMPDIR/report.yaml" <<'EOF'
lessons_useful:
  - id: L163
    useful: false
  - id: L296
    useful: false
EOF
    run validate_lesson_feedback_set "$TEST_TMPDIR/task.yaml" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"extra=L296"* ]]
}

@test "CDP production check skips branch-only dm-signal frontend changes without deploy evidence" {
    export CMD_PROJECT="dm-signal"
    export CMD_CHANGED_FILES=$'backend/app.py\nfrontend/app/dashboard/page.tsx'

    run run_cdp_production_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP (frontend change detected, but no production deploy/live evidence required)"* ]]
    [[ "$output" != *"CDP_MEASURE"* ]]
}

@test "CDP production check is required for dm-signal frontend deploy evidence" {
    export CMD_PROJECT="dm-signal"
    export CMD_CHANGED_FILES=$'backend/app.py\nfrontend/app/dashboard/page.tsx'
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_999
post_deploy_evidence:
  required: true
EOF
    mkdir -p "$TEST_PROJECT/scripts/cdp"
    cat > "$TEST_PROJECT/scripts/cdp/cdp_measure.sh" <<'EOF'
#!/usr/bin/env bash
echo "CDP_MEASURE:$*"
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/cdp/cdp_measure.sh"

    run run_cdp_production_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"REQUIRED: dm-signal frontend change with production deploy/live evidence"* ]]
    [[ "$output" == *"timeout: 900s"* ]]
    [[ "$output" == *"pages: home dashboard summary"* ]]
    [[ "$output" == *"CDP_MEASURE:$TEST_CMD_ID --pages home dashboard summary"* ]]
    [[ "$output" == *"CDP production check: OK"* ]]
}

@test "CDP production check skips non-frontend dm-signal changes" {
    export CMD_PROJECT="dm-signal"
    export CMD_CHANGED_FILES=$'backend/app.py\nscripts/tool.sh'

    run run_cdp_production_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP (project=dm-signal, frontend changes not detected)"* ]]
}

@test "CDP production check detects frontend paths from report files_modified" {
    export CMD_PROJECT="dm-signal"
    export CMD_CHANGED_FILES=""
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_999
files_modified:
  - path: frontend/components/Widget.tsx
post_deploy_evidence:
  required: true
EOF
    mkdir -p "$TEST_PROJECT/scripts/cdp"
    cat > "$TEST_PROJECT/scripts/cdp/cdp_measure.sh" <<'EOF'
#!/usr/bin/env bash
echo "REPORT_CDP:$1"
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/cdp/cdp_measure.sh"

    run run_cdp_production_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"REQUIRED: dm-signal frontend change with production deploy/live evidence"* ]]
    [[ "$output" == *"REPORT_CDP:$TEST_CMD_ID"* ]]
}

@test "dm-signal production smoke passes only when origin/live match and every API is 2xx" {
    source "$GATE_HELPERS_FILE"
    export SCRIPT_DIR="$TEST_PROJECT" LOG_DIR="$TEST_PROJECT/logs" CMD_ID="$TEST_CMD_ID"
    export CMD_PROJECT="dm-signal" TASKS_DIR="$TEST_PROJECT/queue/tasks"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    export DM_SIGNAL_SMOKE_ORIGIN_SHA="0123456789abcdef0123456789abcdef01234567"
    export DM_SIGNAL_SMOKE_LIVE_SHA="$DM_SIGNAL_SMOKE_ORIGIN_SHA"
    export DM_SIGNAL_SMOKE_HTTP_STATUS_MAP="/health=200,/api/signals=204"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_999
post_deploy_evidence:
  required: true
EOF

    run run_dm_signal_production_smoke_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"http_status=200 result=PASS"* ]]
    [[ "$output" == *"http_status=204 result=PASS"* ]]
    grep -q 'gate: "dm_signal_production_smoke", result: PASS' "$TEST_PROJECT/logs/gate_fire_log.yaml"
    grep -q 'detector_fp_rate=tracked' "$TEST_PROJECT/logs/gate_fire_log.yaml"
}

@test "dm-signal production smoke blocks a live API error and records a measurable fire" {
    source "$GATE_HELPERS_FILE"
    export SCRIPT_DIR="$TEST_PROJECT" LOG_DIR="$TEST_PROJECT/logs" CMD_ID="$TEST_CMD_ID"
    export CMD_PROJECT="dm-signal" TASKS_DIR="$TEST_PROJECT/queue/tasks"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    export DM_SIGNAL_SMOKE_ORIGIN_SHA="0123456789abcdef0123456789abcdef01234567"
    export DM_SIGNAL_SMOKE_LIVE_SHA="$DM_SIGNAL_SMOKE_ORIGIN_SHA"
    export DM_SIGNAL_SMOKE_HTTP_STATUS_MAP="/health=200,/api/signals=500"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_999
post_deploy_evidence:
  required: true
EOF

    run run_dm_signal_production_smoke_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"http_status=500 result=BLOCK"* ]]
    [[ "$output" == *"production_api_smoke_failed"* ]]
    grep -q 'gate: "dm_signal_production_smoke", result: FAIL' "$TEST_PROJECT/logs/gate_fire_log.yaml"
    grep -q 'detector_fp_rate=tracked' "$TEST_PROJECT/logs/gate_fire_log.yaml"
}

@test "dm-signal production smoke blocks origin/live mismatch before API acceptance" {
    source "$GATE_HELPERS_FILE"
    export SCRIPT_DIR="$TEST_PROJECT" LOG_DIR="$TEST_PROJECT/logs" CMD_ID="$TEST_CMD_ID"
    export CMD_PROJECT="dm-signal" TASKS_DIR="$TEST_PROJECT/queue/tasks"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    export DM_SIGNAL_SMOKE_ORIGIN_SHA="0123456789abcdef0123456789abcdef01234567"
    export DM_SIGNAL_SMOKE_LIVE_SHA="fedcba9876543210fedcba9876543210fedcba98"
    export DM_SIGNAL_SMOKE_HTTP_STATUS_MAP="/health=200,/api/signals=200"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_999
post_deploy_evidence:
  required: true
EOF

    run run_dm_signal_production_smoke_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"deploy_unreached"* ]]
    grep -q 'gate: "dm_signal_production_smoke", result: FAIL' "$TEST_PROJECT/logs/gate_fire_log.yaml"
}

teardown() {
    cmd_gate_teardown
}

teardown_file() {
    TEST_TMPDIR="$CMD_GATE_MASTER_TMPDIR"
    cmd_gate_teardown
}

reset_gate_state() {
    ALL_CLEAR=true
    BLOCK_REASONS=()
}

@test "gate notification dispatch is non-blocking, single-launch, and route preserving across five variants" {
    source "$GATE_HELPERS_FILE"
    local notify_root="$BATS_TEST_TMPDIR/notify-root"
    local marker="$notify_root/launches"
    local start_ns elapsed_ms before after
    mkdir -p "$notify_root/scripts" "$notify_root/logs"
    export SCRIPT_DIR="$notify_root"

    write_notify_stub() {
        local path="$1" delay="$2" code="$3"
        cat > "$path" <<EOF
#!/usr/bin/env bash
printf '%s|%s\n' "\${0##*/}" "\$*" >> "$marker"
sleep "$delay"
exit "$code"
EOF
        chmod +x "$path"
    }

    assert_fast_single_launch() {
        local expected_route="$1"
        shift
        before="$(wc -l < "$marker" 2>/dev/null || printf '0')"
        start_ns="$(date +%s%N)"
        "$@"
        elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
        [ "$elapsed_ms" -lt 1000 ]
        [ "$LAST_GATE_NOTIFY_ROUTE" = "$expected_route" ]
        for _ in {1..20}; do
            after="$(wc -l < "$marker" 2>/dev/null || printf '0')"
            [ "$after" -eq $((before + 1)) ] && break
            sleep 0.02
        done
        [ "$after" -eq $((before + 1)) ]
    }

    : > "$marker"
    write_notify_stub "$notify_root/scripts/ntfy.sh" 5 0
    assert_fast_single_launch "ntfy.sh" send_high_notification "slow success"

    write_notify_stub "$notify_root/scripts/ntfy.sh" 0 0
    assert_fast_single_launch "ntfy.sh" send_high_notification "immediate success"

    write_notify_stub "$notify_root/scripts/ntfy.sh" 0 1
    assert_fast_single_launch "ntfy.sh" send_high_notification "immediate failure"

    write_notify_stub "$notify_root/scripts/ntfy.sh" 0.2 1
    assert_fast_single_launch "ntfy.sh" send_high_notification "retry failure"

    write_notify_stub "$notify_root/scripts/ntfy_batch.sh" 0 0
    write_notify_stub "$notify_root/scripts/ntfy_cmd.sh" 0 0
    assert_fast_single_launch "ntfy_batch.sh" send_info_cmd_notification cmd_test "batch message"
    rm "$notify_root/scripts/ntfy_batch.sh"
    assert_fast_single_launch "ntfy_cmd.sh" send_info_cmd_notification cmd_test "fallback message"

    [ "$(grep -c '^ntfy_batch.sh|batch message$' "$marker")" -eq 1 ]
    [ "$(grep -c '^ntfy_cmd.sh|cmd_test fallback message$' "$marker")" -eq 1 ]
    [ "$(wc -l < "$marker")" -eq 6 ]
}

# Direct function-level triage decision helper (no full gate execution)
run_binary_checks_triage_decision() {
    local triage="${1:-}"
    local ninja_name="sasuke"
    local report_file="$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml"

    write_triage_report_fixture "$triage" "no"

    local has_fail
    has_fail=$(awk '
        /^binary_checks:/{in_bc=1; next}
        in_bc && /^[^ ]/{in_bc=0}
        in_bc && /result:/{
            val=$0; gsub(/.*result:[[:space:]]*/,"",val); gsub(/[[:space:]]*$/,"",val)
            if (val != "yes") { print "FAIL"; exit }
        }
    ' "$report_file")

    if [ "$has_fail" = "FAIL" ]; then
        local warn_reason
        warn_reason=$(binary_checks_warn_reason "$report_file" "$ninja_name" "" 2>/dev/null || true)
        if [ -n "$warn_reason" ]; then
            echo "[WARN] ${ninja_name}: binary_checks non-PASS"
            echo "  ${warn_reason}"
            echo "GATE CLEAR: cmd完了許可"
            return 0
        else
            echo "[CRITICAL] ${ninja_name}: NG ← binary_checks has non-PASS results"
            echo "GATE BLOCK: ${ninja_name}:binary_checks_fail"
            echo "  ${ninja_name}:binary_checks_fail"
            return 1
        fi
    fi

    echo "GATE CLEAR: cmd完了許可"
    return 0
}

is_cmd_task() {
    local task_file="$1"
    grep -q "parent_cmd: ${TEST_CMD_ID}" "$task_file" 2>/dev/null
}

resolve_report_file() {
    local ninja_name="$1"
    local explicit_path report_parent
    local task_file="$TASKS_DIR/${ninja_name}.yaml"

    if [ -f "$task_file" ]; then
        explicit_path=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "report_filename" "")
        if [ -n "$explicit_path" ] && [ -f "$SCRIPT_DIR/queue/reports/$explicit_path" ]; then
            echo "$SCRIPT_DIR/queue/reports/$explicit_path"
            return 0
        fi
    fi

    if [ -f "$SCRIPT_DIR/queue/reports/${ninja_name}_report_${TEST_CMD_ID}.yaml" ]; then
        echo "$SCRIPT_DIR/queue/reports/${ninja_name}_report_${TEST_CMD_ID}.yaml"
        return 0
    fi

    if [ -f "$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml" ]; then
        report_parent=$(FIELD_GET_NO_LOG=1 field_get "$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml" "parent_cmd" "")
        if [ "$report_parent" = "$TEST_CMD_ID" ]; then
            echo "$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"
            return 0
        fi
    fi

    return 1
}

write_task_fixture() {
    local report_filename="${1:-sasuke_report_${TEST_CMD_ID}.yaml}"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: review
  report_filename: $report_filename
  ac_version: 2
  related_lessons: []
EOF
}

write_triage_report_fixture() {
    local triage="${1:-}"
    local result="${2:-no}"
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-04T00:00:00"
status: done
ac_version_read: 2
verdict: FAIL
test_triage: ${triage}
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
result:
  summary: "binary_checks triage fixture"
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
test_skip_count: 0
binary_checks:
  AC1:
    - check: "binary check triage fixture"
      result: ${result}
EOF
}

prepare_full_gate_triage_fixture() {
    local triage="${1:-}"
    write_cmd_yaml "without_context"
    write_task_fixture "sasuke_report_${TEST_CMD_ID}.yaml"
    write_triage_report_fixture "$triage" "no"

    cmd_gate_lib_override normalize_report.sh
    cat > "$TEST_PROJECT/scripts/lib/normalize_report.sh" <<'EOF'
#!/usr/bin/env bash
echo "no normalization needed"
exit 1
EOF
    cat > "$TEST_PROJECT/scripts/gates/gate_report_autofix.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/gates/gate_report_format.sh" <<'EOF'
#!/usr/bin/env bash
echo "PASS"
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/gates/gate_dc_duplicate.sh" <<'EOF'
#!/usr/bin/env bash
echo "OK: no duplicate"
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/bulletin_write.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/ntfy_cmd.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/queue/inbox/gunshi.yaml" <<'EOF'
messages: []
EOF
    chmod +x \
        "$TEST_PROJECT/scripts/lib/normalize_report.sh" \
        "$TEST_PROJECT/scripts/gates/gate_report_autofix.sh" \
        "$TEST_PROJECT/scripts/gates/gate_report_format.sh" \
        "$TEST_PROJECT/scripts/gates/gate_dc_duplicate.sh" \
        "$TEST_PROJECT/scripts/inbox_write.sh" \
        "$TEST_PROJECT/scripts/bulletin_write.sh" \
        "$TEST_PROJECT/scripts/ntfy_cmd.sh"
}

write_cmd_yaml() {
    local mode="$1"
    if [ "$mode" = "with_context" ]; then
        cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  - id: $TEST_CMD_ID
    purpose: "context update gate test"
    project: infra
    status: delegated
    delegated_at: "2026-03-04T21:25:00"
    context_update:
      - context/infrastructure.md
EOF
    else
        cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  - id: $TEST_CMD_ID
    purpose: "context update gate test"
    project: infra
    status: delegated
    delegated_at: "2026-03-04T21:25:00"
EOF
    fi
}

write_context_file() {
    local last_updated_date="$1"
    cat > "$TEST_PROJECT/context/infrastructure.md" <<EOF
# Infra
<!-- last_updated: ${last_updated_date} cmd_000 test -->
EOF
}

write_report() {
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-04T00:00:00"
status: done
ac_version_read: 2
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
EOF
}

run_context_update_check() {
    reset_gate_state
    check_context_update "$TEST_CMD_ID"
    [ "$ALL_CLEAR" = true ]
}

run_context_freshness_nudge() {
    echo "Context freshness nudge (GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/context_freshness_check.sh" ]; then
        (bash "$SCRIPT_DIR/scripts/context_freshness_check.sh" --cmd-warnings "$TEST_CMD_ID" >/dev/null 2>&1 || true) &
        echo "  queued (async)"
    else
        echo "  [INFO] context_freshness_check.sh not found (skip)"
    fi
}

run_normalize_phase() {
    local task_file ninja_name report_file normalize_exit normalize_output

    export NORMALIZE_LOG="$SCRIPT_DIR/logs/normalize_report.log"
    echo "Normalize report candidates (B層):"
    for task_file in "$TASKS_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        is_cmd_task "$task_file" || continue
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name") || continue
        if [ -f "$report_file" ]; then
            normalize_exit=0
            normalize_output=$(bash "$SCRIPT_DIR/scripts/lib/normalize_report.sh" "$report_file" 2>&1) || normalize_exit=$?
            if [ "$normalize_exit" -eq 0 ]; then
                echo "  [INFO] ${ninja_name}: auto-fixed: ${normalize_output}"
            elif [ "$normalize_exit" -eq 1 ]; then
                echo "  ${ninja_name}: OK (no normalization needed)"
            else
                echo "  ${ninja_name}: ERROR — normalize_report.sh exit=${normalize_exit}: ${normalize_output}"
            fi
        fi
    done
}

run_report_format_validation() {
    local report_file task_file ninja_name gate_output

    REPORT_FORMAT_CHECKED=0
    REPORT_FORMAT_FAILED=0
    declare -A report_format_seen=()

    validate_report_format_file() {
        local candidate="$1"

        [ -n "$candidate" ] || return 0
        [ -f "$candidate" ] || return 0
        if [ -n "${report_format_seen["$candidate"]+x}" ]; then
            return 0
        fi

        report_format_seen["$candidate"]=1
        REPORT_FORMAT_CHECKED=$((REPORT_FORMAT_CHECKED + 1))
        "$SCRIPT_DIR/scripts/gates/gate_report_autofix.sh" "$candidate" 2>/dev/null || true
        gate_output=$("$SCRIPT_DIR/scripts/gates/gate_report_format.sh" "$candidate" 2>&1 || true)
        if echo "$gate_output" | grep -q "^FAIL"; then
            REPORT_FORMAT_FAILED=$((REPORT_FORMAT_FAILED + 1))
            echo "  [CRITICAL] $(basename "$candidate"): $gate_output"
        else
            echo "  $(basename "$candidate"): PASS"
        fi
    }

    level_heading "[L1]" "Report format validation (direct scan):"
    for task_file in "$TASKS_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        is_cmd_task "$task_file" || continue
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name") || continue
        validate_report_format_file "$report_file"
    done

    for report_file in "$SCRIPT_DIR/queue/reports/"*_report_${TEST_CMD_ID}.yaml; do
        [ -f "$report_file" ] || continue
        validate_report_format_file "$report_file"
    done

    if [ "$REPORT_FORMAT_CHECKED" -eq 0 ]; then
        echo "  (no report files found for ${TEST_CMD_ID})"
    elif [ "$REPORT_FORMAT_FAILED" -eq 0 ]; then
        echo "  OK (全${REPORT_FORMAT_CHECKED}件フォーマット検証PASS)"
    fi

    [ "$REPORT_FORMAT_FAILED" -eq 0 ]
}

@test "context_update present + stale last_updated: gate blocks" {
    write_cmd_yaml "with_context"
    write_context_file "2025-01-01"
    write_report

    run run_context_update_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"Context update check:"* ]]
    [[ "$output" == *"context_update:context/infrastructure.md:stale"* ]]
}

@test "context_update present + fresh last_updated: gate clears" {
    write_cmd_yaml "with_context"
    write_context_file "2026-03-05"
    write_report

    run run_context_update_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context update check:"* ]]
    [[ "$output" == *"OK: context/infrastructure.md: last_updated=2026-03-05 (cmd=2026-03-04)"* ]]
}

@test "context_update target without causal links section emits WARN" {
    write_cmd_yaml "with_context"
    write_context_file "2026-03-05"
    write_report

    run run_context_update_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"context_update:context/infrastructure.md:causal_links_section_missing"* ]]
}

@test "committed context remains byte-identical during context_update check" {
    write_cmd_yaml "with_context"
    write_context_file "2026-03-05"
    write_report
    git -C "$TEST_PROJECT" init -q
    git -C "$TEST_PROJECT" config user.email "test@example.invalid"
    git -C "$TEST_PROJECT" config user.name "Test User"
    git -C "$TEST_PROJECT" add context/infrastructure.md
    git -C "$TEST_PROJECT" commit -q -m "baseline"
    CMD_CHANGED_FILES="context/infrastructure.md"
    local before after
    before="$(git -C "$TEST_PROJECT" hash-object context/infrastructure.md)"

    run run_context_update_check
    [ "$status" -eq 0 ]
    after="$(git -C "$TEST_PROJECT" hash-object context/infrastructure.md)"
    [ "$before" = "$after" ]
    [ -z "$(git -C "$TEST_PROJECT" status --short -- context/infrastructure.md)" ]
}

@test "uncommitted context remains byte-identical and stale metadata blocks" {
    write_cmd_yaml "with_context"
    write_context_file "2025-01-01"
    write_report
    git -C "$TEST_PROJECT" init -q
    git -C "$TEST_PROJECT" config user.email "test@example.invalid"
    git -C "$TEST_PROJECT" config user.name "Test User"
    git -C "$TEST_PROJECT" add context/infrastructure.md
    git -C "$TEST_PROJECT" commit -q -m "baseline"
    printf '\nother cmd context detail\n' >> "$TEST_PROJECT/context/infrastructure.md"
    CMD_CHANGED_FILES="context/infrastructure.md"
    local before after
    before="$(git -C "$TEST_PROJECT" hash-object context/infrastructure.md)"

    run run_context_update_check
    [ "$status" -eq 1 ]
    after="$(git -C "$TEST_PROJECT" hash-object context/infrastructure.md)"
    [ "$before" = "$after" ]
    grep -q "last_updated: 2025-01-01 cmd_000 test" "$TEST_PROJECT/context/infrastructure.md"
}

@test "context missing last_updated marker blocks without inserting marker" {
    write_cmd_yaml "with_context"
    printf '# Infra\n' > "$TEST_PROJECT/context/infrastructure.md"
    write_report
    local before after
    before="$(sha256sum "$TEST_PROJECT/context/infrastructure.md" | awk '{print $1}')"

    run run_context_update_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"context_update:context/infrastructure.md:last_updated_missing"* ]]
    after="$(sha256sum "$TEST_PROJECT/context/infrastructure.md" | awk '{print $1}')"
    [ "$before" = "$after" ]
    ! grep -q "last_updated:" "$TEST_PROJECT/context/infrastructure.md"
}

@test "context_update missing: gate skips and keeps existing behavior" {
    write_cmd_yaml "without_context"
    write_context_file "2025-01-01"
    write_report

    run run_context_update_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context update check:"* ]]
    [[ "$output" == *"SKIP (context_update not set)"* ]]
}

@test "GATE CLEAR emits non-blocking context freshness warning when project context is stale" {
    write_cmd_yaml "without_context"
    write_context_file "2026-03-01"
    write_report
    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: infra
    status: active
    path: $TEST_PROJECT
    context_files:
      - context/infrastructure.md
EOF
    git -C "$TEST_PROJECT" init -q
    git -C "$TEST_PROJECT" config user.email "test@example.invalid"
    git -C "$TEST_PROJECT" config user.name "Test User"
    git -C "$TEST_PROJECT" add context/infrastructure.md
    git -C "$TEST_PROJECT" commit -q -m "test source update for context/infrastructure.md"
    mkdir -p "$TEST_PROJECT/scripts"
    printf 'source update\n' > "$TEST_PROJECT/scripts/source_change.sh"
    git -C "$TEST_PROJECT" add scripts/source_change.sh
    git -C "$TEST_PROJECT" commit -q -m "test source update for infra script"

    run run_context_freshness_nudge
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context freshness nudge (GATE CLEAR):"* ]]
    [[ "$output" == *"queued (async)"* ]]
}

@test "lesson_impact rows keyed by subtask_id are updated on gate clear" {
    write_cmd_yaml "with_context"
    write_context_file "2026-03-05"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_id: subtask_test
  subtask_id: subtask_test
  assigned_to: sasuke
  task_type: review
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 2
  related_lessons:
    - id: L100
      summary: "first lesson"
    - id: L101
      summary: "second lesson"
EOF

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-04T00:00:00"
status: done
ac_version_read: 2
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful:
  - id: L100
    useful: true
    reason: 'test'
EOF

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-03-04T00:00:00	subtask_test	sasuke	L100	injected	pending	pending	infra	review	routine
2026-03-04T00:00:00	subtask_test	sasuke	L101	injected	pending	pending	infra	review	routine
2026-03-04T00:00:00	cmd_999	sasuke	L101	injected	pending	pending	infra	review	routine
EOF

    run update_lesson_impact_tsv "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]

    run grep -F $'subtask_test\tsasuke\tL100\tinjected\tUSEFUL\tyes' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]

    run grep -F $'subtask_test\tsasuke\tL101\tinjected\tNOT_USEFUL\tno' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]

    run grep -F $'cmd_999\tsasuke\tL101\tinjected\tNOT_USEFUL\tno' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
}

@test "lesson_impact update preserves score and traversal_depth columns" {
    write_cmd_yaml "with_context"
    write_context_file "2026-03-05"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_id: subtask_test
  subtask_id: subtask_test
  assigned_to: sasuke
  task_type: review
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
lessons_useful:
  - id: L100
    useful: true
    reason: 'test'
EOF

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-03-04T00:00:00	subtask_test	sasuke	L100	injected	pending	pending	infra	review	routine	5	1
EOF

    run update_lesson_impact_tsv "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]

    run grep -F $'timestamp\tcmd_id\tninja\tlesson_id\taction\tresult\treferenced\tproject\ttask_type\tbloom_level\tscore\ttraversal_depth' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]

    run grep -F $'subtask_test\tsasuke\tL100\tinjected\tUSEFUL\tyes\tinfra\treview\troutine\t5\t1' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
}

@test "explicit assigned lesson set leaves unassigned and missing feedback pending" {
    write_cmd_yaml "with_context"
    write_context_file "2026-03-05"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_id: subtask_strict
  subtask_id: subtask_strict
  assigned_to: sasuke
  task_type: exact
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  assigned_lesson_ids:
    - L100
    - L102
EOF

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_strict
parent_cmd: $TEST_CMD_ID
lessons_useful:
  - id: L100
    useful: true
    reason: assigned
EOF

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-03-04T00:00:00	subtask_strict	sasuke	L100	injected	pending	pending	infra	exact	routine
2026-03-04T00:00:00	subtask_strict	sasuke	L101	injected	pending	pending	infra	exact	routine
2026-03-04T00:00:00	subtask_strict	sasuke	L102	injected	pending	pending	infra	exact	routine
EOF

    run update_lesson_impact_tsv "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]
    run grep -F $'subtask_strict\tsasuke\tL100\tinjected\tUSEFUL\tyes' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'subtask_strict\tsasuke\tL101\tinjected\tpending\tpending' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'subtask_strict\tsasuke\tL102\tinjected\tpending\tpending' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
}

@test "lesson_impact update ignores extra TSV fields instead of crashing" {
    write_cmd_yaml "with_context"
    write_context_file "2026-03-05"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_id: subtask_test
  subtask_id: subtask_test
  assigned_to: sasuke
  task_type: review
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
lessons_useful:
  - id: L100
    useful: true
    reason: 'test'
EOF

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-03-04T00:00:00	subtask_test	sasuke	L100	injected	pending	pending	infra	review	routine	EXTRA_FIELD
EOF

    run update_lesson_impact_tsv "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LESSON_IMPACT: $TEST_CMD_ID updated rows=1"* ]]

    run grep -F $'subtask_test\tsasuke\tL100\tinjected\tUSEFUL\tyes\tinfra\treview\troutine' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    ! grep -q "EXTRA_FIELD" "$TEST_PROJECT/logs/lesson_impact.tsv"
}

@test "B層: normalize OK when report already dict format (exit 1)" {
    write_cmd_yaml "without_context"
    write_report

    run run_normalize_phase
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: OK (no normalization needed)"* ]]
}

@test "B層: normalize WARN when report has list-format lesson_candidate (exit 0)" {
    write_cmd_yaml "without_context"

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-04T00:00:00"
status: done
ac_version_read: 2
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
lesson_candidate:
  - "some lesson in list format"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
EOF

    run run_normalize_phase
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO] sasuke:"* ]]
    [[ "$output" == *"自動修正"* ]] || [[ "$output" == *"auto-fixed"* ]]
}

@test "B層: normalize ERROR when normalize_report.sh is missing (exit 127)" {
    write_cmd_yaml "without_context"
    write_report

    rm "$TEST_PROJECT/scripts/lib/normalize_report.sh"

    run run_normalize_phase
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: ERROR"* ]]
    [[ "$output" == *"normalize_report.sh exit=127"* ]]
}

@test "custom report_filename is included in direct report format validation" {
    write_cmd_yaml "without_context"

    cat > "$TEST_PROJECT/scripts/gates/gate_report_autofix.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/gates/gate_report_format.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == *"custom_gate_target.yaml" ]]; then
    echo "FAIL: custom report hit formatter"
    exit 1
fi
echo "PASS"
EOF
    chmod +x "$TEST_PROJECT/scripts/gates/gate_report_autofix.sh" "$TEST_PROJECT/scripts/gates/gate_report_format.sh"

    write_task_fixture "custom_gate_target.yaml"

    cat > "$TEST_PROJECT/queue/reports/custom_gate_target.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-04T00:00:00"
status: done
ac_version_read: 2
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
result:
  summary: "custom report"
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
binary_checks:
  AC1:
    - check: "custom report validated"
      result: "yes"
EOF

    run run_report_format_validation
    [ "$status" -eq 1 ]
    [[ "$output" == *"custom_gate_target.yaml: FAIL: custom report hit formatter"* ]]
}

@test "test_triage pre_existing binary_checks fail is WARN and allows GATE CLEAR" {
    run run_binary_checks_triage_decision "pre_existing"

    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN] sasuke: binary_checks non-PASS"* ]]
    [[ "$output" == *"test_triage=pre_existingのためWARN降格"* ]]
    [[ "$output" == *"GATE CLEAR: cmd完了許可"* ]]
    [[ "$output" != *"sasuke:binary_checks_fail"* ]]
}

@test "test_triage in_branch binary_checks fail remains GATE BLOCK" {
    run run_binary_checks_triage_decision "in_branch"

    [ "$status" -eq 1 ]
    [[ "$output" == *"[CRITICAL] sasuke: NG ← binary_checks has non-PASS results"* ]]
    [[ "$output" == *"GATE BLOCK"* ]]
    [[ "$output" == *"sasuke:binary_checks_fail"* ]]
}

@test "blank test_triage binary_checks fail remains GATE BLOCK" {
    run run_binary_checks_triage_decision ""

    [ "$status" -eq 1 ]
    [[ "$output" == *"[CRITICAL] sasuke: NG ← binary_checks has non-PASS results"* ]]
    [[ "$output" == *"GATE BLOCK"* ]]
    [[ "$output" == *"sasuke:binary_checks_fail"* ]]
}

@test "draft lesson check ignores gate_auto_draft marker but keeps manual drafts blocking" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
assert '--source-marker "gate_auto_draft"' in text

start = text.index('own_draft_count=$(awk -v cmd="${CMD_ID}"')
end = text.index("' \"$DRAFT_LESSONS_FILE\"", start)
block = text[start:end]

assert r'- \*\*source\*\*:[[:space:]]*gate_auto_draft' in block
assert '&& !is_gate_auto_draft' in block
assert 'is_draft && is_own' in block
PY
    [ "$status" -eq 0 ]
}

@test "CI expected head uses origin main when local HEAD diverges" {
    local repo="$BATS_TEST_TMPDIR/ci-main-boundary"
    git init -q "$repo"
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name test
    echo shared > "$repo/state"
    git -C "$repo" add state
    git -C "$repo" commit -qm shared
    local shared_head
    shared_head="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" update-ref refs/remotes/origin/main "$shared_head"
    echo local >> "$repo/state"
    git -C "$repo" commit -qam local

    run env CMD_COMPLETE_GATE_CI_EXPECTED_HEAD_ONLY=1 \
        CMD_COMPLETE_GATE_CI_REPO_DIR="$repo" bash "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "$shared_head" ]
    [ "$output" != "$(git -C "$repo" rev-parse HEAD)" ]
}

@test "CI expected head falls back to origin master" {
    local repo="$BATS_TEST_TMPDIR/ci-master-boundary"
    git init -q "$repo"
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name test
    echo shared > "$repo/state"
    git -C "$repo" add state
    git -C "$repo" commit -qm shared
    local shared_head
    shared_head="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" update-ref refs/remotes/origin/master "$shared_head"

    run env CMD_COMPLETE_GATE_CI_EXPECTED_HEAD_ONLY=1 \
        CMD_COMPLETE_GATE_CI_REPO_DIR="$repo" bash "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "$shared_head" ]
}

@test "CI expected head is empty when remote boundary is missing" {
    local repo="$BATS_TEST_TMPDIR/ci-missing-boundary"
    git init -q "$repo"

    run env CMD_COMPLETE_GATE_CI_EXPECTED_HEAD_ONLY=1 \
        CMD_COMPLETE_GATE_CI_REPO_DIR="$repo" bash "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "task repository resolution uses external target_path git root" {
    local repo="$BATS_TEST_TMPDIR/external-task-repo"
    local task="$BATS_TEST_TMPDIR/external-task.yaml"
    git init -q "$repo"
    mkdir -p "$repo/backend"
    cat > "$task" <<YAML
task:
  project: external
  target_path: $repo/backend
YAML

    run env CMD_COMPLETE_GATE_TASK_REPO_ONLY=1 \
        CMD_COMPLETE_GATE_TASK_FILE="$task" \
        bash "$SRC_GATE_SCRIPT" cmd_external_repo_probe
    [ "$status" -eq 0 ]
    [ "$output" = "$repo" ]
}

@test "post-clear push targets external task repository in both clear paths" {
    local repo="$BATS_TEST_TMPDIR/external-push-repo"
    local task="$BATS_TEST_TMPDIR/external-push-task.yaml"
    git init -q "$repo"
    mkdir -p "$repo/backend"
    cat > "$task" <<YAML
task:
  project: external
  target_path: $repo/backend
YAML

    run env CMD_COMPLETE_GATE_PUSH_REPOS_ONLY=1 \
        CMD_COMPLETE_GATE_TASK_FILE="$task" \
        bash "$SRC_GATE_SCRIPT" cmd_external_push_probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"git push: DRY_RUN ($repo)"* ]]
    [[ "$output" != *"git push: DRY_RUN ($PROJECT_ROOT)"* ]]

    run grep -Fc 'push_task_repositories "${MATCHING_TASK_FILES[@]}"' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
}

# cmd_karo_hotfix_cmd_complete_autopush_overlap_precheck_20260730
# test_necessity: reproduces the real incident (logs/hook_artifacts/20260730T115149_pre-push_1478023.log —
# cmd_complete_gate's auto-push hit a legitimate GA-PUSH1 BLOCK because the pushed
# commit range and the still-dirty worktree touched the same non-autogen path) as an
# isolated fixture, and proves the overlap precheck removes both the wasted git push
# call and the resulting hook-failure artifact without weakening GA-PUSH1 itself.
_push_overlap_repo_init() {
    local base="$1"
    mkdir -p "$base"
    git init -q --bare "$base/origin.git"
    git init -q -b main "$base/repo"
    git -C "$base/repo" config user.email test@example.com
    git -C "$base/repo" config user.name test
    printf 'base\n' > "$base/repo/shared.txt"
    git -C "$base/repo" add -A
    git -C "$base/repo" commit -q -m base
    git -C "$base/repo" remote add origin "$base/origin.git"
    git -C "$base/repo" push -q -u origin main
}

_push_overlap_repo_make_source_overlap() {
    local base="$1"
    printf 'local change\n' >> "$base/repo/shared.txt"
    git -C "$base/repo" add -A
    git -C "$base/repo" commit -q -m "local change"
    printf 'dirty uncommitted\n' >> "$base/repo/shared.txt"
}

_push_overlap_task_yaml() {
    local base="$1"
    cat > "$base/task.yaml" <<YAML
task:
  project: external
  target_path: $base/repo
YAML
}

_push_overlap_install_git_call_counter() {
    local base="$1"
    local real_git
    real_git="$(command -v git)"
    mkdir -p "$base/bin"
    cat > "$base/bin/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-C" ] && [ "\$3" = "push" ]; then
    echo push >> "$base/git_push_calls.log"
fi
exec "$real_git" "\$@"
EOF
    chmod +x "$base/bin/git"
    : > "$base/git_push_calls.log"
}

@test "AC1 baseline: direct git push on a source-overlap dirty tree hits real GA-PUSH1 BLOCK and writes exactly 1 hook-failure artifact" {
    local base="$BATS_TEST_TMPDIR/ac1-baseline"
    _push_overlap_repo_init "$base"
    mkdir -p "$base/repo/scripts/lib" "$base/hooks"
    cp "$PROJECT_ROOT/scripts/lib/autogen_paths.sh" "$base/repo/scripts/lib/autogen_paths.sh"
    install -m 0755 "$PROJECT_ROOT/.githooks/pre-push" "$base/hooks/pre-push"
    _push_overlap_repo_make_source_overlap "$base"
    git -C "$base/repo" config core.hooksPath "$base/hooks"

    run bash -c 'cd "$1" && git push 2>&1' _ "$base/repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]

    run find "$base/repo/logs/hook_artifacts" -name '*.log'
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
}

@test "AC1 fixed: push_task_repositories SKIPs the source-overlap repo, calling git push 0 times and writing 0 hook-failure artifacts" {
    local base="$BATS_TEST_TMPDIR/ac1-fixed"
    _push_overlap_repo_init "$base"
    _push_overlap_repo_make_source_overlap "$base"
    _push_overlap_task_yaml "$base"
    _push_overlap_install_git_call_counter "$base"

    run env PATH="$base/bin:$PATH" CMD_COMPLETE_GATE_PUSH_REPOS_REAL=1 \
        CMD_COMPLETE_GATE_TASK_FILE="$base/task.yaml" \
        bash "$SRC_GATE_SCRIPT" cmd_ac1_fixed_probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"git push: SKIP ($base/repo GA-PUSH1 overlap precheck"* ]]
    [[ "$output" == *$'\n    shared.txt'* ]]

    [ ! -s "$base/git_push_calls.log" ]
    if [ -d "$base/repo/logs/hook_artifacts" ]; then
        run find "$base/repo/logs/hook_artifacts" -name '*.log'
        [ "$status" -eq 0 ]
        [ -z "$output" ]
    fi
}

@test "AC2: clean tree still pushes via the already-up-to-date SKIP path (unaffected by the new precheck)" {
    local base="$BATS_TEST_TMPDIR/ac2-clean"
    _push_overlap_repo_init "$base"
    _push_overlap_task_yaml "$base"
    _push_overlap_install_git_call_counter "$base"

    run env PATH="$base/bin:$PATH" CMD_COMPLETE_GATE_PUSH_REPOS_REAL=1 \
        CMD_COMPLETE_GATE_TASK_FILE="$base/task.yaml" \
        bash "$SRC_GATE_SCRIPT" cmd_ac2_clean_probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"git push: SKIP ($base/repo already up-to-date with origin/main)"* ]]
    [ ! -s "$base/git_push_calls.log" ]
}

@test "AC2: a non-overlapping dirty file does not block the push (git push is still called and succeeds)" {
    local base="$BATS_TEST_TMPDIR/ac2-nonoverlap"
    _push_overlap_repo_init "$base"
    printf 'local change\n' >> "$base/repo/shared.txt"
    git -C "$base/repo" add -A
    git -C "$base/repo" commit -q -m "local change"
    printf 'unrelated wip\n' > "$base/repo/unrelated.txt"
    _push_overlap_task_yaml "$base"
    _push_overlap_install_git_call_counter "$base"

    run env PATH="$base/bin:$PATH" CMD_COMPLETE_GATE_PUSH_REPOS_REAL=1 \
        CMD_COMPLETE_GATE_TASK_FILE="$base/task.yaml" \
        bash "$SRC_GATE_SCRIPT" cmd_ac2_nonoverlap_probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"git push: OK ($base/repo)"* ]]
    [ "$(grep -c . "$base/git_push_calls.log")" -eq 1 ]
}

@test "AC2: an overlap limited to an auto-generated path does not block the push (git push is still called and succeeds)" {
    local base="$BATS_TEST_TMPDIR/ac2-autogen"
    _push_overlap_repo_init "$base"
    mkdir -p "$base/repo/scripts/lib" "$base/repo/context"
    cp "$PROJECT_ROOT/scripts/lib/autogen_paths.sh" "$base/repo/scripts/lib/autogen_paths.sh"
    printf 'idx v1\n' > "$base/repo/context/lord-conversation-index.md"
    git -C "$base/repo" add -A
    git -C "$base/repo" commit -q -m "add index"
    printf 'idx v2\n' > "$base/repo/context/lord-conversation-index.md"
    git -C "$base/repo" add -A
    git -C "$base/repo" commit -q -m "publish idx update"
    printf 'idx v3 uncommitted\n' > "$base/repo/context/lord-conversation-index.md"
    _push_overlap_task_yaml "$base"
    _push_overlap_install_git_call_counter "$base"

    run env PATH="$base/bin:$PATH" CMD_COMPLETE_GATE_PUSH_REPOS_REAL=1 \
        CMD_COMPLETE_GATE_TASK_FILE="$base/task.yaml" \
        bash "$SRC_GATE_SCRIPT" cmd_ac2_autogen_probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"git push: OK ($base/repo)"* ]]
    [ "$(grep -c . "$base/git_push_calls.log")" -eq 1 ]
}

# cmd_karo_hotfix_cmd_complete_autopush_overlap_precheck_20260730 AC2
# test_necessity: the precheck must not silently widen the exclusion. A normal
# source path overlap must still be reported as a blocking path, matching
# GA-PUSH1's own contract (no new exclusion added for ordinary source files).
@test "AC2: overlap precheck does not add ordinary source paths to the autogen exclusion" {
    local base="$BATS_TEST_TMPDIR/ac2-source-not-excluded"
    _push_overlap_repo_init "$base"
    _push_overlap_repo_make_source_overlap "$base"
    _push_overlap_task_yaml "$base"
    _push_overlap_install_git_call_counter "$base"

    run env PATH="$base/bin:$PATH" CMD_COMPLETE_GATE_PUSH_REPOS_REAL=1 \
        CMD_COMPLETE_GATE_TASK_FILE="$base/task.yaml" \
        bash "$SRC_GATE_SCRIPT" cmd_ac2_source_not_excluded_probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"shared.txt"* ]]
    [ ! -s "$base/git_push_calls.log" ]
}

# cmd_karo_hotfix_cmd_complete_autopush_overlap_precheck_20260730 AC3
# test_necessity: the normal CLEAR path and the emergency-override CLEAR path must
# not grow two divergent overlap implementations. Both call sites route through the
# single push_task_repositories function, and push_overlap_blocking_paths must be
# defined exactly once and invoked only from inside it.
@test "AC3: both CLEAR entry points call push_task_repositories, and the overlap helper is defined exactly once" {
    run grep -Fc 'push_task_repositories "${MATCHING_TASK_FILES[@]}"' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]

    run grep -Fc 'push_overlap_blocking_paths()' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]

    run grep -Fc 'overlap_blocking=$(push_overlap_blocking_paths' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

# AC3: positive/negative fixtures for push_overlap_blocking_paths itself, isolated
# from the surrounding push loop via CMD_COMPLETE_GATE_PUSH_OVERLAP_ONLY.
@test "AC3 fixture: push_overlap_blocking_paths reports the overlapping path for a real source overlap" {
    local base="$BATS_TEST_TMPDIR/ac3-overlap"
    _push_overlap_repo_init "$base"
    _push_overlap_repo_make_source_overlap "$base"
    local head_sha upstream_sha
    head_sha="$(git -C "$base/repo" rev-parse HEAD)"
    upstream_sha="$(git -C "$base/repo" rev-parse '@{upstream}')"

    run env CMD_COMPLETE_GATE_PUSH_OVERLAP_ONLY=1 \
        CMD_COMPLETE_GATE_PUSH_OVERLAP_REPO="$base/repo" \
        CMD_COMPLETE_GATE_PUSH_OVERLAP_HEAD="$head_sha" \
        CMD_COMPLETE_GATE_PUSH_OVERLAP_UPSTREAM="$upstream_sha" \
        bash "$SRC_GATE_SCRIPT" cmd_ac3_overlap_probe
    [ "$status" -eq 0 ]
    [ "$output" = "shared.txt" ]
}

@test "AC3 fixture: push_overlap_blocking_paths reports nothing for a non-overlapping dirty file" {
    local base="$BATS_TEST_TMPDIR/ac3-nonoverlap"
    _push_overlap_repo_init "$base"
    printf 'local change\n' >> "$base/repo/shared.txt"
    git -C "$base/repo" add -A
    git -C "$base/repo" commit -q -m "local change"
    printf 'unrelated wip\n' > "$base/repo/unrelated.txt"
    local head_sha upstream_sha
    head_sha="$(git -C "$base/repo" rev-parse HEAD)"
    upstream_sha="$(git -C "$base/repo" rev-parse '@{upstream}')"

    run env CMD_COMPLETE_GATE_PUSH_OVERLAP_ONLY=1 \
        CMD_COMPLETE_GATE_PUSH_OVERLAP_REPO="$base/repo" \
        CMD_COMPLETE_GATE_PUSH_OVERLAP_HEAD="$head_sha" \
        CMD_COMPLETE_GATE_PUSH_OVERLAP_UPSTREAM="$upstream_sha" \
        bash "$SRC_GATE_SCRIPT" cmd_ac3_nonoverlap_probe
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AC3 fixture: push_overlap_blocking_paths reports nothing when the overlap is limited to an autogen path" {
    local base="$BATS_TEST_TMPDIR/ac3-autogen"
    _push_overlap_repo_init "$base"
    mkdir -p "$base/repo/context"
    printf 'idx v1\n' > "$base/repo/context/lord-conversation-index.md"
    git -C "$base/repo" add -A
    git -C "$base/repo" commit -q -m "add index"
    printf 'idx v2\n' > "$base/repo/context/lord-conversation-index.md"
    git -C "$base/repo" add -A
    git -C "$base/repo" commit -q -m "publish idx update"
    printf 'idx v3 uncommitted\n' > "$base/repo/context/lord-conversation-index.md"
    local head_sha upstream_sha
    head_sha="$(git -C "$base/repo" rev-parse HEAD)"
    upstream_sha="$(git -C "$base/repo" rev-parse '@{upstream}')"

    run env CMD_COMPLETE_GATE_PUSH_OVERLAP_ONLY=1 \
        CMD_COMPLETE_GATE_PUSH_OVERLAP_REPO="$base/repo" \
        CMD_COMPLETE_GATE_PUSH_OVERLAP_HEAD="$head_sha" \
        CMD_COMPLETE_GATE_PUSH_OVERLAP_UPSTREAM="$upstream_sha" \
        bash "$SRC_GATE_SCRIPT" cmd_ac3_autogen_probe
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AC3 fixture: push_overlap_blocking_paths reports nothing when the worktree is already up-to-date" {
    local base="$BATS_TEST_TMPDIR/ac3-uptodate"
    _push_overlap_repo_init "$base"
    local head_sha upstream_sha
    head_sha="$(git -C "$base/repo" rev-parse HEAD)"
    upstream_sha="$(git -C "$base/repo" rev-parse '@{upstream}')"

    run env CMD_COMPLETE_GATE_PUSH_OVERLAP_ONLY=1 \
        CMD_COMPLETE_GATE_PUSH_OVERLAP_REPO="$base/repo" \
        CMD_COMPLETE_GATE_PUSH_OVERLAP_HEAD="$head_sha" \
        CMD_COMPLETE_GATE_PUSH_OVERLAP_UPSTREAM="$upstream_sha" \
        bash "$SRC_GATE_SCRIPT" cmd_ac3_uptodate_probe
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

make_ci_push_repo() {
    local repo="$1"
    git init -q "$repo"
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name test
    echo shared > "$repo/state"
    git -C "$repo" add state
    git -C "$repo" commit -qm shared
    git -C "$repo" update-ref refs/remotes/origin/main "$(git -C "$repo" rev-parse HEAD)"
}

run_ci_push_state() {
    local repo="$1" report="$2" task="${3:-}"
    run env CMD_COMPLETE_GATE_CI_PUSH_STATE_ONLY=1 \
        CMD_COMPLETE_GATE_CI_REPO_DIR="$repo" \
        CMD_COMPLETE_GATE_CI_REPORT="$report" \
        CMD_COMPLETE_GATE_TASK_FILE="$task" bash "$SRC_GATE_SCRIPT"
}

# test_necessity: readonly recon/scout reports with a symmetric optional
# commit contract must not be mistaken for unpublished implementation.
@test "CI push detection skips symmetric empty no-code recon contract" {
    local repo="$BATS_TEST_TMPDIR/no-code-contract"
    local report="$BATS_TEST_TMPDIR/no-code-contract-report.yaml"
    local task="$BATS_TEST_TMPDIR/no-code-contract-task.yaml"
    make_ci_push_repo "$repo"
    printf 'task_type: recon2\ncommit_hash: ""\nfiles_modified: []\ncommit_contract: {required: false, task_type: recon2}\n' > "$report"
    printf 'task:\n  task_type: recon2\n  commit_contract: {required: false, task_type: recon2}\n' > "$task"
    run_ci_push_state "$repo" "$report" "$task"
    [ "$status" -eq 0 ]
    [ "$output" = "UNPUSHED: commit_contract no-code task" ]
}

# test_necessity: deployed task YAMLs that carry the same typed contract as a
# JSON scalar must retain the readonly exemption; serialization is not a
# semantic change and must not crash the CI boundary classifier.
@test "CI push detection skips serialized symmetric no-code scout contract" {
    local repo="$BATS_TEST_TMPDIR/no-code-serialized-contract"
    local report="$BATS_TEST_TMPDIR/no-code-serialized-report.yaml"
    local task="$BATS_TEST_TMPDIR/no-code-serialized-task.yaml"
    make_ci_push_repo "$repo"
    printf 'task_type: scout\ncommit_hash: no-code-change\nfiles_modified: [{path: %s}]\ncommit_contract: {required: false, task_type: scout}\n' "$report" > "$report"
    printf 'task:\n  task_type: scout\n  commit_contract: '\''{"required":false,"task_type":"scout"}'\''\n' > "$task"
    run_ci_push_state "$repo" "$report" "$task"
    [ "$status" -eq 0 ]
    [ "$output" = "UNPUSHED: commit_contract no-code task" ]
}

# test_necessity: readonly recon reports may list the report itself as their
# sole artifact without turning a no-code project task into a commit task.
@test "CI push detection skips symmetric no-code recon with only its own report artifact" {
    local repo="$BATS_TEST_TMPDIR/no-code-self-report"
    local report="$BATS_TEST_TMPDIR/no-code-self-report.yaml"
    local task="$BATS_TEST_TMPDIR/no-code-self-report-task.yaml"
    make_ci_push_repo "$repo"
    printf 'task_type: recon2\ncommit_hash: no-code-change\nfiles_modified: [{path: %s}]\ncommit_contract: {required: false, task_type: recon2}\n' "$report" > "$report"
    printf 'task:\n  task_type: recon2\n  commit_contract: {required: false, task_type: recon2}\n' > "$task"
    run_ci_push_state "$repo" "$report" "$task"
    [ "$status" -eq 0 ]
    [ "$output" = "UNPUSHED: commit_contract no-code task" ]
}

# test_necessity: the exemption is exact-file identity, not a blanket allowance
# for arbitrary queue/reports artifacts.
@test "CI push detection blocks no-code recon with a different report artifact" {
    local repo="$BATS_TEST_TMPDIR/no-code-other-report"
    local report="$BATS_TEST_TMPDIR/no-code-other-report.yaml"
    local task="$BATS_TEST_TMPDIR/no-code-other-report-task.yaml"
    make_ci_push_repo "$repo"
    printf 'task_type: recon2\ncommit_hash: ""\nfiles_modified: [{path: %s}]\ncommit_contract: {required: false, task_type: recon2}\n' "$BATS_TEST_TMPDIR/another-report.yaml" > "$report"
    printf 'task:\n  task_type: recon2\n  commit_contract: {required: false, task_type: recon2}\n' > "$task"
    run_ci_push_state "$repo" "$report" "$task"
    [ "$status" -eq 0 ]
    [[ "$output" == "BLOCK: report commit"* ]]
}

# test_necessity: report-only optional-contract claims must remain fail-closed.
@test "CI push detection blocks report-only no-code contract spoof" {
    local repo="$BATS_TEST_TMPDIR/no-code-report-spoof"
    local report="$BATS_TEST_TMPDIR/no-code-report-spoof-report.yaml"
    local task="$BATS_TEST_TMPDIR/no-code-report-spoof-task.yaml"
    make_ci_push_repo "$repo"
    printf 'task_type: recon\ncommit_hash: ""\nfiles_modified: []\ncommit_contract: {required: false, task_type: recon}\n' > "$report"
    printf 'task:\n  task_type: recon\n  commit_contract: {required: true, task_type: recon}\n' > "$task"
    run_ci_push_state "$repo" "$report" "$task"
    [ "$status" -eq 0 ]
    [[ "$output" == "BLOCK: report commit"* ]]
}

# test_necessity: task/report optional-contract disagreement must not bypass CI.
@test "CI push detection blocks no-code contract type mismatch" {
    local repo="$BATS_TEST_TMPDIR/no-code-type-mismatch"
    local report="$BATS_TEST_TMPDIR/no-code-type-mismatch-report.yaml"
    local task="$BATS_TEST_TMPDIR/no-code-type-mismatch-task.yaml"
    make_ci_push_repo "$repo"
    printf 'task_type: recon\ncommit_hash: ""\nfiles_modified: []\ncommit_contract: {required: false, task_type: recon}\n' > "$report"
    printf 'task:\n  task_type: scout\n  commit_contract: {required: false, task_type: scout}\n' > "$task"
    run_ci_push_state "$repo" "$report" "$task"
    [ "$status" -eq 0 ]
    [[ "$output" == "BLOCK: report commit"* ]]
}

# test_necessity: an implementation path cannot hide behind an optional recon contract.
@test "CI push detection blocks nonempty files under no-code contract" {
    local repo="$BATS_TEST_TMPDIR/no-code-files"
    local report="$BATS_TEST_TMPDIR/no-code-files-report.yaml"
    local task="$BATS_TEST_TMPDIR/no-code-files-task.yaml"
    make_ci_push_repo "$repo"
    printf 'task_type: recon\ncommit_hash: ""\nfiles_modified: [{path: scripts/x.sh}]\ncommit_contract: {required: false, task_type: recon}\n' > "$report"
    printf 'task:\n  task_type: recon\n  commit_contract: {required: false, task_type: recon}\n' > "$task"
    run_ci_push_state "$repo" "$report" "$task"
    [ "$status" -eq 0 ]
    [[ "$output" == "BLOCK: report commit"* ]]
}

# test_necessity: an actual commit still uses the remote containment boundary.
@test "CI push detection preserves remote boundary for committed no-code contract" {
    local repo="$BATS_TEST_TMPDIR/no-code-committed"
    local report="$BATS_TEST_TMPDIR/no-code-committed-report.yaml"
    local task="$BATS_TEST_TMPDIR/no-code-committed-task.yaml"
    make_ci_push_repo "$repo"
    printf 'task_type: recon2\ncommit_hash: %s\nfiles_modified: []\ncommit_contract: {required: false, task_type: recon2}\n' "$(git -C "$repo" rev-parse HEAD)" > "$report"
    printf 'task:\n  task_type: recon2\n  commit_contract: {required: false, task_type: recon2}\n' > "$task"
    run_ci_push_state "$repo" "$report" "$task"
    [ "$status" -eq 0 ]
    [[ "$output" == PUSHED:* ]]
}

run_commit_repo_resolution() {
    local fallback_repo="$1" report="$2" task="$3"
    run env CMD_COMPLETE_GATE_COMMIT_REPO_ONLY=1 \
        COMMIT_REPO_RESOLVER_MAIN="$PROJECT_ROOT/scripts/gates/gate_report_format_main.py" \
        CMD_COMPLETE_GATE_CI_REPO_DIR="$fallback_repo" \
        CMD_COMPLETE_GATE_CI_REPORT="$report" \
        CMD_COMPLETE_GATE_TASK_FILE="$task" bash "$SRC_GATE_SCRIPT"
}

# test_necessity: report CI publication must use an explicit commit repo even
# when task.project belongs to a different repository.
@test "CI commit repo contract accepts canonical cross-project repo_root" {
    local project_repo="$BATS_TEST_TMPDIR/project-repo"
    local commit_repo="$BATS_TEST_TMPDIR/commit-repo"
    local report="$BATS_TEST_TMPDIR/report.yaml"
    local task="$BATS_TEST_TMPDIR/task.yaml"
    make_ci_push_repo "$project_repo"
    make_ci_push_repo "$commit_repo"
    printf 'project: dm-signal\ncommit_contract: {required: true, repo_root: %s}\n' "$commit_repo" > "$report"
    printf 'task:\n  project: dm-signal\n  commit_contract: {required: true, repo_root: %s}\n' "$commit_repo" > "$task"
    run_commit_repo_resolution "$project_repo" "$report" "$task"
    [ "$status" -eq 0 ]
    [ "$output" = "$commit_repo" ]
}

# test_necessity: report-side repo tampering must not redirect CI validation.
@test "CI commit repo contract blocks task report repo_root mismatch" {
    local repo_a="$BATS_TEST_TMPDIR/repo-a" repo_b="$BATS_TEST_TMPDIR/repo-b"
    local report="$BATS_TEST_TMPDIR/report.yaml" task="$BATS_TEST_TMPDIR/task.yaml"
    make_ci_push_repo "$repo_a"; make_ci_push_repo "$repo_b"
    printf 'commit_contract: {required: true, repo_root: %s}\n' "$repo_b" > "$report"
    printf 'task:\n  commit_contract: {required: true, repo_root: %s}\n' "$repo_a" > "$task"
    run_commit_repo_resolution "$repo_a" "$report" "$task"
    [ "$status" -eq 0 ]
    [ "$output" = "BLOCK: task/report commit_contract repo_root mismatch" ]
}

# test_necessity: unknown/non-git explicit repo roots fail closed.
@test "CI commit repo contract blocks non-git repo_root" {
    local project_repo="$BATS_TEST_TMPDIR/project-repo" bad_repo="$BATS_TEST_TMPDIR/not-git"
    local report="$BATS_TEST_TMPDIR/report.yaml" task="$BATS_TEST_TMPDIR/task.yaml"
    make_ci_push_repo "$project_repo"; mkdir -p "$bad_repo"
    printf '{}\n' > "$report"
    printf 'task:\n  commit_contract: {required: true, repo_root: %s}\n' "$bad_repo" > "$task"
    run_commit_repo_resolution "$project_repo" "$report" "$task"
    [ "$status" -eq 0 ]
    [[ "$output" == "BLOCK: explicit commit repository is unreadable or not a git repository" ]]
}

# test_necessity: omitting repo_root retains the existing project/fallback repo.
@test "CI commit repo contract preserves fallback when repo_root omitted" {
    local project_repo="$BATS_TEST_TMPDIR/project-repo"
    local report="$BATS_TEST_TMPDIR/report.yaml" task="$BATS_TEST_TMPDIR/task.yaml"
    make_ci_push_repo "$project_repo"
    printf '{}\n' > "$report"
    printf 'task:\n  project: infra\n  commit_contract: {required: true}\n' > "$task"
    run_commit_repo_resolution "$project_repo" "$report" "$task"
    [ "$status" -eq 0 ]
    [ "$output" = "$project_repo" ]
}

@test "CI push detection ignores files_modified for an unpushed report commit" {
    local repo="$BATS_TEST_TMPDIR/unpushed-files" report="$BATS_TEST_TMPDIR/unpushed-files.yaml"
    make_ci_push_repo "$repo"
    echo local >> "$repo/state"; git -C "$repo" commit -qam local
    printf 'commit_hash: %s\nfiles_modified: [{path: scripts/x.sh}]\n' "$(git -C "$repo" rev-parse HEAD)" > "$report"
    run_ci_push_state "$repo" "$report"
    [ "$status" -eq 0 ]; [[ "$output" == UNPUSHED:* ]]
}

@test "CI push detection ignores git push free text for an unpushed report commit" {
    local repo="$BATS_TEST_TMPDIR/unpushed-text" report="$BATS_TEST_TMPDIR/unpushed-text.yaml"
    make_ci_push_repo "$repo"
    echo local >> "$repo/state"; git -C "$repo" commit -qam local
    printf 'commit_hash: %s\nresult: {summary: "git push: OK"}\n' "$(git -C "$repo" rev-parse HEAD)" > "$report"
    run_ci_push_state "$repo" "$report"
    [ "$status" -eq 0 ]; [[ "$output" == UNPUSHED:* ]]
}

@test "CI push detection accepts a remote-contained report commit" {
    local repo="$BATS_TEST_TMPDIR/pushed" report="$BATS_TEST_TMPDIR/pushed.yaml"
    make_ci_push_repo "$repo"
    printf 'commit_hash: %s\nfiles_modified: [{path: scripts/x.sh}]\n' "$(git -C "$repo" rev-parse HEAD)" > "$report"
    run_ci_push_state "$repo" "$report"
    [ "$status" -eq 0 ]; [[ "$output" == PUSHED:* ]]
}

@test "CI push detection blocks when remote boundary is missing" {
    local repo="$BATS_TEST_TMPDIR/missing-remote" report="$BATS_TEST_TMPDIR/missing-remote.yaml"
    git init -q "$repo"
    printf 'commit_hash: %040d\n' 1 > "$report"
    run_ci_push_state "$repo" "$report"
    [ "$status" -eq 0 ]; [[ "$output" == "BLOCK: remote"* ]]
}

@test "CI push detection blocks an invalid report commit" {
    local repo="$BATS_TEST_TMPDIR/invalid-commit" report="$BATS_TEST_TMPDIR/invalid-commit.yaml"
    make_ci_push_repo "$repo"
    printf 'commit_hash: not-a-commit\n' > "$report"
    run_ci_push_state "$repo" "$report"
    [ "$status" -eq 0 ]; [[ "$output" == "BLOCK: report commit"* ]]
}

@test "CI push detection skips a no-code-change sentinel" {
    local repo="$BATS_TEST_TMPDIR/no-code" report="$BATS_TEST_TMPDIR/no-code.yaml"
    make_ci_push_repo "$repo"
    printf 'commit_hash: not-required\nfiles_modified: [{path: no-code-change}]\n' > "$report"
    run_ci_push_state "$repo" "$report"
    [ "$status" -eq 0 ]; [ "$output" = "UNPUSHED: no-code-change sentinel" ]
}

@test "CI push detection accepts only a resolvable unchanged tree for structured no-code-change" {
    local repo="$BATS_TEST_TMPDIR/no-code-tree" report="$BATS_TEST_TMPDIR/no-code-tree.yaml" tree
    make_ci_push_repo "$repo"
    tree="$(git -C "$repo" rev-parse HEAD^{tree})"
    printf 'commit_hash: no-code-change\nno_code_change_evidence: {before_tree: %s, after_tree: %s, tree_unchanged: true}\nfiles_modified: [{path: scripts/x.sh}]\n' "$tree" "$tree" > "$report"
    run_ci_push_state "$repo" "$report"
    [ "$status" -eq 0 ]; [ "$output" = "UNPUSHED: no-code-change tree sentinel ($tree)" ]
}

@test "CI push detection blocks malformed or unresolvable structured no-code-change evidence" {
    local repo="$BATS_TEST_TMPDIR/no-code-adversarial" report="$BATS_TEST_TMPDIR/no-code-adversarial.yaml" tree
    make_ci_push_repo "$repo"
    tree="$(git -C "$repo" rev-parse HEAD^{tree})"
    for evidence in \
        '{}' \
        "{before_tree: $tree, after_tree: 0000000000000000000000000000000000000000, tree_unchanged: true}" \
        "{before_tree: not-hex, after_tree: not-hex, tree_unchanged: true}" \
        "{before_tree: $tree, after_tree: $tree, tree_unchanged: false}"; do
        printf 'commit_hash: no-code-change\nno_code_change_evidence: %s\nfiles_modified: [{path: scripts/x.sh}]\n' "$evidence" > "$report"
        run_ci_push_state "$repo" "$report"
        [ "$status" -eq 0 ]; [ "$output" = "BLOCK: no-code-change evidence invalid" ]
    done
    printf 'commit_hash: no-code-change\nno_code_change_evidence: {before_tree: "%040d", after_tree: "%040d", tree_unchanged: true}\nfiles_modified: [{path: scripts/x.sh}]\n' 1 1 > "$report"
    run_ci_push_state "$repo" "$report"
    [ "$status" -eq 0 ]; [[ "$output" == "BLOCK: no-code-change tree unresolvable"* ]]
}

@test "CI push detection resolves cross-repo commit when primary repo lacks it" {
    # Scenario: task.project=dm-signal so task_repo_dir=dm-signal-repo, but ninja
    # committed to shogun-repo. cross_repo_commits lists the shogun entry.
    local dm_repo="$BATS_TEST_TMPDIR/dm-signal-repo"
    local shogun_repo="$BATS_TEST_TMPDIR/shogun-repo"
    local report="$BATS_TEST_TMPDIR/cross-repo-pushed.yaml"

    # Set up shogun-like repo with a pushed commit
    make_ci_push_repo "$shogun_repo"
    echo infra-change >> "$shogun_repo/state"
    git -C "$shogun_repo" commit -qam "infra fix"
    local shogun_commit
    shogun_commit=$(git -C "$shogun_repo" rev-parse HEAD)
    # Mark shogun commit as "pushed" (in origin/main)
    git -C "$shogun_repo" update-ref refs/remotes/origin/main "$shogun_commit"

    # Set up dm-signal-like repo (does NOT contain shogun_commit)
    make_ci_push_repo "$dm_repo"

    # Report: primary commit_hash is from shogun; cross_repo_commits has shogun entry
    printf 'commit_hash: %s\ncross_repo_commits:\n- repo: %s\n  commit_hash: %s\n  paths:\n  - scripts/cmd_complete_gate.sh\n' \
        "$shogun_commit" "$shogun_repo" "$shogun_commit" > "$report"

    # dm_repo is the task_repo_dir (can't resolve shogun commit)
    run_ci_push_state "$dm_repo" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == PUSHED:* ]]
}

@test "CI push detection resolves cross-repo commit as unpushed when not in cross-repo origin" {
    local dm_repo="$BATS_TEST_TMPDIR/dm-signal-unpushed"
    local shogun_repo="$BATS_TEST_TMPDIR/shogun-unpushed"
    local report="$BATS_TEST_TMPDIR/cross-repo-unpushed.yaml"

    # Set up shogun-like repo with a local-only commit (not pushed to origin)
    make_ci_push_repo "$shogun_repo"
    echo local-only >> "$shogun_repo/state"
    git -C "$shogun_repo" commit -qam "local infra fix"
    local shogun_commit
    shogun_commit=$(git -C "$shogun_repo" rev-parse HEAD)
    # origin/main stays at the earlier commit (shogun_commit not pushed)

    make_ci_push_repo "$dm_repo"

    printf 'commit_hash: %s\ncross_repo_commits:\n- repo: %s\n  commit_hash: %s\n  paths:\n  - scripts/cmd_complete_gate.sh\n' \
        "$shogun_commit" "$shogun_repo" "$shogun_commit" > "$report"

    run_ci_push_state "$dm_repo" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == UNPUSHED:* ]]
}

@test "CI push detection still blocks when commit unresolvable and not in cross_repo_commits" {
    local dm_repo="$BATS_TEST_TMPDIR/dm-signal-still-block"
    local report="$BATS_TEST_TMPDIR/cross-repo-block.yaml"

    make_ci_push_repo "$dm_repo"

    # commit_hash not in dm_repo and cross_repo_commits is empty
    printf 'commit_hash: %040d\ncross_repo_commits: []\n' 9 > "$report"

    run_ci_push_state "$dm_repo" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == "BLOCK: report commit"* ]]
}

# test_necessity: archive publication must use a session-independent worker and a command-correlated failure log.
# regression_justification: cmd_4209 observed the background archive die after stk-trim with process0 and archive.done0.
@test "archive worker is durably detached with null stdin and command-correlated log" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
start = text.index('echo "Archive (post-GATE CLEAR):"')
end = text.index('echo "Task idle transition: queued (async)"', start)
block = text[start:end]
assert '"$_archive_tmux_bin" run-shell -b' in block
assert 'synchronous fallback' in block
assert '</dev/null >>$_archive_log_q 2>&1' in block
assert '_archive_worker_log="$GATES_DIR/archive_worker.log"' in block
assert 'archive_completed.sh" "$CMD_ID"' in block
print('durable_archive_worker=1 correlated_log=1 null_stdin=1')
PY
    [ "$status" -eq 0 ]
    [ "$output" = "durable_archive_worker=1 correlated_log=1 null_stdin=1" ]

    local root="$BATS_TEST_TMPDIR/archive-durable" cmd=cmd_archive_durable
    mkdir -p "$root/scripts" "$root/queue/gates/$cmd"
    cat > "$root/scripts/archive_completed.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
root="${ARCHIVE_TEST_ROOT:?}"
cmd="${1:?}"
if [ ! -f "$root/retry.enabled" ]; then
    echo "forced archive worker failure for $cmd" >&2
    exit 23
fi
sleep 0.1
touch "$root/queue/gates/$cmd/archive.done"
SH
    chmod +x "$root/scripts/archive_completed.sh"

    run bash -c 'nohup setsid -f env ARCHIVE_TEST_ROOT="$1" SHOGUN_COMPLETION_GENERATION=fixture bash "$1/scripts/archive_completed.sh" "$2" </dev/null >>"$1/queue/gates/$2/archive_worker.log" 2>&1 &' _ "$root" "$cmd"
    [ "$status" -eq 0 ]
    for _ in $(seq 1 50); do [ -s "$root/queue/gates/$cmd/archive_worker.log" ] && break; sleep 0.02; done
    [ -s "$root/queue/gates/$cmd/archive_worker.log" ]
    [ ! -e "$root/queue/gates/$cmd/archive.done" ]

    touch "$root/retry.enabled"
    run bash -c 'nohup setsid -f env ARCHIVE_TEST_ROOT="$1" SHOGUN_COMPLETION_GENERATION=fixture bash "$1/scripts/archive_completed.sh" "$2" </dev/null >>"$1/queue/gates/$2/archive_worker.log" 2>&1 &' _ "$root" "$cmd"
    [ "$status" -eq 0 ]
    for _ in $(seq 1 50); do [ -e "$root/queue/gates/$cmd/archive.done" ] && break; sleep 0.02; done
    [ -e "$root/queue/gates/$cmd/archive.done" ]
}

# test_necessity: a report reopened during archive selection must remain live
# and block completion once, rather than triggering three identical retries.
# regression_justification: the live-direct reproduction left archive.done and
# active_reports=1 while every retry logged report changed during selection;
# retrying cannot make a revision_requested report eligible for archive.
@test "archive terminal blocks once when report reopens during selection" {
    local root="$BATS_TEST_TMPDIR/archive-reopened"
    local cmd="cmd_archive_reopened"
    local report="$root/queue/reports/saizo_report_${cmd}.yaml"
    local calls="$root/archive_calls.log"
    mkdir -p "$root/scripts" "$root/queue/reports" "$root/queue/gates/$cmd"
    touch "$root/queue/gates/$cmd/archive.done"
    cat > "$report" <<'EOF'
worker_id: saizo
parent_cmd: cmd_archive_reopened
status: revision_requested
result:
  summary: reopened during archive selection
EOF
    cp "$report" "$root/report.before"
    cat > "$root/scripts/archive_completed.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ARCHIVE_TEST_CALLS:?}"
exit 0
SH
    chmod +x "$root/scripts/archive_completed.sh"

    eval "$(sed -n '/^archive_terminal_has_reopened_report()/,/^}/p; /^archive_terminal()/,/^}/p' \
        "$PROJECT_ROOT/scripts/cmd_complete.sh")"
    export ROOT_DIR="$root" SCRIPT_DIR="$root/scripts" CHECKPOINT_DIR="$root/queue/gates/$cmd"
    export CMD_ID="$cmd" BUNDLE_IDENTITY=fixture CMD_COMPLETE_ARCHIVE_ATTEMPTS=3
    export ARCHIVE_TEST_CALLS="$calls"

    run archive_terminal
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK archive_terminal reopened_report_preserved"* ]]
    [ "$(wc -l < "$calls")" -eq 1 ]
    cmp -s "$root/report.before" "$report"
    [ ! -e "$root/queue/archive/reports/saizo_report_${cmd}.yaml" ]
}
