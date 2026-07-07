#!/usr/bin/env bats
# test_sqlite3_cli_removal.bats - cmd_3719: sqlite3 CLI依存除去の回帰テスト
#
# 背景: 本環境にsqlite3 CLIが存在しない(command -v sqlite3=不在)。
# CLI呼び出しの失敗を `2>/dev/null` や `|| true`/`|| echo 0` で握りつぶす実装は、
# クエリが一度も実行されないまま「正常(0件/100%残量/対話なし)」に見える無言の
# false-negativeを生む。python3のsqlite3モジュールへ置換した箇所が、
# クエリ失敗時に無言の既定値ではなく明示エラーを返すことを確認する。

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/sqlite3_cli_removal.XXXXXX")"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

make_codex_db() {
    # $1 = db path, $2.. = (updated_at, tokens_used) pairs
    local db_path="$1"
    shift
    python3 - "$db_path" "$@" <<'PY'
import sqlite3, sys
db_path = sys.argv[1]
pairs = sys.argv[2:]
con = sqlite3.connect(db_path)
con.execute("CREATE TABLE threads (updated_at INTEGER, tokens_used INTEGER, model_provider TEXT)")
for i in range(0, len(pairs), 2):
    con.execute(
        "INSERT INTO threads(updated_at, tokens_used, model_provider) VALUES (?, ?, 'openai')",
        (int(pairs[i]), int(pairs[i + 1])),
    )
con.commit()
con.close()
PY
}

# --- usage_monitor.sh: monitor_status_codex (--status, PROVIDER=codex) ---

@test "usage_monitor.sh: CODEX_DB不在時はERRを返す(無言の0%ではない)" {
    run env CODEX_DB="$TEST_TMPDIR/no_such.sqlite" PROVIDER=codex \
        bash "$PROJECT_ROOT/scripts/usage_monitor.sh" --status
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'ERR\t--\tERR\t--')" ]
}

@test "usage_monitor.sh: 破損DB(threadsテーブル不在)はERR+明示stderrを返し、無言の0%/100%残量にならない" {
    : > "$TEST_TMPDIR/broken.sqlite"
    run env CODEX_DB="$TEST_TMPDIR/broken.sqlite" PROVIDER=codex \
        bash "$PROJECT_ROOT/scripts/usage_monitor.sh" --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERR"$'\t'"--"$'\t'"ERR"$'\t'"--"* ]]
    [[ "$output" == *"usage_monitor: ERROR codex usage query failed"* ]]
}

@test "usage_monitor.sh: 実データありは実際の残量%を返す(healthy path回帰確認)" {
    make_codex_db "$TEST_TMPDIR/real.sqlite" "$(date +%s)" 1000
    run env CODEX_DB="$TEST_TMPDIR/real.sqlite" CODEX_BUDGET_5H=10000 CODEX_BUDGET_7D=100000 PROVIDER=codex \
        bash "$PROJECT_ROOT/scripts/usage_monitor.sh" --status
    [ "$status" -eq 0 ]
    [[ "$output" != *"ERR"* ]]
    IFS=$'\t' read -r h5_left _ d7_left _ <<< "$output"
    [ "$h5_left" = "90" ]
}

# --- memory_db_health_check.sh ---

make_memory_db() {
    local db_path="$1"
    python3 - "$db_path" <<'PY'
import sqlite3, sys
db_path = sys.argv[1]
con = sqlite3.connect(db_path)
con.executescript("""
CREATE TABLE events (id TEXT PRIMARY KEY);
CREATE TABLE event_concepts (id TEXT);
CREATE TABLE event_links (id TEXT);
INSERT INTO events VALUES ('e1'), ('e2');
""")
con.commit()
con.close()
PY
}

@test "memory_db_health_check.sh: DB不在は明示FAIL(db_not_found)" {
    run bash "$PROJECT_ROOT/scripts/memory_db_health_check.sh" --db "$TEST_TMPDIR/no_such.db"
    [ "$status" -ne 0 ]
    [[ "$output" == *"status=FAIL reason=db_not_found"* ]]
}

@test "memory_db_health_check.sh: 破損DB(必要テーブル不在)は無言のPASSにならず明示エラーで失敗する" {
    : > "$TEST_TMPDIR/broken.db"
    run bash "$PROJECT_ROOT/scripts/memory_db_health_check.sh" --db "$TEST_TMPDIR/broken.db" --cache-dir "$TEST_TMPDIR/cache"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR:"* ]]
    [[ "$output" != *"status=PASS"* ]]
}

@test "memory_db_health_check.sh: 健全DBはPASSしWALチェックポイント結果を明示する(healthy path回帰確認)" {
    make_memory_db "$TEST_TMPDIR/health.db"
    run bash "$PROJECT_ROOT/scripts/memory_db_health_check.sh" --apply --db "$TEST_TMPDIR/health.db" --cache-dir "$TEST_TMPDIR/cache"
    [ "$status" -eq 0 ]
    [[ "$output" == *"status=PASS"* ]]
    [[ "$output" == *"live_checkpoint=wal_checkpoint result="* ]]
    [[ "$output" == *"events=2 "* ]]
}

# --- gate_gunshi_startup.sh: lord_rulings セクション ---

setup_gate_sandbox() {
    mkdir -p \
        "$TEST_TMPDIR/scripts/gates" \
        "$TEST_TMPDIR/memory" \
        "$TEST_TMPDIR/queue/inbox" \
        "$TEST_TMPDIR/queue" \
        "$TEST_TMPDIR/logs" \
        "$TEST_TMPDIR/projects/infra" \
        "$TEST_TMPDIR/docs/research" \
        "$TEST_TMPDIR/data"

    cp "$PROJECT_ROOT/scripts/gates/gate_gunshi_startup.sh" "$TEST_TMPDIR/scripts/gates/gate_gunshi_startup.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_gunshi_startup.sh"
    cp "$PROJECT_ROOT/scripts/gates/session_alerts_render.sh" "$TEST_TMPDIR/scripts/gates/session_alerts_render.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/session_alerts_render.sh"

    cat > "$TEST_TMPDIR/memory/deepdive_why_chain_20260321.md" <<'EOF'
前文
## Phase 1
phase1
EOF
    cat > "$TEST_TMPDIR/queue/inbox/gunshi.yaml" <<'EOF'
messages: []
EOF
    cat > "$TEST_TMPDIR/logs/gunshi_stats.yaml" <<'EOF'
# 累計: total=1
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_gunshi.yaml" <<'EOF'
- id: LG001
  title: manual lesson
  automated: false
EOF
}

@test "gate_gunshi_startup.sh: DB不在はALERTで明示し「対話なし」に化けない" {
    setup_gate_sandbox
    # data/multi_agent_shogun_memory.db をあえて作らない(不在)

    run bash -c "cd '$TEST_TMPDIR' && scripts/gates/gate_gunshi_startup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: lord_rulingsクエリ失敗"* ]]
    [[ "$output" != *"(直近6hの殿→軍師対話なし)"* ]]
}

@test "gate_gunshi_startup.sh: 直近6h裁定があれば表示する(healthy path回帰確認)" {
    setup_gate_sandbox
    python3 - "$TEST_TMPDIR/data/multi_agent_shogun_memory.db" <<'PY'
import sqlite3, sys
db_path = sys.argv[1]
con = sqlite3.connect(db_path)
con.execute("""
CREATE TABLE events (
  id TEXT PRIMARY KEY, ts TEXT, event_type TEXT, agent TEXT, target TEXT,
  direction TEXT, summary TEXT, detail TEXT
)
""")
con.execute(
    "INSERT INTO events(id, ts, event_type, agent, target, direction, summary, detail) "
    "VALUES ('e1', datetime('now'), 'conversation', 'lord', 'gunshi', 'inbound', 'needle_ruling_text', 'd')"
)
con.commit()
con.close()
PY

    run bash -c "cd '$TEST_TMPDIR' && scripts/gates/gate_gunshi_startup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"needle_ruling_text"* ]]
    [[ "$output" != *"ALERT: lord_rulingsクエリ失敗"* ]]
}
