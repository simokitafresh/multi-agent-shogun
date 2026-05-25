#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SESSION_START_SCRIPT="$PROJECT_ROOT/scripts/hooks/session_start_inject.sh"
    export PROMPT_STATE_SCRIPT="$PROJECT_ROOT/scripts/hooks/prompt_state_inject.sh"
    export SESSION_END_SCRIPT="$PROJECT_ROOT/scripts/hooks/session_end_clear_check.sh"
    [ -f "$SESSION_START_SCRIPT" ] || return 1
    [ -f "$PROMPT_STATE_SCRIPT" ] || return 1
    [ -f "$SESSION_END_SCRIPT" ] || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/session_hooks.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/hooks" "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/queue/inbox" "$TEST_TMPDIR/queue/compact_state"

    ln -s "$SESSION_START_SCRIPT" "$TEST_TMPDIR/scripts/hooks/session_start_inject.sh"
    ln -s "$PROMPT_STATE_SCRIPT" "$TEST_TMPDIR/scripts/hooks/prompt_state_inject.sh"
    ln -s "$SESSION_END_SCRIPT" "$TEST_TMPDIR/scripts/hooks/session_end_clear_check.sh"

    export MOCK_BIN="$TEST_TMPDIR/mock_bin"
    mkdir -p "$MOCK_BIN"
    cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"display-message"* ]]; then
    echo "${MOCK_AGENT_ID:-unknown}"
    exit 0
fi
exit 0
EOF
    chmod +x "$MOCK_BIN/tmux"

    export PATH="$MOCK_BIN:$PATH"
    export TMUX_PANE="%0"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

shadow_missing_jq() {
    cat > "$MOCK_BIN/jq" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$MOCK_BIN/jq"
}

@test "SSH-001: session_start_inject injects agent, unread count, and snapshot" {
    export MOCK_AGENT_ID="saizo"
    cat > "$TEST_TMPDIR/queue/inbox/saizo.yaml" <<'YAML'
messages:
  - content: one
    read: false
  - content: two
    read: true
YAML
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<'EOF'
snapshot line
EOF
    cat > "$TEST_TMPDIR/queue/compact_state/saizo.yaml" <<'YAML'
timestamp: '2026-04-18T11:00:00+09:00'
summary: compact ok
YAML

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"type\":\"startup\"}' | scripts/hooks/session_start_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
obj = json.loads(os.environ["OUTPUT_JSON"])
ctx = obj["hookSpecificOutput"]["additionalContext"]
print("agent: saizo" in ctx)
print("inbox_unread: 1" in ctx)
print("snapshot line" in ctx)
print("source: startup" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "True" ]
    [ "${result[3]}" = "True" ]
}

@test "SSH-001b: session_start_inject runs karo startup gate and injects output" {
    export MOCK_AGENT_ID="karo"
    cat > "$TEST_TMPDIR/scripts/gates/gate_karo_startup.sh" <<'EOF'
#!/usr/bin/env bash
echo "=== 家老起動チェック fake ==="
EOF
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_karo_startup.sh"

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"type\":\"startup\"}' | scripts/hooks/session_start_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
obj = json.loads(os.environ["OUTPUT_JSON"])
ctx = obj["hookSpecificOutput"]["additionalContext"]
print("startup_gate: gate_karo_startup.sh" in ctx)
print("=== 家老起動チェック fake ===" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
}

@test "SSH-001c: session_start_inject runs gunshi startup gate and injects output" {
    export MOCK_AGENT_ID="gunshi"
    cat > "$TEST_TMPDIR/scripts/gates/gate_gunshi_startup.sh" <<'EOF'
#!/usr/bin/env bash
echo "=== 軍師起動チェック fake ==="
EOF
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_gunshi_startup.sh"

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"type\":\"startup\"}' | scripts/hooks/session_start_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
obj = json.loads(os.environ["OUTPUT_JSON"])
ctx = obj["hookSpecificOutput"]["additionalContext"]
print("startup_gate: gate_gunshi_startup.sh" in ctx)
print("=== 軍師起動チェック fake ===" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
}

@test "SSH-002: prompt_state_inject returns nothing for non-shogun" {
    export MOCK_AGENT_ID="saizo"
    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"prompt\":\"通常入力\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "SSH-003: prompt_state_inject warns shogun about unread inbox" {
    export MOCK_AGENT_ID="shogun"
    cat > "$TEST_TMPDIR/queue/inbox/shogun.yaml" <<'YAML'
messages:
  - content: one
    read: false
YAML
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<'EOF'
snapshot line
EOF

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"prompt\":\"通常入力\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
obj = json.loads(os.environ["OUTPUT_JSON"])
ctx = obj["hookSpecificOutput"]["additionalContext"]
print("agent: shogun" in ctx)
print("⚠️ INBOX 1件未読" in ctx)
print("snapshot line" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "True" ]
}

@test "SSH-003b: prompt_state_inject injects semantic_search result for shogun prompt" {
    export MOCK_AGENT_ID="shogun"
    semantic_mock="$TEST_TMPDIR/semantic_search_mock.sh"
    cat > "$semantic_mock" <<'EOF'
#!/usr/bin/env bash
printf 'query=%s\n' "$*" > "$SEMANTIC_MOCK_LOG"
cat <<'OUT'
## semantic_dictionary_design — セマンティック辞書構想
matched: 意味検索
resources:
- file: `docs/research/semantic_index_design.md`
OUT
EOF
    chmod +x "$semantic_mock"
    export PROMPT_STATE_SEMANTIC_SEARCH_CMD="$semantic_mock"
    export SEMANTIC_MOCK_LOG="$TEST_TMPDIR/semantic_query.log"

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"prompt\":\"意味検索を使えるか？\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
obj = json.loads(os.environ["OUTPUT_JSON"])
ctx = obj["hookSpecificOutput"]["additionalContext"]
print("--- semantic_knowledge ---" in ctx)
print("semantic_dictionary_design" in ctx)
print("docs/research/semantic_index_design.md" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "True" ]
    [ "$(cat "$SEMANTIC_MOCK_LOG")" = "query=意味検索を使えるか？" ]
}

@test "SSH-003c: prompt_state_inject omits semantic section when semantic_search has no matches" {
    export MOCK_AGENT_ID="shogun"
    semantic_mock="$TEST_TMPDIR/semantic_search_nomatch.sh"
    cat > "$semantic_mock" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$semantic_mock"
    export PROMPT_STATE_SEMANTIC_SEARCH_CMD="$semantic_mock"

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"prompt\":\"未知の入力\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
obj = json.loads(os.environ["OUTPUT_JSON"])
ctx = obj["hookSpecificOutput"]["additionalContext"]
print("--- semantic_knowledge ---" in ctx)
PY
)
    [ "${result[0]}" = "False" ]
}

@test "SSH-003d: prompt_state_inject records semantic NO_MATCH count without prompt text" {
    export MOCK_AGENT_ID="shogun"
    semantic_mock="$TEST_TMPDIR/semantic_search_nomatch.sh"
    cat > "$semantic_mock" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$semantic_mock"
    export PROMPT_STATE_SEMANTIC_SEARCH_CMD="$semantic_mock"
    export PROMPT_STATE_SEMANTIC_NO_MATCH_FILE="$TEST_TMPDIR/logs/semantic_no_match_metrics.log"

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"prompt\":\"秘密の未知クエリ\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]
    [ -f "$PROMPT_STATE_SEMANTIC_NO_MATCH_FILE" ]

    run cat "$PROMPT_STATE_SEMANTIC_NO_MATCH_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"source=prompt_state_inject.sh"* ]]
    [[ "$output" == *"agent_id=shogun"* ]]
    [[ "$output" == *"count=1"* ]]
    [[ "$output" != *"秘密の未知クエリ"* ]]
}

@test "SSH-003e: prompt_state_inject injects lord memory DB FTS5 matches with limit 3" {
    export MOCK_AGENT_ID="shogun"
    mkdir -p "$TEST_TMPDIR/data"
    db_path="$TEST_TMPDIR/data/multi_agent_shogun_memory.db"
    python3 - "$db_path" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.executescript(
    """
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
        parent_event_id TEXT,
        importance TEXT
    );
    CREATE VIRTUAL TABLE events_fts USING fts5(summary, detail, content='events', content_rowid='rowid');
    """
)
for idx in range(1, 5):
    conn.execute(
        """
        INSERT INTO events (
            id, ts, event_type, agent, target, direction, summary, detail,
            session_id, cmd_id, concepts, source_file, parent_event_id, importance
        ) VALUES (?, ?, 'conversation', 'lord', 'shogun', 'inbound', ?, ?, '', ?, '', '', '', 'high')
        """,
        (
            f"lord-{idx}",
            f"2026-05-25T19:0{idx}:00+09:00",
            f"関連裁定 needlememory {idx}",
            f"detail needlememory {idx}",
            f"cmd_{3000 + idx}",
        ),
    )
    rowid = conn.execute("SELECT rowid FROM events WHERE id = ?", (f"lord-{idx}",)).fetchone()[0]
    conn.execute(
        "INSERT INTO events_fts(rowid, summary, detail) VALUES (?, ?, ?)",
        (rowid, f"関連裁定 needlememory {idx}", f"detail needlememory {idx}"),
    )
conn.execute(
    """
    INSERT INTO events (
        id, ts, event_type, agent, target, direction, summary, detail,
        session_id, cmd_id, concepts, source_file, parent_event_id, importance
    ) VALUES ('shogun-1', '2026-05-25T19:10:00+09:00', 'conversation', 'shogun', 'lord', 'response',
              'shogun needlememory should not appear', 'detail needlememory', '', 'cmd_3999', '', '', '', 'high')
    """
)
rowid = conn.execute("SELECT rowid FROM events WHERE id = 'shogun-1'").fetchone()[0]
conn.execute(
    "INSERT INTO events_fts(rowid, summary, detail) VALUES (?, 'shogun needlememory should not appear', 'detail needlememory')",
    (rowid,),
)
conn.commit()
conn.close()
PY

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"prompt\":\"needlememory の件\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
ctx = json.loads(os.environ["OUTPUT_JSON"])["hookSpecificOutput"]["additionalContext"]
print("--- memory_db_fts5 ---" in ctx)
print(ctx.count("summary: 関連裁定 needlememory"))
print("shogun needlememory should not appear" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "3" ]
    [ "${result[2]}" = "False" ]
}

@test "SSH-003f: prompt_state_inject skips memory DB FTS5 for prompts shorter than 5 chars" {
    export MOCK_AGENT_ID="shogun"
    mkdir -p "$TEST_TMPDIR/data"
    db_path="$TEST_TMPDIR/data/multi_agent_shogun_memory.db"
    python3 - "$db_path" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.executescript(
    """
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
        parent_event_id TEXT,
        importance TEXT
    );
    CREATE VIRTUAL TABLE events_fts USING fts5(summary, detail, content='events', content_rowid='rowid');
    INSERT INTO events (
        id, ts, event_type, agent, target, direction, summary, detail,
        session_id, cmd_id, concepts, source_file, parent_event_id, importance
    ) VALUES ('lord-1', '2026-05-25T19:01:00+09:00', 'conversation', 'lord', 'shogun', 'inbound',
              'abcd', 'abcd', '', '', '', '', '', 'high');
    INSERT INTO events_fts(rowid, summary, detail) VALUES (1, 'abcd', 'abcd');
    """
)
conn.commit()
conn.close()
PY

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"prompt\":\"abcd\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
ctx = json.loads(os.environ["OUTPUT_JSON"])["hookSpecificOutput"]["additionalContext"]
print("--- memory_db_fts5 ---" in ctx)
PY
)
    [ "${result[0]}" = "False" ]
}

@test "SSH-004: session_end_clear_check is silent for non-shogun" {
    export MOCK_AGENT_ID="saizo"
    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{}' | scripts/hooks/session_end_clear_check.sh"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "SSH-005: session_end_clear_check reports OK for shogun when checks pass" {
    export MOCK_AGENT_ID="shogun"
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"direction":"inbound"}
EOF
    mkdir -p "$TEST_TMPDIR/scripts"
    cat > "$TEST_TMPDIR/scripts/clear_prep_check.sh" <<'EOF'
#!/usr/bin/env bash
echo "[STATUS] OK"
echo "[INFO] clean"
EOF
    cat > "$TEST_TMPDIR/scripts/ntfy.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "${NTFY_LOG:?}"
EOF
    chmod +x "$TEST_TMPDIR/scripts/clear_prep_check.sh" "$TEST_TMPDIR/scripts/ntfy.sh"
    export NTFY_LOG="$TEST_TMPDIR/ntfy.log"

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{}' | SESSION_END_LORD_CONVERSATION_FILE='$TEST_TMPDIR/queue/lord_conversation.jsonl' SESSION_END_CLEAR_PREP_CMD='$TEST_TMPDIR/scripts/clear_prep_check.sh' SESSION_END_NTFY_CMD='$TEST_TMPDIR/scripts/ntfy.sh' scripts/hooks/session_end_clear_check.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "OK: session_end_clear_check (shogun)" ]
    run cat "$NTFY_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"【SessionEnd 報告】/clear前確認"* ]]
}

@test "bash_state_hook PreToolUse updates agent_state and bash_running_since with one tmux invocation" {
    export TMUX_LOG="$TEST_TMPDIR/tmux.log"
    cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$TMUX_LOG"
EOF
    chmod +x "$MOCK_BIN/tmux"

    run bash -c 'printf "%s" "{\"hook_event_name\":\"PreToolUse\"}" | "$1"' _ "$PROJECT_ROOT/scripts/hooks/bash_state_hook.sh"

    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TMUX_LOG" | tr -d ' ')" -eq 1 ]
    grep -q '@agent_state bash_running' "$TMUX_LOG"
    grep -q '@bash_running_since' "$TMUX_LOG"
}

@test "bash_state_hook PostToolUse restores agent_state and clears bash_running_since with one tmux invocation" {
    export TMUX_LOG="$TEST_TMPDIR/tmux.log"
    cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$TMUX_LOG"
EOF
    chmod +x "$MOCK_BIN/tmux"

    run bash -c 'printf "%s" "{\"hook_event_name\":\"PostToolUse\"}" | "$1"' _ "$PROJECT_ROOT/scripts/hooks/bash_state_hook.sh"

    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TMUX_LOG" | tr -d ' ')" -eq 1 ]
    grep -q '@agent_state active' "$TMUX_LOG"
    grep -q '@bash_running_since' "$TMUX_LOG"
}

@test "SSH-006: session_start_inject emits JSON without jq" {
    shadow_missing_jq
    export MOCK_AGENT_ID="saizo"
    cat > "$TEST_TMPDIR/queue/inbox/saizo.yaml" <<'YAML'
messages:
  - content: one
    read: false
YAML

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"type\":\"startup\"}' | scripts/hooks/session_start_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
obj = json.loads(os.environ["OUTPUT_JSON"])
ctx = obj["hookSpecificOutput"]["additionalContext"]
print("agent: saizo" in ctx)
print("inbox_unread: 1" in ctx)
print("source: startup" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "True" ]
}

@test "SSH-007: prompt_state_inject emits JSON without jq" {
    shadow_missing_jq
    export MOCK_AGENT_ID="shogun"
    cat > "$TEST_TMPDIR/queue/inbox/shogun.yaml" <<'YAML'
messages:
  - content: one
    read: false
YAML

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"prompt\":\"通常入力\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
obj = json.loads(os.environ["OUTPUT_JSON"])
ctx = obj["hookSpecificOutput"]["additionalContext"]
print("agent: shogun" in ctx)
print("⚠️ INBOX 1件未読" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
}
