#!/usr/bin/env bats

setup() {
    export ROOT TMP_EVIDENCE AGENT PANE EVIDENCE
    ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TMP_EVIDENCE="$(mktemp -d)"
    AGENT="kagemaru"
    PANE="%test_${BATS_TEST_NUMBER}"
    EVIDENCE="$TMP_EVIDENCE/evidence_${AGENT}__test_${BATS_TEST_NUMBER}.json"
}

teardown() {
    rm -rf "$TMP_EVIDENCE"
}

verify() {
    env THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" verify "$@"
}

@test "証跡なしの変更系BashをBLOCK" {
    run verify Bash "" "touch repo-file"
    [ "$status" -eq 1 ]
}

@test "三層成功証跡ありのWriteをPASS" {
    cat > "$EVIDENCE" <<'JSON'
{"agent_id":"kagemaru","pane_id":"%test_2","prompt_hash":"new","issued_at":"2026-07-10T15:00:00+09:00","memory_db":"0","semantic":"0","obsidian":"0","status":"success"}
JSON
    run env THREE_LAYER_EXPECTED_PROMPT_HASH=new THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" verify Write "$ROOT/context/infrastructure.md" ""
    [ "$status" -eq 0 ]
}

@test "一層欠落の証跡をBLOCK" {
    cat > "$EVIDENCE" <<'JSON'
{"agent_id":"kagemaru","pane_id":"%test_3","prompt_hash":"new","issued_at":"2026-07-10T15:00:00+09:00","memory_db":"0","semantic":"1","obsidian":"0","status":"failed"}
JSON
    run verify Edit "$ROOT/context/infrastructure.md" ""
    [ "$status" -eq 1 ]
}

@test "旧prompt証跡をBLOCK" {
    cat > "$EVIDENCE" <<'JSON'
{"agent_id":"kagemaru","pane_id":"%test_4","prompt_hash":"old","issued_at":"2026-07-10T14:00:00+09:00","memory_db":"0","semantic":"0","obsidian":"0","status":"success"}
JSON
    run env THREE_LAYER_EXPECTED_PROMPT_HASH=new THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" verify Write "$ROOT/context/infrastructure.md" ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"別prompt"* ]]
}

@test "read-only Bashは証跡なしでもPASS" {
    run verify Bash "" "rg -n three_layer scripts/hooks/three_layer_preflight.sh"
    [ "$status" -eq 0 ]
}

@test "preflight自身のissue経路はPASS" {
    run env THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" issue <<< '{"prompt":"preflight test"}'
    [ "$status" -eq 0 ]
    [ -s "$EVIDENCE" ]
}
