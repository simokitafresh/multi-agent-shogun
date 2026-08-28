#!/usr/bin/env bats

load '../helpers/cmd_gate_scaffold'

setup_file() {
    cmd_gate_setup_file
}

setup() {
    cmd_gate_scaffold "cmd_gate_idle"
    export SCRIPT_DIR="$TEST_PROJECT"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"
    export CMD_ID="$TEST_CMD_ID"
    unset CMD_COMPLETE_GATE_CLEAR_MARKER SHOGUN_COMPLETION_GENERATION

    source "$TEST_PROJECT/scripts/lib/field_get.sh"
    source "$TEST_PROJECT/scripts/lib/yaml_field_set.sh"
    source "$TEST_PROJECT/scripts/lib/task_lifecycle.sh"
    eval "$(sed -n '/^set_matching_tasks_idle()/,/^}/p' "$TEST_PROJECT/scripts/cmd_complete_gate.sh")"
}

teardown() {
    cmd_gate_teardown
}

# test_necessity: review_approval.shの通常起動はgeneration環境変数を渡さないため、
# 検証済みSG7 bundleからcanonical generationを解決でき、明示envはbundleと一致する
# 場合だけ許可する不変量を守る。欠損・不一致の黙認は別generation混同を起こす。
@test "SG7 completion identity resolves normal review trigger and rejects mismatches" {
    eval "$(sed -n '/^resolve_sg7_completion_identity()/,/^}/p' "$SRC_GATE_SCRIPT")"
    local bundle="$TEST_PROJECT/queue/gates/$TEST_CMD_ID/sg7_bundle.json"
    local generation
    generation="$(printf 'a%.0s' {1..64})"
    mkdir -p "$(dirname "$bundle")"
    printf '{"review":{"cmd_id":"%s","report_fingerprint":"%s","cmd_spec_source":"queue/reports/x.yaml","reviewed_at":"now"}}\n' \
        "$TEST_CMD_ID" "$generation" > "$bundle"
    local spec='{"project":"infra","scope":[]}'

    unset SHOGUN_COMPLETION_GENERATION
    resolve_sg7_completion_identity "$bundle"
    [ "$SHOGUN_COMPLETION_GENERATION" = "$generation" ]

    SHOGUN_COMPLETION_GENERATION="$generation"
    run resolve_sg7_completion_identity "$bundle"
    [ "$status" -eq 0 ]

    SHOGUN_COMPLETION_GENERATION="$(printf 'b%.0s' {1..64})"
    run resolve_sg7_completion_identity "$bundle"
    [ "$status" -ne 0 ]
    [[ "$output" == *"completion_generation_bundle_mismatch"* ]]

    printf '{"review":{"cmd_id":"cmd_wrong","report_fingerprint":"%s"}}\n' "$generation" > "$bundle"
    unset SHOGUN_COMPLETION_GENERATION
    run resolve_sg7_completion_identity "$bundle"
    [ "$status" -ne 0 ]
    [[ "$output" == *"completion_bundle_identity_missing_or_invalid"* ]]
}

write_nested_task() {
    local ninja_name="$1"
    local status="${2:-done}"
    cat > "$TEST_PROJECT/queue/tasks/${ninja_name}.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  assigned_to: $ninja_name
  task_id: ${ninja_name}_task
  status: $status
EOF
}

write_in_progress_terminal_fixture() {
    local ninja_name="${1:-hayate}"
    local status="${2:-in_progress}"
    local report_name="${ninja_name}_report_${TEST_CMD_ID}.yaml"
    mkdir -p "$TEST_PROJECT/queue/archive/reports"
    cat > "$TEST_PROJECT/queue/tasks/${ninja_name}.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  assigned_to: $ninja_name
  task_id: ${ninja_name}_terminal_task
  report_id: rpt-${ninja_name}-terminal
  report_identity_version: 2
  report_filename: $report_name
  report_path: queue/reports/$report_name
  status: $status
EOF
    cat > "$TEST_PROJECT/queue/archive/reports/$report_name" <<EOF
report_id: rpt-${ninja_name}-terminal
report_identity_version: 2
task_id: ${ninja_name}_terminal_task
parent_cmd: $TEST_CMD_ID
status: completed
verdict: PASS
EOF
    rm -f "$TEST_PROJECT/queue/reports/$report_name"
    ln -s "$TEST_PROJECT/queue/archive/reports/$report_name" \
        "$TEST_PROJECT/queue/reports/$report_name"
}

write_clear_receipt() {
    local generation="${1:-$(printf 'a%.0s' {1..64})}"
    export SHOGUN_COMPLETION_GENERATION="$generation"
    mkdir -p "$TEST_PROJECT/queue/gates/$TEST_CMD_ID"
    python3 - "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/gate_worker.clear.json" "$TEST_CMD_ID" "$generation" <<'PY'
import json
import sys

path, cmd_id, generation = sys.argv[1:]
json.dump({
    "version": 1,
    "state": "clear",
    "cmd_id": cmd_id,
    "completion_generation": generation,
    "persisted_at_ns": 1,
}, open(path, "w", encoding="utf-8"))
PY
}

# test_necessity: GATE CLEAR後にassigned taskが端末証明なしで残置される回帰を
# 固定し、証明不足のactive taskをidle化しない不変量を守る。
@test "AC1 reproduces archived symlink with assigned task left behind when terminal proof is absent" {
    write_in_progress_terminal_fixture hayate assigned
    MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/hayate.yaml")

    run set_matching_tasks_idle
    [ "$status" -eq 0 ]
    [[ "$output" == *"hayate: skip (status=assigned, terminal proof=completion_generation_missing_or_invalid)"* ]]
    [[ "$output" == *"summary: updated=0 skipped=1 warn=0"* ]]
    run grep -n "^  status: assigned$" "$TEST_PROJECT/queue/tasks/hayate.yaml"
    [ "$status" -eq 0 ]
}

# test_necessity: post-GATE CLEAR task lifecycle must accept an active task
# only when the archived report and generation-bound CLEAR receipt prove the
# exact task/report identity; otherwise a stale active task must remain active.
@test "AC2 terminalizes exact active task states and rejects incomplete or mismatched evidence" {
    for task_status in assigned acknowledged in_progress done completed; do
        write_in_progress_terminal_fixture hayate "$task_status"
        write_clear_receipt
        MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/hayate.yaml")

        run set_matching_tasks_idle
        [ "$status" -eq 0 ]
        [[ "$output" == *"hayate: ${task_status} → idle"* ]]
        run grep -n "^  status: idle$" "$TEST_PROJECT/queue/tasks/hayate.yaml"
        [ "$status" -eq 0 ]
    done

    for evidence_case in incomplete_report mismatched_generation clear_missing; do
        write_in_progress_terminal_fixture hayate acknowledged
        case "$evidence_case" in
            incomplete_report)
                sed -i 's/status: completed/status: pending/' \
                    "$TEST_PROJECT/queue/archive/reports/hayate_report_${TEST_CMD_ID}.yaml"
                write_clear_receipt
                ;;
            mismatched_generation)
                write_clear_receipt
                export SHOGUN_COMPLETION_GENERATION="$(printf 'b%.0s' {1..64})"
                ;;
            clear_missing)
                unset SHOGUN_COMPLETION_GENERATION
                ;;
        esac
        MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/hayate.yaml")
        run set_matching_tasks_idle
        [ "$status" -eq 0 ]
        [[ "$output" == *"summary: updated=0 skipped=1 warn=0"* ]]
        run grep -n "^  status: acknowledged$" "$TEST_PROJECT/queue/tasks/hayate.yaml"
        [ "$status" -eq 0 ]
    done
}

@test "set_matching_tasks_idle transitions matching nested task YAMLs to idle" {
    write_nested_task "hayate" "done"
    write_nested_task "sasuke" "completed"
    MATCHING_TASK_FILES=(
        "$TEST_PROJECT/queue/tasks/hayate.yaml"
        "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    )

    run set_matching_tasks_idle
    [ "$status" -eq 0 ]
    [[ "$output" == *"hayate: done → idle"* ]]
    [[ "$output" == *"sasuke: completed → idle"* ]]
    [[ "$output" == *"summary: updated=2 skipped=0 warn=0"* ]]

    run grep -n "^  status: idle$" "$TEST_PROJECT/queue/tasks/hayate.yaml"
    [ "$status" -eq 0 ]
    run grep -n "^  status: idle$" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
}

# cmd_karo_speed_completion_pipeline_20260725: MATCHING_TASK_FILES is a snapshot
# taken at gate-check-loop start. If karo redeploys the ninja onto a NEW cmd
# (report still being written, status=acknowledged) before this async post-CLEAR
# job runs, the transition must NOT fire — it must never stomp a mid-report task
# back to idle. This is the exact fixture for the "does not fire" half of AC3.
@test "set_matching_tasks_idle does not transition a task mid-report on the same parent_cmd" {
    write_nested_task "hayate" "acknowledged"
    MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/hayate.yaml")

    run set_matching_tasks_idle
    [ "$status" -eq 0 ]
    [[ "$output" == *"hayate: skip (status=acknowledged, terminal proof=report_identity_missing)"* ]]
    [[ "$output" == *"summary: updated=0 skipped=1 warn=0"* ]]

    run grep -n "^  status: acknowledged$" "$TEST_PROJECT/queue/tasks/hayate.yaml"
    [ "$status" -eq 0 ]
}

# The snapshot can also go stale by cmd reassignment: karo redeploys the ninja
# onto a different cmd_id entirely (still status=done from an earlier, unrelated
# task write) before this job runs. parent_cmd no longer matches CMD_ID, so the
# file must be left untouched even though status looks like "done".
@test "set_matching_tasks_idle does not transition a task reassigned to a different parent_cmd" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<EOF
task:
  parent_cmd: cmd_other_reassigned
  assigned_to: hayate
  task_id: hayate_task
  status: done
EOF
    MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/hayate.yaml")

    run set_matching_tasks_idle
    [ "$status" -eq 0 ]
    [[ "$output" == *"hayate: skip (parent_cmd=cmd_other_reassigned != ${TEST_CMD_ID}, reassigned)"* ]]
    [[ "$output" == *"summary: updated=0 skipped=1 warn=0"* ]]

    run grep -n "^  status: done$" "$TEST_PROJECT/queue/tasks/hayate.yaml"
    [ "$status" -eq 0 ]
}

@test "set_matching_tasks_idle handles flat task YAML" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<EOF
parent_cmd: $TEST_CMD_ID
assigned_to: hayate
task_id: hayate_task
status: done
EOF
    MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/hayate.yaml")

    run set_matching_tasks_idle
    [ "$status" -eq 0 ]
    [[ "$output" == *"hayate: done → idle"* ]]
    [[ "$output" == *"summary: updated=1 skipped=0 warn=0"* ]]

    run grep -n "^status: idle$" "$TEST_PROJECT/queue/tasks/hayate.yaml"
    [ "$status" -eq 0 ]
}

@test "set_matching_tasks_idle skips disappeared snapshot task YAML with WARN" {
    write_nested_task "hayate" "done"
    MATCHING_TASK_FILES=(
        "$TEST_PROJECT/queue/tasks/hayate.yaml"
        "$TEST_PROJECT/queue/tasks/missing.yaml"
    )
    MATCHING_TASK_FILES_PROCESSED_COUNT=0
    MATCHING_TASK_FILES_SKIPPED_COUNT=0

    run set_matching_tasks_idle
    [ "$status" -eq 0 ]
    [[ "$output" == *"hayate: done → idle"* ]]
    [[ "$output" == *"[WARN] matching task file disappeared, skipping: $TEST_PROJECT/queue/tasks/missing.yaml"* ]]
    [[ "$output" == *"summary: updated=1 skipped=0 warn=0"* ]]
}

@test "cmd_complete_gate logs matching task snapshot and final processing summary" {
    run grep -n "Matching task files snapshot:" "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
    run grep -n "Matching task files summary: snapshot=" "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
    run grep -n "skipped_missing=" "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
}

@test "cmd_complete_gate wires task idle transition only in GATE CLEAR branch" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
from pathlib import Path

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
call_lines = [
    idx
    for idx, line in enumerate(lines, start=1)
    if line.lstrip().startswith("(set_matching_tasks_idle")
]

if len(call_lines) != 1:
    raise SystemExit(f"expected single set_matching_tasks_idle call, got {len(call_lines)}")

archive_lines = [idx for idx, line in enumerate(lines, start=1) if "Archive (post-GATE CLEAR):" in line]
git_push_lines = [idx for idx, line in enumerate(lines, start=1) if "Git push (post-GATE CLEAR):" in line]

if not archive_lines or not git_push_lines:
    raise SystemExit("missing post-GATE CLEAR markers")

call_line = call_lines[0]
if not (archive_lines[-1] < call_line < git_push_lines[-1]):
    raise SystemExit(
        f"set_matching_tasks_idle call not between archive and git push: "
        f"archive={archive_lines[-1]} call={call_line} git_push={git_push_lines[-1]}"
    )
PY
    [ "$status" -eq 0 ]
}

# test_necessity: the public completion pipeline must checkpoint archive
# terminal evidence before dashboard/ntfy/COMPLETE and invoke the archive
# helper with its positional keep_results argument.
@test "cmd_complete checkpoints archive terminal before public completion" {
    local wrapper="$BATS_TEST_DIRNAME/../../scripts/cmd_complete.sh"
    run python3 - "$wrapper" <<'PY'
import pathlib, sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
step_line = text.index("STEP_ORDER=(")
archive_step = text.index("run_checkpointed archive_terminal archive_terminal")
dashboard_step = text.index("if checkpoint_has dashboard;", archive_step)
assert "archive_terminal" in text[step_line:dashboard_step]
assert archive_step < dashboard_step
assert 'bash "$archive_script" 3 "$CMD_ID"' in text
assert "completion_active_report_count()" in text
assert 'active_count="$(completion_active_report_count)"' in text
assert '[[ -f "$marker" && "$active_count" -eq 0 ]]' in text
print("archive_terminal_before_dashboard=1 retry_postcondition=1 positional_cmd_id=1")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"archive_terminal_before_dashboard=1 retry_postcondition=1 positional_cmd_id=1"* ]]
}

# test_necessity: cmd_complete.shはBashの逐次読込中に正本が更新されても、
# detached completion workerが起動時の全本体snapshotを使い、archive→dashboard→ntfy→COMPLETE
# のcheckpoint列を最後まで完了する不変量を守る。正本追記でworkerが途中停止する回帰を実行時に再現する。
@test "completion worker uses immutable source snapshot after canonical script update" {
    local wrapper="$TEST_PROJECT/scripts/cmd_complete.sh"
    local bundle="$TEST_PROJECT/queue/gates/$TEST_CMD_ID/sg7_bundle.json"
    local fake_tmux="$TEST_PROJECT/fake_tmux"
    local generation
    generation="$(printf 'a%.0s' {1..64})"

    cp "$PROJECT_ROOT/scripts/cmd_complete.sh" "$wrapper"
    rm -f "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/archive.done"
    rm -f "$TEST_PROJECT/scripts/cmd_complete_gate.sh"
    printf 'active report\n' > "$TEST_PROJECT/queue/reports/hanzo_report_${TEST_CMD_ID}.yaml"
    printf '{"review":{"cmd_id":"%s","report_fingerprint":"%s"}}\n' \
        "$TEST_CMD_ID" "$generation" > "$bundle"
    cat > "$TEST_PROJECT/scripts/review_bundle.py" <<'PY'
#!/usr/bin/env python3
print('{"project":"infra"}')
PY
    cat > "$TEST_PROJECT/scripts/lesson_review.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    cat > "$TEST_PROJECT/scripts/cmd_complete_gate.sh" <<'SH'
#!/usr/bin/env bash
printf '%s CLEAR\n' "$1" >> "$(dirname "$(dirname "$0")")/logs/gate_metrics.log"
exit 0
SH
    cat > "$TEST_PROJECT/scripts/cmd_quality_log.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    cat > "$TEST_PROJECT/scripts/gates/gate_yaml_status.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    cat > "$TEST_PROJECT/scripts/dashboard_update.sh" <<'SH'
#!/usr/bin/env bash
printf 'dashboard %s\n' "$1" >> "$(dirname "$(dirname "$0")")/dashboard.log"
exit 0
SH
    cat > "$TEST_PROJECT/scripts/ntfy_cmd.sh" <<'SH'
#!/usr/bin/env bash
printf 'ntfy %s\n' "$1" >> "$(dirname "$(dirname "$0")")/ntfy.log"
exit 0
SH
    cat > "$TEST_PROJECT/scripts/inbox_archive.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    cat > "$TEST_PROJECT/scripts/archive_completed.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
root="${ARCHIVE_COMPLETED_PROJECT_DIR:?}"
cmd_id="$2"
printf 'archive_worker_started\n' > "$root/worker_started"
while [[ ! -f "$root/allow_archive" ]]; do sleep 0.01; done
rm -f "$root/queue/reports/"*_report_${cmd_id}*.yaml
mkdir -p "$root/queue/gates/$cmd_id"
printf 'archive terminal\n' > "$root/queue/gates/$cmd_id/archive.done"
SH
    rm -f "$TEST_PROJECT/scripts/lib/retro_pane_prompt.sh"
    cat > "$TEST_PROJECT/scripts/lib/retro_pane_prompt.sh" <<'SH'
#!/usr/bin/env bash
retro_pane_prompt_async() { :; }
SH
    cat > "$fake_tmux" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "display-message" ]]; then
    exit 1
fi
cmd="${@: -1}"
bash -c "$cmd" &
printf '%s\n' "$!" > "${FAKE_TMUX_WORKER_PID:?}"
exit 0
SH
    chmod +x "$wrapper" "$fake_tmux" "$TEST_PROJECT/scripts/"*.sh \
        "$TEST_PROJECT/scripts/gates/"*.sh

    env \
        CMD_COMPLETE_DASHBOARD_ENABLED=1 \
        CMD_COMPLETE_ROOT_DIR="$TEST_PROJECT" \
        CMD_COMPLETE_SCRIPT_DIR="$TEST_PROJECT/scripts" \
        CMD_COMPLETE_TMUX_BIN="$fake_tmux" \
        FAKE_TMUX_WORKER_PID="$TEST_PROJECT/worker.pid" \
        CMD_COMPLETE_ARCHIVE_ATTEMPTS=1 \
        CMD_COMPLETE_ARCHIVE_RETRY_DELAY=0 \
        CMD_COMPLETE_DASHBOARD_ATTEMPTS=1 \
        CMD_COMPLETE_NTFY_ATTEMPTS=1 \
        DEFENSE_OVERHEAD_ENABLED=0 \
        RETRO_PANE_PENDING_DIR="$TEST_PROJECT/queue/retro/verbatim_pending" \
        RETRO_PANE_STATE_DIR="$TEST_PROJECT/queue/retro/pane_prompt" \
        bash "$wrapper" "$TEST_CMD_ID" "$bundle" \
        > "$TEST_PROJECT/caller.out" 2>&1 &
    local caller_pid=$!
    if ! wait "$caller_pid"; then
        cat "$TEST_PROJECT/caller.out" >&3
        false
    fi

    local attempt=0
    while [[ ! -f "$TEST_PROJECT/worker_started" && "$attempt" -lt 200 ]]; do
        sleep 0.02
        attempt=$((attempt + 1))
    done
    [ -f "$TEST_PROJECT/worker_started" ]
    printf '\npoint: command not found\n' >> "$wrapper"
    : > "$TEST_PROJECT/allow_archive"

    local tail_log="$TEST_PROJECT/queue/gates/$TEST_CMD_ID/completion_tail.log"
    attempt=0
    while [[ ! -f "$tail_log" ]] || ! grep -Fq '[cmd_complete] COMPLETE cmd_999' "$tail_log"; do
        sleep 0.02
        attempt=$((attempt + 1))
        [ "$attempt" -lt 300 ]
    done
    grep -F '[cmd_complete] COMPLETE cmd_999' "$tail_log"
    run python3 - "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/completion_checkpoint.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
expected = [
    'sg7_consume', 'lesson_review', 'cmd_complete_gate', 'quality_log',
    'status_completed', 'archive_terminal', 'dashboard', 'ntfy', 'inbox_archive',
]
assert data['completed'] == expected, data['completed']
print('immutable_snapshot_checkpoint_order=1')
PY
    [ "$status" -eq 0 ]
    [ -f "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/archive.done" ]
    [ ! -f "$TEST_PROJECT/queue/reports/hanzo_report_${TEST_CMD_ID}.yaml" ]
    [ -f "$TEST_PROJECT/dashboard.log" ]
    [ -f "$TEST_PROJECT/ntfy.log" ]
}

# cmd_karo_hotfix_task_idle_transition_verify_202607041407: append_codd_registry_entry
# is called bare (no "||" guard) between "GATE CLEAR: cmd完了許可" and
# set_matching_tasks_idle. Under `set -e` (active at the top of cmd_complete_gate.sh),
# an unguarded failing command anywhere in that call chain aborts the whole script
# before set_matching_tasks_idle ever runs, leaving the ninja's task status stuck at
# "done" instead of transitioning to "idle". This test proves the function itself
# never propagates a non-zero exit even when its embedded python3 subprocess raises.
@test "append_codd_registry_entry never propagates failure (would abort GATE CLEAR post-processing under set -e)" {
    eval "$(sed -n '/^append_codd_registry_entry()/,/^}/p' "$SRC_GATE_SCRIPT")"

    lock_path() { echo "$TEST_PROJECT/registry.lock.$$"; }
    SCRIPT_DIR="$TEST_PROJECT"
    CMD_ID="cmd_999"
    YAML_FILE="$TEST_PROJECT/dummy.yaml"
    MATCHING_TASK_FILES=()

    mkdir -p "$TEST_PROJECT/docs/research"
    printf '# registry\n|------|\n' > "$TEST_PROJECT/docs/research/codd_refactor_registry.md"

    # Simulate ANY unhandled exception inside the embedded CoDD registry python
    # body (malformed ledger YAML, unexpected data shape, etc.) by hijacking
    # python3 on PATH to always fail — mirrors the real failure class without
    # needing to reverse-engineer the exact python bug.
    mkdir -p "$TEST_PROJECT/stub_bin"
    cat > "$TEST_PROJECT/stub_bin/python3" <<'PYSTUB'
#!/usr/bin/env bash
echo "Traceback (most recent call last): simulated CoDD registry bug" >&2
exit 1
PYSTUB
    chmod +x "$TEST_PROJECT/stub_bin/python3"
    PATH="$TEST_PROJECT/stub_bin:$PATH" run append_codd_registry_entry "$CMD_ID"

    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN] CoDD registry append failed (non-blocking)"* ]]
}

stub_cmd_complete_side_effects() {
    local stub
    for stub in \
        archive_completed dashboard_auto_section dashboard_update gist_sync ntfy_cmd ntfy \
        gunshi_gate_reflux bulletin_write lesson_impact_rotate lesson_impact_analysis \
        lesson_deprecation_scan rotate_gate_metrics auto_failure_lesson skill_gate_feedback
    do
        printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_PROJECT/scripts/${stub}.sh"
        chmod +x "$TEST_PROJECT/scripts/${stub}.sh"
    done
}

@test "no-task/no-report benchmark fast path still clears" {
    TEST_CMD_ID="cmd_fixture"
    stub_cmd_complete_side_effects
    rm -f "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/"*.done
    : > "$TEST_PROJECT/queue/shogun_to_karo.yaml"

    run env SHOGUN_COMPLETION_GENERATION="$(printf 'a%.0s' {1..64})" \
        bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No-task benchmark fast path"* ]]
    [[ "$output" == *"GATE CLEAR: cmd完了許可"* ]]
}

@test "no-task parent report with FAIL verdict blocks instead of benchmark fast path clear" {
    TEST_CMD_ID="cmd_fixture"
    stub_cmd_complete_side_effects
    rm -f "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/"*.done
    : > "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    cat > "$TEST_PROJECT/queue/reports/hanzo_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: hanzo
parent_cmd: $TEST_CMD_ID
status: completed
verdict: FAIL
binary_checks:
  commit:
  - check: git commitが完了したか
    result: no
EOF

    run env SHOGUN_COMPLETION_GENERATION="$(printf 'a%.0s' {1..64})" \
        bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 1 ]
    [[ "$output" != *"No-task benchmark fast path"* ]]
    [[ "$output" == *"No-task parent report validation"* ]]
    [[ "$output" == *"hanzo_report_${TEST_CMD_ID}.yaml: verdict=FAIL"* ]]
    [[ "$output" == *"GATE BLOCK"* ]]
}

@test "no-task parent validation uses newest report mtime per worker not lexical round name" {
    TEST_CMD_ID="cmd_fixture"
    stub_cmd_complete_side_effects
    rm -f "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/"*.done
    : > "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    local stale="$TEST_PROJECT/queue/reports/test_speed_report_${TEST_CMD_ID}_r2.yaml"
    local submitted="$TEST_PROJECT/queue/reports/test_speed_report_${TEST_CMD_ID}_r1.yaml"
    cat > "$stale" <<EOF
worker_id: hanzo
parent_cmd: $TEST_CMD_ID
status: pending
verdict: ""
binary_checks: {}
EOF
    cat > "$submitted" <<EOF
worker_id: hanzo
parent_cmd: $TEST_CMD_ID
status: completed
verdict: PASS
binary_checks:
  commit:
  - check: git commitが完了したか
    result: yes
EOF
    python3 - "$stale" "$submitted" <<'PY'
import os, sys
os.utime(sys.argv[1], ns=(100, 100))
os.utime(sys.argv[2], ns=(200, 200))
PY

    run env SHOGUN_COMPLETION_GENERATION="$(printf 'a%.0s' {1..64})" \
        bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [[ "$output" == *"$(basename "$submitted"): OK"* ]]
    [[ "$output" != *"$(basename "$stale"): verdict=MISSING"* ]]
    [[ "$output" != *"no_task_parent_report:$(basename "$stale")"* ]]
}

# cmd_karo_hotfix_post_clear_fail_open_20260725 (AC1): regression guard for the exact
# fatal pattern that killed cmd_4171 — a bare "|| exit" chained directly onto
# auto_resolve_cmd_related_insights would abort the script before Auto-notification/
# Bulletin/Task idle transition ever ran (hayate stuck at status=done). Fails if this
# pattern is reintroduced at either the normal or emergency-override CLEAR branch.
@test "AC1: auto_resolve_cmd_related_insights call sites no longer chain a bare exit" {
    run grep -n 'auto_resolve_cmd_related_insights "\$CMD_ID" || exit' "$SRC_GATE_SCRIPT"
    [ "$status" -ne 0 ]

    run grep -c 'if ! auto_resolve_cmd_related_insights "\$CMD_ID"; then' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
}

# cmd_karo_hotfix_post_clear_fail_open_20260725 (AC4): reproduces cmd_4171's exact
# condition — auto_resolve_cmd_related_insights fails with "insight declaration
# selection failed" (INSIGHTS_FILE unreadable) — using the real function AND the
# real set_matching_tasks_idle function (both extracted verbatim from source), run
# in the same sequence as the actual normal-CLEAR call site. Proves the insight
# failure no longer prevents the ninja's task from transitioning to idle.
@test "AC4: insight auto-triage failure does not block task idle transition (cmd_4171 reproduction)" {
    log_gate_stderr_file() { :; }
    eval "$(awk '/^auto_resolve_cmd_related_insights\(\)/,/^}/' "$SRC_GATE_SCRIPT")"

    export INSIGHTS_FILE="$TEST_PROJECT/queue/insights_as_dir.yaml"
    mkdir -p "$INSIGHTS_FILE"
    cp "$PROJECT_ROOT/scripts/insight_write.sh" "$TEST_PROJECT/scripts/insight_write.sh"
    cp "$PROJECT_ROOT/scripts/insight_resolve.sh" "$TEST_PROJECT/scripts/insight_resolve.sh"
    chmod +x "$TEST_PROJECT/scripts/insight_write.sh" "$TEST_PROJECT/scripts/insight_resolve.sh"

    write_nested_task "hayate" "done"
    MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/hayate.yaml")

    post_insight_sequence() {
        if ! auto_resolve_cmd_related_insights "$TEST_CMD_ID"; then
            echo "  [WARN] Insight auto-triage failed (non-blocking, GATE CLEAR continues)"
        fi
        echo ""
        echo "Task idle transition: queued (async)"
        set_matching_tasks_idle
    }

    run post_insight_sequence
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN] insight declaration selection failed (non-blocking)"* ]]
    [[ "$output" == *"[WARN] Insight auto-triage failed (non-blocking, GATE CLEAR continues)"* ]]
    [[ "$output" == *"Task idle transition: queued (async)"* ]]
    [[ "$output" == *"hayate: done → idle"* ]]

    run grep -n "^  status: idle$" "$TEST_PROJECT/queue/tasks/hayate.yaml"
    [ "$status" -eq 0 ]
}
