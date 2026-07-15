#!/usr/bin/env bash
# Durable Layer2/3 worker for memory_db_knowledge_write.sh.
# Usage: bash scripts/three_layer_knowledge_chain.sh <pending-request.json>

set -euo pipefail

request_path="${1:?Usage: three_layer_knowledge_chain.sh <pending-request.json>}"
[[ -f "$request_path" ]] || { echo "ERROR: pending request not found: $request_path" >&2; exit 1; }

mapfile -t request_fields < <(jq -r \
    '.event_id, .knowledge_b64, .source_b64, .chain_log, .semantic_update_cmd' \
    "$request_path")
[[ "${#request_fields[@]}" -eq 5 ]] || { echo "ERROR: invalid pending request: $request_path" >&2; exit 1; }

event_id="${request_fields[0]}"
knowledge="$(printf '%s' "${request_fields[1]}" | base64 -d)"
source="$(printf '%s' "${request_fields[2]}" | base64 -d)"
chain_log="${request_fields[3]}"
semantic_update_cmd="${request_fields[4]}"
result_path="${request_path%.pending.json}.result"
safe_event="${event_id//[^[:alnum:]_.-]/_}"
lock_path="${THREE_LAYER_CHAIN_LOCK_DIR:-/tmp}/mas-three-layer-${safe_event}.lock"
finalized=0

mkdir -p "$(dirname "$chain_log")" "$(dirname "$result_path")"
exec 9>"$lock_path"
if ! flock -n 9; then
    exit 0
fi

sanitize_detail() {
    local text="$1"
    text="${text//$'\r'/ }"
    text="${text//$'\n'/ }"
    text="${text//$'\t'/ }"
    text="${text//\\/\\\\}"
    text="${text//\"/\\\"}"
    printf '%s' "${text:0:240}"
}

append_log() {
    local line="$1"
    {
        flock -x 8
        printf '%s\n' "$line" >> "$chain_log"
    } 8>"${chain_log}.lock"
}

write_result() {
    local state="$1" reason="$2"
    local tmp="${result_path}.tmp.$$"
    {
        printf 'state=%s\n' "$state"
        printf 'reason=%s\n' "$reason"
        printf 'event_id=%s\n' "$event_id"
        printf 'finished_at=%s\n' "$(date -Iseconds)"
    } > "$tmp"
    mv "$tmp" "$result_path"
    rm -f "$request_path"
    finalized=1
}

finalize_unexpected_exit() {
    local rc=$?
    if [[ "$finalized" -eq 0 ]]; then
        append_log "$(date -Iseconds) ERROR layer2_semantic_index_update_failed event=${event_id} source=${source} detail=\"worker_exit_${rc}\""
        write_result FAIL "worker_exit_${rc}" || true
    fi
}
trap finalize_unexpected_exit EXIT

run_semantic_update() {
    local payload="$1" attempt=1
    local max_attempts="${THREE_LAYER_CHAIN_RETRIES:-3}"
    local sleep_sec="${THREE_LAYER_CHAIN_RETRY_SLEEP:-2}"
    local tmp_out tmp_err combined
    tmp_out="$(mktemp "${TMPDIR:-/tmp}/three_layer_semantic_out.XXXXXX")"
    tmp_err="$(mktemp "${TMPDIR:-/tmp}/three_layer_semantic_err.XXXXXX")"
    last_error=""
    while [[ "$attempt" -le "$max_attempts" ]]; do
        : > "$tmp_out"
        : > "$tmp_err"
        if bash "$semantic_update_cmd" discussion "$payload" >"$tmp_out" 2>"$tmp_err"; then
            rm -f "$tmp_out" "$tmp_err"
            return 0
        fi
        combined="$(cat "$tmp_err" "$tmp_out" 2>/dev/null || true)"
        [[ -n "$combined" ]] || combined="semantic_index_update exited non-zero without output"
        last_error="$(sanitize_detail "$combined")"
        [[ "$attempt" -lt "$max_attempts" ]] && sleep "$sleep_sec"
        attempt=$((attempt + 1))
    done
    rm -f "$tmp_out" "$tmp_err"
    return 1
}

repair_unresolved() {
    [[ "${THREE_LAYER_CHAIN_REPAIR:-1}" == "1" ]] || return 0
    [[ -f "$chain_log" ]] || return 0
    exec 7>"${chain_log}.repair.lock"
    flock -n 7 || return 0
    local repairs old_event old_source payload_b64 old_payload repair_ts old_safe old_result tmp
    repairs="$(awk '
        function field(line, key,    value) {
            value = line
            if (value ~ (key "=[^[:space:]]+")) {
                sub("^.*" key "=", "", value)
                sub("[[:space:]].*$", "", value)
                return value
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
    ' "$chain_log" 2>/dev/null || true)"
    [[ -n "$repairs" ]] || return 0
    while IFS='|' read -r old_event old_source payload_b64; do
        [[ -n "$old_event" && -n "$payload_b64" ]] || continue
        old_payload="$(printf '%s' "$payload_b64" | base64 -d 2>/dev/null || true)"
        [[ -n "$old_payload" ]] || continue
        if run_semantic_update "$old_payload"; then
            repair_ts="$(date -Iseconds)"
            append_log "$repair_ts OK layer2_semantic_index_update event=${old_event} source=${old_source} repair=1"
            old_safe="${old_event//[^[:alnum:]_.-]/_}"
            old_result="$(dirname "$request_path")/${old_safe}.result"
            if [[ -f "$old_result" ]]; then
                tmp="${old_result}.tmp.$$"
                {
                    printf 'state=PASS\nreason=repaired\nevent_id=%s\nfinished_at=%s\n' \
                        "$old_event" "$repair_ts"
                } > "$tmp"
                mv "$tmp" "$old_result"
            fi
        fi
    done <<< "$repairs"
}

ts="$(date -Iseconds)"
payload="$(jq -cn --arg ts "$ts" --arg summary "$knowledge" --arg detail "source: $source" \
    '{"timestamp":$ts,"summary":$summary,"detail":$detail}')"
repair_unresolved
if ! run_semantic_update "$payload"; then
    payload_b64="$(printf '%s' "$payload" | base64 | tr -d '\n')"
    append_log "$ts ERROR layer2_semantic_index_update_failed event=${event_id} source=${source} detail=\"${last_error}\" payload_b64=${payload_b64}"
    write_result FAIL semantic_index_update_failed
    exit 0
fi

append_log "$ts OK layer2_semantic_index_update event=${event_id} source=${source}"
targets="$(grep -oP '(?<=\[\[)[^][]+(?=\]\])' <<< "$knowledge" 2>/dev/null | sort -u || true)"
if [[ -n "$targets" ]]; then
    while IFS= read -r target; do
        [[ -n "$target" ]] || continue
        append_log "$ts CANDIDATE layer3_obsidian_link_candidate event=${event_id} target=${target} source=${source}"
    done <<< "$targets"
fi

write_result PASS ok
