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
    cp "$PROJECT_ROOT/scripts/memory_db_live_insert.py" "${TEST_TMP}/scripts/memory_db_live_insert.py"
    chmod +x "${TEST_TMP}/scripts/insight_write.sh"
}

teardown() {
    rm -rf "$TEST_TMP"
}

create_memory_db_fixture() {
    local db_path="$1"
    mkdir -p "$(dirname "$db_path")"
    python3 - "$db_path" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.executescript("""
CREATE TABLE events (
    id TEXT PRIMARY KEY,
    ts TEXT,
    event_type TEXT,
    agent TEXT,
    target TEXT,
    direction TEXT,
    summary TEXT,
    detail TEXT,
    session_id TEXT,
    cmd_id TEXT,
    concepts TEXT,
    source_file TEXT,
    parent_event_id INTEGER,
    importance TEXT
);
CREATE VIRTUAL TABLE events_fts USING fts5(
    summary,
    detail,
    content='events',
    content_rowid='rowid'
);
""")
conn.commit()
PY
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

@test "DB連携: insight write後にmemory DB eventsとFTSへ投入される" {
    local memory_db="$TEST_TMP/data/memory.db"
    create_memory_db_fixture "$memory_db"

    run env SHOGUN_MEMORY_DB="$memory_db" bash "${TEST_TMP}/scripts/insight_write.sh" "cmd_2983 insight realtime searchable" "high" "unit_test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]

    readarray -t result < <(python3 - "$memory_db" "$output" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
event_id = "insight:" + sys.argv[2].splitlines()[0]
row = conn.execute(
    "SELECT event_type, agent, direction, cmd_id, importance FROM events WHERE id = ?",
    (event_id,),
).fetchone()
fts_count = conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'searchable'
      AND e.id = ?
    """,
    (event_id,),
).fetchone()[0]
print(row[0])
print(row[1])
print(row[2])
print(row[3])
print(row[4])
print(fts_count)
PY
)
    [ "${result[0]}" = "insight" ]
    [ "${result[1]}" = "unit_test" ]
    [ "${result[2]}" = "pending" ]
    [ "${result[3]}" = "cmd_2983" ]
    [ "${result[4]}" = "high" ]
    [ "${result[5]}" = "1" ]
}

@test "DB連携: DB失敗時もinsights YAML追記は成功する" {
    local broken_db="$TEST_TMP/data/broken.db"
    mkdir -p "$(dirname "$broken_db")"
    printf 'not sqlite\n' > "$broken_db"

    run env SHOGUN_MEMORY_DB="$broken_db" bash "${TEST_TMP}/scripts/insight_write.sh" "DB失敗でもYAML成功" "medium" "unit_test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]
    [[ "$output" == *"WARN: insight DB INSERT skipped"* ]]
    run grep -F "DB失敗でもYAML成功" "$TEST_TMP/queue/insights.yaml"
    [ "$status" -eq 0 ]
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

@test "中断耐性: 未完了の末尾エントリを退避してparse可能なまま追記する" {
    cat > "${TEST_TMP}/queue/insights.yaml" <<'EOF'
insights:
- id: INS-20260612-000000000-good
  ts: "2026-06-12T00:00:00+09:00"
  insight: "既存"
  priority: "medium"
  source: "unit"
  status: pending
- id: INS-20260612-000000001-part
  ts: "2026-06-12T00:00:01+09:00"
  insight: "書込み途中"
EOF

    run bash "${TEST_TMP}/scripts/insight_write.sh" "中断後の追記" "high" "unit_test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]

    run python3 -c "
import glob
import yaml
with open('${TEST_TMP}/queue/insights.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f)
entries = data['insights']
assert [e['insight'] for e in entries] == ['既存', '中断後の追記']
assert glob.glob('${TEST_TMP}/queue/insights.yaml.corrupt.*'), 'corrupt quarantine missing'
print('PARTIAL RECOVERED')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PARTIAL RECOVERED"* ]]
}

@test "破損退避: 末尾の構文破損行を退避しparseを継続する" {
    cat > "${TEST_TMP}/queue/insights.yaml" <<'EOF'
insights:
- id: INS-20260612-000000000-good
  ts: "2026-06-12T00:00:00+09:00"
  insight: "既存"
  priority: "medium"
  source: "unit"
  status: pending
  broken: [unterminated
EOF

    run bash "${TEST_TMP}/scripts/insight_write.sh" "破損後の追記" "low" "unit_test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]

    run python3 -c "
import glob
import yaml
with open('${TEST_TMP}/queue/insights.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f)
entries = data['insights']
assert [e['insight'] for e in entries] == ['既存', '破損後の追記']
assert glob.glob('${TEST_TMP}/queue/insights.yaml.corrupt.*'), 'corrupt quarantine missing'
print('CORRUPT RECOVERED')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CORRUPT RECOVERED"* ]]
}

@test "repair: resolved_reason付きresolved entryを正常フィールドとして保持する" {
    cat > "${TEST_TMP}/queue/insights.yaml" <<'EOF'
insights:
- id: INS-20260702-151336042-7e9f
  ts: "2026-07-02T15:13:36+09:00"
  insight: "commit_missing insight"
  priority: "high"
  source: "unit"
  resolved_reason: "classified as existing coverage"
  status: resolved
EOF

    run bash "${TEST_TMP}/scripts/insight_write.sh" "resolved_reason後の追記" "low" "unit_test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]

    run python3 -c "
import glob
import yaml
with open('${TEST_TMP}/queue/insights.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f)
entries = data['insights']
assert entries[0]['resolved_reason'] == 'classified as existing coverage'
assert [e['insight'] for e in entries] == ['commit_missing insight', 'resolved_reason後の追記']
assert not glob.glob('${TEST_TMP}/queue/insights.yaml.corrupt.*'), 'resolved_reason should not be quarantined'
print('RESOLVED_REASON PRESERVED')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_REASON PRESERVED"* ]]
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

@test "--help: usage表示のみでinsightを作らない" {
    run bash "${TEST_TMP}/scripts/insight_write.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: bash scripts/insight_write.sh"* ]]
    [ ! -f "${TEST_TMP}/queue/insights.yaml" ]
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

@test "重複防止: 同一sourceの同一direct alias pendingは既存IDを返して件数不増" {
    local first_id
    first_id="$(bash "${TEST_TMP}/scripts/insight_write.sh" "[[creator_brainwashing_defense]] alias: 秘密のプロンプト, アントロピックが秘密のプロンプトを付け加えてる" "high" "semantic_stress_test")"
    [[ "$first_id" =~ ^INS- ]]

    local before_count
    before_count="$(python3 -c "
import yaml
with open('${TEST_TMP}/queue/insights.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f)
print(sum(1 for entry in data['insights'] if entry.get('status') == 'pending'))
")"

    run bash "${TEST_TMP}/scripts/insight_write.sh" "[[creator_brainwashing_defense]] alias: アントロピックが秘密のプロンプトを付け加えてる, 秘密のプロンプト" "high" "semantic_stress_test"
    [ "$status" -eq 0 ]
    [[ "$output" == "SKIP:$first_id" ]]

    run python3 -c "
import yaml
with open('${TEST_TMP}/queue/insights.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f)
pending = sum(1 for entry in data['insights'] if entry.get('status') == 'pending')
assert pending == int('${before_count}'), f'pending grew: before=${before_count} after={pending}'
print(f'PENDING_UNCHANGED {pending}')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PENDING_UNCHANGED 1"* ]]
}

@test "重複防止: 同一sourceの同一query pendingはSOURCE_REPEAT_THRESHOLD到達でも新規投稿しない" {
    rm -f /tmp/shogun_insight_repeat_semantic_stress_test.last
    cat > "${TEST_TMP}/scripts/bulletin_write.sh" <<'EOF'
#!/usr/bin/env bash
printf 'notify=%s\nposted_by=%s\ncontent=%s\n' "${BULLETIN_NOTIFY:-}" "$1" "$2" >> "$TEST_TMP/bulletin.log"
EOF
    chmod +x "${TEST_TMP}/scripts/bulletin_write.sh"

    local first_id
    first_id="$(env TEST_TMP="$TEST_TMP" INSIGHT_SOURCE_REPEAT_THRESHOLD=1 bash "${TEST_TMP}/scripts/insight_write.sh" "semantic query duplicate candidate" "high" "semantic_stress_test")"
    [[ "$first_id" =~ ^INS- ]]
    [ -f "$TEST_TMP/bulletin.log" ]
    rm -f "$TEST_TMP/bulletin.log"

    run env TEST_TMP="$TEST_TMP" INSIGHT_SOURCE_REPEAT_THRESHOLD=1 bash "${TEST_TMP}/scripts/insight_write.sh" "semantic query duplicate candidate" "high" "semantic_stress_test"
    [ "$status" -eq 0 ]
    [[ "$output" == "SKIP:$first_id" ]]
    [ ! -f "$TEST_TMP/bulletin.log" ]

    run python3 -c "
import yaml
with open('${TEST_TMP}/queue/insights.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f)
pending = [entry for entry in data['insights'] if entry.get('status') == 'pending']
assert len(pending) == 1, f'expected 1 pending, got {len(pending)}'
print('NO_REPEAT_POST pending=1')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NO_REPEAT_POST pending=1"* ]]
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

@test "resolve: INSIGHTS_FILE環境変数で対象ファイルを切り替えられる" {
    local custom_file="${TEST_TMP}/queue/custom_insights.yaml"
    local ins_id
    ins_id="$(INSIGHTS_FILE="$custom_file" bash "${TEST_TMP}/scripts/insight_write.sh" "custom resolve target")"

    run env INSIGHTS_FILE="$custom_file" bash "${TEST_TMP}/scripts/insight_write.sh" --resolve "$ins_id"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED: $ins_id"* ]]

    run python3 -c "
import yaml
with open('${custom_file}') as f:
    data = yaml.safe_load(f)
entry = data['insights'][0]
assert entry['status'] == 'done'
print('CUSTOM RESOLVE OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CUSTOM RESOLVE OK"* ]]
}

@test "resolve: replace直前に中断されてもinsights本体は欠損しない" {
    local ins_id
    ins_id="$(bash "${TEST_TMP}/scripts/insight_write.sh" "atomic resolve target")"
    cp "${TEST_TMP}/queue/insights.yaml" "${TEST_TMP}/queue/insights.before.yaml"

    TEST_TMP_ENV="$TEST_TMP" INS_ID_ENV="$ins_id" python3 - <<'PY'
import os
import subprocess
import time

tmp = os.environ["TEST_TMP_ENV"]
ins_id = os.environ["INS_ID_ENV"]
env = os.environ.copy()
env["INSIGHT_TEST_SLEEP_BEFORE_REPLACE"] = "5"
proc = subprocess.Popen(["bash", f"{tmp}/scripts/insight_write.sh", "--resolve", ins_id], env=env)
time.sleep(1)
proc.terminate()
try:
    proc.wait(timeout=3)
except subprocess.TimeoutExpired:
    proc.terminate()
    proc.wait(timeout=3)
PY

    cmp "${TEST_TMP}/queue/insights.before.yaml" "${TEST_TMP}/queue/insights.yaml"

    run python3 -c "
import yaml
with open('${TEST_TMP}/queue/insights.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f)
entry = data['insights'][0]
assert entry['status'] == 'pending', entry
print('INTERRUPT PRESERVED')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"INTERRUPT PRESERVED"* ]]
}

@test "tail repair: replace直前に中断されてもinsights本体は欠損しない" {
    cat > "${TEST_TMP}/queue/insights.yaml" <<'EOF'
insights:
- id: INS-KEEP
  ts: "2026-01-01T00:00:00+09:00"
  insight: "keep me"
  priority: "medium"
  source: "unit_test"
  status: pending
- id: INS-PARTIAL
  ts: "2026-01-01T00:00:01+09:00"
EOF
    cp "${TEST_TMP}/queue/insights.yaml" "${TEST_TMP}/queue/insights.before.yaml"

    TEST_TMP_ENV="$TEST_TMP" python3 - <<'PY'
import os
import subprocess
import time

tmp = os.environ["TEST_TMP_ENV"]
env = os.environ.copy()
env["INSIGHT_TEST_SLEEP_BEFORE_REPLACE"] = "5"
proc = subprocess.Popen(["bash", f"{tmp}/scripts/insight_write.sh", "after interrupt", "high", "unit_test"], env=env)
time.sleep(1)
proc.terminate()
try:
    proc.wait(timeout=3)
except subprocess.TimeoutExpired:
    proc.terminate()
    proc.wait(timeout=3)
PY

    cmp "${TEST_TMP}/queue/insights.before.yaml" "${TEST_TMP}/queue/insights.yaml"

    run python3 -c "
from pathlib import Path
text = Path('${TEST_TMP}/queue/insights.yaml').read_text(encoding='utf-8')
assert 'INS-KEEP' in text
assert 'INS-PARTIAL' in text
print('REPAIR INTERRUPT PRESERVED')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"REPAIR INTERRUPT PRESERVED"* ]]
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

@test "自動完了: 修正済みメッセージはdoneで保存される" {
    run bash "${TEST_TMP}/scripts/insight_write.sh" "foo修正済みのため記録のみ" "medium" "unit_test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]

    run python3 -c "
import yaml
with open('${TEST_TMP}/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
entry = data['insights'][0]
assert entry['status'] == 'done', f'status={entry[\"status\"]}'
assert 'resolved_at' in entry, 'resolved_at missing'
print('AUTO DONE OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO DONE OK"* ]]
}

@test "スキップ: test_pattern/test_fix含むメッセージは保存しない" {
    run bash "${TEST_TMP}/scripts/insight_write.sh" "fixture test_pattern with test_fix marker" "medium" "unit_test"
    [ "$status" -eq 0 ]
    [[ "$output" == "SKIP:test-fixture" ]]

    run python3 -c "
import os, yaml
path='${TEST_TMP}/queue/insights.yaml'
if os.path.exists(path):
    with open(path) as f:
        data = yaml.safe_load(f)
    entries = (data or {}).get('insights', []) if isinstance(data, dict) else []
    assert len(entries) == 0, f'expected 0 entries, got {len(entries)}'
print('TEST FIXTURE SKIPPED')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST FIXTURE SKIPPED"* ]]
}

@test "同一source繰返し: 閾値到達で将軍へbulletin通知する" {
    # デバウンスファイルをクリア(前回テストの残存防止)
    rm -f /tmp/shogun_insight_repeat_repeat_source.last
    cat > "${TEST_TMP}/scripts/bulletin_write.sh" <<'EOF'
#!/usr/bin/env bash
printf 'notify=%s\nposted_by=%s\ncontent=%s\n' "${BULLETIN_NOTIFY:-}" "$1" "$2" >> "$TEST_TMP/bulletin.log"
EOF
    chmod +x "${TEST_TMP}/scripts/bulletin_write.sh"

    run env TEST_TMP="$TEST_TMP" INSIGHT_SOURCE_REPEAT_THRESHOLD=2 bash "${TEST_TMP}/scripts/insight_write.sh" "同一source一件目" "high" "repeat_source"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]
    [ ! -f "$TEST_TMP/bulletin.log" ]

    run env TEST_TMP="$TEST_TMP" INSIGHT_SOURCE_REPEAT_THRESHOLD=2 bash "${TEST_TMP}/scripts/insight_write.sh" "同一source二件目" "high" "repeat_source"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]

    run grep -F "notify=shogun" "$TEST_TMP/bulletin.log"
    [ "$status" -eq 0 ]
    run grep -F "source=repeat_source pending_count=2 threshold=2" "$TEST_TMP/bulletin.log"
    [ "$status" -eq 0 ]
    run grep -F "insight_summary=同一source二件目" "$TEST_TMP/bulletin.log"
    [ "$status" -eq 0 ]
}
