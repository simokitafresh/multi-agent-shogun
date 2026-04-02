#!/usr/bin/env bats
# test_deploy_task_recon_template.bats - recon report template includes dependency_constraints

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
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

    deploy_task_template_only sasuke cmd_test

    export REPORT_FILE
    REPORT_FILE=$(find "$TEST_PROJECT/queue/reports" -maxdepth 1 -name 'sasuke_report*.yaml' | head -1)
    [ -n "$REPORT_FILE" ]
}

teardown() {
    deploy_task_teardown
}

@test "recon report template includes dependency_constraints field" {
    run grep -Fq "dependency_constraints" "$REPORT_FILE"
    [ "$status" -eq 0 ]
}

@test "recon report template includes all 5 implementation_readiness fields" {
    run grep -Fq "files_to_modify" "$REPORT_FILE"
    [ "$status" -eq 0 ]
    run grep -Fq "affected_files" "$REPORT_FILE"
    [ "$status" -eq 0 ]
    run grep -Fq "related_tests" "$REPORT_FILE"
    [ "$status" -eq 0 ]
    run grep -Fq "edge_cases" "$REPORT_FILE"
    [ "$status" -eq 0 ]
    run grep -Fq "dependency_constraints" "$REPORT_FILE"
    [ "$status" -eq 0 ]
}
