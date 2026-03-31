#!/usr/bin/env bats
# test_cmd_save_archive_dup.bats — Check 12拡張: archive内容重複チェック ユニットテスト
#
# テスト構成:
#   T-A01: archive側に類似cmd存在時にWARNINGが出力される
#   T-A02: archive側に類似cmdなし時にWARNINGが出力されない
#   T-A03: archiveが空/不在でもエラーにならない

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    [ -f "$PROJECT_ROOT/scripts/cmd_save.sh" ] || return 1

    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_save_archive_dup.XXXXXX")"

    # テスト用ラッパースクリプト: check_content_duplicate関数のみ抽出+実行
    cat > "$TEST_TMPDIR/test_func.sh" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
QUEUE_FILE="$1"
CMD_ID="$2"
CMD_BLOCK="$3"
ARCHIVE_CMD_DIR="${4:-}"
WRAPPER

    # cmd_save.shからcheck_content_duplicate関数定義を抽出
    sed -n '/^check_content_duplicate()/,/^}$/p' "$PROJECT_ROOT/scripts/cmd_save.sh" >> "$TEST_TMPDIR/test_func.sh"
    echo 'check_content_duplicate' >> "$TEST_TMPDIR/test_func.sh"

    chmod +x "$TEST_TMPDIR/test_func.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ヘルパー: テスト用shogun_to_karo.yaml生成（新cmdのみ、既存cmdなし）
create_queue_yaml() {
    local file="$1"
    cat > "$file" <<'YAML'
commands:
  cmd_2001:
    title: 'inbox_write.sh品質ゲート強化'
    purpose: 'inbox_writeの報告フォーマットチェックを追加して未完了報告の送信を防止する'
    status: new
YAML
}

# ヘルパー: テスト用archiveファイル生成
create_archive_similar() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/cmd_1500_done_20260330.yaml" <<'YAML'
commands:
  cmd_1500:
    title: 'inbox_write.sh品質ゲート強化'
    purpose: 'inbox_writeの報告フォーマットチェックを追加して未完了報告の送信を防止する'
    status: done
YAML
}

create_archive_different() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/cmd_1400_done_20260329.yaml" <<'YAML'
commands:
  cmd_1400:
    title: 'fullrecalculate高速化'
    purpose: 'fullrecalculateのバッチサイズ最適化で処理時間を50%削減'
    status: done
YAML
}

# T-A01: archive側に類似cmd存在時にWARNINGが出力される
@test "T-A01: similar cmd in archive produces WARNING with (archive) marker" {
    local YAML_FILE="$TEST_TMPDIR/queue.yaml"
    create_queue_yaml "$YAML_FILE"

    local ARCHIVE_DIR="$TEST_TMPDIR/archive_cmds"
    create_archive_similar "$ARCHIVE_DIR"

    local CMD_BLOCK="    title: 'inbox_write.sh品質ゲート強化'
    purpose: 'inbox_writeの報告フォーマットチェックを追加して未完了報告の送信を防止する'"

    run bash "$TEST_TMPDIR/test_func.sh" "$YAML_FILE" "cmd_2001" "$CMD_BLOCK" "$ARCHIVE_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"(archive)"* ]]
    [[ "$output" == *"cmd_1500"* ]]
    [[ "$output" == *"類似度"* ]]
}

# T-A02: archive側に類似cmdなし時にWARNINGが出力されない
@test "T-A02: different cmd in archive produces no archive WARNING" {
    local YAML_FILE="$TEST_TMPDIR/queue.yaml"
    create_queue_yaml "$YAML_FILE"

    local ARCHIVE_DIR="$TEST_TMPDIR/archive_cmds"
    create_archive_different "$ARCHIVE_DIR"

    local CMD_BLOCK="    title: 'inbox_write.sh品質ゲート強化'
    purpose: 'inbox_writeの報告フォーマットチェックを追加して未完了報告の送信を防止する'"

    run bash "$TEST_TMPDIR/test_func.sh" "$YAML_FILE" "cmd_2001" "$CMD_BLOCK" "$ARCHIVE_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *"(archive)"* ]]
}

# T-A03: archiveが空/不在でもエラーにならない
@test "T-A03: missing archive dir produces no error" {
    local YAML_FILE="$TEST_TMPDIR/queue.yaml"
    create_queue_yaml "$YAML_FILE"

    local CMD_BLOCK="    title: 'inbox_write.sh品質ゲート強化'
    purpose: 'inbox_writeの報告フォーマットチェックを追加して未完了報告の送信を防止する'"

    # ARCHIVE_CMD_DIR未設定(空文字)
    run bash "$TEST_TMPDIR/test_func.sh" "$YAML_FILE" "cmd_2001" "$CMD_BLOCK" ""
    [ "$status" -eq 0 ]
    [[ "$output" != *"(archive)"* ]]

    # ARCHIVE_CMD_DIRが存在しないパス
    run bash "$TEST_TMPDIR/test_func.sh" "$YAML_FILE" "cmd_2001" "$CMD_BLOCK" "$TEST_TMPDIR/nonexistent_dir"
    [ "$status" -eq 0 ]
    [[ "$output" != *"(archive)"* ]]

    # ARCHIVE_CMD_DIRが空ディレクトリ
    mkdir -p "$TEST_TMPDIR/empty_archive"
    run bash "$TEST_TMPDIR/test_func.sh" "$YAML_FILE" "cmd_2001" "$CMD_BLOCK" "$TEST_TMPDIR/empty_archive"
    [ "$status" -eq 0 ]
    [[ "$output" != *"(archive)"* ]]
}
