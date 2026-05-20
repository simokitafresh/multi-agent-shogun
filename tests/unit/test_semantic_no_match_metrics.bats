#!/usr/bin/env bats

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

setup() {
    deploy_task_scaffold "semantic_no_match"
}

teardown() {
    deploy_task_teardown
}

@test "inject_semantic_concepts: NO_MATCH時にpurposeとtarget_pathをdeploy_task.logへ記録する" {
    mkdir -p "$TEST_PROJECT/docs/semantic-index"
    printf '# semantic index\n' > "$TEST_PROJECT/docs/semantic-index/index.md"
    cat > "$TEST_PROJECT/scripts/semantic_search.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/semantic_search.sh"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  purpose: aliases品質改善のため未登録概念を測る
  target_path: scripts/deploy_task.sh
EOF

    run bash -lc '
        export DEPLOY_TASK_LIB_ONLY=1
        source "'"$TEST_PROJECT/scripts/deploy_task.sh"'"
        inject_semantic_concepts "'"$TEST_PROJECT/queue/tasks/sasuke.yaml"'"
        cat "'"$TEST_PROJECT/logs/deploy_task.log"'"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"inject_semantic_concepts: NO_MATCH"* ]]
    [[ "$output" == *"purpose=aliases品質改善のため未登録概念を測る"* ]]
    [[ "$output" == *"target_path=scripts/deploy_task.sh"* ]]
}

@test "gate_karo_startup: deploy_task.logからNO_MATCH率とTOP3 miss purposeを表示する" {
    local log_file="$TEST_PROJECT/logs/deploy_task.log"
    cat > "$log_file" <<'EOF'
[2026-05-20 10:00:00] [DEPLOY] inject_semantic_concepts: NO_MATCH purpose=aliases品質 target_path=scripts/deploy_task.sh
[2026-05-20 10:01:00] [DEPLOY] inject_semantic_concepts: NO_MATCH purpose=aliases品質 target_path=scripts/deploy_task.sh
[2026-05-20 10:02:00] [DEPLOY] inject_semantic_concepts: NO_MATCH purpose=未知cmd target_path=context/foo.md
[2026-05-20 10:03:00] [DEPLOY] inject_semantic_concepts: 2 concepts injected
EOF

    run bash -lc '
        export GATE_KARO_STARTUP_LIB_ONLY=1
        export KARO_STARTUP_DEPLOY_LOG="'"$log_file"'"
        export KARO_STARTUP_NO_MATCH_SCAN_LINES=20
        source "'"$PROJECT_ROOT/scripts/gates/gate_karo_startup.sh"'"
        show_semantic_no_match_metrics
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"NO_MATCH率: 75.0% (3/4, scan_lines=20)"* ]]
    [[ "$output" == *"TOP3 miss purpose:"* ]]
    [[ "$output" == *"1. aliases品質 (2件)"* ]]
    [[ "$output" == *"未知cmd (1件)"* ]]
}
