#!/usr/bin/env bash
# semantic-links: [[SQLite記憶DB]], [[三層記憶システム]], [[cmd_3715_1コマンド3層連鎖]]
# memory_db_knowledge_write.sh — Layer1 knowledge insert that auto-chains
# Layer2 (semantic_index_update.sh discussion) and Layer3 (Obsidian [[link]]
# candidate log) in a detached durable worker, without mailbox/bulletin side effects.
# Usage: bash scripts/memory_db_knowledge_write.sh "knowledge text" "source" [--db PATH] [--cmd-id CMD_ID]
#        echo "knowledge text" | bash scripts/memory_db_knowledge_write.sh - "source"
# THREE_LAYER_CHAIN_SYNC=1 forces the Layer2/3 chain to run synchronously (tests only).

set -euo pipefail

usage() {
    cat <<'EOF' >&2
Usage: memory_db_knowledge_write.sh "knowledge text" "source" [--db PATH] [--cmd-id CMD_ID]
       memory_db_knowledge_write.sh - "source" [--db PATH] [--cmd-id CMD_ID]

Writes a knowledge event directly to the local memory DB (Layer1), then
auto-chains semantic_index_update.sh discussion (Layer2) and an Obsidian
[[link]] candidate log (Layer3) through a durable pending request so the caller
returns at Layer1 latency. Chain failures and stale pending requests are exposed
by gate_three_layer_health.sh. It still does not
write bulletin, inbox, or any other communication channel itself.
EOF
}

if [[ $# -lt 2 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
knowledge_text="$1"
source_text="$2"
shift 2

db_path="${SHOGUN_MEMORY_DB:-$SCRIPT_DIR/data/multi_agent_shogun_memory.db}"
cmd_id=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            db_path="$2"
            shift 2
            ;;
        --cmd-id)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            cmd_id="$2"
            shift 2
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ "$knowledge_text" == "-" ]]; then
    knowledge_text="$(cat)"
fi

if [[ -z "${knowledge_text//[[:space:]]/}" ]]; then
    echo "ERROR: knowledge text is required" >&2
    exit 1
fi
if [[ -z "${source_text//[[:space:]]/}" ]]; then
    echo "ERROR: source is required" >&2
    exit 1
fi
if [[ ! -f "$db_path" ]]; then
    echo "ERROR: memory DB not found: $db_path" >&2
    exit 1
fi

agent_id="${AGENT_ID:-}"
if [[ -z "$agent_id" && -n "${TMUX_PANE:-}" ]]; then
    agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
fi
agent_id="${agent_id:-memory_db_knowledge_write}"

py_output="$(python3 - "$SCRIPT_DIR" "$db_path" "$knowledge_text" "$source_text" "$cmd_id" "$agent_id" <<'PY'
import hashlib
import os
import sqlite3
import sys
import time

repo_root, db_path, knowledge_text, source_text, cmd_id, agent_id = sys.argv[1:7]
sys.path.insert(0, f"{repo_root}/scripts")
import memory_db_live_insert as live_insert
import memory_db_import

if os.environ.get("MEMORY_DB_SEMANTIC_INDEX_PATH"):
    semantic_index_path = os.environ["MEMORY_DB_SEMANTIC_INDEX_PATH"]
    live_insert.DEFAULT_SEMANTIC_INDEX_PATH = semantic_index_path
    live_insert._SEMANTIC_CONCEPT_CACHE = live_insert.load_semantic_map_concept_cache(
        semantic_index_path=semantic_index_path,
    )

busy_timeout_ms = int(os.environ.get("MEMORY_DB_WRITE_BUSY_TIMEOUT_MS", "250"))
max_attempts = int(os.environ.get("MEMORY_DB_WRITE_MAX_ATTEMPTS", "5"))
retry_sleep_seconds = float(os.environ.get("MEMORY_DB_WRITE_RETRY_SLEEP_SECONDS", "0.05"))
if busy_timeout_ms <= 0 or max_attempts <= 0 or retry_sleep_seconds < 0:
    raise ValueError("memory DB write retry settings must be positive")
live_insert.SQLITE_BUSY_TIMEOUT_MS = busy_timeout_ms
knowledge = live_insert.normalize_text(knowledge_text)
source = live_insert.normalize_text(source_text)
explicit_cmd_id = live_insert.normalize_text(cmd_id)
agent = live_insert.normalize_text(agent_id) or "memory_db_knowledge_write"
ts = live_insert.now_timestamp()
summary = live_insert.summarize(knowledge) or "knowledge"
detail = "\n".join(
    line for line in [
        knowledge,
        f"source: {source}",
    ] if line
)
event_cmd_id = explicit_cmd_id or live_insert.infer_cmd_id(summary, detail)
event_hash = hashlib.sha1(f"{ts}\n{agent}\n{source}\n{knowledge}".encode("utf-8")).hexdigest()[:16]
event_id = f"knowledge:{event_hash}"

event_row = (
    event_id,
    ts,
    "knowledge",
    agent,
    "",
    "direct_insert",
    summary,
    detail,
    "memory_db_knowledge_write",
    event_cmd_id,
    "[]",
    source,
    None,
    "normal",
)

append_started = time.monotonic()
for attempt in range(1, max_attempts + 1):
    try:
        live_insert.append_event(
            db_path,
            event_row,
            concept_text_extra=f"{source}\n{event_cmd_id}",
            raw_content=knowledge,
        )
        break
    except sqlite3.OperationalError as exc:
        if "database is locked" not in str(exc).lower() or attempt == max_attempts:
            raise
        time.sleep(retry_sleep_seconds * (2 ** (attempt - 1)))
append_ms = (time.monotonic() - append_started) * 1000

cache_started = time.monotonic()
cache_path = memory_db_import.default_lord_ruling_cache_path(memory_db_import.Path(db_path))
live_insert.upsert_lord_ruling_cache_event(str(cache_path), db_path, event_id)
cache_ms = (time.monotonic() - cache_started) * 1000
if os.environ.get("MEMORY_DB_WRITE_TIMING", "0") == "1":
    print(
        f"TIMING append_ms={append_ms:.3f} cache_ms={cache_ms:.3f} attempts={attempt}",
        file=sys.stderr,
    )
print(f"OK: {event_id}")
PY
)"
printf '%s\n' "$py_output"
event_id="${py_output#OK: }"

# --- 三層貫通自動連鎖: durable Layer2/3 request + detached worker ---
chain_log="${THREE_LAYER_CHAIN_LOG:-$SCRIPT_DIR/logs/three_layer_chain_async.log}"
semantic_update_cmd="${THREE_LAYER_SEMANTIC_UPDATE_CMD:-$SCRIPT_DIR/scripts/semantic_index_update.sh}"
chain_state_dir="${THREE_LAYER_CHAIN_STATE_DIR:-$SCRIPT_DIR/logs/three_layer_chain_state}"
safe_event="${event_id//[^[:alnum:]_.-]/_}"
pending_path="$chain_state_dir/${safe_event}.pending.json"
worker="$SCRIPT_DIR/scripts/three_layer_knowledge_chain.sh"
mkdir -p "$chain_state_dir"
pending_tmp="${pending_path}.tmp.$$"
jq -n \
    --arg event_id "$event_id" \
    --arg knowledge_b64 "$(printf '%s' "$knowledge_text" | base64 | tr -d '\n')" \
    --arg source_b64 "$(printf '%s' "$source_text" | base64 | tr -d '\n')" \
    --arg chain_log "$chain_log" \
    --arg semantic_update_cmd "$semantic_update_cmd" \
    '{event_id:$event_id,knowledge_b64:$knowledge_b64,source_b64:$source_b64,chain_log:$chain_log,semantic_update_cmd:$semantic_update_cmd}' \
    > "$pending_tmp"
mv "$pending_tmp" "$pending_path"

if [[ "${THREE_LAYER_CHAIN_SYNC:-0}" == "1" ]]; then
    bash "$worker" "$pending_path"
else
    nohup setsid env SHOGUN_HEAVY_JOB_LOCK_HELD=0 \
        bash "$worker" "$pending_path" >/dev/null 2>&1 </dev/null &
fi

# --- L1/L2/L3 貫通可視化(将軍R6指示・軍師是正済みAC3反映) ---
# 制約: 新規gate/hook/状態ファイル追加禁止・BLOCKしない(fail-open)。
# 既存の pending/result ファイル(three_layer_knowledge_chain.sh が書く)に相乗りする。
# 出力1行目の "OK: <event_id>" は既存パーサー(自スクリプト内)互換のためそのまま維持する。
link_targets="$(grep -oP '(?<=\[\[)[^][]+(?=\]\])' <<< "$knowledge_text" 2>/dev/null | sort -u || true)"
if [[ -z "$link_targets" ]]; then
    # AC2: [[リンク]]欠落は可視WARNのみ(fail-open)。L3候補生成の唯一の入力は本文中の[[リンク]]である
    # (three_layer_knowledge_chain.sh の layer3_obsidian_link_candidate 抽出ロジックと同一パターン)。
    echo "WARN: 本文に[[リンク]]が無い。Layer3候補が0件になる見込み" >&2
    l3_status="WARN_NO_LINK(候補0件見込み)"
else
    l3_status="candidate見込み: $(tr '\n' ',' <<< "$link_targets" | sed 's/,$//')"
fi

# AC3是正(軍師指摘): L2は3状態表示。書込み直後は detached worker 委譲のため原理的に
# pending が正であり、これを「未貫通」と誤表示すると殿厳命2026-06-14の狼少年になる。
# THREE_LAYER_CHAIN_SYNC=1(tests only)の時だけ worker 完了を待っているため確定判定できる。
result_path="${pending_path%.pending.json}.result"
if [[ "${THREE_LAYER_CHAIN_SYNC:-0}" == "1" && -f "$result_path" ]]; then
    chain_state="$(awk -F= '/^state=/{print $2; exit}' "$result_path")"
    if [[ "$chain_state" == "PASS" ]]; then
        # alias層への実到達は semantic_search.sh の判定基準と同一にする
        # (/three-layer-penetrate: 出力先頭が MEMORY_DB_MATCH/NO_MATCH = alias層miss)。
        search_target="$(head -n1 <<< "$link_targets")"
        search_target="${search_target:-$event_id}"
        semantic_search_cmd="${THREE_LAYER_SEMANTIC_SEARCH_CMD:-$SCRIPT_DIR/scripts/semantic_search.sh}"
        if search_out="$(bash "$semantic_search_cmd" "$search_target" 2>/dev/null)"; then
            if [[ "$search_out" == MEMORY_DB_MATCH* || "$search_out" == NO_MATCH* ]]; then
                l2_status="semantic未貫通(alias層miss): $search_target"
            else
                l2_status="貫通(alias層ヒット): $search_target"
            fi
        else
            l2_status="判定不能(semantic_search実行失敗)"
        fi
    else
        l2_status="未貫通(chain失敗: ${chain_state:-unknown})"
    fi
else
    l2_status="pending(chain実行中。確定判定は bash scripts/gate_three_layer_health.sh または bash scripts/semantic_search.sh '<alias>' で後日確認せよ)"
fi

printf 'L1: 記憶DB書込み完了 event=%s\n' "$event_id"
printf 'L2: %s\n' "$l2_status"
printf 'L3: %s\n' "$l3_status"
