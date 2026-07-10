#!/usr/bin/env bats
# test_deploy_task_push_allowed.bats
# cmd_karo_hotfix_startup_alerts_202607101046 AC2: deploy_task.sh の inject_push_allowed() ユニットテスト
# 再現対象: cmd_3820 — ACに'push'要求があるcmdでtask YAMLにpush_allowed:trueが付与されず
# 忍者のgit pushがG2ガード(.claude/hooks/pre-bash-combined.sh)でBLOCKされ、家老が手動でWA処理した
# (logs/karo_workarounds.yaml cmd_3820, category=push_deploy_permission_gap)。

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "push_allowed"

    source "$TEST_PROJECT/scripts/lib/field_get.sh"
    export FIELD_GET_NO_LOG=1
    export SCRIPT_DIR="$TEST_PROJECT"
    export LOG="/dev/null"
    log() { :; }
    export -f log
}

teardown() {
    deploy_task_teardown
}

# ─── ヘルパー ───

run_inject_push_allowed() {
    local ninja_name="$1"
    local task_file="$TEST_PROJECT/queue/tasks/${ninja_name}.yaml"
    (
        export DEPLOY_TASK_LIB_ONLY=1
        export SCRIPT_DIR="$TEST_PROJECT"
        export LOG="/dev/null"
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        log() { :; }
        inject_push_allowed "$task_file"
    ) 2>&1
}

read_push_allowed() {
    grep -m1 '^[[:space:]]*push_allowed:' "$TEST_PROJECT/queue/tasks/sasuke.yaml" || true
}

# ═══════════════════════════════════════════════════════════
# 再現: cmd_3820相当のAC(push+deploy要求)で欠落状態を確認
# ═══════════════════════════════════════════════════════════

@test "REPRO: cmd_3820相当のAC2(push+CI+自走deploy)がある場合、注入前はpush_allowedが存在しない" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_3820_repro
  acceptance_criteria:
    AC1:
      description: "WARN件数のrun単位集計を実装する"
    AC2:
      description: "push+CI conclusion=successをghで数値確認し、自走deployしてヘルスチェックを記録する"
EOF

    run read_push_allowed
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ═══════════════════════════════════════════════════════════
# AC1: ACにpushが含まれる → push_allowed:trueが付与される
# ═══════════════════════════════════════════════════════════

@test "ACに'push'が含まれる場合push_allowed:trueが付与される(cmd_3820修正後)" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_3820_fixed
  acceptance_criteria:
    AC1:
      description: "WARN件数のrun単位集計を実装する"
    AC2:
      description: "push+CI conclusion=successをghで数値確認し、自走deployしてヘルスチェックを記録する"
EOF

    run run_inject_push_allowed sasuke
    [ "$status" -eq 0 ]

    run read_push_allowed
    [ "$status" -eq 0 ]
    [[ "$output" == *"push_allowed:"*"true"* ]]
}

@test "ACの'push'が大文字小文字混在でも検出される" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_case
  acceptance_criteria:
    AC1:
      description: "PUSH+CI success確認後にRenderへ自走Deployする"
EOF

    run run_inject_push_allowed sasuke
    [ "$status" -eq 0 ]

    run read_push_allowed
    [ "$status" -eq 0 ]
    [[ "$output" == *"true"* ]]
}

@test "descriptionリスト形式のACでも'push'が検出される" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_list_ac
  acceptance_criteria:
    - id: AC1
      description: "commit後 pushしてCIを確認する"
EOF

    run run_inject_push_allowed sasuke
    [ "$status" -eq 0 ]

    run read_push_allowed
    [ "$status" -eq 0 ]
    [[ "$output" == *"true"* ]]
}

# ═══════════════════════════════════════════════════════════
# AC2: ACにpushが含まれない → push_allowedは付与されない
# ═══════════════════════════════════════════════════════════

@test "ACに'push'が含まれない場合push_allowedは付与されない" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_no_push
  acceptance_criteria:
    AC1:
      description: "monthly_trade_implのWARN集計機構を実装しユニットテストをPASSさせてcommitする"
EOF

    run run_inject_push_allowed sasuke
    [ "$status" -eq 0 ]

    run read_push_allowed
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "'pushpin'等の部分一致では誤検出しない(単語境界)" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_word_boundary
  acceptance_criteria:
    AC1:
      description: "pushpinアイコンのUI配置を修正する"
EOF

    run run_inject_push_allowed sasuke
    [ "$status" -eq 0 ]

    run read_push_allowed
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "acceptance_criteria外(command欄等)の'push'では誤検出しない" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_outside_ac
  acceptance_criteria:
    AC1:
      description: "commitして完了する"
  command: |
    1. commitする。pushはしない
EOF

    run run_inject_push_allowed sasuke
    [ "$status" -eq 0 ]

    run read_push_allowed
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ═══════════════════════════════════════════════════════════
# 既存値の尊重 / 冪等性
# ═══════════════════════════════════════════════════════════

@test "既にpush_allowed:falseが手動設定済みの場合は上書きしない" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_manual_false
  push_allowed: false
  acceptance_criteria:
    AC1:
      description: "push+deployする"
EOF

    run run_inject_push_allowed sasuke
    [ "$status" -eq 0 ]

    run read_push_allowed
    [ "$status" -eq 0 ]
    [[ "$output" == *"false"* ]]
}

@test "2回実行しても重複しない" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_double
  acceptance_criteria:
    AC1:
      description: "push+deployする"
EOF

    run_inject_push_allowed sasuke
    run_inject_push_allowed sasuke

    local count
    count=$(grep -c '^[[:space:]]*push_allowed:' "$TEST_PROJECT/queue/tasks/sasuke.yaml" || true)
    [ "$count" -eq 1 ]
}

@test "task YAMLが存在しない場合はエラーなく終了する" {
    rm -f "$TEST_PROJECT/queue/tasks/sasuke.yaml"

    run run_inject_push_allowed sasuke
    [ "$status" -eq 0 ]
}
