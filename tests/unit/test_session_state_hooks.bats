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

@test "SSH-001a: session_start_inject preserves compact_state 24h stale contract without date command" {
    export MOCK_AGENT_ID="saizo"
    cat > "$TEST_TMPDIR/queue/compact_state/saizo.yaml" <<'YAML'
timestamp: '2000-01-01T00:00:00Z'
summary: old compact
YAML

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"type\":\"startup\"}' | scripts/hooks/session_start_inject.sh"
    [ "$status" -eq 0 ]
    readarray -t stale_result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
ctx = json.loads(os.environ["OUTPUT_JSON"])["hookSpecificOutput"]["additionalContext"]
print("stale:" in ctx)
print("old compact" in ctx)
PY
)
    [ "${stale_result[0]}" = "True" ]
    [ "${stale_result[1]}" = "True" ]

    printf -v now_compact_ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1
    cat > "$TEST_TMPDIR/queue/compact_state/saizo.yaml" <<YAML
timestamp: '$now_compact_ts'
summary: fresh compact
YAML

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"type\":\"startup\"}' | scripts/hooks/session_start_inject.sh"
    [ "$status" -eq 0 ]
    readarray -t fresh_result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
ctx = json.loads(os.environ["OUTPUT_JSON"])["hookSpecificOutput"]["additionalContext"]
print("stale:" in ctx)
print("fresh compact" in ctx)
PY
)
    [ "${fresh_result[0]}" = "False" ]
    [ "${fresh_result[1]}" = "True" ]
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

@test "SSH-001d: session_start_inject injects gunshi auto idle actions" {
    export MOCK_AGENT_ID="gunshi"
    cat > "$TEST_TMPDIR/scripts/gates/gate_gunshi_startup.sh" <<'EOF'
#!/usr/bin/env bash
mkdir -p queue
cat > queue/auto_idle_actions.txt <<'ACTIONS'
# auto-generated by gate_gunshi_startup.sh
1. idle Step 3: 未自動化教訓のgate化を実施
ACTIONS
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
print("--- auto_idle_actions ---" in ctx)
print("idle Step 3: 未自動化教訓のgate化を実施" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
}

@test "SSH-002: prompt_state_inject exposes memory candidate counts for non-shogun" {
    export MOCK_AGENT_ID="saizo"
    mkdir -p "$TEST_TMPDIR/data"
    db_path="$TEST_TMPDIR/data/multi_agent_shogun_memory.db"
    python3 - "$db_path" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.executescript(
    """
    CREATE TABLE events (
        event_id TEXT PRIMARY KEY,
        state TEXT
    );
    INSERT INTO events (event_id, state) VALUES
      ('e1', 'obsidian_candidate'),
      ('e2', 'duplicate_candidate'),
      ('e3', 'contradiction_candidate');
    """
)
conn.commit()
conn.close()
PY

    run bash -c "cd '$TEST_TMPDIR' && export PROMPT_STATE_MEMORY_DB_PATH='$db_path' && printf '%s' '{\"prompt\":\"通常入力\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
ctx = json.loads(os.environ["OUTPUT_JSON"])["hookSpecificOutput"]["additionalContext"]
print("agent: saizo" in ctx)
print("--- memory_candidates ---" in ctx)
print("memory_candidate_pending: contradiction=1, duplicate=1, obsidian=1" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "True" ]
}

@test "SSH-002b: prompt_state_inject exposes memory db FTS5 matches for gunshi" {
    export MOCK_AGENT_ID="gunshi"
    mkdir -p "$TEST_TMPDIR/data"
    cache_path="$TEST_TMPDIR/data/lord_ruling_cache.db"
    python3 - "$cache_path" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.executescript(
    """
    CREATE TABLE lord_rulings (
        event_id TEXT PRIMARY KEY,
        ts TEXT,
        event_type TEXT,
        cmd_id TEXT,
        summary TEXT,
        detail TEXT
    );
    INSERT INTO lord_rulings (
        event_id, ts, event_type, cmd_id, summary, detail
    ) VALUES (
        'lord-1', '2026-06-04T14:00:00+09:00', 'conversation', 'cmd_3179',
        '三層記憶 全ロール開放', 'prompt_state_inject'
    );
    """
)
conn.commit()
conn.close()
PY

    run bash -c "cd '$TEST_TMPDIR' && export PROMPT_STATE_LORD_RULING_CACHE_PATH='$cache_path' && printf '%s' '{\"prompt\":\"三層記憶\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
ctx = json.loads(os.environ["OUTPUT_JSON"])["hookSpecificOutput"]["additionalContext"]
print("agent: gunshi" in ctx)
print("--- memory_db_fts5 ---" in ctx)
print("summary: 三層記憶 全ロール開放" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "True" ]
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
print("semantic_knowledgeの該当resource/議論を引用" in ctx)
print("semantic_dictionary_design" in ctx)
print("docs/research/semantic_index_design.md" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "True" ]
    [ "${result[3]}" = "True" ]
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

@test "SSH-003c2: prompt_state semantic cache is isolated per prompt" {
    export MOCK_AGENT_ID="shogun"
    semantic_mock="$TEST_TMPDIR/semantic_search_cache.sh"
    cat > "$semantic_mock" <<'EOF'
#!/usr/bin/env bash
printf 'result for %s\n' "$1"
EOF
    chmod +x "$semantic_mock"
    export PROMPT_STATE_SEMANTIC_SEARCH_CMD="$semantic_mock"

    prompt_one="cache prompt one"
    prompt_two="cache prompt two"
    hash_one="$(printf '%s' "$prompt_one" | sha256sum | awk '{print $1}')"
    hash_two="$(printf '%s' "$prompt_two" | sha256sum | awk '{print $1}')"
    rm -f "/tmp/prompt_state_semantic_cache_shogun" \
          "/tmp/prompt_state_semantic_cache_shogun_${hash_one}" \
          "/tmp/prompt_state_semantic_cache_shogun_${hash_two}"

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"prompt\":\"cache prompt one\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]
    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"prompt\":\"cache prompt two\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]

    [ -f "/tmp/prompt_state_semantic_cache_shogun_${hash_one}" ]
    [ -f "/tmp/prompt_state_semantic_cache_shogun_${hash_two}" ]
    [ ! -f "/tmp/prompt_state_semantic_cache_shogun" ]
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

@test "SSH-003e: prompt_state_inject injects lord ruling cache LIKE matches with limit 3" {
    export MOCK_AGENT_ID="shogun"
    mkdir -p "$TEST_TMPDIR/data"
    cache_path="$TEST_TMPDIR/data/lord_ruling_cache.db"
    python3 - "$cache_path" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.executescript(
    """
    CREATE TABLE lord_rulings (
        event_id TEXT PRIMARY KEY,
        ts TEXT,
        event_type TEXT,
        cmd_id TEXT,
        summary TEXT,
        detail TEXT
    );
    """
)
for idx in range(1, 5):
    conn.execute(
        """
        INSERT INTO lord_rulings (
            event_id, ts, event_type, cmd_id, summary, detail
        ) VALUES (?, ?, 'conversation', ?, ?, ?)
        """,
        (
            f"lord-{idx}",
            f"2026-05-25T19:0{idx}:00+09:00",
            f"cmd_{3000 + idx}",
            f"関連裁定 needlememory {idx}",
            f"detail needlememory {idx}",
        ),
    )
conn.execute(
    """
    INSERT INTO lord_rulings (
        event_id, ts, event_type, cmd_id, summary, detail
    ) VALUES ('old-1', '2026-05-25T18:10:00+09:00', 'conversation', 'cmd_2999',
              '古い needlememory should not appear by limit', 'detail needlememory')
    """
)
conn.commit()
conn.close()
PY

    run bash -c "cd '$TEST_TMPDIR' && export PROMPT_STATE_LORD_RULING_CACHE_PATH='$cache_path' && printf '%s' '{\"prompt\":\"needlememory の件\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
ctx = json.loads(os.environ["OUTPUT_JSON"])["hookSpecificOutput"]["additionalContext"]
print("--- memory_db_fts5 ---" in ctx)
print(ctx.count("summary: 関連裁定 needlememory"))
print("古い needlememory should not appear by limit" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "3" ]
    [ "${result[2]}" = "False" ]
}

@test "SSH-003f: prompt_state_inject searches lord ruling cache for 2 character chunks" {
    export MOCK_AGENT_ID="shogun"
    mkdir -p "$TEST_TMPDIR/data"
    cache_path="$TEST_TMPDIR/data/lord_ruling_cache.db"
    python3 - "$cache_path" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.executescript(
    """
    CREATE TABLE lord_rulings (
        event_id TEXT PRIMARY KEY,
        ts TEXT,
        event_type TEXT,
        cmd_id TEXT,
        summary TEXT,
        detail TEXT
    );
    INSERT INTO lord_rulings (
        event_id, ts, event_type, cmd_id, summary, detail
    ) VALUES ('lord-1', '2026-05-25T19:01:00+09:00', 'conversation', '',
              '配備完了', '配備');
    """
)
conn.commit()
conn.close()
PY

    run bash -c "cd '$TEST_TMPDIR' && export PROMPT_STATE_LORD_RULING_CACHE_PATH='$cache_path' && printf '%s' '{\"prompt\":\"配備\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
ctx = json.loads(os.environ["OUTPUT_JSON"])["hookSpecificOutput"]["additionalContext"]
print("summary: 配備完了" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
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
