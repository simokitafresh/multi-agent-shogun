#!/usr/bin/env bats
# test_cmd_save_content_dup.bats — Check 12: 内容重複チェック ユニットテスト
#
# テスト構成:
#   T-001: 類似度50%以上 → WARNING出力(cmdID+title+類似度%)
#   T-002: 類似度50%未満 → WARNING出ない
#   T-003: 完全一致(100%) → WARNING出力
#   T-004: CMD_BLOCK空 → 何もしない（空振り耐性）
#   T-005: QUEUE_FILE不在 → 何もしない（空振り耐性）

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    [ -f "$PROJECT_ROOT/scripts/cmd_save.sh" ] || return 1

    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_save_dup_test.XXXXXX")"

    # テスト用ラッパースクリプト: check_content_duplicate関数のみ抽出+実行
    cat > "$TEST_TMPDIR/test_func.sh" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
QUEUE_FILE="$1"
CMD_ID="$2"
CMD_BLOCK="$3"
WRAPPER

    # cmd_save.shからcheck_content_duplicate関数定義を抽出
    sed -n '/^check_content_duplicate()/,/^}$/p' "$PROJECT_ROOT/scripts/cmd_save.sh" >> "$TEST_TMPDIR/test_func.sh"
    echo 'check_content_duplicate' >> "$TEST_TMPDIR/test_func.sh"

    chmod +x "$TEST_TMPDIR/test_func.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ヘルパー: テスト用shogun_to_karo.yaml生成
create_test_yaml() {
    local file="$1"
    cat > "$file" <<'YAML'
commands:
  cmd_1001:
    title: 'cmd_save.sh内容重複チェック実装'
    purpose: 'cmd_save.shに内容重複チェック追加。shogun_to_karo.yamlの直近cmdとの類似度を簡易比較しWARN検出。重複cmd起票の構造的防止'
    status: delegated
  cmd_1002:
    title: 'archive_completed.sh修練cmd対応'
    purpose: '修練サイクルの報告がqueue/reports/に永久蓄積。archive_completed.shに修練cmd判定ロジック追加し再発防止'
    status: delegated
  cmd_1003:
    title: 'fullrecalculate baseline自動保存'
    purpose: 'fullrecalculate実行前にbaseline自動保存し差分比較を出力。変更の正当性を数値的に証明'
    status: delegated
YAML
}

# T-001: 類似度50%以上 → WARNING出力(cmdID+title+類似度%)
@test "T-001: similar cmd (>=50%) produces WARNING with cmdID and similarity" {
    local YAML_FILE="$TEST_TMPDIR/queue.yaml"
    create_test_yaml "$YAML_FILE"

    # cmd_1001とほぼ同じ内容の新cmd追加
    cat >> "$YAML_FILE" <<'YAML'
  cmd_1010:
    title: 'cmd_save.sh内容重複チェック追加'
    purpose: 'cmd_save.shに内容重複チェック追加。shogun_to_karo.yamlの直近cmdとの類似度を比較しWARN検出。重複cmd起票の防止'
    status: new
YAML

    local CMD_BLOCK="    title: 'cmd_save.sh内容重複チェック追加'
    purpose: 'cmd_save.shに内容重複チェック追加。shogun_to_karo.yamlの直近cmdとの類似度を比較しWARN検出。重複cmd起票の防止'"

    run bash "$TEST_TMPDIR/test_func.sh" "$YAML_FILE" "cmd_1010" "$CMD_BLOCK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"内容重複"* ]]
    [[ "$output" == *"cmd_1001"* ]]
    [[ "$output" == *"類似度"* ]]
}

# T-002: 類似度50%未満 → WARNING出ない
@test "T-002: different cmd (<50%) produces no WARNING" {
    local YAML_FILE="$TEST_TMPDIR/queue.yaml"
    create_test_yaml "$YAML_FILE"

    cat >> "$YAML_FILE" <<'YAML'
  cmd_1010:
    title: 'ninja_monitor.sh CTX閾値調整'
    purpose: 'ninja_monitorのコンテキスト閾値を80%から85%に変更。CTX溢れの早期検知'
    status: new
YAML

    local CMD_BLOCK="    title: 'ninja_monitor.sh CTX閾値調整'
    purpose: 'ninja_monitorのコンテキスト閾値を80%から85%に変更。CTX溢れの早期検知'"

    run bash "$TEST_TMPDIR/test_func.sh" "$YAML_FILE" "cmd_1010" "$CMD_BLOCK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING"* ]]
}

# T-003: 完全一致(100%) → WARNING出力
@test "T-003: identical title+purpose produces WARNING with high similarity" {
    local YAML_FILE="$TEST_TMPDIR/queue.yaml"
    create_test_yaml "$YAML_FILE"

    cat >> "$YAML_FILE" <<'YAML'
  cmd_1010:
    title: 'cmd_save.sh内容重複チェック実装'
    purpose: 'cmd_save.shに内容重複チェック追加。shogun_to_karo.yamlの直近cmdとの類似度を簡易比較しWARN検出。重複cmd起票の構造的防止'
    status: new
YAML

    local CMD_BLOCK="    title: 'cmd_save.sh内容重複チェック実装'
    purpose: 'cmd_save.shに内容重複チェック追加。shogun_to_karo.yamlの直近cmdとの類似度を簡易比較しWARN検出。重複cmd起票の構造的防止'"

    run bash "$TEST_TMPDIR/test_func.sh" "$YAML_FILE" "cmd_1010" "$CMD_BLOCK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"cmd_1001"* ]]
    [[ "$output" == *"100%"* ]]
}

# T-004: CMD_BLOCK空 → 何もしない（空振り耐性）
@test "T-004: empty CMD_BLOCK produces no output" {
    local YAML_FILE="$TEST_TMPDIR/queue.yaml"
    create_test_yaml "$YAML_FILE"

    run bash "$TEST_TMPDIR/test_func.sh" "$YAML_FILE" "cmd_1010" ""
    [ "$status" -eq 0 ]
    [[ "$output" == "" ]]
}

# T-005: QUEUE_FILE不在 → 何もしない（空振り耐性）
@test "T-005: non-existing QUEUE_FILE produces no output" {
    run bash "$TEST_TMPDIR/test_func.sh" "$TEST_TMPDIR/nonexistent.yaml" "cmd_1010" "some block"
    [ "$status" -eq 0 ]
    [[ "$output" == "" ]]
}
