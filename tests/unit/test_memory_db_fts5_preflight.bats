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
  summary TEXT, detail TEXT, target TEXT, event_type TEXT
);
CREATE VIRTUAL TABLE events_fts USING fts5(summary, detail, content='events', content_rowid='rowid');
''')
rows = [
  ('self', '2026-01-01', 'lord', 'cmd_self', 1, 'alpha 自分記憶', 'alpha 自分詳細', 'kagemaru', 'knowledge'),
  ('other', '2026-01-02', 'lord', 'cmd_other', 1, 'alpha 他者記憶', 'alpha 他者詳細', 'hanzo', 'knowledge'),
  ('all', '2026-01-03', 'lord', 'cmd_all', 1, 'alpha 全員記憶', 'alpha 全員詳細', '', 'knowledge'),
  ('cdp', '2026-01-04', 'lord', 'cmd_cdp', 1, 'CDP getComputedStyle knowledge', 'remote-debugging', '', 'knowledge'),
  ('nonknowledge', '2026-01-05', 'lord', 'cmd_nonknowledge', 1, 'CDP operational event', 'remote-debugging', '', 'operation'),
  ('plain', '2026-01-06', 'lord', 'cmd_plain', 1, 'ordinary knowledge', 'no browser protocol', '', 'knowledge'),
]
conn.executemany('INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?)', rows)
conn.execute("INSERT INTO events_fts(events_fts) VALUES('rebuild')")
conn.commit()
PY
}

@test "migration is idempotent and only classified knowledge injects a skill command" {
  local backup="$BATS_TEST_TMPDIR/memory.backup.db"
  run python3 "$SCRIPT" --backup "$DB" "$backup"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'quick_check=ok' ]]
  run python3 - "$backup" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as conn:
    assert conn.execute("PRAGMA quick_check").fetchone()[0] == "ok"
    assert conn.execute("SELECT count(*) FROM events").fetchone()[0] == 6
PY
  [ "$status" -eq 0 ]

  run python3 "$SCRIPT" --migrate-skill-metadata "$DB"
  [ "$status" -eq 0 ]
  [ "$output" = $'targets=1\tfalse_positive=0' ]

  run python3 "$SCRIPT" --inspect-skill-metadata "$DB"
  [ "$status" -eq 0 ]
  [ "$output" = $'skill_column=1\ttargets=1\tskill_set=1\tfalse_positive=0\tfalse_negative=0\tnull_events=5' ]

  run python3 "$SCRIPT" --migrate-skill-metadata "$DB"
  [ "$status" -eq 0 ]
  [ "$output" = $'targets=1\tfalse_positive=0' ]

  run python3 "$SCRIPT" "$DB" CDP kagemaru
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skill(claude-in-chrome)を起動せよ"* ]]
  nonknowledge_line="$(printf '%s\n' "$output" | grep '^nonknowledge')"
  [[ "$nonknowledge_line" != *"Skill("* ]]

  run python3 "$SCRIPT" "$DB" ordinary kagemaru
  [ "$status" -eq 0 ]
  [[ "$output" == plain$'\t'* ]]
  [[ "$output" != *"Skill("* ]]

  run python3 "$SCRIPT" --backup "$backup" "$DB"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'quick_check=ok' ]]
  run python3 "$SCRIPT" --inspect-skill-metadata "$DB"
  [ "$status" -eq 0 ]
  [ "$output" = $'skill_column=0\ttargets=0\tskill_set=0\tfalse_positive=0\tfalse_negative=0\tnull_events=0' ]
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
  run env -u TMUX_PANE python3 "$SCRIPT" "$DB" alpha
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
