#!/usr/bin/env bats
# test_necessity: memory_db_query.sh's delta-search decision and
# gate_three_layer_health.sh's cache-freshness check both compare cache/source
# rowid watermarks directly (never mtime), and a 9p-unreachable-source or
# missing-file condition always degrades to cache-only / no-alert rather than
# hard-failing or false-alerting; violation is either a missed delta read
# (stale results survive a fresh write) or a spurious BLOCK/WARN under a
# healthy 9p-unreachable or small-gap condition.
# cmd_karo_impl_b45_memory_cache_rowid_watermark_20260726 (B45, 疾風偵察
# cmd_karo_recon_memory_cache_mtime_freshness_20260726由来)

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export QUERY_SCRIPT="$PROJECT_ROOT/scripts/memory_db_query.sh"
    export HEALTH_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_three_layer_health.sh"
    [ -f "$QUERY_SCRIPT" ] || return 1
    [ -f "$HEALTH_SCRIPT" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/rowid_watermark.XXXXXX")"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# events table with the columns memory_db_import.py's --force-like LIKE path
# reads (id/ts/event_type/agent/target/summary/detail/cmd_id/parent_event_id/
# importance/concepts/raw_content). --force-like avoids needing a live FTS5
# virtual table in the fixture (delta search always forces LIKE mode).
make_events_db() {
    local path="$1"
    python3 - "$path" <<'PY'
import sqlite3, sys
path = sys.argv[1]
with sqlite3.connect(path) as conn:
    conn.execute("""
        CREATE TABLE events (
            id INTEGER PRIMARY KEY,
            ts TEXT, event_type TEXT, agent TEXT, target TEXT,
            summary TEXT, detail TEXT, cmd_id TEXT, parent_event_id TEXT,
            importance TEXT, concepts TEXT, raw_content TEXT
        )
    """)
    conn.commit()
PY
}

insert_event() {
    local path="$1" summary="$2"
    python3 - "$path" "$summary" <<'PY'
import sqlite3, sys
path, summary = sys.argv[1], sys.argv[2]
with sqlite3.connect(path) as conn:
    conn.execute(
        "INSERT INTO events (ts, event_type, agent, target, summary, detail, importance) "
        "VALUES (datetime('now'), 'note', 'test', 'kagemaru', ?, '', 'normal')",
        (summary,),
    )
    conn.commit()
PY
}

max_rowid() {
    python3 - "$1" <<'PY'
import sqlite3, sys
with sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True) as conn:
    print(conn.execute("SELECT COALESCE(MAX(rowid), 0) FROM events").fetchone()[0])
PY
}

@test "AC5(b)陽性: cache再生成直後でもmtimeではなくrowid水位差で書込み直後の検索が引ける" {
    local source="$TEST_TMPDIR/source.db" cache
    make_events_db "$source"
    insert_event "$source" "古いエントリ 三層記憶テスト"
    # cacheはsourceのコピー(mkstemp→copy→os.replace公開を模す)。生成後に
    # sourceへ新規書込みを行い、cacheのmtimeをsourceより新しくする
    # (実運用のcache生成のコピー所要時間ぶんmtimeが後ろへずれる状況を再現)。
    cp "$source" "$TEST_TMPDIR/cache.db"
    cache="$TEST_TMPDIR/cache.db"
    sleep 1.1
    touch "$cache"
    insert_event "$source" "新規書込み直後エントリ 三層記憶テスト"

    # 機序を特定した(2026-07-26、家老指摘の再調査): memory_db_query.sh:70-71は
    # --targetが空の場合 `tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}'`
    # で実行者自身のagent_idをtargetへ自動解決し、SQLの--targetフィルタへ渡す。
    # fixtureはtarget='kagemaru'で挿入しているため、この自動解決経路をtmux
    # pane由来のTMUX_PANE(またはAGENT_ID/MEMORY_DB_QUERY_TARGET)に依存させると
    # 実行者がkagemaru以外(karo/hayate等)の場合にtargetが一致せず0件になる
    # (実測で再現・確定済み: MEMORY_DB_QUERY_TARGET=karoを模擬指定すると0件)。
    # target解決に使う3変数を明示的にunsetし(env -u)、実行者の身元に依存しない
    # 決定論的な検索にする(env -iのような包括遮断ではなく、特定した変数のみ)。
    run env -u TMUX_PANE -u AGENT_ID -u MEMORY_DB_QUERY_TARGET \
        MEMORY_DB_QUERY_DB="$source" SHOGUN_MEMORY_DB_CACHE_PATH="$cache" \
        bash "$QUERY_SCRIPT" --search "三層記憶テスト"
    [ "$status" -eq 0 ]
    [[ "$output" == *"新規書込み直後エントリ"* ]]
}

@test "AC5(a)陰性: source側が読めない(9p不通を模す)場合でもcacheのみへフォールバックし検索は失敗しない" {
    local source="$TEST_TMPDIR/source.db" cache="$TEST_TMPDIR/cache.db"
    make_events_db "$source"
    insert_event "$source" "cache内エントリ 三層記憶テスト"
    cp "$source" "$cache"
    # sourceを不正なSQLiteファイル(壊れたヘッダ)に差し替える。ファイル自体は
    # 存在する(prepare_memory_db_for_readのファイル存在チェックは通る)ため
    # source未マウント/9p不通に近い状態を模す。rowid取得は例外で失敗し
    # timeoutと同じ経路(source_max_rowidが非数値→delta無効化)をたどる。
    printf 'not a sqlite database\n' > "$source"

    # 非デフォルトDBパスはprepare_memory_db_for_readが素通し(cache未使用)する
    # 安全側ガードを持つ(cmd_2xxx由来、本タスクの対象外)。本番の既定DBパスは
    # このガードに該当しないため、fixtureではcache経路へ明示的にopt-inする。
    # target解決に使う3変数を明示的にunsetする(上のAC5(b)テストと同じ機序:
    # TMUX_PANE経由の実行者自身のagent_id自動解決が、target='kagemaru'固定の
    # fixtureデータと実行者が異なる場合に0件を生む)。
    run env -u TMUX_PANE -u AGENT_ID -u MEMORY_DB_QUERY_TARGET \
        MEMORY_DB_QUERY_DB="$source" SHOGUN_MEMORY_DB_CACHE_PATH="$cache" \
        SHOGUN_MEMORY_DB_QUERY_CACHE_NONDEFAULT=1 \
        bash "$QUERY_SCRIPT" --search "三層記憶テスト"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cache内エントリ"* ]]
}

@test "AC5(c)陰性: gate_three_layer_health.shは正常な小さなgapで誤ってWARNを出さない" {
    local source="$TEST_TMPDIR/source.db" cache="$TEST_TMPDIR/cache.db"
    make_events_db "$source"
    for i in 1 2 3 4 5; do
        insert_event "$source" "entry $i"
    done
    cp "$source" "$cache"
    insert_event "$source" "entry 6 (直後の追加書込み、cache未反映)"

    run env SHOGUN_MEMORY_DB="$source" SHOGUN_MEMORY_DB_CACHE_PATH="$cache" \
        SHOGUN_THREE_LAYER_CLEANUP_SCRIPT="/bin/true" \
        bash "$HEALTH_SCRIPT"
    [[ "$output" == *"OK: cacheは本体に追随している"* ]]
    [[ "$output" != *"WARN: cacheが本体に追随していない"* ]]
}

@test "AC5(c)陽性対照: gate_three_layer_health.shは閾値を超える異常なgapでWARNを出す(疾風実証の沈黙する検知器を解消)" {
    local source="$TEST_TMPDIR/source.db" cache="$TEST_TMPDIR/cache.db"
    make_events_db "$source"
    make_events_db "$cache"
    insert_event "$cache" "cache側だけの古いエントリ"
    python3 - "$source" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as conn:
    conn.executemany(
        "INSERT INTO events (ts, event_type, agent, target, summary, detail, importance) "
        "VALUES (datetime('now'), 'note', 'test', 'kagemaru', ?, '', 'normal')",
        [(f"source entry {i}",) for i in range(1, 1501)],
    )
    conn.commit()
PY

    run env SHOGUN_MEMORY_DB="$source" SHOGUN_MEMORY_DB_CACHE_PATH="$cache" \
        SHOGUN_THREE_LAYER_CLEANUP_SCRIPT="/bin/true" \
        bash "$HEALTH_SCRIPT"
    [[ "$output" == *"WARN: cacheが本体に追随していない"* ]]
    [[ "$output" == *"STATUS: BLOCK"* ]]
}

# test_necessity: A corrupt published cache must fail closed and delegate its
# rebuild without making the SQL caller synchronously quick-check or back up
# the canonical 9P database; violation can hang every pre-action hook.
@test "corrupt cache recovery is delegated and returns fail-closed within 5s" {
    local source="$TEST_TMPDIR/source.db" cache="$TEST_TMPDIR/cache.db"
    make_events_db "$source"
    insert_event "$source" "canonical row"
    printf 'not sqlite\n' > "$cache"

    local started elapsed
    started="$(date +%s%3N)"
    run env -u TMUX_PANE -u AGENT_ID -u MEMORY_DB_QUERY_TARGET \
        MEMORY_DB_QUERY_DB="$source" SHOGUN_MEMORY_DB_CACHE_PATH="$cache" \
        SHOGUN_MEMORY_DB_QUERY_CACHE_NONDEFAULT=1 \
        bash "$QUERY_SCRIPT" --db "$source" "SELECT summary FROM events"
    elapsed=$(( $(date +%s%3N) - started ))

    [ "$status" -eq 2 ]
    [ "$elapsed" -lt 5000 ]
    [[ "$output" == *"cache recovery scheduled"* ]]
}

# regression_justification: This overlaps the corrupt-cache contract above on
# purpose: the invariant here is single-flight latency under competing callers,
# not the single-caller fail-closed result.
# test_necessity: Concurrent corrupt-cache readers must all return within the
# hook budget while the existing refresh lock serializes detached rebuilding.
@test "competing corrupt cache callers all return within 5s without silent output" {
    local source="$TEST_TMPDIR/source.db" cache="$TEST_TMPDIR/cache.db"
    make_events_db "$source"
    insert_event "$source" "canonical row"
    printf 'not sqlite\n' > "$cache"
    local started pid rc failures=0 empty=0
    started="$(date +%s%3N)"
    for i in 1 2 3; do
        env -u TMUX_PANE -u AGENT_ID -u MEMORY_DB_QUERY_TARGET \
            MEMORY_DB_QUERY_DB="$source" SHOGUN_MEMORY_DB_CACHE_PATH="$cache" \
            SHOGUN_MEMORY_DB_QUERY_CACHE_NONDEFAULT=1 \
            bash "$QUERY_SCRIPT" --db "$source" "SELECT summary FROM events" \
            >"$TEST_TMPDIR/out.$i" 2>&1 &
        eval "pid_$i=$!"
    done
    for i in 1 2 3; do
        eval "pid=\$pid_$i"
        if wait "$pid"; then
            rc=0
        else
            rc=$?
        fi
        [ "$rc" -eq 2 ] || failures=$((failures + 1))
        [ -s "$TEST_TMPDIR/out.$i" ] || empty=$((empty + 1))
    done
    [ $(( $(date +%s%3N) - started )) -lt 5000 ]
    [ "$failures" -eq 0 ]
    [ "$empty" -eq 0 ]
}

# test_necessity: The SQL caller must not contain a synchronous canonical-DB
# health scan or backup path; source I/O delay belongs only to the detached
# cache publisher and cannot retain the foreground hook process.
@test "SQL recovery caller has no synchronous canonical quick-check or backup" {
    run python3 - "$QUERY_SCRIPT" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index("def main() -> int:")
caller = text[start:]
assert "source.backup(" not in caller
assert "require_healthy_database(source_db_path)" not in caller
assert "force_refresh_memory_db_cache_async" in caller
PY
    [ "$status" -eq 0 ]
}
