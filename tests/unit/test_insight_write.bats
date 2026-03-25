#!/usr/bin/env bats
# test_insight_write.bats — scripts/insight_write.sh ユニットテスト

setup() {
    TEST_TMP="$(mktemp -d)"
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    mkdir -p "${TEST_TMP}/scripts"
    mkdir -p "${TEST_TMP}/queue"

    # insight_write.sh をコピーし、SCRIPT_DIRをテスト用に差し替え
    sed \
        -e "s|SCRIPT_DIR=\"\$(cd \"\$(dirname \"\${BASH_SOURCE\[0\]}\")\/\.\.\" && pwd)\"|SCRIPT_DIR=\"${TEST_TMP}\"|" \
        "$PROJECT_ROOT/scripts/insight_write.sh" > "${TEST_TMP}/scripts/insight_write.sh"
    chmod +x "${TEST_TMP}/scripts/insight_write.sh"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# --- 1. 正常なinsight追加 ---

@test "正常: insightが追加されフィールドが正しい" {
    run bash "${TEST_TMP}/scripts/insight_write.sh" "テスト気づき" "high" "unit_test"
    [ "$status" -eq 0 ]

    # IDが出力される
    [[ "$output" =~ ^INS- ]]

    # YAMLファイルにエントリが存在
    run python3 -c "
import yaml
with open('${TEST_TMP}/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
entry = data['insights'][0]
assert entry['insight'] == 'テスト気づき', f'insight mismatch: {entry[\"insight\"]}'
assert entry['priority'] == 'high', f'priority mismatch: {entry[\"priority\"]}'
assert entry['source'] == 'unit_test', f'source mismatch: {entry[\"source\"]}'
assert entry['status'] == 'pending', f'status mismatch: {entry[\"status\"]}'
print('ALL FIELDS OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALL FIELDS OK"* ]]
}

# --- 2. queue/insights.yamlへの追記確認 ---

@test "追記: 既存エントリを壊さず末尾に追加される" {
    # 1件目
    bash "${TEST_TMP}/scripts/insight_write.sh" "一件目" "low" "test1"
    # 2件目
    bash "${TEST_TMP}/scripts/insight_write.sh" "二件目" "high" "test2"

    run python3 -c "
import yaml
with open('${TEST_TMP}/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
entries = data['insights']
assert len(entries) == 2, f'expected 2 entries, got {len(entries)}'
assert entries[0]['insight'] == '一件目'
assert entries[1]['insight'] == '二件目'
print('APPEND OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"APPEND OK"* ]]
}

# --- 3. ID自動生成の形式確認 ---

@test "ID形式: INS-YYYYMMDD-HHMMSSmmm-{4hex}に一致する" {
    run bash "${TEST_TMP}/scripts/insight_write.sh" "ID形式テスト"
    [ "$status" -eq 0 ]

    # INS-20260325-174530123-a1b2 のような形式
    [[ "$output" =~ ^INS-[0-9]{8}-[0-9]{9}-[0-9a-f]{4}$ ]]
}

# --- 4. 空文字入力時のエラー処理 ---

@test "エラー: 引数なしで実行するとエラー終了する" {
    run bash "${TEST_TMP}/scripts/insight_write.sh"
    [ "$status" -ne 0 ]
}

# --- 5. 複数回実行で重複しないこと(完全一致dedup) ---

@test "重複防止: 同一メッセージのpending insightは二重登録されない" {
    bash "${TEST_TMP}/scripts/insight_write.sh" "重複テスト" "medium" "test"

    # 同じメッセージを再投入
    run bash "${TEST_TMP}/scripts/insight_write.sh" "重複テスト" "medium" "test"
    [ "$status" -eq 0 ]
    # SKIP:INS-... が出力される
    [[ "$output" =~ ^SKIP:INS- ]]

    # エントリ数は1件のまま
    run python3 -c "
import yaml
with open('${TEST_TMP}/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
assert len(data['insights']) == 1, f'expected 1, got {len(data[\"insights\"])}'
print('DEDUP OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEDUP OK"* ]]
}

# --- 6. 先頭50文字一致によるdedup ---

@test "重複防止: 先頭50文字が一致するpending insightも二重登録されない" {
    # 51文字以上の共通先頭を持つ2つのメッセージ
    local prefix="あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんアイウエオカ"
    bash "${TEST_TMP}/scripts/insight_write.sh" "${prefix}末尾A" "medium" "test"

    run bash "${TEST_TMP}/scripts/insight_write.sh" "${prefix}末尾B" "medium" "test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^SKIP:INS- ]]
}

# --- 7. --resolve モード ---

@test "resolve: pendingのinsightをdoneに変更できる" {
    # insightを追加してIDを取得
    local ins_id
    ins_id="$(bash "${TEST_TMP}/scripts/insight_write.sh" "解決テスト")"

    # resolve
    run bash "${TEST_TMP}/scripts/insight_write.sh" --resolve "$ins_id"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED: $ins_id"* ]]

    # statusがdoneに変わっている
    run python3 -c "
import yaml
with open('${TEST_TMP}/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
entry = data['insights'][0]
assert entry['status'] == 'done', f'status={entry[\"status\"]}'
assert 'resolved_at' in entry, 'resolved_at missing'
print('RESOLVE OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVE OK"* ]]
}

# --- 8. --resolve 存在しないID ---

@test "resolve: 存在しないIDでエラー終了する" {
    echo "insights: []" > "${TEST_TMP}/queue/insights.yaml"
    run bash "${TEST_TMP}/scripts/insight_write.sh" --resolve "INS-NONEXISTENT"
    [ "$status" -ne 0 ]
}

# --- 9. デフォルト値の確認 ---

@test "デフォルト値: priority=medium, source=manualが設定される" {
    run bash "${TEST_TMP}/scripts/insight_write.sh" "デフォルトテスト"
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('${TEST_TMP}/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
entry = data['insights'][0]
assert entry['priority'] == 'medium', f'priority={entry[\"priority\"]}'
assert entry['source'] == 'manual', f'source={entry[\"source\"]}'
print('DEFAULT OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEFAULT OK"* ]]
}
