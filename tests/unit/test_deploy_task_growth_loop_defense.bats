#!/usr/bin/env bats
# test_deploy_task_growth_loop_defense.bats
# cmd_2649: deploy_task.sh の inject_growth_loop_defense() ユニットテスト
# AC1: gate/hook関連cmdにgrowth-loop.md §11が注入される
# AC2: gate/hook非関連cmdには注入されない

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
    command -v python3 >/dev/null 2>&1 || return 1
    [ -f "$PROJECT_ROOT/context/growth-loop.md" ] || return 1
}

setup() {
    deploy_task_scaffold "growth_loop_defense"

    # growth-loop.md を TEST_PROJECT/context/ にコピー
    mkdir -p "$TEST_PROJECT/context"
    cp "$PROJECT_ROOT/context/growth-loop.md" "$TEST_PROJECT/context/growth-loop.md"

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

run_inject_growth_loop_defense() {
    local ninja_name="$1"
    local task_file="$TEST_PROJECT/queue/tasks/${ninja_name}.yaml"
    (
        export DEPLOY_TASK_LIB_ONLY=1
        export SCRIPT_DIR="$TEST_PROJECT"
        export LOG="/dev/null"
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        log() { :; }
        inject_growth_loop_defense "$task_file"
    ) 2>&1
}

read_growth_loop_defense() {
    awk '
        /^  growth_loop_defense:/ { in_field=1; next }
        in_field && /^  - "/ { sub(/^  - "/, ""); sub(/"$/, ""); print; next }
        in_field && /^  [a-zA-Z_]/ { exit }
        in_field && /^[^ ]/ { exit }
    ' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
}

# ═══════════════════════════════════════════════════════════
# AC1: gate/hook関連cmd → 注入される
# ═══════════════════════════════════════════════════════════

@test "gate関連purposeのcmdにgrowth_loop_defenseが注入される" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_gate
  purpose: "gate_report_format.shを改善してgateのBLOCK率を下げる"
  description: "test"
EOF

    run run_inject_growth_loop_defense sasuke
    [ "$status" -eq 0 ]

    run read_growth_loop_defense
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -gt 0 ]
    [[ "${output}" == *"ゲートの成功"* ]] || [[ "${output}" == *"Level"* ]]
}

@test "hook関連purposeのcmdにgrowth_loop_defenseが注入される" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_hook
  purpose: "pre-bashフックのBLOCK条件を見直す"
  description: "test"
EOF

    run run_inject_growth_loop_defense sasuke
    [ "$status" -eq 0 ]

    run read_growth_loop_defense
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -gt 0 ]
}

@test "BLOCK関連purposeのcmdにgrowth_loop_defenseが注入される" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_block
  purpose: "BLOCKされた場合に環境に埋め込む仕組みを設計する"
  description: "test"
EOF

    run run_inject_growth_loop_defense sasuke
    [ "$status" -eq 0 ]

    run read_growth_loop_defense
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -gt 0 ]
}

@test "growth-loop関連purposeのcmdにgrowth_loop_defenseが注入される" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_growth
  purpose: "growth-loop.mdの§11を参照してLevel5化を推進する"
  description: "test"
EOF

    run run_inject_growth_loop_defense sasuke
    [ "$status" -eq 0 ]

    run read_growth_loop_defense
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -gt 0 ]
}

@test "acceptance_criteriaにgateが含まれる場合に注入される" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_ac_gate
  purpose: "deploy_task.shを改善する"
  acceptance_criteria:
    - id: AC1
      description: "gate_report_format.shが正常に動作する"
EOF

    run run_inject_growth_loop_defense sasuke
    [ "$status" -eq 0 ]

    run read_growth_loop_defense
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -gt 0 ]
}

@test "注入内容に5段階のLevel情報が含まれる" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_levels
  purpose: "gateシステムのLevel5化を実装する"
  description: "test"
EOF

    run_inject_growth_loop_defense sasuke

    run read_growth_loop_defense
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -ge 5 ]  # Level1-5 + ゲートの成功 行
    [[ "${output}" == *"Level1"* ]]
    [[ "${output}" == *"Level5"* ]]
}

@test "注入内容にBLOCK対応のキーメッセージが含まれる" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_msg
  purpose: "gate BLOCKの仕組みを改善する"
  description: "test"
EOF

    run_inject_growth_loop_defense sasuke

    run read_growth_loop_defense
    [ "$status" -eq 0 ]
    # BLOCKされたら行またはLevel5目指せ行が含まれる
    [[ "${output}" == *"BLOCK"* ]] || [[ "${output}" == *"Level 5を目指せ"* ]]
}

# ═══════════════════════════════════════════════════════════
# AC2: gate/hook非関連cmd → 注入されない
# ═══════════════════════════════════════════════════════════

@test "gate/hook非関連cmdにはgrowth_loop_defenseが注入されない" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_unrelated
  purpose: "DM-Signalのシグナル計算ロジックを改善する"
  description: "test"
EOF

    run run_inject_growth_loop_defense sasuke
    [ "$status" -eq 0 ]

    run read_growth_loop_defense
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 0 ]
}

@test "DBクエリ関連cmdにはgrowth_loop_defenseが注入されない" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_db
  purpose: "monthly_returnsテーブルのパリティ検証を実行する"
  description: "test"
EOF

    run run_inject_growth_loop_defense sasuke
    [ "$status" -eq 0 ]

    run read_growth_loop_defense
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════
# 冪等性テスト
# ═══════════════════════════════════════════════════════════

@test "既存のgrowth_loop_defenseは上書きされる（冪等性）" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_idempotent
  purpose: "gateシステムのBLOCK率改善"
  growth_loop_defense:
    - "古い内容"
  description: "test"
EOF

    run_inject_growth_loop_defense sasuke

    run read_growth_loop_defense
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -gt 0 ]
    [[ "${output}" != *"古い内容"* ]]
}

@test "2回実行しても重複しない" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_double
  purpose: "gate_fire_logを最適化する"
  description: "test"
EOF

    run_inject_growth_loop_defense sasuke
    run_inject_growth_loop_defense sasuke

    # growth_loop_defenseの開始行が1回だけ現れる
    local count
    count=$(grep -c "^  growth_loop_defense:" "$TEST_PROJECT/queue/tasks/sasuke.yaml" || true)
    [ "$count" -eq 1 ]
}

@test "task YAMLが存在しない場合はエラーなく終了する" {
    rm -f "$TEST_PROJECT/queue/tasks/sasuke.yaml"

    run run_inject_growth_loop_defense sasuke
    [ "$status" -eq 0 ]
}
