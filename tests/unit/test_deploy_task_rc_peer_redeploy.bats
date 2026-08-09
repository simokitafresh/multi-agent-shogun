#!/usr/bin/env bats
# test_necessity: a peer report only bypasses deploy_task_has_completed_peer_report's
# BLOCK when it is formally karo-RC'd, revision_requested, and verdict FAIL.
# No RC, a PASS verdict, an in-progress runtime claim on the same cmd, and the
# deploying ninja's own pending report must all still BLOCK
# (cmd_karo_hotfix_rc_peer_report_redeploy_20260809, AC3/AC4).

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    export TEST_TMPDIR="$BATS_TEST_TMPDIR"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    cp -rP "$DEPLOY_TASK_PROJECT_TEMPLATE" "$TEST_PROJECT"
    mkdir -p \
        "$TEST_PROJECT/queue/tasks" \
        "$TEST_PROJECT/queue/reports" \
        "$TEST_PROJECT/queue/gates/cmd_rc_peer/review_approvals/reports/case"
    source "$SRC_FIELD_GET_SCRIPT"
    export FIELD_GET_NO_LOG=1
}

write_peer_report() {
    local verdict="$1"
    cat > "$TEST_PROJECT/queue/reports/hayate_report_cmd_rc_peer.yaml" <<EOF
worker_id: hayate
parent_cmd: cmd_rc_peer
status: revision_requested
verdict: ${verdict}
EOF
}

write_karo_rc_approval() {
    cat > "$TEST_PROJECT/queue/gates/cmd_rc_peer/review_approvals/reports/case/karo.yaml" <<'EOF'
role: karo
result: RC
report: queue/reports/hayate_report_cmd_rc_peer.yaml
EOF
}

run_has_completed_peer_report() {
    local ninja="$1"
    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        log() { echo "$*"; }
        deploy_task_has_completed_peer_report cmd_rc_peer "$2" "$1/queue/tasks/$2.yaml"
    ' _ "$TEST_PROJECT" "$ninja"
}

@test "ALLOW: karo-RC'd revision_requested FAIL peer report permits redeploy to a different idle ninja" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  status: idle
EOF
    write_peer_report FAIL
    write_karo_rc_approval

    run_has_completed_peer_report sasuke
    [ "$status" -eq 1 ]
    [[ "$output" == *"formal_karo_rc_peer_redeploy: cmd_rc_peer peer=hayate"* ]]

    # The original (failed) peer report must remain byte-identical.
    run sha256sum "$TEST_PROJECT/queue/reports/hayate_report_cmd_rc_peer.yaml"
    before_sha="${output%% *}"
    write_karo_rc_approval  # no-op rewrite to prove idempotent read-only path
    run sha256sum "$TEST_PROJECT/queue/reports/hayate_report_cmd_rc_peer.yaml"
    [ "${output%% *}" = "$before_sha" ]
}

@test "REJECT 1/4: no karo RC approval still BLOCKs redeploy" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  status: idle
EOF
    write_peer_report FAIL
    # no write_karo_rc_approval

    run_has_completed_peer_report sasuke
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK: cmd_rc_peer already has completed report from hayate"* ]]
}

@test "REJECT 2/4: RC'd but PASS-verdict peer report still BLOCKs redeploy" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  status: idle
EOF
    write_peer_report PASS
    write_karo_rc_approval

    run_has_completed_peer_report sasuke
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK: cmd_rc_peer already has completed report from hayate"* ]]
}

@test "REJECT 3/4: peer runtime already in_progress on the same cmd still BLOCKs (unaffected by the RC exception)" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  task_type: exact
  parent_cmd: cmd_rc_peer_busy
  status: in_progress
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_type: exact
  status: idle
EOF
    run bash -c '
        set -euo pipefail
        project="$1"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$project/scripts/deploy_task.sh"
        log() { :; }
        resolve_pane() { echo "test-pane"; }
        get_ctx_pct() { echo 0; }
        cli_type() { echo codex; }
        sleep() { :; }
        check_idle() { return 0; }
        deploy_task_validate_cli_target() { return 0; }
        normalize_task_yaml() { :; }
        capture_done_redeploy_context() { :; }
        reset_stale_fields() { _STALE_RESET_DONE=1; }
        check_firefighting_title() { :; }
        warn_same_ninja_redeploy() { :; }
        warn_task_clarity() { :; }
        warn_recent_noncmd_commit_targets() { :; }
        deploy_task_apply_task_mutations() { :; }
        notify_initial_deploy_ntfy_once() { :; }
        record_deployed_at() { :; }
        preflight_gate_artifacts() { :; }
        maybe_notify_draft_review() { :; }
        deploy_task_send_direct_renudge() { :; }
        tmux() { return 0; }
        deploy_task_main --direct sasuke cmd_rc_peer_busy
    ' _ "$TEST_PROJECT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: cmd_rc_peer_busy is already assigned to hayate"* ]]
    [[ "$output" == *"in_progress"* ]]
}

@test "REJECT 4/4: deploying ninja's own pending report (not a peer) still BLOCKs without formal RC" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_rc_peer_own
  report_path: queue/reports/sasuke_report_cmd_rc_peer_own.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_cmd_rc_peer_own.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_rc_peer_own
status: revision_requested
verdict: FAIL
EOF
    # no karo RC approval for this report
    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        log() { echo "$*"; }
        deploy_task_has_pending_own_report cmd_rc_peer_own sasuke "$1/queue/tasks/sasuke.yaml"
    ' _ "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK: sasuke has pending report for cmd_rc_peer_own"* ]]
}
