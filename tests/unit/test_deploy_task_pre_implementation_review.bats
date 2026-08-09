#!/usr/bin/env bats
# test_necessity: deployment for bugfix/hotfix/ci_fix must never block on
# Gunshi pre-implementation LGTM presence, absence, or staleness — deployment
# and draft review run in parallel and deployment never waits for APPROVE
# (殿裁定2026-08-09 14:05, cmd_karo_hotfix_rc_peer_report_redeploy_20260809).
# This supersedes the removed deploy_task_require_pre_implementation_review
# gate (AC1 reproduction of the prior BLOCK is preserved in git history).

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    export TEST_TMPDIR="$BATS_TEST_TMPDIR"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    cp -rP "$DEPLOY_TASK_PROJECT_TEMPLATE" "$TEST_PROJECT"
    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports" "$TEST_TMPDIR/logs"
}

@test "deploy_task_require_pre_implementation_review no longer exists" {
    run grep -n '^deploy_task_require_pre_implementation_review()' "$SRC_DEPLOY_SCRIPT"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "deploy_task_main no longer calls a pre-implementation review gate" {
    run grep -n 'deploy_task_require_pre_implementation_review' "$SRC_DEPLOY_SCRIPT"
    [ "$status" -eq 1 ]
}

run_direct_deploy() {
    local ninja="$1" cmd="$2"
    run bash -c '
        set -euo pipefail
        project="$1"; ninja="$2"; cmd="$3"
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
        maybe_notify_draft_review() { echo "draft_review_notified"; }
        deploy_task_send_direct_renudge() { :; }
        tmux() { return 0; }
        deploy_task_main --direct "$ninja" "$cmd"
    ' _ "$TEST_PROJECT" "$ninja" "$cmd"
}

@test "hotfix task with no pre_implementation_review field deploys without BLOCK" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_type: hotfix
  status: idle
EOF
    run_direct_deploy sasuke cmd_rc_gate_hotfix
    [ "$status" -eq 0 ]
    [[ "$output" != *"pre-implementation"* ]]
    [[ "$output" != *"LGTM"* ]]
}

@test "bugfix task with no pre_implementation_review field deploys without BLOCK" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_type: bugfix
  status: idle
EOF
    run_direct_deploy sasuke cmd_rc_gate_bugfix
    [ "$status" -eq 0 ]
    [[ "$output" != *"pre-implementation"* ]]
    [[ "$output" != *"LGTM"* ]]
}

@test "ci_fix task with no pre_implementation_review field deploys without BLOCK" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_type: ci_fix
  status: idle
EOF
    run_direct_deploy sasuke cmd_rc_gate_ci_fix
    [ "$status" -eq 0 ]
    [[ "$output" != *"pre-implementation"* ]]
    [[ "$output" != *"LGTM"* ]]
}

@test "hotfix task with a stale pre_implementation_review fingerprint still deploys without BLOCK" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_type: hotfix
  status: idle
  ac_version: fp-current
  pre_implementation_review:
    reviewer: gunshi
    result: LGTM
    task_id: cmd_other
    task_fingerprint: fp-old
    evidence_message_id: msg-1
EOF
    run_direct_deploy sasuke cmd_rc_gate_stale
    [ "$status" -eq 0 ]
    [[ "$output" != *"pre-implementation"* ]]
}

@test "draft review notification still fires in parallel for hotfix deployment" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_type: hotfix
  status: idle
EOF
    run_direct_deploy sasuke cmd_rc_gate_parallel
    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review_notified"* ]]
}
