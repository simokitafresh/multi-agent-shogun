#!/usr/bin/env bats

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_gpt_priority"
}

teardown() {
    deploy_task_teardown
}

write_gpt_priority_settings() {
    cat > "$TEST_TMPDIR/settings_gpt_priority.yaml" <<'EOF'
cli:
  default: claude
  agents:
    saizo:
      type: codex
      role: ninja
    hayate:
      type: codex
      role: ninja
    tobisaru:
      type: claude
      role: ninja
EOF
}

write_task_status() {
    local ninja="$1"
    local status="$2"
    cat > "$TEST_PROJECT/queue/tasks/${ninja}.yaml" <<EOF
task:
  status: ${status}
EOF
}

@test "GPT priority blocks non-Codex deployment while Codex ninja is idle" {
    write_gpt_priority_settings
    write_task_status saizo idle
    write_task_status hayate in_progress
    write_task_status tobisaru idle

    run bash -lc '
        export DEPLOY_TASK_LIB_ONLY=1
        export DEPLOY_TASK_GPT_PRIORITY=1
        export CLI_LOOKUP_SETTINGS="'"$TEST_TMPDIR/settings_gpt_priority.yaml"'"
        source "'"$TEST_PROJECT/scripts/deploy_task.sh"'"
        log() { :; }
        TYPE=task_assigned
        deploy_task_enforce_gpt_priority tobisaru normal
    '

    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: GPT優先配備"* ]]
    [[ "$output" == *"idle GPT忍者(saizo)"* ]]
}

@test "GPT priority allows Codex deployment" {
    write_gpt_priority_settings
    write_task_status saizo idle
    write_task_status tobisaru idle

    run bash -lc '
        export DEPLOY_TASK_LIB_ONLY=1
        export DEPLOY_TASK_GPT_PRIORITY=1
        export CLI_LOOKUP_SETTINGS="'"$TEST_TMPDIR/settings_gpt_priority.yaml"'"
        source "'"$TEST_PROJECT/scripts/deploy_task.sh"'"
        log() { :; }
        TYPE=task_assigned
        deploy_task_enforce_gpt_priority saizo normal
    '

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "GPT priority override requires explicit reason and then allows non-Codex deployment" {
    write_gpt_priority_settings
    write_task_status saizo idle
    write_task_status tobisaru idle

    run bash -lc '
        export DEPLOY_TASK_LIB_ONLY=1
        export DEPLOY_TASK_GPT_PRIORITY=1
        export CLI_LOOKUP_SETTINGS="'"$TEST_TMPDIR/settings_gpt_priority.yaml"'"
        export DEPLOY_TASK_ALLOW_NON_GPT=1
        export DEPLOY_TASK_GPT_PRIORITY_REASON="Sonnet観点の比較レビュー"
        source "'"$TEST_PROJECT/scripts/deploy_task.sh"'"
        log() { :; }
        TYPE=task_assigned
        deploy_task_enforce_gpt_priority tobisaru normal
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: GPT優先override"* ]]
    [[ "$output" == *"reason=Sonnet観点の比較レビュー"* ]]
}
