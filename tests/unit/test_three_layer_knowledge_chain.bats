#!/usr/bin/env bats
# test_necessity: Worker persists semantic failure instead of silently dropping it and detached worker survives launcher exit; violation is BLOCK.
# test_necessity: memory_db_knowledge_write.sh L1/L2/L3 penetration visibility contract (cmd_karo_impl_r6_knowledge_write_penetration_visible_20260727) —
#   (1) missing [[link]] emits a visible WARN without blocking, (2) the async (default) path always reports L2 as pending
#   (never a false "未貫通" before the detached worker runs — the 2026-06-14 fail-open/no-decaying-WARN mandate), and
#   (3) THREE_LAYER_CHAIN_SYNC=1 resolves L2 to a definitive 貫通/未貫通 verdict using the same MEMORY_DB_MATCH/NO_MATCH
#   alias-miss criteria as /three-layer-penetrate. Regression on any of these three states is BLOCK.
# test_necessity: L3 wording aligned to the 2026-07-27 12:38 ruling (cmd_karo_hotfix_r6_l3_wording_ruling_align_20260727) —
#   candidate generation must never be displayed as completion. Default/async path shows "L1/L2完了・L3昇格待ち"
#   (never "L3貫通完了") until an independent grep of causal_index.tsv confirms the [[link]] is actually reachable.
#   Regression back to the old "candidate見込み" wording (which read as completion) is BLOCK.
# test_necessity: L3 must check EVERY [[link]] against causal_index.tsv column-1 exact match, not just the first
#   sorted candidate with a substring grep (fingerprint=8a287fc4, 2026-07-27 gunshi escalation) — a partially-reached
#   multi-link knowledge item must never display "L3貫通完了" while an unreached link remains, and a link name that
#   is merely a substring of an unrelated causal_index.tsv row must not count as reached. Regression is BLOCK.

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

setup_knowledge_write_fixture() {
    export KW_ROOT="$(mktemp -d)"
    mkdir -p "$KW_ROOT/logs" "$KW_ROOT/state"
    KW_DB="$KW_ROOT/memory.db"
    # 隔離fixture: data/multi_agent_shogun_memory.db(gitignore済み本番データ、CI checkoutには
    # 存在しない)へ依存せず、正本スキーマ(scripts/memory_db_import.py CREATE TABLE events /
    # events_fts)をここへ直接複製する。他fixture(test_semantic_index_update.bats等)と同一方針。
    python3 - "$KW_DB" <<'PY'
import sqlite3, sys
dst_path = sys.argv[1]
dst = sqlite3.connect(dst_path)
dst.executescript(
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
        parent_event_id INTEGER,
        importance TEXT,
        confidence TEXT DEFAULT 'medium',
        freshness TEXT DEFAULT 'current',
        source_type TEXT DEFAULT 'fact',
        state TEXT DEFAULT 'raw',
        occurred_at TEXT,
        recorded_at TEXT,
        updated_at TEXT
    );
    CREATE VIRTUAL TABLE events_fts USING fts5(
        summary,
        detail,
        content='events',
        content_rowid='rowid',
        tokenize='trigram'
    );
    """
)
dst.commit()
PY
    cat > "$KW_ROOT/mock_semantic_update.sh" <<'SH'
#!/usr/bin/env bash
exit "${SEMANTIC_EXIT:-0}"
SH
    chmod +x "$KW_ROOT/mock_semantic_update.sh"
}

teardown_knowledge_write_fixture() {
    find "$KW_ROOT" -depth -delete 2>/dev/null || true
}

@test "knowledge writer emits visible WARN when body has no [[link]] (fail-open, no BLOCK)" {
    setup_knowledge_write_fixture
    run env SHOGUN_MEMORY_DB="$KW_DB" THREE_LAYER_CHAIN_LOG="$KW_ROOT/logs/chain.log" \
        THREE_LAYER_CHAIN_STATE_DIR="$KW_ROOT/state" \
        bash "$BATS_TEST_DIRNAME/../../scripts/memory_db_knowledge_write.sh" \
        "fixture body without a link" "kw-fixture-nolink"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 本文に[[リンク]]が無い"* ]]
    [[ "$output" == *"L3: WARN_NO_LINK"* ]]
    teardown_knowledge_write_fixture
}

@test "knowledge writer reports L2 as pending on the default async path (never a premature 未貫通)" {
    setup_knowledge_write_fixture
    mkdir -p "$KW_ROOT/.cache"
    : > "$KW_ROOT/.cache/causal_index.tsv"
    run env SHOGUN_MEMORY_DB="$KW_DB" THREE_LAYER_CHAIN_LOG="$KW_ROOT/logs/chain.log" \
        THREE_LAYER_CHAIN_STATE_DIR="$KW_ROOT/state" \
        THREE_LAYER_SEMANTIC_UPDATE_CMD="$KW_ROOT/mock_semantic_update.sh" \
        THREE_LAYER_CAUSAL_INDEX_PATH="$KW_ROOT/.cache/causal_index.tsv" \
        bash "$BATS_TEST_DIRNAME/../../scripts/memory_db_knowledge_write.sh" \
        "fixture body with [[mock_concept]]" "kw-fixture-pending"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L2: pending"* ]]
    [[ "$output" != *"未貫通"* ]]
    [[ "$output" == *"L3: L1/L2完了・L3昇格待ち(到達0/1件。未到達: mock_concept"* ]]
    # 案内文自体に「L3貫通完了」という語が含まれるため、部分一致ではなくL3行の先頭語で確定判定と区別する
    [[ "$(grep '^L3:' <<< "$output")" != "L3: L3貫通完了"* ]]
    teardown_knowledge_write_fixture
}

@test "knowledge writer L3 pending guidance cites a real awk command against an existing causal_index.tsv" {
    setup_knowledge_write_fixture
    mkdir -p "$KW_ROOT/.cache"
    : > "$KW_ROOT/.cache/causal_index.tsv"
    run env SHOGUN_MEMORY_DB="$KW_DB" THREE_LAYER_CHAIN_LOG="$KW_ROOT/logs/chain.log" \
        THREE_LAYER_CHAIN_STATE_DIR="$KW_ROOT/state" \
        THREE_LAYER_SEMANTIC_UPDATE_CMD="$KW_ROOT/mock_semantic_update.sh" \
        THREE_LAYER_CAUSAL_INDEX_PATH="$KW_ROOT/.cache/causal_index.tsv" \
        bash "$BATS_TEST_DIRNAME/../../scripts/memory_db_knowledge_write.sh" \
        "fixture body with [[mock_concept]]" "kw-fixture-pending-guidance"
    [ "$status" -eq 0 ]
    [[ "$output" == *"awk -F"*"$KW_ROOT/.cache/causal_index.tsv"* ]]
    # 軍師指摘(msg_20260727_131926): 案内文中のパスは実在確認せよ。L2案内(gate_three_layer_health.sh)も同様に実在すること。
    [ -f "$BATS_TEST_DIRNAME/../../scripts/gates/gate_three_layer_health.sh" ]
    [ -f "$KW_ROOT/.cache/causal_index.tsv" ]
    teardown_knowledge_write_fixture
}

@test "knowledge writer resolves L3 to 貫通完了 when the link already exists in causal_index.tsv" {
    setup_knowledge_write_fixture
    mkdir -p "$KW_ROOT/.cache"
    printf 'mock_link_existing\tsome_row\n' > "$KW_ROOT/.cache/causal_index.tsv"
    run env SHOGUN_MEMORY_DB="$KW_DB" THREE_LAYER_CHAIN_LOG="$KW_ROOT/logs/chain.log" \
        THREE_LAYER_CHAIN_STATE_DIR="$KW_ROOT/state" \
        THREE_LAYER_SEMANTIC_UPDATE_CMD="$KW_ROOT/mock_semantic_update.sh" \
        THREE_LAYER_CAUSAL_INDEX_PATH="$KW_ROOT/.cache/causal_index.tsv" \
        bash "$BATS_TEST_DIRNAME/../../scripts/memory_db_knowledge_write.sh" \
        "fixture body with [[mock_link_existing]]" "kw-fixture-l3-complete"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L3: L3貫通完了(1/1件): mock_link_existing"* ]]
    teardown_knowledge_write_fixture
}

@test "knowledge writer L3 reports partial reach across multiple [[links]] without false-completing on prefix match" {
    setup_knowledge_write_fixture
    mkdir -p "$KW_ROOT/.cache"
    # 軍師是正(msg_20260727_133945・fingerprint=8a287fc4)の再発防止契約:
    # (1) 複数[[リンク]]のうち一部だけ到達していても「貫通完了」を名乗らない
    # (2) causal_index.tsv第1列の完全一致で判定し、一般語の部分一致(行内サブストリング)でヒットさせない
    printf 'rules\tsome_file\nsome_other_rules_reference\tfile_x\n' > "$KW_ROOT/.cache/causal_index.tsv"
    run env SHOGUN_MEMORY_DB="$KW_DB" THREE_LAYER_CHAIN_LOG="$KW_ROOT/logs/chain.log" \
        THREE_LAYER_CHAIN_STATE_DIR="$KW_ROOT/state" \
        THREE_LAYER_SEMANTIC_UPDATE_CMD="$KW_ROOT/mock_semantic_update.sh" \
        THREE_LAYER_CAUSAL_INDEX_PATH="$KW_ROOT/.cache/causal_index.tsv" \
        bash "$BATS_TEST_DIRNAME/../../scripts/memory_db_knowledge_write.sh" \
        "多リンク検証 [[rules]](到達済) と [[zzz_gunshi_unreached_20260727]](未到達)" "kw-fixture-partial-reach"
    [ "$status" -eq 0 ]
    [[ "$(grep '^L3:' <<< "$output")" != "L3: L3貫通完了"* ]]
    [[ "$output" == *"到達1/2件"* ]]
    [[ "$output" == *"未到達: zzz_gunshi_unreached_20260727"* ]]
    teardown_knowledge_write_fixture
}

@test "knowledge writer resolves L2 to 貫通 when SYNC=1 and alias layer hits" {
    setup_knowledge_write_fixture
    cat > "$KW_ROOT/mock_search_hit.sh" <<'SH'
#!/usr/bin/env bash
echo "## mock_concept — fixture concept"
SH
    chmod +x "$KW_ROOT/mock_search_hit.sh"
    run env SHOGUN_MEMORY_DB="$KW_DB" THREE_LAYER_CHAIN_LOG="$KW_ROOT/logs/chain.log" \
        THREE_LAYER_CHAIN_STATE_DIR="$KW_ROOT/state" THREE_LAYER_CHAIN_SYNC=1 \
        THREE_LAYER_SEMANTIC_UPDATE_CMD="$KW_ROOT/mock_semantic_update.sh" \
        THREE_LAYER_SEMANTIC_SEARCH_CMD="$KW_ROOT/mock_search_hit.sh" \
        bash "$BATS_TEST_DIRNAME/../../scripts/memory_db_knowledge_write.sh" \
        "fixture body with [[mock_concept]]" "kw-fixture-hit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L2: 貫通(alias層ヒット): mock_concept"* ]]
    teardown_knowledge_write_fixture
}

@test "knowledge writer resolves L2 to semantic未貫通 when SYNC=1 and alias layer misses" {
    setup_knowledge_write_fixture
    cat > "$KW_ROOT/mock_search_miss.sh" <<'SH'
#!/usr/bin/env bash
echo "NO_MATCH: $1"
SH
    chmod +x "$KW_ROOT/mock_search_miss.sh"
    run env SHOGUN_MEMORY_DB="$KW_DB" THREE_LAYER_CHAIN_LOG="$KW_ROOT/logs/chain.log" \
        THREE_LAYER_CHAIN_STATE_DIR="$KW_ROOT/state" THREE_LAYER_CHAIN_SYNC=1 \
        THREE_LAYER_SEMANTIC_UPDATE_CMD="$KW_ROOT/mock_semantic_update.sh" \
        THREE_LAYER_SEMANTIC_SEARCH_CMD="$KW_ROOT/mock_search_miss.sh" \
        bash "$BATS_TEST_DIRNAME/../../scripts/memory_db_knowledge_write.sh" \
        "fixture body with [[mock_concept_miss]]" "kw-fixture-miss"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L2: semantic未貫通(alias層miss): mock_concept_miss"* ]]
    teardown_knowledge_write_fixture
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

# test_necessity: 型十五弾-6 の不変量 — 本文が名指す "commit <hash>" が repo に存在しない時は必ず WARN を出し(反映前通知の検出)、存在する hash には WARN を出さない。BLOCK にはしない(fail-open)。
@test "knowledge writer WARNs on a named commit hash that does not exist in the repo, and stays silent for an existing one" {
    setup_knowledge_write_fixture
    local existing
    existing="$(git -C "$BATS_TEST_DIRNAME/../.." rev-parse --short HEAD)"
    run env SHOGUN_MEMORY_DB="$KW_DB" THREE_LAYER_CHAIN_LOG="$KW_ROOT/logs/chain.log" \
        THREE_LAYER_CHAIN_STATE_DIR="$KW_ROOT/state" \
        bash "$BATS_TEST_DIRNAME/../../scripts/memory_db_knowledge_write.sh" \
        "[[fixture]] 設計書を commit deadbeef01 で反映、map は commit ${existing}" "kw-fixture-hash"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: knowledge text names commit deadbeef01"* ]]
    [[ "$output" != *"names commit ${existing}"* ]]
    teardown_knowledge_write_fixture
}
