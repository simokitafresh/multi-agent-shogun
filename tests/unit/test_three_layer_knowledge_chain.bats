#!/usr/bin/env bats

setup() {
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
