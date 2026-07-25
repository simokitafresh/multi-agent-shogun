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

    # env -iで環境変数を完全にクリアしてから明示指定のみ渡す。継承された
    # MEMORY_DB_QUERY_*/SHOGUN_MEMORY_DB_*系の値が呼出し元シェルに残っていて
    # 結果へ紛れ込む余地を断つ(親シェルの汚染に対する耐性)。
    run env -i PATH="$PATH" HOME="$HOME" \
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
    run env -i PATH="$PATH" HOME="$HOME" \
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
    [[ "$output" == *"STATUS: WARN"* ]]
}
