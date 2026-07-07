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

_three_layer_sanitize_detail() {
    local _text="$1"
    _text="${_text//$'\r'/ }"
    _text="${_text//$'\n'/ }"
    _text="${_text//$'\t'/ }"
    _text="${_text//\\/\\\\}"
    _text="${_text//\"/\\\"}"
    printf '%s' "${_text:0:240}"
}

_three_layer_payload_b64() {
    printf '%s' "$1" | base64 | tr -d '\n'
}

_three_layer_run_semantic_update() {
    local _semantic_update_cmd="$1" _payload="$2"
    local _attempt=1 _max_attempts _sleep_sec _tmp_out _tmp_err _combined
    _max_attempts="${THREE_LAYER_CHAIN_RETRIES:-3}"
    _sleep_sec="${THREE_LAYER_CHAIN_RETRY_SLEEP:-2}"
    _tmp_out="$(mktemp "${TMPDIR:-/tmp}/three_layer_semantic_out.XXXXXX")"
    _tmp_err="$(mktemp "${TMPDIR:-/tmp}/three_layer_semantic_err.XXXXXX")"
    THREE_LAYER_LAST_ERROR=""
    while [[ "$_attempt" -le "$_max_attempts" ]]; do
        : > "$_tmp_out"
        : > "$_tmp_err"
        if [[ -n "$_payload" ]] && bash "$_semantic_update_cmd" discussion "$_payload" >"$_tmp_out" 2>"$_tmp_err"; then
            rm -f "$_tmp_out" "$_tmp_err"
            return 0
        fi
        _combined="$(cat "$_tmp_err" "$_tmp_out" 2>/dev/null || true)"
        if [[ -z "$_combined" && -z "$_payload" ]]; then
            _combined="payload_generation_failed"
        elif [[ -z "$_combined" ]]; then
            _combined="semantic_index_update exited non-zero without output"
        fi
        THREE_LAYER_LAST_ERROR="$(_three_layer_sanitize_detail "$_combined")"
        [[ "$_attempt" -lt "$_max_attempts" ]] && sleep "$_sleep_sec"
        _attempt=$((_attempt + 1))
    done
    rm -f "$_tmp_out" "$_tmp_err"
    return 1
}

_three_layer_repair_unresolved() {
    local _chain_log="$1" _semantic_update_cmd="$2"
    [[ "${THREE_LAYER_CHAIN_REPAIR:-1}" == "1" ]] || return 0
    [[ -f "$_chain_log" ]] || return 0
    local _repairs
    _repairs="$(
        awk '
            function field(line, key,    tmp) {
                tmp = line
                if (tmp ~ (key "=[^[:space:]]+")) {
                    sub("^.*" key "=", "", tmp)
                    sub("[[:space:]].*$", "", tmp)
                    return tmp
                }
                return ""
            }
            / ERROR layer2_semantic_index_update_failed / {
                event = field($0, "event")
                if (event == "") event = "line:" NR
                unresolved[event] = field($0, "payload_b64")
                sources[event] = field($0, "source")
            }
            / OK layer2_semantic_index_update / {
                event = field($0, "event")
                if (event != "") delete unresolved[event]
            }
            END {
                for (event in unresolved) {
                    if (unresolved[event] != "") print event "|" sources[event] "|" unresolved[event]
                }
            }
        ' "$_chain_log" 2>/dev/null || true
    )"
    [[ -n "$_repairs" ]] || return 0
    local _line _event_id _source _payload_b64 _payload _ts
    while IFS='|' read -r _event_id _source _payload_b64; do
        [[ -n "$_event_id" && -n "$_payload_b64" ]] || continue
        _payload="$(printf '%s' "$_payload_b64" | base64 -d 2>/dev/null || true)"
        [[ -n "$_payload" ]] || continue
        if _three_layer_run_semantic_update "$_semantic_update_cmd" "$_payload"; then
            _ts="$(date -Iseconds)"
            printf '%s OK layer2_semantic_index_update event=%s source=%s repair=1\n' "$_ts" "$_event_id" "$_source" >> "$_chain_log"
        fi
    done <<< "$_repairs"
}

_three_layer_chain() {
    local _event_id="$1" _knowledge="$2" _source="$3" _chain_log="$4" _semantic_update_cmd="$5"
    local _ts
    _ts="$(date -Iseconds)"
    mkdir -p "$(dirname "$_chain_log")"

    # Layer2: セマンティックインデックス連携(discussion payload)
    local _payload
    _payload="$(jq -cn --arg ts "$_ts" --arg summary "$_knowledge" --arg detail "source: $_source" \
        '{"timestamp":$ts,"summary":$summary,"detail":$detail}' 2>/dev/null || true)"
    _three_layer_repair_unresolved "$_chain_log" "$_semantic_update_cmd"
    if ! _three_layer_run_semantic_update "$_semantic_update_cmd" "$_payload"; then
        printf '%s ERROR layer2_semantic_index_update_failed event=%s source=%s detail="%s" payload_b64=%s\n' \
            "$_ts" "$_event_id" "$_source" "$THREE_LAYER_LAST_ERROR" "$(_three_layer_payload_b64 "$_payload")" >> "$_chain_log"
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
