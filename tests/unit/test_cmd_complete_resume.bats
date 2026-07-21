#!/usr/bin/env bats

setup() {
    # test_necessity: resume tests must observe the durable worker's terminal
    # failure status rather than the public caller's successful queue handoff.
    # These tests exercise the worker's durable failure propagation and resume
    # contract.  Keep the tail synchronous so Bats observes the worker exit
    # status; the public caller's detached latency contract is covered by
    # test_cmd_complete_wrapper.bats.
    export CMD_COMPLETE_SYNC_TAIL=1
    ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$ROOT/scripts/gates" "$ROOT/scripts/lib" "$ROOT/queue/gates/cmd_resume" "$ROOT/queue/archive/cmds" "$ROOT/logs"
    cp "$BATS_TEST_DIRNAME/../../scripts/cmd_complete.sh" "$ROOT/scripts/cmd_complete.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/defense_overhead_writer.sh" "$ROOT/scripts/lib/defense_overhead_writer.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/retro_pane_prompt.sh" "$ROOT/scripts/lib/retro_pane_prompt.sh"
    printf '{"project":"infra","verdict":"APPROVE"}\n' > "$ROOT/queue/gates/cmd_resume/sg7_bundle.json"
    : > "$ROOT/logs/gate_metrics.log"
    for name in lesson_review cmd_complete_gate cmd_quality_log dashboard_update ntfy_cmd inbox_archive; do
        cat > "$ROOT/scripts/$name.sh" <<'EOF'
#!/usr/bin/env bash
name="$(basename "$0" .sh)"
printf '%s\n' "$name" >> "$CMD_COMPLETE_TEST_LOG"
fail_file="${CMD_COMPLETE_FAIL_DIR:-}/$name"
if [[ -f "$fail_file" ]]; then
    n="$(cat "$fail_file")"
    if (( n > 0 )); then printf '%s\n' "$((n-1))" > "$fail_file"; exit 1; fi
fi
[[ "$name" == cmd_complete_gate ]] && printf '%s CLEAR\n' "$2" >> "${CMD_COMPLETE_ROOT_DIR}/logs/gate_metrics.log"
exit 0
EOF
        chmod +x "$ROOT/scripts/$name.sh"
    done
    cat > "$ROOT/scripts/gates/gate_yaml_status.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$ROOT/scripts/gates/gate_yaml_status.sh"
    cat > "$ROOT/scripts/review_bundle.py" <<'PY'
import json, os
with open(os.environ["CMD_COMPLETE_TEST_LOG"], "a") as fh: fh.write("sg7_consume\n")
print(json.dumps({"project": "infra"}))
PY
    LOG="$ROOT/steps.log"
    FAIL="$ROOT/fail"
    mkdir -p "$FAIL"
    export CMD_COMPLETE_ROOT_DIR="$ROOT" CMD_COMPLETE_SCRIPT_DIR="$ROOT/scripts"
    export CMD_COMPLETE_TEST_LOG="$LOG" CMD_COMPLETE_FAIL_DIR="$FAIL"
    export CMD_COMPLETE_DASHBOARD_RETRY_DELAY=0 CMD_COMPLETE_NTFY_RETRY_DELAY=0
    export DEFENSE_OVERHEAD_ENABLED=0
}

run_complete() {
    run bash "$ROOT/scripts/cmd_complete.sh" cmd_resume "$ROOT/queue/gates/cmd_resume/sg7_bundle.json"
}

@test "archive failure resumes at the sole unfinished step without duplicate dashboard or ntfy" {
    printf '1\n' > "$FAIL/inbox_archive"
    run_complete
    [ "$status" -ne 0 ]
    [ "$(wc -l < "$LOG")" -eq 7 ]
    run_complete
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$LOG")" -eq 8 ]
    [ "$(grep -c '^dashboard_update$' "$LOG")" -eq 1 ]
    [ "$(grep -c '^ntfy_cmd$' "$LOG")" -eq 1 ]
    [[ "$output" == *"SKIP ntfy checkpoint_verified"* ]]
}

@test "dashboard transient exhaustion resumes at dashboard and does not repeat the first five steps" {
    printf '3\n' > "$FAIL/dashboard_update"
    run_complete
    [ "$status" -ne 0 ]
    [ "$(wc -l < "$LOG")" -eq 7 ]
    run_complete
    [ "$status" -eq 0 ]
    [ "$(grep -c '^sg7_consume$' "$LOG")" -eq 1 ]
    [ "$(grep -c '^dashboard_update$' "$LOG")" -eq 4 ]
    [ "$(grep -c '^ntfy_cmd$' "$LOG")" -eq 1 ]
}

@test "ntfy exhaustion resumes at ntfy without duplicate dashboard" {
    printf '3\n' > "$FAIL/ntfy_cmd"
    run_complete
    [ "$status" -ne 0 ]
    run_complete
    [ "$status" -eq 0 ]
    [ "$(grep -c '^dashboard_update$' "$LOG")" -eq 1 ]
    [ "$(grep -c '^ntfy_cmd$' "$LOG")" -eq 4 ]
}

@test "corrupt checkpoint fails closed before any side effect" {
    printf '{broken\n' > "$ROOT/queue/gates/cmd_resume/completion_checkpoint.json"
    run_complete
    [ "$status" -ne 0 ]
    [ ! -s "$LOG" ]
    [[ "$output" == *"FAILED corrupt checkpoint"* ]]
}

@test "changed SG7 fingerprint starts a new generation instead of skipping old steps" {
    run_complete
    [ "$status" -eq 0 ]
    printf ' \n' >> "$ROOT/queue/gates/cmd_resume/sg7_bundle.json"
    run_complete
    [ "$status" -eq 0 ]
    [ "$(grep -c '^sg7_consume$' "$LOG")" -eq 2 ]
    [ "$(grep -c '^dashboard_update$' "$LOG")" -eq 2 ]
}

@test "same cmd parallel invocations serialize and publish each side effect once" {
    bash "$ROOT/scripts/cmd_complete.sh" cmd_resume "$ROOT/queue/gates/cmd_resume/sg7_bundle.json" > "$ROOT/a.out" 2>&1 &
    p1=$!
    bash "$ROOT/scripts/cmd_complete.sh" cmd_resume "$ROOT/queue/gates/cmd_resume/sg7_bundle.json" > "$ROOT/b.out" 2>&1 &
    p2=$!
    wait "$p1"; wait "$p2"
    [ "$(grep -c '^dashboard_update$' "$LOG")" -eq 1 ]
    [ "$(grep -c '^ntfy_cmd$' "$LOG")" -eq 1 ]
    [ "$(grep -c '^inbox_archive$' "$LOG")" -eq 1 ]
}
