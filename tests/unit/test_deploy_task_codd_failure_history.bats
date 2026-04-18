#!/usr/bin/env bats
# test_deploy_task_codd_failure_history.bats
# GP-201: inject_codd_failure_history() のテスト
# AC2: revert履歴のあるスクリプト(stop-lint-gate.sh)でcodd_failure_historyが注入されること
# AC3: revert履歴のないスクリプトでは注入なし(ノイズ防止)

load '../helpers/deploy_task_scaffold'

# ─── ヘルパー ───

setup_file() {
    deploy_task_setup_file
}

teardown_file() {
    # deploy_task_scaffold で定義
    :
}

setup() {
    deploy_task_scaffold "codd_failure_history"
    # docs/research ディレクトリを作成
    mkdir -p "$TEST_PROJECT/queue" \
             "$TEST_PROJECT/docs/research"
}

teardown() {
    deploy_task_teardown
}

# shogun_to_karo.yaml フィクスチャ: CoDD改善cmd (stop-lint-gate.sh, revert履歴あり)
write_stk_with_codd_cmd() {
    local root="$1"
    cat > "$root/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_9901:
    title: "stop-lint-gate.sh CoDD改善 — L3診断推論+Session State"
    project: infra
    scope_mode: IMPL
    status: delegated
    command: |
      stop-lint-gate.shの改善。CoDD #5のSession Stateを適用。
      過去の全改善試行の失敗履歴を注入し、同じ失敗を繰り返さない。
      正規CoDDフロー厳守: spec→Before→実装→After→revertチェック
    acceptance_criteria:
      - id: AC1
        description: "計測+改善実装"
      - id: AC2
        description: "テストPASS。commit"
EOF
}

# shogun_to_karo.yaml フィクスチャ: 非CoDD cmd
write_stk_without_codd_cmd() {
    local root="$1"
    cat > "$root/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_9902:
    title: "gate_report_format.sh バグ修正"
    project: infra
    scope_mode: IMPL
    status: delegated
    command: |
      gate_report_format.shのバグを修正する。
      YAML解析エラーを修正。
    acceptance_criteria:
      - id: AC1
        description: "修正+テストPASS"
EOF
}

# codd_refactor_registry.md: stop-lint-gate.shのrevertエントリあり
write_registry_with_revert() {
    local root="$1"
    cat > "$root/docs/research/codd_refactor_registry.md" <<'EOF'
# CoDD Refactor Registry

| 日付 | 実施者 | 対象スクリプト/領域 | Phase到達 | Before→After | spec/after設計書パス |
|------|--------|---------------------|-----------|--------------|----------------------|
| 2026-04-18 | saizo | `.claude/hooks/stop-lint-gate.sh` | Phase 5(spec+benchmark+trial revert) | `34.0ms → 35.7ms` (`+5.0%`, regression) → reverted | spec+after: `docs/research/cmd_2061_codd_hook_batch_a.md` |
| 2026-04-18 | hayate | `.claude/hooks/pre-bash-combined.sh` | Phase 5(計測+実装+検証) | `20.6ms → 18.0ms` (`-12.6%`, improvement) | spec+after: `docs/research/cmd_2062.md` |
| 2026-04-16 | hayate | `.claude/hooks/stop-lint-gate.sh` | Phase 5(計測+実装+検証) | `0.82s → 0.65s` (`-20.7%`, improvement) | spec+after: `docs/research/codd_spec_stop_lint_gate.md` |
EOF
}

# codd_refactor_registry.md: stop-lint-gate.sh のエントリが成功のみ (revertなし)
write_registry_success_only() {
    local root="$1"
    cat > "$root/docs/research/codd_refactor_registry.md" <<'EOF'
# CoDD Refactor Registry

| 日付 | 実施者 | 対象スクリプト/領域 | Phase到達 | Before→After | spec/after設計書パス |
|------|--------|---------------------|-----------|--------------|----------------------|
| 2026-04-18 | hayate | `.claude/hooks/pre-bash-combined.sh` | Phase 5(計測+実装+検証) | `20.6ms → 18.0ms` (`-12.6%`, improvement) | spec+after: `docs/research/cmd_2062.md` |
| 2026-04-16 | hayate | `.claude/hooks/stop-lint-gate.sh` | Phase 5(計測+実装+検証) | `0.82s → 0.65s` (`-20.7%`, improvement) | spec+after: `docs/research/codd_spec_stop_lint_gate.md` |
EOF
}

# タスクYAML フィクスチャ (CoDD cmd, parent_cmd指定)
write_task_yaml() {
    local root="$1"
    local parent_cmd="$2"
    cat > "$root/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: ${parent_cmd}
  task_id: ${parent_cmd}_impl
  task_type: impl
  project: infra
  status: assigned
EOF
}

# inject_codd_failure_history を単体で呼び出すヘルパー
run_inject_codd_failure_history() {
    local ninja_name="$1"
    local task_file="$TEST_PROJECT/queue/tasks/${ninja_name}.yaml"
    (
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        SCRIPT_DIR="$TEST_PROJECT"
        inject_codd_failure_history "$task_file"
    )
}

# ─── AC2テスト: revert履歴のあるスクリプトで注入される ───

@test "AC2-1: stop-lint-gate.shのrevert履歴があればcodd_failure_historyが注入される" {
    write_stk_with_codd_cmd "$TEST_PROJECT"
    write_registry_with_revert "$TEST_PROJECT"
    write_task_yaml "$TEST_PROJECT" "cmd_9901"

    run run_inject_codd_failure_history "sasuke"
    [ "$status" -eq 0 ]

    # codd_failure_historyがタスクYAMLに含まれること
    task_content=$(cat "$TEST_PROJECT/queue/tasks/sasuke.yaml")
    [[ "$task_content" == *"codd_failure_history:"* ]]
}

@test "AC2-2: 注入されたcodd_failure_historyにcount>0が含まれる" {
    write_stk_with_codd_cmd "$TEST_PROJECT"
    write_registry_with_revert "$TEST_PROJECT"
    write_task_yaml "$TEST_PROJECT" "cmd_9901"

    run_inject_codd_failure_history "sasuke" >/dev/null 2>&1

    task_content=$(cat "$TEST_PROJECT/queue/tasks/sasuke.yaml")
    # count: 1以上の数値が含まれること
    [[ "$task_content" == *"count:"* ]]
    count_val=$(echo "$task_content" | grep "count:" | head -1 | sed 's/.*count: *//')
    [ "$count_val" -ge 1 ]
}

@test "AC2-3: 注入されたcodd_failure_historyにattemptsブロックがある" {
    write_stk_with_codd_cmd "$TEST_PROJECT"
    write_registry_with_revert "$TEST_PROJECT"
    write_task_yaml "$TEST_PROJECT" "cmd_9901"

    run_inject_codd_failure_history "sasuke" >/dev/null 2>&1

    task_content=$(cat "$TEST_PROJECT/queue/tasks/sasuke.yaml")
    [[ "$task_content" == *"attempts:"* ]]
    [[ "$task_content" == *"stop-lint-gate.sh"* ]]
}

@test "AC2-4: 注入されたcodd_failure_historyにnoteが含まれる" {
    write_stk_with_codd_cmd "$TEST_PROJECT"
    write_registry_with_revert "$TEST_PROJECT"
    write_task_yaml "$TEST_PROJECT" "cmd_9901"

    run_inject_codd_failure_history "sasuke" >/dev/null 2>&1

    task_content=$(cat "$TEST_PROJECT/queue/tasks/sasuke.yaml")
    [[ "$task_content" == *"note:"* ]]
}

# ─── AC3テスト: revert履歴のないスクリプトでは注入なし ───

@test "AC3-1: 非CoDDコマンドではcodd_failure_historyを注入しない" {
    write_stk_without_codd_cmd "$TEST_PROJECT"
    write_registry_with_revert "$TEST_PROJECT"
    write_task_yaml "$TEST_PROJECT" "cmd_9902"

    run_inject_codd_failure_history "sasuke" >/dev/null 2>&1

    task_content=$(cat "$TEST_PROJECT/queue/tasks/sasuke.yaml")
    # codd_failure_historyが含まれないこと
    [[ "$task_content" != *"codd_failure_history:"* ]]
}

@test "AC3-2: CoDD cmdでもrevert履歴なしスクリプトなら注入しない" {
    write_stk_with_codd_cmd "$TEST_PROJECT"
    write_registry_success_only "$TEST_PROJECT"
    write_task_yaml "$TEST_PROJECT" "cmd_9901"

    run_inject_codd_failure_history "sasuke" >/dev/null 2>&1

    task_content=$(cat "$TEST_PROJECT/queue/tasks/sasuke.yaml")
    # stop-lint-gate.shはregistryにあるが全て成功エントリのみ
    [[ "$task_content" != *"codd_failure_history:"* ]]
}

@test "AC3-3: registryファイルがなければ注入しない(エラー終了しない)" {
    write_stk_with_codd_cmd "$TEST_PROJECT"
    # registryを作成しない
    write_task_yaml "$TEST_PROJECT" "cmd_9901"

    run run_inject_codd_failure_history "sasuke"
    # エラーで終了しないこと(exit 0 or benign)
    [ "$status" -eq 0 ]

    task_content=$(cat "$TEST_PROJECT/queue/tasks/sasuke.yaml")
    [[ "$task_content" != *"codd_failure_history:"* ]]
}

@test "AC3-4: shogun_to_karo.yamlにcmd_idがなければ注入しない" {
    write_stk_with_codd_cmd "$TEST_PROJECT"
    write_registry_with_revert "$TEST_PROJECT"
    # 存在しないcmd_idを指定
    write_task_yaml "$TEST_PROJECT" "cmd_9999"

    run run_inject_codd_failure_history "sasuke" >/dev/null 2>&1

    task_content=$(cat "$TEST_PROJECT/queue/tasks/sasuke.yaml")
    [[ "$task_content" != *"codd_failure_history:"* ]]
}
