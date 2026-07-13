#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_WRITE="$PROJECT_ROOT/scripts/bulletin_write.sh"
    export SRC_ARCHIVE="$PROJECT_ROOT/scripts/bulletin_archive.sh"
    export SRC_CONFIRM="$PROJECT_ROOT/scripts/bulletin_confirm.sh"
    export SRC_CLOSE="$PROJECT_ROOT/scripts/bulletin_close.sh"
    export SRC_AGENT_CONFIG="$PROJECT_ROOT/scripts/lib/agent_config.sh"
    export SRC_MEMORY_DB_LIVE_INSERT="$PROJECT_ROOT/scripts/memory_db_live_insert.py"
    export SRC_MEMORY_DB_LIVE_INSERT_ASYNC="$PROJECT_ROOT/scripts/memory_db_live_insert_async.py"
    export SRC_INBOX_WRITE="$PROJECT_ROOT/scripts/inbox_write.sh"
    [ -f "$SRC_WRITE" ] || return 1
    [ -f "$SRC_ARCHIVE" ] || return 1
    [ -f "$SRC_CONFIRM" ] || return 1
    [ -f "$SRC_CLOSE" ] || return 1
    [ -f "$SRC_AGENT_CONFIG" ] || return 1
    [ -f "$SRC_MEMORY_DB_LIVE_INSERT" ] || return 1
    [ -f "$SRC_MEMORY_DB_LIVE_INSERT_ASYNC" ] || return 1
    [ -f "$SRC_INBOX_WRITE" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/bulletin.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/lib" "$TEST_TMPDIR/scripts/bin" "$TEST_TMPDIR/queue" "$TEST_TMPDIR/config"
    cp "$SRC_WRITE" "$TEST_TMPDIR/scripts/bulletin_write.sh"
    cp "$SRC_ARCHIVE" "$TEST_TMPDIR/scripts/bulletin_archive.sh"
    cp "$SRC_CONFIRM" "$TEST_TMPDIR/scripts/bulletin_confirm.sh"
    cp "$SRC_CLOSE" "$TEST_TMPDIR/scripts/bulletin_close.sh"
    cp "$SRC_AGENT_CONFIG" "$TEST_TMPDIR/scripts/lib/agent_config.sh"
    cp "$SRC_MEMORY_DB_LIVE_INSERT" "$TEST_TMPDIR/scripts/memory_db_live_insert.py"
    cp "$SRC_MEMORY_DB_LIVE_INSERT_ASYNC" "$TEST_TMPDIR/scripts/memory_db_live_insert_async.py"
cat > "$TEST_TMPDIR/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
if [ -n "${INBOX_WRITE_LOG:-}" ]; then
    printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$INBOX_WRITE_LOG"
fi
EOF
    chmod +x "$TEST_TMPDIR/scripts/bulletin_write.sh" "$TEST_TMPDIR/scripts/bulletin_archive.sh" "$TEST_TMPDIR/scripts/bulletin_confirm.sh" "$TEST_TMPDIR/scripts/bulletin_close.sh" "$TEST_TMPDIR/scripts/inbox_write.sh" "$TEST_TMPDIR/scripts/memory_db_live_insert_async.py"
    cat > "$TEST_TMPDIR/scripts/bin/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${BULLETIN_TEST_AGENT_ID:-hayate}"
EOF
    chmod +x "$TEST_TMPDIR/scripts/bin/tmux"
    cat > "$TEST_TMPDIR/scripts/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_TMPDIR/scripts/bin/pgrep"
    export PATH="$TEST_TMPDIR/scripts/bin:$PATH"
    export TMUX_PANE="%999"
    cat > "$TEST_TMPDIR/config/settings.yaml" <<'YAML'
cli:
  agents:
    gunshi:
      role: gunshi
      japanese_name: 軍師
    saizo:
      role: ninja
      japanese_name: 才蔵
YAML
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

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "bulletin_write adds entry to bulletin YAML" {
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "共有連絡"
    [ "$status" -eq 0 ]
    [[ "$output" == blt_* ]]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"content: |-"* ]]
    [[ "$output" == *"共有連絡"* ]]
    [[ "$output" == *"posted_by: 'saizo'"* ]]
    [[ "$output" == *"action_type: 'info'"* ]]
    [[ "$output" == *"actioned_by: ''"* ]]
    [[ "$output" == *"notify_targets:"* ]]
    [[ "$output" == *"confirmed_by: []"* ]]
}

@test "bulletin_write rejects agent-name content (argument order mistake)" {
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" gunshi karo
    [ "$status" -eq 1 ]
    [[ "$output" == *"argument order mistake"* ]]
}

@test "bulletin_write records action_required with empty actioned_by" {
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" saizo "対応要請" false action_required
    [ "$status" -eq 0 ]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"action_type: 'action_required'"* ]]
    [[ "$output" == *"actioned_by: ''"* ]]
}

@test "bulletin_write auto marks gunshi hole discovery as action_required" {
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=gunshi TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" gunshi "idle分析: 構造的穴発見。gate追加の改善提案として対応必要"
    [ "$status" -eq 0 ]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"posted_by: 'gunshi'"* ]]
    [[ "$output" == *"action_type: 'action_required'"* ]]
    [[ "$output" == *"actioned_by: ''"* ]]
}

@test "bulletin_write inserts bulletin event into memory DB after YAML write" {
    local memory_db="$TEST_TMPDIR/data/memory.db"
    create_memory_db_fixture "$memory_db"

    run env MEMORY_DB_LIVE_INSERT_SYNC=1 SHOGUN_MEMORY_DB="$memory_db" SHOGUN_MEMORY_DB_LIVE_ASYNC_LOCK="$TEST_TMPDIR/memory_db_live_insert.lock" SHOGUN_MEMORY_DB_LIVE_QUEUE_DIR="$TEST_TMPDIR/queue/memory_db_live_insert_queue" BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" saizo "cmd_2983 bulletin realtime searchable" false action_required
    [ "$status" -eq 0 ]
    [[ "$output" == blt_* ]]

    readarray -t result < <(python3 - "$memory_db" "$output" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
event_id = "bulletin:" + sys.argv[2].splitlines()[0]
row = conn.execute(
    "SELECT event_type, agent, direction, cmd_id, importance FROM events WHERE id = ?",
    (event_id,),
).fetchone()
if row is None:
    raise SystemExit(1)
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
    [ "${result[0]}" = "bulletin" ]
    [ "${result[1]}" = "saizo" ]
    [ "${result[2]}" = "action_required" ]
    [ "${result[3]}" = "cmd_2983" ]
    [ "${result[4]}" = "high" ]
    [ "${result[5]}" = "1" ]
}

@test "bulletin_write keeps YAML success when memory DB insert fails" {
    local broken_db="$TEST_TMPDIR/data/broken.db"
    mkdir -p "$(dirname "$broken_db")"
    printf 'not sqlite\n' > "$broken_db"

    run env SHOGUN_MEMORY_DB="$broken_db" BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "DB失敗でもYAML成功"
    [ "$status" -eq 0 ]
    [[ "$output" == blt_* ]]
    run grep -F "DB失敗でもYAML成功" "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
}

@test "bulletin_write accepts explicit posted_by from shared agent config" {
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=hayate TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" saizo "名義指定"
    [ "$status" -eq 0 ]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"posted_by: 'saizo'"* ]]
    [[ "$output" == *"名義指定"* ]]
}

@test "bulletin_write accepts explicit posted_by without tmux agent_id" {
    run env -u TMUX_PANE BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" PATH="/usr/bin:/bin" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" saizo "tmuxなし名義指定"
    [ "$status" -eq 0 ]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"posted_by: 'saizo'"* ]]
    [[ "$output" == *"tmuxなし名義指定"* ]]
}

@test "bulletin_write trims BULLETIN_NOTIFY targets before notifying" {
    export INBOX_WRITE_LOG="$TEST_TMPDIR/inbox_write.log"
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo BULLETIN_NOTIFY="shogun, gunshi" TMUX_PANE="$TMUX_PANE" PATH="$PATH" INBOX_WRITE_LOG="$INBOX_WRITE_LOG" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "通知確認"
    [ "$status" -eq 0 ]
    run cat "$INBOX_WRITE_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun|掲示板新規投稿("* ]]
    [[ "$output" == *"gunshi|掲示板新規投稿("* ]]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"notify_targets:"* ]]
    [[ "$output" == *"- 'shogun'"* ]]
    [[ "$output" == *"- 'gunshi'"* ]]
}

@test "bulletin_write prints entry id before watcher warning when watcher is absent" {
    export INBOX_WRITE_LOG="$TEST_TMPDIR/inbox_write.log"
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo BULLETIN_NOTIFY="shogun" TMUX_PANE="$TMUX_PANE" PATH="$PATH" INBOX_WRITE_LOG="$INBOX_WRITE_LOG" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "watcher不在"
    [ "$status" -eq 0 ]
    [[ "$output" == blt_* ]]
    [[ "$output" == *"[bulletin_write] WARN: inbox_watcher not running for shogun"* ]]
}

@test "bulletin_write rejects unknown requires_confirmation agents" {
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "確認先不正" "shogun, unknown_agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown requires_confirmation agent"* ]]
    [ ! -f "$TEST_TMPDIR/queue/bulletin_board.yaml" ]
}

@test "bulletin_write rejects unknown single requires_confirmation agent" {
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "確認先不正" "unknown_agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown requires_confirmation agent"* ]]
    [ ! -f "$TEST_TMPDIR/queue/bulletin_board.yaml" ]
}

@test "bulletin_write rejects misspelled explicit posted_by instead of writing malformed entry" {
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=hayate TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" saizoo "名義指定"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown requires_confirmation agent"* ]]
    [ ! -f "$TEST_TMPDIR/queue/bulletin_board.yaml" ]
}

@test "bulletin_write duplicate post does not notify again" {
    export INBOX_WRITE_LOG="$TEST_TMPDIR/inbox_write.log"
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo BULLETIN_NOTIFY="shogun,gunshi" TMUX_PANE="$TMUX_PANE" PATH="$PATH" INBOX_WRITE_LOG="$INBOX_WRITE_LOG" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "重複禁止"
    [ "$status" -eq 0 ]

    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo BULLETIN_NOTIFY="shogun,gunshi" TMUX_PANE="$TMUX_PANE" PATH="$PATH" INBOX_WRITE_LOG="$INBOX_WRITE_LOG" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "重複禁止"
    [ "$status" -eq 0 ]
    [[ "$output" == DEDUP:* ]]

    run wc -l "$INBOX_WRITE_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == "2 $INBOX_WRITE_LOG" ]]
}

@test "bulletin_write auto archives when bulletin exceeds threshold" {
    for i in $(seq 1 50); do
        env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo BULLETIN_NOTIFY="shogun" TMUX_PANE="$TMUX_PANE" PATH="$PATH" INBOX_WRITE_LOG="$TEST_TMPDIR/inbox_write.log" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "既存投稿 $i" >/dev/null
    done

    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo BULLETIN_NOTIFY="shogun" TMUX_PANE="$TMUX_PANE" PATH="$PATH" INBOX_WRITE_LOG="$TEST_TMPDIR/inbox_write.log" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "閾値超過投稿"
    [ "$status" -eq 0 ]

    run python3 - "$TEST_TMPDIR/queue/bulletin_board.yaml" "$TEST_TMPDIR/queue/archive/bulletin_$(date +%Y%m%d).yaml" <<'PY'
import sys
import yaml

board_path, archive_path = sys.argv[1:3]
with open(board_path, encoding="utf-8") as fh:
    board = yaml.safe_load(fh) or {}
with open(archive_path, encoding="utf-8") as fh:
    archive = yaml.safe_load(fh) or {}
print(f"board={len(board.get('entries', []))} archive={len(archive.get('entries', []))}")
PY
    [ "$status" -eq 0 ]
    [ "$output" = "board=30 archive=21" ]
}

@test "bulletin_write retries and fails closed when inbox_write fails" {
    cat > "$TEST_TMPDIR/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
    chmod +x "$TEST_TMPDIR/scripts/inbox_write.sh"

    local failure_log="$TEST_TMPDIR/logs/bulletin_notify_failures.yaml"
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_NOTIFY_FAILURE_LOG="$failure_log" BULLETIN_NOTIFY_RETRIES=3 BULLETIN_TEST_AGENT_ID=saizo BULLETIN_NOTIFY="shogun" TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "通知失敗"
    [ "$status" -eq 1 ]
    [[ "$output" == blt_* ]]
    [[ "$output" == *"ERROR: inbox_write failed for shogun after 3 attempts"* ]]
    [[ "$output" == *"command failed closed"* ]]
    [[ "$output" != *"inbox_watcher not running for shogun"* ]]
    [ "$(wc -l < "$failure_log")" -ge 6 ]
    run grep -F "target: 'shogun'" "$failure_log"
    [ "$status" -eq 0 ]
    run grep -F "attempts: 3" "$failure_log"
    [ "$status" -eq 0 ]
}

@test "bulletin_write succeeds after a transient notification failure" {
    cat > "$TEST_TMPDIR/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
state="${INBOX_RETRY_STATE:?}"
count=0
[ -f "$state" ] && count="$(cat "$state")"
count=$((count + 1))
printf '%s\n' "$count" > "$state"
[ "$count" -ge 2 ]
EOF
    chmod +x "$TEST_TMPDIR/scripts/inbox_write.sh"
    local retry_state="$TEST_TMPDIR/retry.count"
    local failure_log="$TEST_TMPDIR/logs/bulletin_notify_failures.yaml"
    run env INBOX_RETRY_STATE="$retry_state" BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_NOTIFY_FAILURE_LOG="$failure_log" BULLETIN_NOTIFY_RETRIES=3 BULLETIN_TEST_AGENT_ID=saizo BULLETIN_NOTIFY="shogun" TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "再送成功"
    [ "$status" -eq 0 ]
    [[ "$output" == blt_* ]]
    [ "$(cat "$retry_state")" -eq 2 ]
    [ ! -e "$failure_log" ]
}

@test "bulletin_write pins real inbox_write to bulletin root for INSIGHT_REPEAT notification" {
    mkdir -p "$TEST_TMPDIR/queue/inbox"
    printf 'messages: []\n' > "$TEST_TMPDIR/queue/inbox/shogun.yaml"
    local failure_log="$TEST_TMPDIR/logs/bulletin_notify_failures.yaml"
    local payload="INSIGHT_REPEAT: source=manual pending_count=3 threshold=3 latest=INS-probe priority=medium insight_summary=probe"

    # /proc/invalid simulates a leaked caller fixture root. bulletin_write must
    # override it and use its own root while executing the real inbox_write.
    run env \
        BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" \
        BULLETIN_INBOX_WRITE="$SRC_INBOX_WRITE" \
        BULLETIN_INBOX_WRITE_TEST=1 \
        BULLETIN_NOTIFY_FAILURE_LOG="$failure_log" \
        BULLETIN_NOTIFY_RETRIES=1 \
        BULLETIN_NOTIFY=shogun \
        INBOX_WRITE_ROOT_OVERRIDE=/proc/invalid \
        INBOX_WRITE_TEST=1 \
        PATH="$PATH" \
        bash "$TEST_TMPDIR/scripts/bulletin_write.sh" saizo "$payload" false action_required

    [ "$status" -eq 0 ]
    [ ! -e "$failure_log" ]
    run python3 - "$TEST_TMPDIR/queue/inbox/shogun.yaml" <<'PY'
import sys, yaml
messages = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("messages", [])
matches = [m for m in messages if m.get("type") == "bulletin_notify"]
print(len(matches))
print(matches[0]["from"] if matches else "")
print(matches[0].get("action", "") if matches else "")
print("INSIGHT_REPEAT" in matches[0]["content"] if matches else False)
PY
    [ "$status" -eq 0 ]
    [ "$output" = $'1\nsaizo\nbulletin_notify\nTrue' ]
}

@test "bulletin_confirm adds agent to confirmed_by" {
    entry_id="$(env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "確認対象")"
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" bash "$TEST_TMPDIR/scripts/bulletin_confirm.sh" saizo "$entry_id"
    [ "$status" -eq 0 ]
    [[ "$output" == *"|1|open" ]]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"- 'saizo'"* ]]
    [[ "$output" == *"action_type: 'info'"* ]]
    [[ "$output" == *"actioned_by: ''"* ]]
    [[ "$output" == *"status: 'open'"* ]]
}

@test "bulletin_confirm closes entry after all notify_targets confirm" {
    entry_id="$(env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo BULLETIN_NOTIFY='shogun' TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "将軍のみ通知")"
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" bash "$TEST_TMPDIR/scripts/bulletin_confirm.sh" shogun "$entry_id"
    [ "$status" -eq 0 ]
    [[ "$output" == *"|1|closed" ]]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"status: 'closed'"* ]]
}

@test "bulletin_confirm closes entry after all agents confirm" {
    entry_id="$(env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "全員確認" true)"
    for agent in shogun karo gunshi saizo; do
        run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" bash "$TEST_TMPDIR/scripts/bulletin_confirm.sh" "$agent" "$entry_id"
        [ "$status" -eq 0 ]
    done
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"- 'shogun'"* ]]
    [[ "$output" == *"- 'karo'"* ]]
    [[ "$output" == *"- 'gunshi'"* ]]
    [[ "$output" == *"- 'saizo'"* ]]
    [[ "$output" == *"status: 'closed'"* ]]
}

@test "bulletin_confirm closes old all-agent broadcast after posted_by plus one confirmation" {
    cat > "$TEST_TMPDIR/queue/bulletin_board.yaml" <<'EOF'
entries:
- id: 'blt_old_all'
  content: |-
    全員通知が古くなった
  posted_by: 'saizo'
  posted_at: '2026-06-26T00:00:00+00:00'
  requires_confirmation: false
  action_type: 'info'
  actioned_by: ''
  notify_targets: []
  confirmed_by:
    - 'saizo'
  status: 'open'
EOF
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_CONFIRM_NOW="2026-06-26T07:00:00+00:00" bash "$TEST_TMPDIR/scripts/bulletin_confirm.sh" shogun blt_old_all
    [ "$status" -eq 0 ]
    [[ "$output" == *"blt_old_all|2|closed"* ]]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"- 'saizo'"* ]]
    [[ "$output" == *"- 'shogun'"* ]]
    [[ "$output" == *"notify_targets: []"* ]]
    [[ "$output" == *"status: 'closed'"* ]]
}

@test "bulletin_close closes entry explicitly" {
    entry_id="$(env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "手動クローズ")"
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" bash "$TEST_TMPDIR/scripts/bulletin_close.sh" "$entry_id"
    [ "$status" -eq 0 ]
    [ "$output" = "$entry_id" ]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"action_type: 'info'"* ]]
    [[ "$output" == *"actioned_by: ''"* ]]
    [[ "$output" == *"status: 'closed'"* ]]
}

@test "bulletin_action closes action_required entry" {
    cp "$PROJECT_ROOT/scripts/bulletin_action.sh" "$TEST_TMPDIR/scripts/bulletin_action.sh"
    chmod +x "$TEST_TMPDIR/scripts/bulletin_action.sh"
    entry_id="$(env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" saizo "要対応" false action_required)"
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" bash "$TEST_TMPDIR/scripts/bulletin_action.sh" shogun "$entry_id"
    [ "$status" -eq 0 ]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"actioned_by: 'shogun'"* ]]
    [[ "$output" == *"status: 'closed'"* ]]
}
