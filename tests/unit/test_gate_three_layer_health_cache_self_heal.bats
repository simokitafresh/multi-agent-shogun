#!/usr/bin/env bats

# test_necessity: A corrupt metadata-current memory cache must schedule exactly
# one atomic refresh, leave the detecting run WARN, preserve the source bytes,
# and allow the next run to pass without refreshing a healthy cache.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FIXTURE_DIR="$(mktemp -d)"
  SOURCE_DB="$FIXTURE_DIR/source.db"
  CACHE_DB="$FIXTURE_DIR/cache.db"
  REFRESH_LOG="$FIXTURE_DIR/refresh.log"
  CLEANUP_STUB="$FIXTURE_DIR/cleanup_stub.sh"

  python3 - "$SOURCE_DB" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as conn:
    conn.executescript('''
      CREATE TABLE events(state TEXT, raw_content TEXT);
      CREATE TABLE search_logs(ts TEXT, created_at TEXT);
      INSERT INTO events VALUES ('obsidian_candidate', 'fixture');
      INSERT INTO search_logs VALUES (datetime('now'), datetime('now'));
    ''')
PY
  printf 'not-a-sqlite-database' > "$CACHE_DB"
  touch -r "$SOURCE_DB" "$CACHE_DB"
  SOURCE_SHA="$(sha256sum "$SOURCE_DB" | awk '{print $1}')"
  printf '#!/usr/bin/env bash\necho "mode=dry-run total_bytes=0"\n' > "$CLEANUP_STUB"
  chmod +x "$CLEANUP_STUB"
}

teardown() {
  rm -r "$FIXTURE_DIR"
}

run_gate() {
  run env \
    SHOGUN_MEMORY_DB="$SOURCE_DB" \
    SHOGUN_MEMORY_DB_CACHE_PATH="$CACHE_DB" \
    SHOGUN_MEMORY_DB_CACHE_REFRESH_TIMEOUT=10 \
    SHOGUN_THREE_LAYER_CACHE_WARN_BYTES=999999999 \
    SHOGUN_THREE_LAYER_CLEANUP_SCRIPT="$CLEANUP_STUB" \
    THREE_LAYER_CHAIN_LOG="$FIXTURE_DIR/no-chain.log" \
    THREE_LAYER_CHAIN_STATE_DIR="$FIXTURE_DIR/no-chain-state" \
    bash "$REPO_ROOT/scripts/gates/gate_three_layer_health.sh"
}

@test "metadata-current corrupt cache self-heals once and healthy cache does not refresh" {
  source "$REPO_ROOT/scripts/lib/memory_db_cache.sh"
  run memory_db_cache_is_current "$SOURCE_DB" "$CACHE_DB"
  [ "$status" -eq 0 ]

  run python3 - "$CACHE_DB" <<'PY'
import sqlite3, sys
with sqlite3.connect(f'file:{sys.argv[1]}?mode=ro&immutable=1', uri=True) as conn:
    conn.execute('SELECT COUNT(*) FROM events').fetchone()
PY
  [ "$status" -eq 1 ]
  [[ "$output" == *"sqlite3.DatabaseError"* ]]

  run_gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"cache query failed; scheduling single-flight atomic refresh"* ]]

  for _ in $(seq 1 100); do
    python3 - "$CACHE_DB" <<'PY' >/dev/null 2>&1 && break
import sqlite3, sys
with sqlite3.connect(f'file:{sys.argv[1]}?mode=ro&immutable=1', uri=True) as conn:
    conn.execute('SELECT COUNT(*) FROM events').fetchone()
PY
    sleep 0.05
  done

  [ "$(sha256sum "$SOURCE_DB" | awk '{print $1}')" = "$SOURCE_SHA" ]
  run_gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS: PASS"* ]]
  [[ "$output" != *"scheduling single-flight atomic refresh"* ]]
}
