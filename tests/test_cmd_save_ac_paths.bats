#!/usr/bin/env bats
# test_cmd_save_ac_paths.bats — Check 10: AC内ファイルパス存在チェック ユニットテスト
#
# テスト構成:
#   T-001: 存在するパス → WARNING出ない
#   T-002: 存在しないパス → WARNING出る
#   T-003: パスなし → 何もしない（空振り耐性）
#   T-004: WARN_COUNTに加算しない（check_ac_file_pathsはWARN_COUNTを変更しない）
#   T-005: 複数パス（存在+不在混在）
#
# 注: check_ac_file_paths関数を単体テスト。cmd_save.shフルパイプラインは
#     check_pi_number_collisionの既存pipefailバグで途中exitするため
#     関数抽出テストで検証する（既存バグはlesson_candidate報告済み）

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    [ -f "$PROJECT_ROOT/scripts/cmd_save.sh" ] || return 1

    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_save_test.XXXXXX")"

    # テスト用の外部プロジェクトディレクトリ
    export FAKE_PROJECT_DIR="$TEST_TMPDIR/fake_project"
    mkdir -p "$FAKE_PROJECT_DIR/backend/app/services"
    mkdir -p "$FAKE_PROJECT_DIR/frontend/app/components"
    touch "$FAKE_PROJECT_DIR/backend/app/services/engine.py"
    touch "$FAKE_PROJECT_DIR/frontend/app/components/Chart.tsx"

    # config/projects.yaml
    mkdir -p "$TEST_TMPDIR/config"
    cat > "$TEST_TMPDIR/config/projects.yaml" <<YAML
projects:
  - id: test-proj
    name: "Test Project"
    path: "$FAKE_PROJECT_DIR"
    status: active
current_project: test-proj
YAML

    # テスト用ラッパースクリプト: check_ac_file_paths関数のみ抽出+実行
    cat > "$TEST_TMPDIR/test_func.sh" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="__PROJECT_DIR__"
CMD_BLOCK="$1"
WRAPPER

    # cmd_save.shからcheck_ac_file_paths関数定義を抽出
    sed -n '/^check_ac_file_paths()/,/^}$/p' "$PROJECT_ROOT/scripts/cmd_save.sh" >> "$TEST_TMPDIR/test_func.sh"
    echo 'check_ac_file_paths' >> "$TEST_TMPDIR/test_func.sh"

    # PROJECT_DIRをテスト用に置換
    sed -i "s|__PROJECT_DIR__|$TEST_TMPDIR|g" "$TEST_TMPDIR/test_func.sh"
    chmod +x "$TEST_TMPDIR/test_func.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# T-001: 存在するパス → WARNING出ない
@test "T-001: existing paths produce no WARNING" {
    local CMD_BLOCK="    acceptance_criteria:
      - 'AC1: backend/app/services/engine.py を修正'
    project: test-proj"
    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"AC内のファイルパスが存在しません"* ]]
}

# T-002: 存在しないパス → WARNING出る
@test "T-002: non-existing paths produce WARNING" {
    local CMD_BLOCK="    acceptance_criteria:
      - 'AC1: backend/generators/monthly_returns.py を修正'
    project: test-proj"
    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AC内のファイルパスが存在しません"* ]]
    [[ "$output" == *"backend/generators/monthly_returns.py"* ]]
}

# T-003: パスなし → 何もしない（空振り耐性）
@test "T-003: no paths in AC produces no WARNING" {
    local CMD_BLOCK="    acceptance_criteria:
      - 'AC1: データベースのマイグレーションを実行'
    project: test-proj"
    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"AC内のファイルパスが存在しません"* ]]
}

# T-004: WARN_COUNTに加算しない（関数はWARN_COUNTを変更せずreturn 0）
@test "T-004: function returns 0 even with missing paths (no WARN_COUNT impact)" {
    local CMD_BLOCK="    acceptance_criteria:
      - 'AC1: backend/nonexistent/file.py を修正'
    project: test-proj"
    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    # 関数はWARNINGを出力するがexit 0で返る（WARN_COUNTに加算しない）
    [ "$status" -eq 0 ]
    [[ "$output" == *"AC内のファイルパスが存在しません"* ]]
}

# T-005: 複数パス（存在+不在混在）
@test "T-005: mixed existing and non-existing paths" {
    local CMD_BLOCK="    acceptance_criteria:
      - 'AC1: backend/app/services/engine.py 修正'
      - 'AC2: frontend/app/nonexistent.tsx 新規作成'
    project: test-proj"
    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    [ "$status" -eq 0 ]
    # 存在しないパスだけWARNING
    [[ "$output" == *"frontend/app/nonexistent.tsx"* ]]
    # 存在するパスはWARNING行に出ない
    [[ "$output" != *"✗ backend/app/services/engine.py"* ]]
}
