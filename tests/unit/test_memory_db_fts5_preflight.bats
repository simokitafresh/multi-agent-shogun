#!/usr/bin/env bats
# test_necessity: memory preflight returns only requesting-agent or empty-target rows and fails closed without identity/schema

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$ROOT/scripts/hooks/memory_db_fts5_preflight.py"
  DB="$BATS_TEST_TMPDIR/memory.db"
  python3 - "$DB" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.executescript('''
CREATE TABLE events (
  id TEXT, ts TEXT, agent TEXT, cmd_id TEXT, importance INTEGER,
  summary TEXT, detail TEXT, target TEXT
);
CREATE VIRTUAL TABLE events_fts USING fts5(summary, detail, content='events', content_rowid='rowid');
''')
rows = [
  ('self', '2026-01-01', 'lord', 'cmd_self', 1, 'alpha 自分記憶', 'alpha 自分詳細', 'kagemaru'),
  ('other', '2026-01-02', 'lord', 'cmd_other', 1, 'alpha 他者記憶', 'alpha 他者詳細', 'hanzo'),
  ('all', '2026-01-03', 'lord', 'cmd_all', 1, 'alpha 全員記憶', 'alpha 全員詳細', ''),
]
conn.executemany('INSERT INTO events VALUES (?,?,?,?,?,?,?,?)', rows)
conn.execute("INSERT INTO events_fts(events_fts) VALUES('rebuild')")
conn.commit()
PY
}

@test "LIKE and FTS5 visibility allow self and empty target but exclude another agent" {
  run python3 "$SCRIPT" "$DB" "自分記憶" kagemaru
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == self$'\t'* ]]

  run python3 "$SCRIPT" "$DB" alpha kagemaru
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "$output" == *$'self\t'* ]]
  [[ "$output" == *$'all\t'* ]]
  [[ "$output" != *$'other\t'* ]]
}

@test "missing agent identity and missing target schema fail closed with zero rows" {
  run python3 "$SCRIPT" "$DB" alpha
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  local legacy="$BATS_TEST_TMPDIR/legacy.db"
  python3 - "$legacy" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute('CREATE TABLE events (id TEXT, ts TEXT, agent TEXT, cmd_id TEXT, importance INTEGER, summary TEXT, detail TEXT)')
c.execute("INSERT INTO events VALUES ('legacy','2026','lord','cmd',1,'alpha','alpha')")
c.commit()
PY
  run python3 "$SCRIPT" "$legacy" alpha kagemaru
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
