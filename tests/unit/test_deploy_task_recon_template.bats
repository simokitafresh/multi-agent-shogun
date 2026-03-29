#!/usr/bin/env bats
# test_deploy_task_recon_template.bats - recon report template includes dependency_constraints

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_recon"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "recon template test"
  task_type: recon
  acceptance_criteria:
    - ac1: investigate target
EOF

    # CMD_ID regex拡張(cmd_[a-zA-Z0-9_]+)によりcmd_testがCMD_IDとして検出される
    # → resolve_cmd_to_taskがSTK必須。STKにcmd_testエントリを追加
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_test:
    id: cmd_test
    title: 'recon template test'
    project: infra
    type: recon
    purpose: 'test purpose'
    status: delegated
EOF
}

teardown() {
    deploy_task_teardown
}

@test "recon report template includes dependency_constraints field" {
    cd "$TEST_PROJECT"
    bash scripts/deploy_task.sh sasuke cmd_test 2>/dev/null || true

    local report_file
    report_file=$(ls queue/reports/sasuke_report*.yaml 2>/dev/null | head -1)
    [ -n "$report_file" ]

    run grep -c "dependency_constraints" "$report_file"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "recon report template includes all 5 implementation_readiness fields" {
    cd "$TEST_PROJECT"
    bash scripts/deploy_task.sh sasuke cmd_test 2>/dev/null || true

    local report_file
    report_file=$(ls queue/reports/sasuke_report*.yaml 2>/dev/null | head -1)
    [ -n "$report_file" ]

    run grep -c "files_to_modify" "$report_file"
    [ "$status" -eq 0 ]
    run grep -c "affected_files" "$report_file"
    [ "$status" -eq 0 ]
    run grep -c "related_tests" "$report_file"
    [ "$status" -eq 0 ]
    run grep -c "edge_cases" "$report_file"
    [ "$status" -eq 0 ]
    run grep -c "dependency_constraints" "$report_file"
    [ "$status" -eq 0 ]
}
