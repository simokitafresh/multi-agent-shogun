#!/usr/bin/env bats

setup_file() {
    export ROOT THREE_LAYER_DB_FIXTURE THREE_LAYER_FIXTURE_ROOT
    ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    THREE_LAYER_FIXTURE_ROOT="$(mktemp -d)"
    mkdir -p "$THREE_LAYER_FIXTURE_ROOT/archive"
    printf '%s\n' '{"ts":"2026-07-10T15:00:00+09:00","agent":"lord","direction":"inbound","summary":"fixture","detail":"three layer preflight fixture"}' > "$THREE_LAYER_FIXTURE_ROOT/archive/fixture.jsonl"
    : > "$THREE_LAYER_FIXTURE_ROOT/semantic-index.md"
    THREE_LAYER_DB_FIXTURE="$THREE_LAYER_FIXTURE_ROOT/memory.db"
    python3 "$ROOT/scripts/memory_db_import.py" \
        --archive-dir "$THREE_LAYER_FIXTURE_ROOT/archive" \
        --semantic-index "$THREE_LAYER_FIXTURE_ROOT/semantic-index.md" \
        --db "$THREE_LAYER_DB_FIXTURE" >/dev/null
}

teardown_file() {
    rm -rf "$THREE_LAYER_FIXTURE_ROOT"
}

setup() {
    export ROOT TMP_EVIDENCE AGENT PANE EVIDENCE MEMORY_DB_QUERY_DB
    TMP_EVIDENCE="$(mktemp -d)"
    MEMORY_DB_QUERY_DB="$TMP_EVIDENCE/memory.db"
    cp "$THREE_LAYER_DB_FIXTURE" "$MEMORY_DB_QUERY_DB"
    AGENT="kagemaru"
    PANE="%test_${BATS_TEST_NUMBER}"
    EVIDENCE="$TMP_EVIDENCE/evidence_${AGENT}__test_${BATS_TEST_NUMBER}.json"
}

teardown() {
    rm -rf "$TMP_EVIDENCE"
}

verify() {
    env MEMORY_DB_QUERY_DB="$MEMORY_DB_QUERY_DB" THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" verify "$@"
}

@test "有効なSQLite DBのNO_MATCHは成功" {
    run env MEMORY_DB_QUERY_DB="$MEMORY_DB_QUERY_DB" THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" issue "definitely-absent-memory-query"
    [ "$status" -eq 0 ]
    run grep -o '"memory_db":"[0-9]*"' "$EVIDENCE"
    [ "$output" = '"memory_db":"0"' ]
}

@test "欠落SQLite DBはfail-closed" {
    run env MEMORY_DB_QUERY_DB="$TMP_EVIDENCE/missing-parent/missing.db" THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" issue "missing database"
    [ "$status" -ne 0 ]
    run grep -o '"status":"[a-z]*"' "$EVIDENCE"
    [ "$output" = '"status":"failed"' ]
}

@test "壊れたSQLite DBはfail-closed" {
    local broken_db="$TMP_EVIDENCE/broken.db"
    printf 'not sqlite' > "$broken_db"
    run env MEMORY_DB_QUERY_DB="$broken_db" THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" issue "broken database"
    [ "$status" -ne 0 ]
    run grep -o '"status":"[a-z]*"' "$EVIDENCE"
    [ "$output" = '"status":"failed"' ]
}

@test "memory_db_query exit1 stubはscript存在でもfail-closed" {
    local tmp_root="$TMP_EVIDENCE/exit_one"
    mkdir -p "$tmp_root/scripts/hooks" "$tmp_root/scripts" "$tmp_root/context" "$tmp_root/docs/semantic-index"
    cp "$ROOT/scripts/hooks/three_layer_preflight.sh" "$tmp_root/scripts/hooks/three_layer_preflight.sh"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp_root/scripts/memory_db_query.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp_root/scripts/semantic_search.sh"
    chmod +x "$tmp_root/scripts/memory_db_query.sh" "$tmp_root/scripts/semantic_search.sh"
    cp "$ROOT/context/semantic-map.md" "$tmp_root/context/semantic-map.md"
    : > "$tmp_root/docs/semantic-index/index.md"
    run env THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE/exit_one_evidence" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" issue "exit one stub"
    [ "$status" -ne 0 ]
    [[ "$output" == *"memory=1"* ]]
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

@test "同一paneの並行issueは固有tempで世代整合しverify可能" {
    local log="$TMP_EVIDENCE/parallel.log" verify_log="$TMP_EVIDENCE/verify.log"
    : > "$log"
    : > "$verify_log"
    for i in 1 2 3 4; do
        env MEMORY_DB_QUERY_DB="$MEMORY_DB_QUERY_DB" THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
            bash "$ROOT/scripts/hooks/three_layer_preflight.sh" issue "parallel generation $i" >>"$log" 2>&1 &
    done
    local issue_pids verify_rc i
    issue_pids="$(jobs -pr)"
    for i in $(seq 1 80); do
        verify_rc=0
        verify Write "$ROOT/context/infrastructure.md" "" >>"$verify_log" 2>&1 || verify_rc=$?
        [ "$verify_rc" -eq 0 ] || [ "$verify_rc" -eq 1 ]
        sleep 0.01
    done
    wait $issue_pids

    ! grep -Eq 'No such file|JSONDecodeError|Traceback|nonce mismatch' "$log" "$verify_log"
    run verify Write "$ROOT/context/infrastructure.md" ""
    [ "$status" -eq 0 ]
    [ "$(find "$TMP_EVIDENCE" -maxdepth 1 -name '.nonce.*' | wc -l)" -eq 0 ]
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

@test "改行を含むpromptでもissue()はrg exit2でクラッシュしない" {
    # rg --fixed-strings with an embedded newline used to exit 2 (a real
    # error, not "no match"), failing the whole evidence record even when
    # memory/semantic succeeded. Recurred 3x on 2026-07-10 and locked
    # agents out of every tool for the evidence TTL.
    run env THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" issue "$(printf 'line one about the codebase\nline two more detail\nline three')"
    [ "$status" -eq 0 ]
    [ -s "$EVIDENCE" ]
    run grep -o '"obsidian":"[0-9]*"' "$EVIDENCE"
    [ "$output" = '"obsidian":"0"' ]
    run grep -o '"status":"[a-z]*"' "$EVIDENCE"
    [ "$output" = '"status":"success"' ]
}

@test "break-glass: 三層検索スクリプト自体はevidence failedでも実行許可され続ける" {
    printf '{"agent_id":"%s","pane_id":"%s","prompt_hash":"x","nonce":"n","issued_at":"2026-07-10T15:00:00+09:00","memory_db":"0","semantic":"0","obsidian":"2","status":"failed"}\n' \
        "$AGENT" "$PANE" > "$EVIDENCE"
    printf 'n\n' > "$EVIDENCE.current"
    run verify Bash "" "bash scripts/memory_db_query.sh --search test"
    [ "$status" -eq 0 ]
    run verify Bash "" "bash scripts/semantic_search.sh test"
    [ "$status" -eq 0 ]
    run verify Bash "" "bash scripts/hooks/three_layer_preflight.sh issue test"
    [ "$status" -eq 0 ]
}

@test "evidence statusがfailedのままなら一般Bashは引き続きBLOCK" {
    printf '{"agent_id":"%s","pane_id":"%s","prompt_hash":"x","nonce":"n","issued_at":"2026-07-10T15:00:00+09:00","memory_db":"0","semantic":"0","obsidian":"2","status":"failed"}\n' \
        "$AGENT" "$PANE" > "$EVIDENCE"
    printf 'n\n' > "$EVIDENCE.current"
    run verify Bash "" "touch repo-file"
    [ "$status" -eq 1 ]
}

@test "一層が失敗すれば他二層が成功してもstatusはfailedのまま(並列実行後も個別rc集計)" {
    local tmp_root="$TMP_EVIDENCE/one_layer_fail"
    mkdir -p "$tmp_root/scripts/hooks" "$tmp_root/context" "$tmp_root/docs"
    cp "$ROOT/scripts/hooks/three_layer_preflight.sh" "$tmp_root/scripts/hooks/three_layer_preflight.sh"
    cat > "$tmp_root/scripts/memory_db_query.sh" <<'EOF'
#!/usr/bin/env bash
exit 3
EOF
    chmod +x "$tmp_root/scripts/memory_db_query.sh"
    cat > "$tmp_root/scripts/semantic_search.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$tmp_root/scripts/semantic_search.sh"

    local evidence_dir="$TMP_EVIDENCE/one_layer_fail_evidence"
    mkdir -p "$evidence_dir"
    run env THREE_LAYER_PREACTION_EVIDENCE_DIR="$evidence_dir" THREE_LAYER_AGENT_ID="onelayer" TMUX_PANE="%onelayer" \
        bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" issue "one layer fail test"
    [ "$status" -eq 1 ]
    run grep -o '"status":"[a-z]*"' "$evidence_dir"/evidence_onelayer*.json
    [ "$output" = '"status":"failed"' ]
    run grep -o '"memory_db":"[0-9]*"' "$evidence_dir"/evidence_onelayer*.json
    [ "$output" = '"memory_db":"3"' ]
    run grep -o '"semantic":"[0-9]*"' "$evidence_dir"/evidence_onelayer*.json
    [ "$output" = '"semantic":"0"' ]
}
