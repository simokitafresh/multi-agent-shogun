#!/usr/bin/env bash
# semantic-links: [[SQLite記憶DB]], [[三層記憶システム]], [[cmd_3715_1コマンド3層連鎖]]
# memory_db_knowledge_write.sh — Layer1 knowledge insert that auto-chains
# Layer2 (semantic_index_update.sh discussion) and Layer3 (Obsidian [[link]]
# candidate log) in the background, without mailbox/bulletin side effects.
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
[[link]] candidate log (Layer3) in the background so the caller returns at
Layer1 latency. Chain failures are appended to logs/three_layer_chain_async.log
for startup-gate detection (gate_three_layer_health.sh). It still does not
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
import sqlite3
import sys
import time

repo_root, db_path, knowledge_text, source_text, cmd_id, agent_id = sys.argv[1:7]
sys.path.insert(0, f"{repo_root}/scripts")
import memory_db_live_insert as live_insert

live_insert.SQLITE_BUSY_TIMEOUT_MS = 1000
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

for attempt in range(1, 11):
    try:
        live_insert.append_event(
            db_path,
            event_row,
            concept_text_extra=f"{source}\n{event_cmd_id}",
            raw_content=knowledge,
        )
        break
    except sqlite3.OperationalError as exc:
        if "database is locked" not in str(exc).lower() or attempt == 10:
            raise
        time.sleep(1)
print(f"OK: {event_id}")
PY
)"
printf '%s\n' "$py_output"
event_id="${py_output#OK: }"

# --- 三層貫通自動連鎖: Layer2(セマンティック)+Layer3(Obsidianリンク候補ログ) ---
# 呼び出し側の体感をLayer1書込みと同等に保つため、既定ではバックグラウンド実行する。
chain_log="${THREE_LAYER_CHAIN_LOG:-$SCRIPT_DIR/logs/three_layer_chain_async.log}"
semantic_update_cmd="${THREE_LAYER_SEMANTIC_UPDATE_CMD:-$SCRIPT_DIR/scripts/semantic_index_update.sh}"

_three_layer_chain() {
    local _event_id="$1" _knowledge="$2" _source="$3" _chain_log="$4" _semantic_update_cmd="$5"
    local _ts
    _ts="$(date -Iseconds)"
    mkdir -p "$(dirname "$_chain_log")"

    # Layer2: セマンティックインデックス連携(discussion payload)
    local _payload
    _payload="$(jq -cn --arg ts "$_ts" --arg summary "$_knowledge" --arg detail "source: $_source" \
        '{"timestamp":$ts,"summary":$summary,"detail":$detail}' 2>/dev/null || true)"
    local _attempt=1 _max_attempts _sleep_sec _layer2_ok=0
    _max_attempts="${THREE_LAYER_CHAIN_RETRIES:-3}"
    _sleep_sec="${THREE_LAYER_CHAIN_RETRY_SLEEP:-2}"
    while [[ "$_attempt" -le "$_max_attempts" ]]; do
        if [[ -n "$_payload" ]] && bash "$_semantic_update_cmd" discussion "$_payload" >/dev/null 2>&1; then
            _layer2_ok=1
            break
        fi
        [[ "$_attempt" -lt "$_max_attempts" ]] && sleep "$_sleep_sec"
        _attempt=$((_attempt + 1))
    done
    if [[ "$_layer2_ok" != "1" ]]; then
        printf '%s ERROR layer2_semantic_index_update_failed event=%s source=%s\n' "$_ts" "$_event_id" "$_source" >> "$_chain_log"
    else
        # 成功も記録する: 失敗のみのログは「ログ不在=実行履歴なし」と「不在=無失敗」を区別できず、
        # 健全性チェックが連鎖未使用と誤読する(2026-07-07修正)
        printf '%s OK layer2_semantic_index_update event=%s source=%s\n' "$_ts" "$_event_id" "$_source" >> "$_chain_log"
    fi

    # Layer3: 知識テキスト中の[[リンク]]ターゲット候補をログ出力(実際の昇格はobsidian_promote_candidate.shが担う)
    local _targets
    _targets="$(grep -oP '(?<=\[\[)[^][]+(?=\]\])' <<< "$_knowledge" 2>/dev/null | sort -u || true)"
    if [[ -n "$_targets" ]]; then
        while IFS= read -r _target; do
            [[ -n "$_target" ]] || continue
            printf '%s CANDIDATE layer3_obsidian_link_candidate event=%s target=%s source=%s\n' \
                "$_ts" "$_event_id" "$_target" "$_source" >> "$_chain_log"
        done <<< "$_targets"
    fi
}

if [[ "${THREE_LAYER_CHAIN_SYNC:-0}" == "1" ]]; then
    _three_layer_chain "$event_id" "$knowledge_text" "$source_text" "$chain_log" "$semantic_update_cmd"
else
    _three_layer_chain "$event_id" "$knowledge_text" "$source_text" "$chain_log" "$semantic_update_cmd" &
    disown 2>/dev/null || true
fi
