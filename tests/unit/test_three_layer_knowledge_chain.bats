#!/usr/bin/env bats
# test_necessity: Worker persists semantic failure instead of silently dropping it and detached worker survives launcher exit; violation is BLOCK.

setup() {
    exec 8>"$BATS_FILE_TMPDIR/three-layer-chain-fixture.lock"
    flock -x 8
    export ROOT="$(mktemp -d)"
    mkdir -p "$ROOT/scripts" "$ROOT/state" "$ROOT/logs"
    cp "$BATS_TEST_DIRNAME/../../scripts/three_layer_knowledge_chain.sh" "$ROOT/scripts/"
    cat > "$ROOT/scripts/semantic_index_update.sh" <<'SH'
#!/usr/bin/env bash
exit "${SEMANTIC_EXIT:-0}"
SH
    chmod +x "$ROOT/scripts/semantic_index_update.sh"
    export CHAIN_LOG="$ROOT/logs/chain.log"
}

teardown() {
    find "$ROOT" -depth -delete
}

make_request() {
    local event_id="${1:-knowledge:test}" knowledge="${2:-durable [[chain]]}"
    export REQUEST="$ROOT/state/${event_id//:/_}.pending.json"
    jq -n \
        --arg event_id "$event_id" \
        --arg knowledge_b64 "$(printf '%s' "$knowledge" | base64 | tr -d '\n')" \
        --arg source_b64 "$(printf '%s' test-source | base64 | tr -d '\n')" \
        --arg chain_log "$CHAIN_LOG" \
        --arg semantic_update_cmd "$ROOT/scripts/semantic_index_update.sh" \
        '{event_id:$event_id,knowledge_b64:$knowledge_b64,source_b64:$source_b64,chain_log:$chain_log,semantic_update_cmd:$semantic_update_cmd}' \
        > "$REQUEST"
}

@test "worker persists PASS and Layer2/3 evidence" {
    make_request

    run env THREE_LAYER_CHAIN_RETRIES=1 bash "$ROOT/scripts/three_layer_knowledge_chain.sh" "$REQUEST"

    [ "$status" -eq 0 ]
    [ ! -e "$REQUEST" ]
    grep -q '^state=PASS$' "${REQUEST%.pending.json}.result"
    grep -q 'OK layer2_semantic_index_update event=knowledge:test' "$CHAIN_LOG"
    grep -q 'CANDIDATE layer3_obsidian_link_candidate event=knowledge:test target=chain' "$CHAIN_LOG"
}

@test "worker persists semantic failure instead of silently dropping it" {
    make_request

    run env SEMANTIC_EXIT=9 THREE_LAYER_CHAIN_RETRIES=1 THREE_LAYER_CHAIN_RETRY_SLEEP=0 \
        bash "$ROOT/scripts/three_layer_knowledge_chain.sh" "$REQUEST"

    [ "$status" -eq 0 ]
    [ ! -e "$REQUEST" ]
    grep -q '^state=FAIL$' "${REQUEST%.pending.json}.result"
    grep -q 'ERROR layer2_semantic_index_update_failed event=knowledge:test' "$CHAIN_LOG"
}

@test "detached worker survives launcher shell exit" {
    cat > "$ROOT/scripts/semantic_index_update.sh" <<'SH'
#!/usr/bin/env bash
sleep 0.2
exit 0
SH
    chmod +x "$ROOT/scripts/semantic_index_update.sh"
    make_request

    run bash -c 'nohup setsid env THREE_LAYER_CHAIN_RETRIES=1 bash "$1/scripts/three_layer_knowledge_chain.sh" "$2" >/dev/null 2>&1 </dev/null &' _ "$ROOT" "$REQUEST"
    [ "$status" -eq 0 ]
    for _ in {1..50}; do
        [ -f "${REQUEST%.pending.json}.result" ] && break
        sleep 0.05
    done

    grep -q '^state=PASS$' "${REQUEST%.pending.json}.result"
    [ ! -e "$REQUEST" ]
}

@test "knowledge writer creates durable pending request before setsid launch" {
    writer="$BATS_TEST_DIRNAME/../../scripts/memory_db_knowledge_write.sh"

    run python3 - "$writer" <<'PY'
import sys
text=open(sys.argv[1], encoding="utf-8").read()
assert 'pending_path="$chain_state_dir/${safe_event}.pending.json"' in text
assert 'mv "$pending_tmp" "$pending_path"' in text
assert 'nohup setsid env SHOGUN_HEAVY_JOB_LOCK_HELD=0' in text
assert '_three_layer_chain "$event_id"' not in text
PY
    [ "$status" -eq 0 ]
}

@test "knowledge cache incremental upsert is synchronous and exact" {
    run python3 - "$BATS_TEST_DIRNAME/../.." "$ROOT" <<'PY'
import sqlite3
import sys
from pathlib import Path

repo, root = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(repo / "scripts"))
import memory_db_live_insert as live

db = root / "memory.db"
cache = root / "lord_ruling_cache.db"
with sqlite3.connect(db) as conn:
    conn.execute("""CREATE TABLE events (
        id TEXT PRIMARY KEY, ts TEXT, event_type TEXT, agent TEXT, target TEXT,
        direction TEXT, summary TEXT, detail TEXT, cmd_id TEXT, concepts TEXT,
        raw_content TEXT
    )""")
    conn.execute(
        "INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?,?,?)",
        ("knowledge:exact", "2026-07-23T00:00:00", "knowledge", "kagemaru", "",
         "direct_insert", "exact", "durable", "cmd_test", '["cache"]',
         "durable [[cache]]"),
    )

live.upsert_lord_ruling_cache_event(str(cache), str(db), "knowledge:exact")
with sqlite3.connect(cache) as conn:
    row = conn.execute(
        "SELECT event_id, summary FROM lord_rulings WHERE event_id = ?",
        ("knowledge:exact",),
    ).fetchone()
assert row is not None and row[0] == "knowledge:exact" and "durable" in row[1], row
PY
    [ "$status" -eq 0 ]
}

@test "full rebuild cannot replace a concurrent incremental cache event with a stale snapshot" {
    run python3 - "$BATS_TEST_DIRNAME/../.." "$ROOT" <<'PY'
import sqlite3
import sys
import threading
from pathlib import Path

repo, root = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(repo / "scripts"))
import memory_db_import as importer
import memory_db_live_insert as live

db = root / "memory.db"
cache = root / "lord_ruling_cache.db"
with sqlite3.connect(db) as conn:
    conn.execute("""CREATE TABLE events (
        id TEXT PRIMARY KEY, ts TEXT, event_type TEXT, agent TEXT, target TEXT,
        direction TEXT, summary TEXT, detail TEXT, cmd_id TEXT, concepts TEXT,
        raw_content TEXT
    )""")
    conn.execute(
        "INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?,?,?)",
        ("knowledge:old", "2026-07-23T00:00:00", "knowledge", "kagemaru", "",
         "direct_insert", "old", "old", "cmd_test", "[]", "old"),
    )

snapshot_projecting = threading.Event()
release_rebuild = threading.Event()
original_project = importer._prompt_cache_summary
def paused_project(*args):
    snapshot_projecting.set()
    assert release_rebuild.wait(5)
    return original_project(*args)
importer._prompt_cache_summary = paused_project

rebuild = threading.Thread(target=importer.build_lord_ruling_cache, args=(cache, db))
rebuild.start()
assert snapshot_projecting.wait(5)
with sqlite3.connect(db) as conn:
    conn.execute(
        "INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?,?,?)",
        ("knowledge:new", "2026-07-23T00:00:01", "knowledge", "kagemaru", "",
         "direct_insert", "new", "new", "cmd_test", "[]", "new"),
    )

upsert = threading.Thread(
    target=live.upsert_lord_ruling_cache_event,
    args=(str(cache), str(db), "knowledge:new"),
)
upsert.start()
release_rebuild.set()
rebuild.join(5)
upsert.join(5)
assert not rebuild.is_alive() and not upsert.is_alive()
with sqlite3.connect(cache) as conn:
    count = conn.execute(
        "SELECT COUNT(*) FROM lord_rulings WHERE event_id = 'knowledge:new'"
    ).fetchone()[0]
assert count == 1, count
PY
    [ "$status" -eq 0 ]
}
