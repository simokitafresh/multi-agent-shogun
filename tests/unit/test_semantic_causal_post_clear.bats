#!/usr/bin/env bats

setup() {
    export ROOT="$(mktemp -d)"
    mkdir -p "$ROOT/scripts" "$ROOT/queue/gates/cmd_test"
    cp "$BATS_TEST_DIRNAME/../../scripts/semantic_causal_post_clear.sh" "$ROOT/scripts/"
    chmod +x "$ROOT/scripts/semantic_causal_post_clear.sh"
    cat > "$ROOT/scripts/heavy_job_admission.sh" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = -- ] && shift
exec "$@"
SH
    chmod +x "$ROOT/scripts/heavy_job_admission.sh"
    cat > "$ROOT/scripts/bulletin_write.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${BULLETIN_LOG:?}"
SH
    chmod +x "$ROOT/scripts/bulletin_write.sh"
    export BULLETIN_LOG="$ROOT/bulletin.log"
    : > "$ROOT/queue/gates/cmd_test/semantic_causal_audit.pending"
    printf '%s\n' '{"id":"cmd_test","title":"test","purpose":"test","files":[]}' > "$ROOT/queue/gates/cmd_test/semantic_causal_payload.json"
    cat > "$ROOT/scripts/semantic_index_update.sh" <<'SH'
#!/usr/bin/env bash
printf 'index\n' >> "${ORDER_LOG:?}"
SH
    cat > "$ROOT/scripts/semantic_map_generate.sh" <<'SH'
#!/usr/bin/env bash
printf 'map\n' >> "${ORDER_LOG:?}"
SH
    chmod +x "$ROOT/scripts/semantic_index_update.sh" "$ROOT/scripts/semantic_map_generate.sh"
    export ORDER_LOG="$ROOT/order.log"
}

teardown() {
    rm -rf "$ROOT"
}

@test "durable semantic audit persists PASS and clears pending" {
    cat > "$ROOT/scripts/pass_test.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$ROOT/scripts/pass_test.sh"
    cat > "$ROOT/scripts/semantic_causal_traverse.sh" <<'SH'
#!/usr/bin/env bash
printf 'traverse\n' >> "${ORDER_LOG:?}"
printf '%s\n' '{"total":1,"no_test_scripts_count":0,"start_concepts":["gate_quality_framework"],"affected_nodes":[{"test_scripts":["scripts/pass_test.sh"]}]}'
SH
    chmod +x "$ROOT/scripts/semantic_causal_traverse.sh"

    run bash "$ROOT/scripts/semantic_causal_post_clear.sh" cmd_test
    [ "$status" -eq 0 ]
    grep -q '^state=PASS$' "$ROOT/queue/gates/cmd_test/semantic_causal_audit.result"
    grep -q '^tests_pass=1$' "$ROOT/queue/gates/cmd_test/semantic_causal_audit.result"
    [ "$(paste -sd, "$ORDER_LOG")" = "index,map,traverse" ]
    [ ! -e "$ROOT/queue/gates/cmd_test/semantic_causal_audit.pending" ]
}

@test "declared missing test is durable FAIL and sends warning" {
    cat > "$ROOT/scripts/semantic_causal_traverse.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"total":1,"no_test_scripts_count":0,"start_concepts":["gate_quality_framework"],"affected_nodes":[{"test_scripts":["tests/missing.bats"]}]}'
SH
    chmod +x "$ROOT/scripts/semantic_causal_traverse.sh"

    run bash "$ROOT/scripts/semantic_causal_post_clear.sh" cmd_test
    [ "$status" -eq 0 ]
    grep -q '^state=FAIL$' "$ROOT/queue/gates/cmd_test/semantic_causal_audit.result"
    grep -q '^tests_missing=1$' "$ROOT/queue/gates/cmd_test/semantic_causal_audit.result"
    grep -q 'semantic causal audit FAIL' "$BULLETIN_LOG"
}

@test "invalid traverse JSON clears pending with durable FAIL" {
    cat > "$ROOT/scripts/semantic_causal_traverse.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'not-json'
SH
    chmod +x "$ROOT/scripts/semantic_causal_traverse.sh"

    run bash "$ROOT/scripts/semantic_causal_post_clear.sh" cmd_test
    [ "$status" -eq 0 ]
    grep -q '^state=FAIL$' "$ROOT/queue/gates/cmd_test/semantic_causal_audit.result"
    grep -q '^reason=traverse_invalid_json$' "$ROOT/queue/gates/cmd_test/semantic_causal_audit.result"
    [ ! -e "$ROOT/queue/gates/cmd_test/semantic_causal_audit.pending" ]
}

@test "detached worker survives launcher shell exit and persists result" {
    cat > "$ROOT/scripts/pass_test.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$ROOT/scripts/pass_test.sh"
    cat > "$ROOT/scripts/semantic_causal_traverse.sh" <<'SH'
#!/usr/bin/env bash
sleep 0.2
printf '%s\n' '{"total":1,"no_test_scripts_count":0,"start_concepts":["gate_quality_framework"],"affected_nodes":[{"test_scripts":["scripts/pass_test.sh"]}]}'
SH
    chmod +x "$ROOT/scripts/semantic_causal_traverse.sh"

    run bash -c 'nohup setsid env SHOGUN_HEAVY_JOB_LOCK_HELD=0 bash "$1/scripts/semantic_causal_post_clear.sh" cmd_test >/dev/null 2>&1 </dev/null &' _ "$ROOT"
    [ "$status" -eq 0 ]
    for _ in {1..50}; do
        [ -f "$ROOT/queue/gates/cmd_test/semantic_causal_audit.result" ] && break
        sleep 0.05
    done
    grep -q '^state=PASS$' "$ROOT/queue/gates/cmd_test/semantic_causal_audit.result"
}

@test "CLEAR route keeps small evidence writers synchronous and launches durable worker" {
    gate="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"
    run python3 - "$gate" <<'PY'
import sys
t=open(sys.argv[1], encoding="utf-8").read()
start=t.index("Semantic index update (GATE CLEAR):")
normal=t[start:t.index("exit 0\nelse", start)]
assert "nohup setsid env SHOGUN_HEAVY_JOB_LOCK_HELD=0" in normal
assert "semantic_causal_audit.result" in normal
assert "semantic_causal_payload.json" in normal
assert '(bash "$SCRIPT_DIR/scripts/semantic_index_update.sh"' not in normal
assert '(bash "$SCRIPT_DIR/scripts/semantic_map_generate.sh"' not in normal
assert '(bash "$SCRIPT_DIR/scripts/gunshi_gate_reflux.sh"' not in normal
assert '(bash "$SCRIPT_DIR/scripts/gates/gate_workaround_rate.sh"' not in normal
PY
    [ "$status" -eq 0 ]
}
