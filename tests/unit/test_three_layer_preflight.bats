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
    exec 8>"$BATS_FILE_TMPDIR/three-layer-preflight-fixture.lock"
    flock -x 8
    export ROOT TMP_EVIDENCE AGENT PANE EVIDENCE MEMORY_DB_QUERY_DB THREE_LAYER_PREFLIGHT_WARN_LOG
    TMP_EVIDENCE="$(mktemp -d)"
    THREE_LAYER_PREFLIGHT_WARN_LOG="$TMP_EVIDENCE/warn.tsv"
    MEMORY_DB_QUERY_DB="$TMP_EVIDENCE/memory.db"
    cp "$THREE_LAYER_DB_FIXTURE" "$MEMORY_DB_QUERY_DB"
    AGENT="kagemaru"
    PANE="%test_${BATS_TEST_NUMBER}"
    EVIDENCE="$TMP_EVIDENCE/evidence_${AGENT}__test_${BATS_TEST_NUMBER}.json"
    THREE_LAYER_SEMANTIC_FIXTURE="$TMP_EVIDENCE/semantic-index.md"
    THREE_LAYER_CAUSAL_FIXTURE="$TMP_EVIDENCE/causal-index.tsv"
    printf '%s\n' 'fixture preflight line wal_live_event' > "$THREE_LAYER_SEMANTIC_FIXTURE"
    printf '%s\t%s\n' 'fixture preflight line wal_live_event' "$THREE_LAYER_SEMANTIC_FIXTURE" > "$THREE_LAYER_CAUSAL_FIXTURE"
}

teardown() {
    rm -rf "$TMP_EVIDENCE"
}

verify() {
    env MEMORY_DB_QUERY_DB="$MEMORY_DB_QUERY_DB" THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" verify "$@"
}

issue_with_fixtures() {
    env MEMORY_DB_QUERY_DB="$MEMORY_DB_QUERY_DB" \
        THREE_LAYER_SEMANTIC_INDEX="$THREE_LAYER_SEMANTIC_FIXTURE" \
        THREE_LAYER_CAUSAL_INDEX_CACHE="$THREE_LAYER_CAUSAL_FIXTURE" \
        THREE_LAYER_CAUSAL_REFRESH_DISABLED=1 \
        THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" \
        THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" issue "$@"
}

@test "有効なSQLite DBでも全層NO_MATCHはfail-closed" {
    run env MEMORY_DB_QUERY_DB="$MEMORY_DB_QUERY_DB" THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" issue "definitely-absent-memory-query"
    [ "$status" -ne 0 ]
    [ ! -e "$EVIDENCE" ]
}

@test "欠落SQLite DBはfail-closed" {
    run env MEMORY_DB_QUERY_DB="$TMP_EVIDENCE/missing-parent/missing.db" THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" issue "missing database"
    [ "$status" -ne 0 ]
    [ ! -e "$EVIDENCE" ]
}

@test "壊れたSQLite DBはfail-closed" {
    local broken_db="$TMP_EVIDENCE/broken.db"
    printf 'not sqlite' > "$broken_db"
    run env MEMORY_DB_QUERY_DB="$broken_db" THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" issue "broken database"
    [ "$status" -ne 0 ]
    [ ! -e "$EVIDENCE" ]
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

make_timeout_root() {
    local tmp_root="$1"
    mkdir -p "$tmp_root/scripts/hooks" "$tmp_root/scripts" "$tmp_root/context" "$tmp_root/docs/semantic-index" "$tmp_root/docs/fixture" "$tmp_root/bin"
    cp "$ROOT/scripts/hooks/three_layer_preflight.sh" "$tmp_root/scripts/hooks/three_layer_preflight.sh"
    cp "$ROOT/context/semantic-map.md" "$tmp_root/context/semantic-map.md"
    cp "$ROOT/docs/semantic-index/index.md" "$tmp_root/docs/semantic-index/index.md"
    printf 'three layer preflight fixture\n' > "$tmp_root/docs/fixture/causal.md"
    printf '#!/usr/bin/env bash\nsleep 1\n' > "$tmp_root/scripts/memory_db_query.sh"
    cp "$tmp_root/scripts/memory_db_query.sh" "$tmp_root/scripts/semantic_search.sh"
    printf '#!/usr/bin/env bash\nsleep 1\nexit 124\n' > "$tmp_root/bin/rg"
    chmod +x "$tmp_root/scripts/memory_db_query.sh" "$tmp_root/scripts/semantic_search.sh" "$tmp_root/bin/rg"
}

@test "3層primary timeoutは実データfallback完了時のみsuccess" {
    local tmp_root="$TMP_EVIDENCE/timeout_success"
    make_timeout_root "$tmp_root"
    local started elapsed
    started="$(date +%s%3N)"
    run env PATH="$tmp_root/bin:$PATH" MEMORY_DB_QUERY_DB="$MEMORY_DB_QUERY_DB" THREE_LAYER_PRIMARY_TIMEOUT_SECONDS=0.05 THREE_LAYER_GLOBAL_BUDGET_MS=900 THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE/timeout_success_evidence" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" issue "three layer preflight fixture"
    elapsed=$(( $(date +%s%3N) - started ))
    [ "$status" -eq 0 ]
    [ "$elapsed" -lt 1000 ]
    run grep -o '"memory_db":"[0-9]*"\|"semantic":"[0-9]*"\|"obsidian":"[0-9]*"\|"status":"[a-z]*"' "$TMP_EVIDENCE/timeout_success_evidence/evidence_${AGENT}__test_${BATS_TEST_NUMBER}.json"
    [[ "$output" == *'"memory_db":"0"'* ]]
    [[ "$output" == *'"semantic":"0"'* ]]
    [[ "$output" == *'"obsidian":"0"'* ]]
    [[ "$output" == *'"status":"success"'* ]]
    run python3 - "$TMP_EVIDENCE/timeout_success_evidence/evidence_${AGENT}__test_${BATS_TEST_NUMBER}.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
for layer in ("memory", "semantic", "obsidian"):
    assert int(data[f"{layer}_count"]) > 0
    assert data[f"{layer}_source"]
    assert data[f"{layer}_timestamp"]
PY
    [ "$status" -eq 0 ]
}

@test "memory timeout fallbackのDB欠落はfailed" {
    local tmp_root="$TMP_EVIDENCE/timeout_memory_fail"
    make_timeout_root "$tmp_root"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp_root/scripts/semantic_search.sh"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp_root/bin/rg"
    run env PATH="$tmp_root/bin:$PATH" MEMORY_DB_QUERY_DB="$TMP_EVIDENCE/missing.db" THREE_LAYER_PRIMARY_TIMEOUT_SECONDS=0.05 THREE_LAYER_FALLBACK_TIMEOUT_SECONDS=1 THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE/timeout_memory_fail_evidence" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" issue "missing memory"
    [ "$status" -ne 0 ]
    [[ "$output" == *"evidence failed"* ]]
}

@test "semantic timeout fallbackのindex欠落はfailed" {
    local tmp_root="$TMP_EVIDENCE/timeout_semantic_fail"
    make_timeout_root "$tmp_root"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp_root/scripts/memory_db_query.sh"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp_root/bin/rg"
    rm "$tmp_root/docs/semantic-index/index.md"
    run env PATH="$tmp_root/bin:$PATH" THREE_LAYER_PRIMARY_TIMEOUT_SECONDS=0.05 THREE_LAYER_FALLBACK_TIMEOUT_SECONDS=1 THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE/timeout_semantic_fail_evidence" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" issue "missing semantic"
    [ "$status" -ne 0 ]
    [[ "$output" == *"evidence failed"* ]]
}

@test "obsidian timeout fallbackのcausal index欠落はfailed" {
    local tmp_root="$TMP_EVIDENCE/timeout_obsidian_fail"
    make_timeout_root "$tmp_root"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp_root/scripts/memory_db_query.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp_root/scripts/semantic_search.sh"
    rm "$tmp_root/context/semantic-map.md"
    run env PATH="$tmp_root/bin:$PATH" THREE_LAYER_PRIMARY_TIMEOUT_SECONDS=0.05 THREE_LAYER_FALLBACK_TIMEOUT_SECONDS=1 THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE/timeout_obsidian_fail_evidence" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" issue "missing obsidian"
    [ "$status" -ne 0 ]
    [[ "$output" == *"evidence failed"* ]]
}

@test "証跡なしの変更系BashをWARNしてfail-open" {
    run verify Bash "" "touch repo-file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN:"* ]]
    [ "$(wc -l < "$THREE_LAYER_PREFLIGHT_WARN_LOG")" -eq 1 ]
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

@test "一層欠落の証跡をWARNしてfail-open" {
    cat > "$EVIDENCE" <<'JSON'
{"agent_id":"kagemaru","pane_id":"%test_3","prompt_hash":"new","nonce":"nonce_3","issued_at":"2026-07-10T15:00:00+09:00","memory_db":"0","semantic":"1","obsidian":"0","status":"failed"}
JSON
    printf 'nonce_3\n' > "$EVIDENCE.current"
    run verify Edit "$ROOT/context/infrastructure.md" ""
    [ "$status" -eq 0 ]
}

@test "旧prompt証跡をWARNしてfail-open" {
    cat > "$EVIDENCE" <<'JSON'
{"agent_id":"kagemaru","pane_id":"%test_4","prompt_hash":"old","nonce":"old_nonce","issued_at":"2026-07-10T14:00:00+09:00","memory_db":"0","semantic":"0","obsidian":"0","status":"success"}
JSON
    printf 'new_nonce\n' > "$EVIDENCE.current"
    run env THREE_LAYER_PREACTION_EVIDENCE_DIR="$TMP_EVIDENCE" THREE_LAYER_AGENT_ID="$AGENT" TMUX_PANE="$PANE" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" verify Write "$ROOT/context/infrastructure.md" ""
    [ "$status" -eq 0 ]
}

@test "read-only Bashは証跡なしでもPASS" {
    run verify Bash "" "rg -n three_layer scripts/hooks/three_layer_preflight.sh"
    [ "$status" -eq 0 ]
}

@test "safe time and env wrappers normalize to the read-only allowlist" {
    run verify Bash "" "/usr/bin/time -f elapsed=%e env LC_ALL=C rg -n three_layer scripts/hooks/three_layer_preflight.sh"
    [ "$status" -eq 0 ]
}

@test "wrapper command substitution remains fail-closed" {
    run verify Bash "" "env TOKEN=\$(cat secret) rg fixture"
    [ "$status" -eq 0 ]
}

@test "preflight自身のissue経路はPASS" {
    run issue_with_fixtures <<< '{"prompt":"preflight test"}'
    [ "$status" -eq 0 ]
    [ -s "$EVIDENCE" ]
}

@test "linked worktreeの.git fileでもGit checkout経路を使う" {
    local tmp_root="$TMP_EVIDENCE/linked-worktree" evidence_dir="$TMP_EVIDENCE/linked-evidence"
    mkdir -p "$tmp_root/scripts/hooks" "$tmp_root/scripts/lib" "$tmp_root/bin"
    cp "$ROOT/scripts/hooks/three_layer_preflight.sh" "$tmp_root/scripts/hooks/three_layer_preflight.sh"
    printf 'gitdir: /tmp/fixture-worktree.git\n' > "$tmp_root/.git"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp_root/bin/git"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp_root/scripts/lib/causal_index.sh"
    chmod +x "$tmp_root/bin/git"
    chmod 0644 "$tmp_root/scripts/lib/causal_index.sh"
    run env PATH="$tmp_root/bin:$PATH" MEMORY_DB_QUERY_DB="$MEMORY_DB_QUERY_DB" \
        THREE_LAYER_SEMANTIC_INDEX="$THREE_LAYER_SEMANTIC_FIXTURE" \
        THREE_LAYER_CAUSAL_INDEX_CACHE="$THREE_LAYER_CAUSAL_FIXTURE" \
        THREE_LAYER_CAUSAL_REFRESH_DISABLED=1 THREE_LAYER_PREACTION_EVIDENCE_DIR="$evidence_dir" \
        THREE_LAYER_AGENT_ID="linked" TMUX_PANE="%linked" \
        bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" issue "fixture"
    [ "$status" -eq 0 ]
    [ -s "$evidence_dir/evidence_linked__linked.json" ]
}

@test "同一paneの並行issueは固有tempで世代整合しverify可能" {
    local log="$TMP_EVIDENCE/parallel.log" verify_log="$TMP_EVIDENCE/verify.log"
    : > "$log"
    : > "$verify_log"
    local -a issue_pids=()
    local success_count=0 superseded_count=0 other_count=0 rc
    for i in 1 2 3 4; do
        issue_with_fixtures "fixture parallel generation $i" >>"$log" 2>&1 &
        issue_pids+=("$!")
    done
    local verify_rc i pid
    for i in $(seq 1 80); do
        verify_rc=0
        verify Write "$ROOT/context/infrastructure.md" "" >>"$verify_log" 2>&1 || verify_rc=$?
        [ "$verify_rc" -eq 0 ] || [ "$verify_rc" -eq 1 ]
        sleep 0.01
    done
    for pid in "${issue_pids[@]}"; do
        rc=0
        wait "$pid" || rc=$?
        case "$rc" in
            0) success_count=$((success_count + 1)) ;;
            75) superseded_count=$((superseded_count + 1)) ;;
            *) other_count=$((other_count + 1)) ;;
        esac
    done

    [ "$success_count" -eq 1 ]
    [ "$superseded_count" -eq 3 ]
    [ "$other_count" -eq 0 ]
    ! grep -Eq 'No such file|JSONDecodeError|Traceback|nonce mismatch' "$log" "$verify_log"
    run verify Write "$ROOT/context/infrastructure.md" ""
    [ "$status" -eq 0 ]
    [ "$(find "$TMP_EVIDENCE" -maxdepth 1 -name '.nonce.*' | wc -l)" -eq 0 ]
}

@test "slow A is superseded by fast B and cannot resurrect old proof" {
    local tmp_root="$TMP_EVIDENCE/generation_order"
    local evidence_dir="$TMP_EVIDENCE/generation_order_evidence"
    mkdir -p "$tmp_root/scripts/hooks" "$tmp_root/scripts" "$tmp_root/context" "$tmp_root/docs/semantic-index" "$evidence_dir"
    cp "$ROOT/scripts/hooks/three_layer_preflight.sh" "$tmp_root/scripts/hooks/three_layer_preflight.sh"
    cp "$ROOT/context/semantic-map.md" "$tmp_root/context/semantic-map.md"
    : > "$tmp_root/context/probe.md"
    : > "$tmp_root/docs/semantic-index/index.md"
    cat > "$tmp_root/scripts/memory_db_query.sh" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *slow-A* ]] && sleep 0.8 || sleep 0.2
exit 0
EOF
    cp "$tmp_root/scripts/memory_db_query.sh" "$tmp_root/scripts/semantic_search.sh"
    chmod +x "$tmp_root/scripts/memory_db_query.sh" "$tmp_root/scripts/semantic_search.sh"

    local agent="generation" pane="%generation" evidence="$evidence_dir/evidence_generation__generation.json"
    local a_pid b_pid a_rc=0 b_rc=0 a_nonce b_nonce old_proof_pass=0 observed_nonce
    run env THREE_LAYER_PREACTION_EVIDENCE_DIR="$evidence_dir" THREE_LAYER_AGENT_ID="$agent" TMUX_PANE="$pane" \
        bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" verify Write "$tmp_root/context/probe.md" ""
    [ "$status" -eq 0 ]
    env THREE_LAYER_PREACTION_EVIDENCE_DIR="$evidence_dir" THREE_LAYER_AGENT_ID="$agent" TMUX_PANE="$pane" \
        bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" issue "slow-A" >"$TMP_EVIDENCE/a.out" 2>&1 &
    a_pid=$!
    for _ in $(seq 1 50); do [ -s "$evidence.current" ] && break; sleep 0.01; done
    a_nonce="$(cat "$evidence.current")"

    env THREE_LAYER_PREACTION_EVIDENCE_DIR="$evidence_dir" THREE_LAYER_AGENT_ID="$agent" TMUX_PANE="$pane" \
        bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" issue "fast-B" >"$TMP_EVIDENCE/b.out" 2>&1 &
    b_pid=$!
    for _ in $(seq 1 50); do
        b_nonce="$(cat "$evidence.current" 2>/dev/null || true)"
        [ -n "$b_nonce" ] && [ "$b_nonce" != "$a_nonce" ] && break
        sleep 0.01
    done
    [ -n "$b_nonce" ]
    [ "$b_nonce" != "$a_nonce" ]
    while kill -0 "$a_pid" 2>/dev/null || kill -0 "$b_pid" 2>/dev/null; do
        if [ -s "$evidence" ] && env THREE_LAYER_PREACTION_EVIDENCE_DIR="$evidence_dir" THREE_LAYER_AGENT_ID="$agent" TMUX_PANE="$pane" \
            bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" verify Write "$tmp_root/context/probe.md" "" >/dev/null 2>&1; then
            observed_nonce="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["nonce"])' "$evidence")"
            [ "$observed_nonce" = "$b_nonce" ] || old_proof_pass=$((old_proof_pass + 1))
        fi
        sleep 0.01
    done
    wait "$a_pid" || a_rc=$?
    wait "$b_pid" || b_rc=$?

    [ "$a_rc" -eq 75 ]
    [ "$b_rc" -eq 0 ]
    ! grep -q "$evidence" "$TMP_EVIDENCE/a.out"
    [ "$old_proof_pass" -eq 0 ]
    run python3 - "$evidence" "$b_nonce" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["nonce"] == sys.argv[2]
assert data["prompt_hash"]
PY
    [ "$status" -eq 0 ]
    run env THREE_LAYER_PREACTION_EVIDENCE_DIR="$evidence_dir" THREE_LAYER_AGENT_ID="$agent" TMUX_PANE="$pane" \
        bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" verify Write "$tmp_root/context/probe.md" ""
    [ "$status" -eq 0 ]
}

@test "redirectを含むechoは変更系としてWARN fail-open" {
    run verify Bash "" "echo ok > repo-file"
    [ "$status" -eq 0 ]
}

@test "複合rgとtouchは全体を変更系としてWARN fail-open" {
    run verify Bash "" "rg -n foo file; touch repo-file"
    [ "$status" -eq 0 ]
}

@test "batsはread-only許可リスト外だが証跡なし時WARN fail-open" {
    run verify Bash "" "bats tests/unit/test_three_layer_preflight.bats"
    [ "$status" -eq 0 ]
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
    [ "$status" -eq 0 ]
}

@test "4時間超の証跡はBLOCK" {
    local issued
    issued="$(date -Iseconds -d '5 hours ago')"
    printf '{"agent_id":"%s","pane_id":"%s","prompt_hash":"old","nonce":"expired_nonce","issued_at":"%s","memory_db":"0","semantic":"0","obsidian":"0","status":"success"}\n' "$AGENT" "$PANE" "$issued" > "$EVIDENCE"
    printf 'expired_nonce\n' > "$EVIDENCE.current"
    run verify Write "$ROOT/context/infrastructure.md" ""
    [ "$status" -eq 0 ]
}

@test "prompt引数でstdin欠落を回復" {
    run issue_with_fixtures "fixture recovered prompt" </dev/null
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
    run issue_with_fixtures "$(printf 'line one about the codebase\nline two more detail\nline three')"
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

@test "evidence statusがfailedでも一般BashはWARN fail-open" {
    printf '{"agent_id":"%s","pane_id":"%s","prompt_hash":"x","nonce":"n","issued_at":"2026-07-10T15:00:00+09:00","memory_db":"0","semantic":"0","obsidian":"2","status":"failed"}\n' \
        "$AGENT" "$PANE" > "$EVIDENCE"
    printf 'n\n' > "$EVIDENCE.current"
    run verify Bash "" "touch repo-file"
    [ "$status" -eq 0 ]
}

@test "一層が失敗すれば他二層が成功しても証跡を公開しない" {
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
    run find "$evidence_dir" -maxdepth 1 -name 'evidence_onelayer*.json' -print
    [ -z "$output" ]
}

@test "cold TTL refresh timeoutはparse可能なstale causal cacheからmetadataを復元" {
    local tmp_root="$TMP_EVIDENCE/stale_causal"
    mkdir -p "$tmp_root/scripts/hooks" "$tmp_root/scripts/lib" "$tmp_root/scripts" "$tmp_root/context" "$tmp_root/docs/semantic-index" "$tmp_root/.git"
    git -C "$tmp_root" init -q
    cp "$ROOT/scripts/hooks/three_layer_preflight.sh" "$tmp_root/scripts/hooks/three_layer_preflight.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp_root/scripts/memory_db_query.sh"
    cp "$tmp_root/scripts/memory_db_query.sh" "$tmp_root/scripts/semantic_search.sh"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$2"\nexit 124\n' > "$tmp_root/scripts/lib/causal_index.sh"
    chmod +x "$tmp_root/scripts/memory_db_query.sh" "$tmp_root/scripts/semantic_search.sh" "$tmp_root/scripts/lib/causal_index.sh"
    printf 'fixture\tdocs/fixture.md\n' > "$tmp_root/stale.tsv"
    : > "$tmp_root/docs/semantic-index/index.md"
    local evidence_dir="$TMP_EVIDENCE/stale_causal_evidence"
    run env THREE_LAYER_BATCH_PRIMARY=0 THREE_LAYER_PRIMARY_TIMEOUT_SECONDS=0.05 THREE_LAYER_GLOBAL_BUDGET_MS=900 THREE_LAYER_CAUSAL_INDEX_CACHE="$tmp_root/stale.tsv" THREE_LAYER_PREACTION_EVIDENCE_DIR="$evidence_dir" THREE_LAYER_AGENT_ID="stale" TMUX_PANE="%stale" \
        bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" issue "fixture"
    echo "$output" >&3
    [ "$status" -eq 0 ]
    run python3 - "$evidence_dir/evidence_stale__stale.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(data["obsidian_count"]) == 1
assert data["obsidian_source"].endswith("stale.tsv")
assert data["obsidian_timestamp"]
PY
    [ "$status" -eq 0 ]
}

@test "evidence失敗中はrepairと一般変更の双方をfail-openし一般変更をWARN記録" {
    printf '{"agent_id":"%s","pane_id":"%s","prompt_hash":"x","nonce":"n","issued_at":"2026-07-10T15:00:00+09:00","memory_db":"0","semantic":"0","obsidian":"124","status":"failed"}\n' "$AGENT" "$PANE" > "$EVIDENCE"
    printf 'n\n' > "$EVIDENCE.current"
    run verify Bash "" "bash scripts/inbox_mark_read.sh hanzo msg_1"
    [ "$status" -eq 0 ]
    run verify Bash "" "bash scripts/inbox_write.sh karo notice feedback hanzo inspect"
    [ "$status" -eq 0 ]
    run verify Bash "" "bash scripts/bulletin_write.sh hanzo notice"
    [ "$status" -eq 0 ]
    run verify Bash "" "bash scripts/lib/causal_index.sh build /tmp/causal.tsv"
    [ "$status" -eq 0 ]
    run verify Bash "" "touch repo-file"
    [ "$status" -eq 0 ]
}

@test "WAL sidecar許容でもempty immutable mainは拒否し既存refresh lockとsingle-flight" {
    local tmp_root="$TMP_EVIDENCE/wal_cache" cache="$TMP_EVIDENCE/wal_cache.db"
    mkdir -p "$tmp_root/scripts/hooks" "$tmp_root/scripts/lib" "$tmp_root/scripts" "$tmp_root/context" "$tmp_root/docs/semantic-index" "$tmp_root/data" "$tmp_root/.git"
    git -C "$tmp_root" init -q
    cp "$ROOT/scripts/hooks/three_layer_preflight.sh" "$tmp_root/scripts/hooks/three_layer_preflight.sh"
    cp "$ROOT/scripts/lib/memory_db_cache.sh" "$tmp_root/scripts/lib/memory_db_cache.sh"
    cp "$ROOT/scripts/memory_db_live_insert.py" "$tmp_root/scripts/memory_db_live_insert.py"
    cp "$THREE_LAYER_DB_FIXTURE" "$tmp_root/data/multi_agent_shogun_memory.db"
    cp "$THREE_LAYER_DB_FIXTURE" "$cache"
    python3 - "$cache" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as conn:
    conn.execute("DELETE FROM events")
PY
    printf '%s\n' "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf unknown)" > "$cache.boot_id"
    : > "$cache-wal"
    : > "$cache-shm"
    printf 'fixture\n' > "$tmp_root/docs/semantic-index/index.md"
    printf 'fixture\tdocs/fixture.md\n' > "$tmp_root/stale.tsv"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$2"\nexit 124\n' > "$tmp_root/scripts/lib/causal_index.sh"
    chmod +x "$tmp_root/scripts/lib/causal_index.sh"
    exec 9>"$cache.refresh.lock"
    flock -x 9
    local evidence_dir="$TMP_EVIDENCE/wal_cache_evidence"
    run env SHOGUN_MEMORY_DB_CACHE_PATH="$cache" THREE_LAYER_CAUSAL_INDEX_CACHE="$tmp_root/stale.tsv" THREE_LAYER_PREACTION_EVIDENCE_DIR="$evidence_dir" THREE_LAYER_AGENT_ID="wal" TMUX_PANE="%wal" \
        bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" issue "fixture"
    [ "$status" -eq 0 ]
    run python3 - "$evidence_dir/evidence_wal__wal.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(data["memory_count"]) > 0
assert data["status"] == "success"
PY
    [ "$status" -eq 0 ]
    run python3 - "$cache" <<'PY'
import sqlite3, sys
with sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True) as conn:
    assert conn.execute("SELECT COUNT(*) FROM events").fetchone()[0] == 0
PY
    [ "$status" -eq 0 ]
    flock -u 9
}

@test "ext4 FTS5 snapshotは複数語CJKを20回安定検索する" {
    local tmp_root="$TMP_EVIDENCE/fts20" cache="$TMP_EVIDENCE/fts20-cache.db"
    local evidence_dir="$TMP_EVIDENCE/fts20-evidence" boot_id
    mkdir -p "$tmp_root/scripts/hooks" "$tmp_root/scripts/lib" "$tmp_root/scripts" "$tmp_root/context" "$tmp_root/docs/semantic-index" "$tmp_root/data" "$tmp_root/.git"
    git -C "$tmp_root" init -q
    cp "$ROOT/scripts/hooks/three_layer_preflight.sh" "$tmp_root/scripts/hooks/three_layer_preflight.sh"
    cp "$ROOT/scripts/lib/memory_db_cache.sh" "$tmp_root/scripts/lib/memory_db_cache.sh"
    cp "$ROOT/scripts/memory_db_live_insert.py" "$tmp_root/scripts/memory_db_live_insert.py"
    cp "$THREE_LAYER_DB_FIXTURE" "$tmp_root/data/multi_agent_shogun_memory.db"
    cp "$THREE_LAYER_DB_FIXTURE" "$cache"
    boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf unknown)"
    printf '%s\n' "$boot_id" > "$cache.boot_id"
    printf '三層 記憶 preflight fixture\n' > "$tmp_root/docs/semantic-index/index.md"
    printf '三層 記憶 preflight fixture\tdocs/fixture.md\n' > "$tmp_root/stale.tsv"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$2"\n' > "$tmp_root/scripts/lib/causal_index.sh"
    chmod +x "$tmp_root/scripts/lib/causal_index.sh"

    local successes=0 memory_124=0 i rc evidence
    for i in $(seq 1 20); do
        rc=0
        env SHOGUN_MEMORY_DB_CACHE_PATH="$cache" THREE_LAYER_CAUSAL_INDEX_CACHE="$tmp_root/stale.tsv" THREE_LAYER_PREACTION_EVIDENCE_DIR="$evidence_dir" THREE_LAYER_AGENT_ID="fts$i" TMUX_PANE="%fts$i" \
            bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" issue "三層 記憶 preflight fixture" >/dev/null 2>&1 || rc=$?
        if [ "$rc" -eq 0 ]; then
            successes=$((successes + 1))
            evidence="$evidence_dir/evidence_fts${i}__fts${i}.json"
            python3 - "$evidence" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["memory_db"] == "0"
assert int(data["memory_count"]) == 1
assert data["memory_query"]
assert data["memory_timestamp"]
PY
        elif [ "$rc" -eq 124 ]; then
            memory_124=$((memory_124 + 1))
        fi
    done
    [ "$successes" -eq 20 ]
    [ "$memory_124" -eq 0 ]

}

@test "外部source DBはimmutableにせず未checkpoint WAL eventを検索" {
    local external_db="$TMP_EVIDENCE/external-wal.db" ready="$TMP_EVIDENCE/external-wal.ready"
    cp "$THREE_LAYER_DB_FIXTURE" "$external_db"
    python3 - "$external_db" "$ready" <<'PY' &
import pathlib, sqlite3, sys, time
db, ready = sys.argv[1:]
conn = sqlite3.connect(db)
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("PRAGMA wal_autocheckpoint=0")
conn.execute("INSERT INTO events(id, ts, agent, direction, summary, detail, source_file) VALUES(?,?,?,?,?,?,?)", ("wal-live", "2026-07-17T23:00:00+09:00", "test", "internal", "wal_live_event", "wal_live_event", "fixture"))
rowid = conn.execute("SELECT rowid FROM events WHERE id='wal-live'").fetchone()[0]
conn.execute("INSERT INTO events_fts(rowid, summary, detail) VALUES(?,?,?)", (rowid, "wal_live_event", "wal_live_event"))
conn.commit()
pathlib.Path(ready).touch()
time.sleep(5)
conn.close()
PY
    local writer=$!
    for _ in 1 2 3 4 5; do [ -e "$ready" ] && break; sleep 0.1; done
    [ -e "$ready" ]
    local evidence_dir="$TMP_EVIDENCE/external_wal_evidence"
    run env MEMORY_DB_QUERY_DB="$external_db" THREE_LAYER_SEMANTIC_INDEX="$THREE_LAYER_SEMANTIC_FIXTURE" THREE_LAYER_CAUSAL_INDEX_CACHE="$THREE_LAYER_CAUSAL_FIXTURE" THREE_LAYER_CAUSAL_REFRESH_DISABLED=1 THREE_LAYER_PREACTION_EVIDENCE_DIR="$evidence_dir" THREE_LAYER_AGENT_ID="externalwal" TMUX_PANE="%externalwal" \
        bash "$ROOT/scripts/hooks/three_layer_preflight.sh" issue "wal_live_event fixture"
    wait "$writer"
    [ "$status" -eq 0 ]
    run python3 - "$evidence_dir/evidence_externalwal__externalwal.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(data["memory_count"]) >= 1
assert data["memory_query"] == "wal_live_event"
PY
    [ "$status" -eq 0 ]
}

@test "並行issueのdetached causal refreshはbuild完了までsingle-flight" {
    local tmp_root="$TMP_EVIDENCE/causal_singleflight" counter="$TMP_EVIDENCE/causal-build.count"
    mkdir -p "$tmp_root/scripts/hooks" "$tmp_root/scripts/lib" "$tmp_root/scripts" "$tmp_root/context" "$tmp_root/docs/semantic-index" "$tmp_root/.git"
    git -C "$tmp_root" init -q
    cp "$ROOT/scripts/hooks/three_layer_preflight.sh" "$tmp_root/scripts/hooks/three_layer_preflight.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp_root/scripts/memory_db_query.sh"
    cp "$tmp_root/scripts/memory_db_query.sh" "$tmp_root/scripts/semantic_search.sh"
    cat > "$tmp_root/scripts/lib/causal_index.sh" <<'EOF'
#!/usr/bin/env bash
printf '1\n' >> "$CAUSAL_BUILD_COUNTER"
sleep 1
printf '%s\n' "$2"
EOF
    chmod +x "$tmp_root/scripts/memory_db_query.sh" "$tmp_root/scripts/semantic_search.sh" "$tmp_root/scripts/lib/causal_index.sh"
    printf 'fixture\tdocs/fixture.md\n' > "$tmp_root/stale.tsv"
    : > "$tmp_root/docs/semantic-index/index.md"
    local evidence_dir="$TMP_EVIDENCE/causal_singleflight_evidence"
    env CAUSAL_BUILD_COUNTER="$counter" THREE_LAYER_BATCH_PRIMARY=0 THREE_LAYER_CAUSAL_INDEX_CACHE="$tmp_root/stale.tsv" THREE_LAYER_PREACTION_EVIDENCE_DIR="$evidence_dir" THREE_LAYER_AGENT_ID="causalsf" TMUX_PANE="%causalsf" \
        bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" issue "fixture" >/dev/null &
    local p1=$!
    env CAUSAL_BUILD_COUNTER="$counter" THREE_LAYER_BATCH_PRIMARY=0 THREE_LAYER_CAUSAL_INDEX_CACHE="$tmp_root/stale.tsv" THREE_LAYER_PREACTION_EVIDENCE_DIR="$evidence_dir" THREE_LAYER_AGENT_ID="causalsf" TMUX_PANE="%causalsf" \
        bash "$tmp_root/scripts/hooks/three_layer_preflight.sh" issue "fixture" >/dev/null &
    local p2=$!
    wait "$p1" || true
    wait "$p2" || true
    sleep 1.2
    [ "$(wc -l < "$counter")" -eq 1 ]
}
