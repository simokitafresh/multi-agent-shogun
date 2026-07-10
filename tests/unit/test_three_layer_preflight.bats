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
{"agent_id":"kagemaru","pane_id":"%test_2","prompt_hash":"new","nonce":"nonce_2","issued_at":"2026-07-10T15:00:00+09:00","memory_db":"0","semantic":"0","obsidian":"0","status":"success"}
JSON
    printf 'nonce_2\n' > "$EVIDENCE.current"
    run env THREE_LAYER_PREACTION_MAX_AGE_SECONDS=10000000000 THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" verify Write "$ROOT/context/infrastructure.md" ""
    [ "$status" -eq 0 ]
}

@test "一層欠落の証跡をBLOCK" {
    cat > "$EVIDENCE" <<'JSON'
{"agent_id":"kagemaru","pane_id":"%test_3","prompt_hash":"new","nonce":"nonce_3","issued_at":"2026-07-10T15:00:00+09:00","memory_db":"0","semantic":"1","obsidian":"0","status":"failed"}
JSON
    printf 'nonce_3\n' > "$EVIDENCE.current"
    run verify Edit "$ROOT/context/infrastructure.md" ""
    [ "$status" -eq 1 ]
}

@test "旧prompt証跡をBLOCK" {
    cat > "$EVIDENCE" <<'JSON'
{"agent_id":"kagemaru","pane_id":"%test_4","prompt_hash":"old","nonce":"old_nonce","issued_at":"2026-07-10T14:00:00+09:00","memory_db":"0","semantic":"0","obsidian":"0","status":"success"}
JSON
    printf 'new_nonce\n' > "$EVIDENCE.current"
    run env THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" verify Write "$ROOT/context/infrastructure.md" ""
    [ "$status" -eq 1 ]
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

@test "redirectを含むechoはread-only偽装としてBLOCK" {
    run verify Bash "" "echo ok > repo-file"
    [ "$status" -eq 1 ]
}

@test "複合rgとtouchは全体を変更系としてBLOCK" {
    run verify Bash "" "rg -n foo file; touch repo-file"
    [ "$status" -eq 1 ]
}

@test "batsはread-only許可リストから除外" {
    run verify Bash "" "bats tests/unit/test_three_layer_preflight.bats"
    [ "$status" -eq 1 ]
}

@test "PATH上のrgを解決" {
    local path_dir="$TMP_EVIDENCE/path-bin"
    mkdir -p "$path_dir"
    printf '#!/bin/sh\n' > "$path_dir/rg"
    chmod +x "$path_dir/rg"
    run env PATH="$path_dir" HOME="$TMP_EVIDENCE/no-home" /bin/bash "$ROOT/scripts/hooks/three_layer_preflight.sh" resolve-rg
    [ "$status" -eq 0 ]
    [ "$output" = "$path_dir/rg" ]
}

@test "HOME local rg fallbackを解決" {
    local home_dir="$TMP_EVIDENCE/home"
    mkdir -p "$home_dir/.local/bin"
    printf '#!/bin/sh\n' > "$home_dir/.local/bin/rg"
    chmod +x "$home_dir/.local/bin/rg"
    run env PATH="/nonexistent" HOME="$home_dir" /bin/bash "$ROOT/scripts/hooks/three_layer_preflight.sh" resolve-rg
    [ "$status" -eq 0 ]
    [ "$output" = "$home_dir/.local/bin/rg" ]
}

@test "rg fallbackが無ければ失敗" {
    local home_dir="$TMP_EVIDENCE/empty-home"
    mkdir -p "$home_dir"
    run env PATH="/nonexistent" HOME="$home_dir" THREE_LAYER_DISABLE_SYSTEM_RG=1 /bin/bash "$ROOT/scripts/hooks/three_layer_preflight.sh" resolve-rg
    [ "$status" -eq 1 ]
}

@test "5分超でもnonce一致ならPASS" {
    local issued
    issued="$(date -Iseconds -d '10 minutes ago')"
    printf '{"agent_id":"%s","pane_id":"%s","prompt_hash":"old","nonce":"ttl_nonce","issued_at":"%s","memory_db":"0","semantic":"0","obsidian":"0","status":"success"}\n' "$AGENT" "$PANE" "$issued" > "$EVIDENCE"
    printf 'ttl_nonce\n' > "$EVIDENCE.current"
    run verify Write "$ROOT/context/infrastructure.md" ""
    [ "$status" -eq 0 ]
}

@test "nonce不一致はfreshでも即BLOCK" {
    local issued
    issued="$(date -Iseconds)"
    printf '{"agent_id":"%s","pane_id":"%s","prompt_hash":"old","nonce":"evidence_nonce","issued_at":"%s","memory_db":"0","semantic":"0","obsidian":"0","status":"success"}\n' "$AGENT" "$PANE" "$issued" > "$EVIDENCE"
    printf 'current_nonce\n' > "$EVIDENCE.current"
    run verify Edit "$ROOT/context/infrastructure.md" ""
    [ "$status" -eq 1 ]
}

@test "4時間超の証跡はBLOCK" {
    local issued
    issued="$(date -Iseconds -d '5 hours ago')"
    printf '{"agent_id":"%s","pane_id":"%s","prompt_hash":"old","nonce":"expired_nonce","issued_at":"%s","memory_db":"0","semantic":"0","obsidian":"0","status":"success"}\n' "$AGENT" "$PANE" "$issued" > "$EVIDENCE"
    printf 'expired_nonce\n' > "$EVIDENCE.current"
    run verify Write "$ROOT/context/infrastructure.md" ""
    [ "$status" -eq 1 ]
}

@test "prompt引数でstdin欠落を回復" {
    run env THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        /bin/bash "$ROOT/scripts/hooks/three_layer_preflight.sh" issue "recovered prompt" </dev/null
    [ "$status" -eq 0 ]
    [ -s "$EVIDENCE" ]
    run verify Write "$ROOT/context/infrastructure.md" ""
    [ "$status" -eq 0 ]
}

@test "stdinもprompt引数も無いissueはFAIL" {
    run env THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        /bin/bash "$ROOT/scripts/hooks/three_layer_preflight.sh" issue </dev/null
    [ "$status" -eq 1 ]
}

@test "pre-bash hook script欠落はfail-closed" {
    local tmp_root="$TMP_EVIDENCE/missing_bash"
    mkdir -p "$tmp_root/.claude/hooks"
    cp "$ROOT/.claude/hooks/pre-bash-combined.sh" "$tmp_root/.claude/hooks/pre-bash-combined.sh"
    run bash -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"touch repo-file\"}}' | /bin/bash '$tmp_root/.claude/hooks/pre-bash-combined.sh'"
    [ "$status" -eq 2 ]
}

@test "pre-write hook script欠落はfail-closed" {
    local tmp_root="$TMP_EVIDENCE/missing_write"
    mkdir -p "$tmp_root/.claude/hooks"
    cp "$ROOT/.claude/hooks/pre-write-edit-combined.sh" "$tmp_root/.claude/hooks/pre-write-edit-combined.sh"
    run bash -c "printf '%s' '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$tmp_root/repo.txt\"}}' | /bin/bash '$tmp_root/.claude/hooks/pre-write-edit-combined.sh'"
    [ "$status" -eq 2 ]
}
