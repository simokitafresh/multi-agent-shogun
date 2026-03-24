#!/usr/bin/env bats
# test_cmd_save.bats — cmd_save.sh ユニットテスト（Check 6: GP重複チェック中心）

setup() {
    TEST_TMP="$(mktemp -d)"
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    mkdir -p "${TEST_TMP}/queue/archive/cmds"
    mkdir -p "${TEST_TMP}/scripts"

    # cmd_save.sh をコピーし、パスをテスト用に差し替え
    sed \
        -e "s|SCRIPT_DIR=\"\$(cd \"\$(dirname \"\$0\")\" && pwd)\"|SCRIPT_DIR=\"${TEST_TMP}/scripts\"|" \
        -e "s|PROJECT_DIR=\"\$(dirname \"\$SCRIPT_DIR\")\"|PROJECT_DIR=\"${TEST_TMP}\"|" \
        "$PROJECT_ROOT/scripts/cmd_save.sh" > "${TEST_TMP}/scripts/cmd_save.sh"
    chmod +x "${TEST_TMP}/scripts/cmd_save.sh"

    # git stub（Check 5用）
    mkdir -p "${TEST_TMP}/bin"
    cat > "${TEST_TMP}/bin/git" << 'GIT_STUB'
#!/bin/bash
echo ""
GIT_STUB
    chmod +x "${TEST_TMP}/bin/git"
    export PATH="${TEST_TMP}/bin:$PATH"

    # 品質ログ不要
    mkdir -p "${TEST_TMP}/logs"
    touch "${TEST_TMP}/logs/cmd_design_quality.yaml"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# --- ヘルパー: 最小限のshogun_to_karo.yaml生成 ---
create_queue_file() {
    cat > "${TEST_TMP}/queue/shogun_to_karo.yaml"
}

# --- Check 6: GP重複検出 ---

@test "Check6: GP番号一致でWARN出力" {
    create_queue_file << 'YAML'
commands:
  cmd_1001:
    id: cmd_1001
    command: "GP-031対応の修正"
    status: delegated
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
  cmd_1002:
    id: cmd_1002
    command: "GP-031+GP-033統合修正"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
YAML

    run bash "${TEST_TMP}/scripts/cmd_save.sh" cmd_1002
    echo "$output" >&2
    # GP-031がcmd_1001(delegated)と重複 → WARN
    [[ "$output" == *"GP-031"* ]]
    [[ "$output" == *"cmd_1001"* ]]
}

@test "Check6: GP番号なしcmdはスキップ" {
    create_queue_file << 'YAML'
commands:
  cmd_1001:
    id: cmd_1001
    command: "GP-031対応の修正"
    status: delegated
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
  cmd_1010:
    id: cmd_1010
    command: "inbox_write.shのリファクタリング"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
YAML

    run bash "${TEST_TMP}/scripts/cmd_save.sh" cmd_1010
    echo "$output" >&2
    # GP番号なし → Check 6スキップ → WARNなし → 保存確認OK
    [[ "$output" == *"保存確認OK"* ]]
    # GP関連のWARNが出ていないこと
    [[ "$output" != *"GP-"* ]]
}

@test "Check6: status=completedのcmdは無視" {
    create_queue_file << 'YAML'
commands:
  cmd_1001:
    id: cmd_1001
    command: "GP-031対応の修正"
    status: completed
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
  cmd_1002:
    id: cmd_1002
    command: "GP-031の追加修正"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
YAML

    run bash "${TEST_TMP}/scripts/cmd_save.sh" cmd_1002
    echo "$output" >&2
    # cmd_1001はcompleted → GP重複WARNなし
    [[ "$output" == *"保存確認OK"* ]]
    [[ "$output" != *"GP-031"*"cmd_1001"* ]]
}

@test "Check6: status=in_progressのcmdで検出" {
    create_queue_file << 'YAML'
commands:
  cmd_1001:
    id: cmd_1001
    command: "GP-042対応"
    status: in_progress
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
  cmd_1002:
    id: cmd_1002
    command: "GP-042の再実装"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
YAML

    run bash "${TEST_TMP}/scripts/cmd_save.sh" cmd_1002
    echo "$output" >&2
    [[ "$output" == *"GP-042"* ]]
    [[ "$output" == *"cmd_1001"* ]]
    [[ "$output" == *"in_progress"* ]]
}

@test "Check6: 複数GP番号で部分一致検出" {
    create_queue_file << 'YAML'
commands:
  cmd_1001:
    id: cmd_1001
    command: "GP-031修正"
    status: delegated
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
  cmd_1002:
    id: cmd_1002
    command: "GP-031+GP-033+GP-034統合"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
YAML

    run bash "${TEST_TMP}/scripts/cmd_save.sh" cmd_1002
    echo "$output" >&2
    # GP-031のみ重複、GP-033/034は重複なし
    [[ "$output" == *"GP-031"* ]]
    [[ "$output" != *"GP-033"*"cmd_1001"* ]]
}

@test "Check6: 非BLOCKのため保存確認OKで終了" {
    create_queue_file << 'YAML'
commands:
  cmd_1001:
    id: cmd_1001
    command: "GP-031対応"
    status: delegated
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
  cmd_1002:
    id: cmd_1002
    command: "GP-031の再実装"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
YAML

    run bash "${TEST_TMP}/scripts/cmd_save.sh" cmd_1002
    echo "$output" >&2
    # GP重複WARNは出るが、非BLOCKなので保存確認OKで終了
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"保存確認OK"* ]]
}

@test "Check1-5: 既存チェックに影響なし（正常系）" {
    create_queue_file << 'YAML'
commands:
  cmd_9999:
    id: cmd_9999
    command: "テスト用cmdブロック"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
YAML

    run bash "${TEST_TMP}/scripts/cmd_save.sh" cmd_9999
    echo "$output" >&2
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"保存確認OK: cmd_9999"* ]]
}

@test "Check1-5: quality_gate未記入でBLOCK" {
    create_queue_file << 'YAML'
commands:
  cmd_8888:
    id: cmd_8888
    command: "quality_gate無しcmd"
    status: pending
YAML

    run bash "${TEST_TMP}/scripts/cmd_save.sh" cmd_8888
    echo "$output" >&2
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"BLOCK"* ]]
}
