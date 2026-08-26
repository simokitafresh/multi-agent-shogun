#!/usr/bin/env bats
# test_necessity: Interrupted/corrupted tail entries are repaired to maintain YAML parseability; violation is BLOCK.
# test_insight_write.bats — scripts/insight_write.sh ユニットテスト

setup() {
    TEST_TMP="$(mktemp -d)"
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    mkdir -p "${TEST_TMP}/scripts/lib"
    mkdir -p "${TEST_TMP}/queue"

    # insight_write.sh をコピーし、SCRIPT_DIRをテスト用に差し替え
    sed \
        -e "s|SCRIPT_DIR=\"\$(cd \"\$(dirname \"\${BASH_SOURCE\[0\]}\")\/\.\.\" && pwd)\"|SCRIPT_DIR=\"${TEST_TMP}\"|" \
        "$PROJECT_ROOT/scripts/insight_write.sh" > "${TEST_TMP}/scripts/insight_write.sh"
    # Read-only dependencies are shared fixtures; only insight_write.sh needs
    # a per-test rewritten copy for TEST_TMP isolation.
    ln -s "$PROJECT_ROOT/scripts/memory_db_live_insert.py" "${TEST_TMP}/scripts/memory_db_live_insert.py"
    ln -s "$PROJECT_ROOT/scripts/insight_resolve.sh" "${TEST_TMP}/scripts/insight_resolve.sh"
    ln -s "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "${TEST_TMP}/scripts/lib/yaml_field_set.sh"
    chmod +x "${TEST_TMP}/scripts/insight_write.sh"

    # Every fixture must stay off the production memory DB.  The symlinked
    # live-insert module resolves its own real path, so leaving SHOGUN_MEMORY_DB
    # unset silently selects PROJECT_ROOT/data/multi_agent_shogun_memory.db.
    # TEST_TMP is an ext4 /tmp directory; use it as the primary test DB and do
    # not build a redundant cache copy for this already-isolated database.
    export SHOGUN_MEMORY_DB="${TEST_TMP}/data/test_memory.db"
    export SHOGUN_MEMORY_DB_SKIP_CACHE_SYNC=1
    # The fixture queue is outside the real repository.  Production auto-commit
    # retries cannot succeed here and would add 18 seconds to every write while
    # contaminating command output with a warning.
    export INSIGHT_AUTO_COMMIT=0
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

# test_necessity: insight-write fixtures must never open the production memory DB and a locked isolated SQLite write must fail within the configured busy timeout.
@test "memory DB isolation: ext4 fixture only and locked insert exits within timeout" {
    production_db="$PROJECT_ROOT/data/multi_agent_shogun_memory.db"
    [ "$SHOGUN_MEMORY_DB" != "$production_db" ]
    create_memory_db_fixture "$SHOGUN_MEMORY_DB"
    [ "$(stat -f -c %T "$(dirname "$SHOGUN_MEMORY_DB")")" != "9p" ]

    ready="$TEST_TMP/lock.ready"
    release="$TEST_TMP/lock.release"
    python3 - "$SHOGUN_MEMORY_DB" "$ready" "$release" <<'PY' &
import sqlite3
import sys
import time
from pathlib import Path

db_path, ready_path, release_path = sys.argv[1:]
conn = sqlite3.connect(db_path)
conn.execute("BEGIN EXCLUSIVE")
Path(ready_path).touch()
deadline = time.monotonic() + 12
while not Path(release_path).exists() and time.monotonic() < deadline:
    time.sleep(0.02)
conn.rollback()
conn.close()
PY
    locker_pid=$!
    for _ in $(seq 1 100); do
        [ -f "$ready" ] && break
        sleep 0.02
    done
    [ -f "$ready" ]

    started_ms="$(date +%s%3N)"
    run timeout 8s python3 "${TEST_TMP}/scripts/memory_db_live_insert.py" \
        insight --entry-id INS-LOCKED --ts 2026-07-23T04:15:00+0900 \
        --insight "locked fixture" --priority high --source unit_test \
        --status pending --resolved-at "" --source-file "$TEST_TMP/queue/insights.yaml"
    elapsed_ms=$(( $(date +%s%3N) - started_ms ))
    [ "$status" -ne 0 ]
    [ "$status" -ne 124 ]
    [ "$elapsed_ms" -le 7000 ]

    touch "$release"
    wait "$locker_pid"
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

# test_necessity: Valid YAML provenance comments before the top-level key must never cause whole-queue quarantine or entry loss.
@test "追記: 先頭provenanceコメント付きqueueの既存全件を保持する" {
    cat > "${TEST_TMP}/queue/insights.yaml" <<'EOF'
# archive-reconciliation provenance: stable multiset verified
insights:
- id: INS-20260805-000000000-kept
  ts: "2026-08-05T00:00:00+09:00"
  insight: "保持対象"
  priority: "medium"
  source: "unit"
  status: pending
EOF

    run bash "${TEST_TMP}/scripts/insight_write.sh" "コメント後の追記" "high" "unit_test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]

    run python3 - "${TEST_TMP}/queue/insights.yaml" <<'PY'
import glob
import sys
import yaml

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = yaml.safe_load(handle)
assert [entry["insight"] for entry in data["insights"]] == ["保持対象", "コメント後の追記"]
assert open(path, encoding="utf-8").readline().startswith("# archive-reconciliation provenance:")
assert not glob.glob(path.replace("/insights.yaml", "/archive/insights_corrupt/*"))
PY
    [ "$status" -eq 0 ]
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
assert glob.glob('${TEST_TMP}/queue/archive/insights_corrupt/insights.yaml.corrupt.*'), 'corrupt quarantine missing'
assert not glob.glob('${TEST_TMP}/queue/insights.yaml.corrupt.*'), 'corrupt quarantine must not remain in queue root'
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
assert glob.glob('${TEST_TMP}/queue/archive/insights_corrupt/insights.yaml.corrupt.*'), 'corrupt quarantine missing'
assert not glob.glob('${TEST_TMP}/queue/insights.yaml.corrupt.*'), 'corrupt quarantine must not remain in queue root'
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

@test "repair: 完全証跡resolved entryと後続entryを保持する" {
    cat > "${TEST_TMP}/queue/insights.yaml" <<'YAML'
insights:
- id: INS-COMPLETE
  ts: "2026-07-14T05:00:00+09:00"
  insight: "complete resolution"
  priority: "high"
  source: "unit"
  status: resolved
  resolved_reason: "implemented"
  action_artifact: "commit=abc"
  resolved_at: "2026-07-14T05:01:00+09:00"
- id: INS-AFTER
  ts: "2026-07-14T05:02:00+09:00"
  insight: "after complete"
  priority: "low"
  source: "unit"
  status: pending
YAML
    before_corrupt="$(find "${TEST_TMP}/queue/archive/insights_corrupt" -type f 2>/dev/null | wc -l)"
    run bash "${TEST_TMP}/scripts/insight_write.sh" "new append after complete" "low" "unit"
    [ "$status" -eq 0 ]
    python3 - "${TEST_TMP}/queue/insights.yaml" "$before_corrupt" <<'PY'
import glob, sys, yaml
rows=yaml.safe_load(open(sys.argv[1]))['insights']
by_id={x['id']:x for x in rows}
assert {'INS-COMPLETE','INS-AFTER'} <= set(by_id)
complete=by_id['INS-COMPLETE']
assert all(complete.get(k) for k in ('resolved_reason','action_artifact','resolved_at'))
after=len(glob.glob(sys.argv[1].replace('/insights.yaml','/archive/insights_corrupt/*')))
assert after == int(sys.argv[2]), (after, sys.argv[2])
PY
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

@test "resolve: pendingのinsightを完全証跡付きresolvedに変更できる" {
    # insightを追加してIDを取得
    local ins_id
    ins_id="$(bash "${TEST_TMP}/scripts/insight_write.sh" "解決テスト")"

    # resolve
    run bash "${TEST_TMP}/scripts/insight_write.sh" --resolve "$ins_id" "unit test resolution" "test=test_insight_write"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: $ins_id → resolved"* ]]

    # statusがdoneに変わっている
    run python3 -c "
import yaml
with open('${TEST_TMP}/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
entry = data['insights'][0]
assert entry['status'] == 'resolved', f'status={entry[\"status\"]}'
assert 'resolved_at' in entry, 'resolved_at missing'
assert entry['resolved_reason'] == 'unit test resolution'
assert entry['action_artifact'] == 'test=test_insight_write'
print('RESOLVE OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVE OK"* ]]
}

# test_necessity: identical resolution retries must preserve resolved_at and
# file bytes so report revalidation cannot create a post-commit dirty diff.
@test "resolve: 同一証跡の再実行は完全no-opになる" {
    local ins_id before_hash before_at after_hash after_at
    ins_id="$(bash "${TEST_TMP}/scripts/insight_write.sh" "冪等解決テスト")"
    bash "${TEST_TMP}/scripts/insight_write.sh" --resolve "$ins_id" "same reason" "test=idempotent"
    before_hash="$(sha256sum "${TEST_TMP}/queue/insights.yaml" | awk '{print $1}')"
    before_at="$(python3 -c "import yaml; print(yaml.safe_load(open('${TEST_TMP}/queue/insights.yaml'))['insights'][0]['resolved_at'])")"

    sleep 1
    run bash "${TEST_TMP}/scripts/insight_write.sh" --resolve "$ins_id" "same reason" "test=idempotent"
    [ "$status" -eq 0 ]
    [[ "$output" == *"IDEMPOTENT:"* ]]
    after_hash="$(sha256sum "${TEST_TMP}/queue/insights.yaml" | awk '{print $1}')"
    after_at="$(python3 -c "import yaml; print(yaml.safe_load(open('${TEST_TMP}/queue/insights.yaml'))['insights'][0]['resolved_at'])")"
    [ "$after_hash" = "$before_hash" ]
    [ "$after_at" = "$before_at" ]
}

@test "resolve: queue直下にcorrupt残骸がある場合は現物不一致として拒否する" {
    ins_id="$(bash "${TEST_TMP}/scripts/insight_write.sh" "resolve blocked by corrupt")"
    printf 'partial\n' > "${TEST_TMP}/queue/insights.yaml.corrupt.leftover"

    run bash "${TEST_TMP}/scripts/insight_write.sh" --resolve "$ins_id" "blocked corrupt test" "test=corrupt"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unresolved corrupt insight quarantine remains in queue root"* ]]

    run grep -q "status: pending" "${TEST_TMP}/queue/insights.yaml"
    [ "$status" -eq 0 ]
}

@test "resolve: INSIGHTS_FILE環境変数で対象ファイルを切り替えられる" {
    local custom_file="${TEST_TMP}/queue/custom_insights.yaml"
    local ins_id
    ins_id="$(INSIGHTS_FILE="$custom_file" bash "${TEST_TMP}/scripts/insight_write.sh" "custom resolve target")"

    run env INSIGHTS_FILE="$custom_file" bash "${TEST_TMP}/scripts/insight_write.sh" --resolve "$ins_id" "custom target test" "test=custom"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: $ins_id → resolved"* ]]

    run python3 -c "
import yaml
with open('${custom_file}') as f:
    data = yaml.safe_load(f)
entry = data['insights'][0]
assert entry['status'] == 'resolved'
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
proc = subprocess.Popen(["bash", f"{tmp}/scripts/insight_write.sh", "--resolve", ins_id, "interrupt test", "test=atomic"], env=env)
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
    run bash "${TEST_TMP}/scripts/insight_write.sh" --resolve "INS-NONEXISTENT" "missing test" "test=missing"
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

@test "自動完了禁止: 修正済み文言だけではpendingのまま保存される" {
    run bash "${TEST_TMP}/scripts/insight_write.sh" "foo修正済みのため記録のみ" "medium" "unit_test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]

    run python3 -c "
import yaml
with open('${TEST_TMP}/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
entry = data['insights'][0]
assert entry['status'] == 'pending', f'status={entry[\"status\"]}'
assert not entry.get('resolved_at'), entry
print('AUTO RESOLVE BLOCKED OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO RESOLVE BLOCKED OK"* ]]
}

@test "resolve: evidence引数欠落はfail-closedでpendingを維持する" {
    ins_id="$(bash "${TEST_TMP}/scripts/insight_write.sh" "missing evidence")"
    run bash "${TEST_TMP}/scripts/insight_write.sh" --resolve "$ins_id"
    [ "$status" -ne 0 ]
    grep -q 'status: pending' "${TEST_TMP}/queue/insights.yaml"
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

@test "fix_known: 検証成功ならsource閾値を待たずaction_required掲示板へ通知する" {
    rm -f /tmp/shogun_insight_repeat_fix_known_source.last
    cat > "${TEST_TMP}/scripts/bulletin_write.sh" <<'EOF'
#!/usr/bin/env bash
printf 'notify=%s\nposted_by=%s\ncontent=%s\naction_type=%s\n' "${BULLETIN_NOTIFY:-}" "$1" "$2" "$4" >> "$TEST_TMP/bulletin.log"
EOF
    chmod +x "${TEST_TMP}/scripts/bulletin_write.sh"
    printf 'exists\n' > "$TEST_TMP/target.txt"

    run env TEST_TMP="$TEST_TMP" \
        INSIGHT_SOURCE_REPEAT_THRESHOLD=3 \
        INSIGHT_FIX_KNOWN=true \
        INSIGHT_TARGET_FILE="$TEST_TMP/target.txt" \
        INSIGHT_VERIFY_COMMAND="test -f '$TEST_TMP/target.txt'" \
        bash "${TEST_TMP}/scripts/insight_write.sh" "fix known target exists" "high" "fix_known_source"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]
    local ins_id="$output"

    run grep -F "notify=shogun" "$TEST_TMP/bulletin.log"
    [ "$status" -eq 0 ]
    run grep -F "action_type=action_required" "$TEST_TMP/bulletin.log"
    [ "$status" -eq 0 ]
    run grep -F "INSIGHT_FIX_KNOWN: latest=${ins_id}" "$TEST_TMP/bulletin.log"
    [ "$status" -eq 0 ]
    run grep -F "verification=passed" "$TEST_TMP/bulletin.log"
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('${TEST_TMP}/queue/insights.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f)
entry = data['insights'][0]
assert entry['fix_known'] is True, entry
assert entry['target_file'] == '${TEST_TMP}/target.txt', entry
assert entry['verification']['status'] == 'passed', entry
assert entry['verification']['exit_code'] == 0, entry
print('FIX_KNOWN_RECORDED')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FIX_KNOWN_RECORDED"* ]]
}

@test "fix_known: 検証失敗なら即時通知せず従来閾値経路へフォールバックし結果を記録する" {
    rm -f /tmp/shogun_insight_repeat_fix_known_fail.last
    cat > "${TEST_TMP}/scripts/bulletin_write.sh" <<'EOF'
#!/usr/bin/env bash
printf 'notify=%s\nposted_by=%s\ncontent=%s\naction_type=%s\n' "${BULLETIN_NOTIFY:-}" "$1" "$2" "$4" >> "$TEST_TMP/bulletin.log"
EOF
    chmod +x "${TEST_TMP}/scripts/bulletin_write.sh"

    run env TEST_TMP="$TEST_TMP" \
        INSIGHT_SOURCE_REPEAT_THRESHOLD=3 \
        INSIGHT_FIX_KNOWN=true \
        INSIGHT_TARGET_FILE="$TEST_TMP/missing.txt" \
        INSIGHT_VERIFY_COMMAND="test -f '$TEST_TMP/missing.txt'" \
        bash "${TEST_TMP}/scripts/insight_write.sh" "fix known target missing" "high" "fix_known_fail"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]
    [ ! -f "$TEST_TMP/bulletin.log" ]

    run python3 -c "
import yaml
with open('${TEST_TMP}/queue/insights.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f)
entry = data['insights'][0]
assert entry['fix_known'] is True, entry
assert entry['verification']['status'] == 'failed', entry
assert entry['verification']['exit_code'] != 0, entry
print('FIX_KNOWN_FAILED_RECORDED')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FIX_KNOWN_FAILED_RECORDED"* ]]
}

# test_necessity: fix_known identity is the normalized conclusion plus source; pending duplicates aggregate, while a resolved identity is byte-stable and cannot re-dirty Git state.
@test "fix_known: 同一summaryはpending中だけ集約しresolved後はbyte no-opになる" {
    cat > "${TEST_TMP}/scripts/bulletin_write.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$2" >> "$TEST_TMP/bulletin.log"
EOF
    chmod +x "${TEST_TMP}/scripts/bulletin_write.sh"

    run env TEST_TMP="$TEST_TMP" INSIGHT_FIX_KNOWN=true INSIGHT_VERIFY_COMMAND=true \
        bash "${TEST_TMP}/scripts/insight_write.sh" "Same   conclusion" high self_retro
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]
    local first_id="$output"

    run env TEST_TMP="$TEST_TMP" INSIGHT_FIX_KNOWN=true INSIGHT_VERIFY_COMMAND="printf changed" \
        bash "${TEST_TMP}/scripts/insight_write.sh" " same conclusion " high self_retro
    [ "$status" -eq 0 ]
    [ "$output" = "AGGREGATE:${first_id}" ]

    run bash "${TEST_TMP}/scripts/insight_write.sh" --resolve "$first_id" \
        "unit test resolution" "test=test_insight_write"
    [ "$status" -eq 0 ]
    local resolved_sha
    resolved_sha=$(sha256sum "$TEST_TMP/queue/insights.yaml" | awk '{print $1}')
    run env TEST_TMP="$TEST_TMP" INSIGHT_FIX_KNOWN=true INSIGHT_VERIFY_COMMAND="printf changed" \
        bash "${TEST_TMP}/scripts/insight_write.sh" "same conclusion" high self_retro
    [ "$status" -eq 0 ]
    [ "$output" = "AGGREGATE:${first_id}" ]
    [ "$(sha256sum "$TEST_TMP/queue/insights.yaml" | awk '{print $1}')" = "$resolved_sha" ]

    run python3 - "$TEST_TMP/queue/insights.yaml" "$first_id" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['insights']
assert len(data) == 1, data
entry = data[0]
assert entry['id'] == sys.argv[2], entry
assert entry['occurrence_count'] == 2, entry
assert entry['last_seen'], entry
assert len(entry['insight_summary_hash']) == 64, entry
PY
    [ "$status" -eq 0 ]
    run wc -l < "$TEST_TMP/bulletin.log"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

# test_necessity: distinct conclusions or sources must never be suppressed by fix_known aggregation.
@test "fix_known: 異なるsummaryと異なるsourceは新規作成する" {
    cat > "${TEST_TMP}/scripts/bulletin_write.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$2" >> "$TEST_TMP/bulletin.log"
EOF
    chmod +x "${TEST_TMP}/scripts/bulletin_write.sh"

    run env TEST_TMP="$TEST_TMP" INSIGHT_FIX_KNOWN=true INSIGHT_VERIFY_COMMAND=true \
        bash "${TEST_TMP}/scripts/insight_write.sh" "conclusion A" high source_a
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]
    run env TEST_TMP="$TEST_TMP" INSIGHT_FIX_KNOWN=true INSIGHT_VERIFY_COMMAND=true \
        bash "${TEST_TMP}/scripts/insight_write.sh" "conclusion B" high source_a
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]
    run env TEST_TMP="$TEST_TMP" INSIGHT_FIX_KNOWN=true INSIGHT_VERIFY_COMMAND=true \
        bash "${TEST_TMP}/scripts/insight_write.sh" "conclusion A" high source_b
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^INS- ]]
    run python3 - "$TEST_TMP/queue/insights.yaml" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['insights']
assert len(data) == 3, data
PY
    [ "$status" -eq 0 ]
}

@test "並行排他: insight_write追記とyaml_field_set status更新を同時多重実行してもinsights.yamlが破損しない (cmd_3874 AC1)" {
    local ids=()
    local id
    for i in 1 2 3 4 5; do
        id="$(bash "${TEST_TMP}/scripts/insight_write.sh" "concurrent base entry ${i}" "medium" "test")"
        ids+=("$id")
    done

    local pids=()
    for i in $(seq 1 10); do
        bash "${TEST_TMP}/scripts/insight_write.sh" "concurrent write ${i}" "medium" "concurrent_test" >/dev/null 2>&1 &
        pids+=("$!")
    done
    for id in "${ids[@]}"; do
        bash "${TEST_TMP}/scripts/lib/yaml_field_set.sh" "${TEST_TMP}/queue/insights.yaml" "$id" status resolved >/dev/null 2>&1 &
        pids+=("$!")
    done

    local failures=0
    local pid
    for pid in "${pids[@]}"; do
        wait "$pid" || failures=$((failures + 1))
    done
    [ "$failures" -eq 0 ]

    run python3 -c "
import yaml
with open('${TEST_TMP}/queue/insights.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f)
entries = data['insights']
assert len(entries) == 15, f'expected 15 entries (no loss), got {len(entries)}'
resolved = [e for e in entries if e.get('status') == 'resolved']
assert len(resolved) == 5, f'expected 5 resolved, got {len(resolved)}'
print('CONCURRENT_OK entries=' + str(len(entries)) + ' resolved=' + str(len(resolved)))
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CONCURRENT_OK entries=15 resolved=5"* ]]
}
