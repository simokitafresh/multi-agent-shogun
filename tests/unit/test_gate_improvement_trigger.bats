#!/usr/bin/env bats
# gate_improvement_trigger.sh regression tests

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_improvement_trigger.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/logs" "$TEST_TMPDIR/queue/inbox"
    echo "messages: []" > "$TEST_TMPDIR/queue/inbox/karo.yaml"

    cat > "$TEST_TMPDIR/scripts/inbox_write.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GATE_IMPROVEMENT_ROOT/inbox_calls.log"
exit 0
SH
    chmod +x "$TEST_TMPDIR/scripts/inbox_write.sh"

    cat > "$TEST_TMPDIR/scripts/ntfy.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GATE_IMPROVEMENT_ROOT/ntfy_calls.log"
exit 0
SH
    chmod +x "$TEST_TMPDIR/scripts/ntfy.sh"

    write_ok_gate gate_lesson_health.sh
    write_ok_gate gate_cmd_state.sh
    write_ok_gate gate_p_average_freshness.sh

    mkdir -p "$TEST_TMPDIR/bin"
    cat > "$TEST_TMPDIR/bin/gh" <<'SH'
#!/usr/bin/env bash
echo success
exit 0
SH
    chmod +x "$TEST_TMPDIR/bin/gh"
    export PATH="$TEST_TMPDIR/bin:$PATH"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
    unset GATE_IMPROVEMENT_ROOT GATE_IMPROVEMENT_NOW GATE_IMPROVEMENT_DEDUP_WINDOW_SECONDS
}

write_ok_gate() {
    local name="$1"
    cat > "$TEST_TMPDIR/scripts/gates/$name" <<'SH'
#!/usr/bin/env bash
echo "--- 総合判定: OK ---"
exit 0
SH
    chmod +x "$TEST_TMPDIR/scripts/gates/$name"
}

write_context_gate() {
    local body="$1"
    cat > "$TEST_TMPDIR/scripts/gates/gate_context_freshness.sh" <<SH
#!/usr/bin/env bash
cat <<'OUT'
${body}
OUT
exit 2
SH
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_context_freshness.sh"
}

run_trigger() {
    GATE_IMPROVEMENT_ROOT="$TEST_TMPDIR" \
    GATE_IMPROVEMENT_NOW="${GATE_IMPROVEMENT_NOW:-1770000000}" \
    run bash "$PROJECT_ROOT/scripts/gate_improvement_trigger.sh"
}

inbox_call_count() {
    grep -c '^karo ' "$TEST_TMPDIR/inbox_calls.log" 2>/dev/null || true
}

@test "same file+alert_type within 24h suppresses ALERT and emits SKIP" {
    write_context_gate "WARN: codd.md (11日前更新)"

    GATE_IMPROVEMENT_NOW=1770000000 run_trigger
    [ "$status" -eq 0 ]
    [[ "$output" == *"SENT: context_freshness"* ]]
    [ "$(inbox_call_count)" -eq 1 ]

    GATE_IMPROVEMENT_NOW=1770000300 run_trigger
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP: context_freshness — WARN: codd.md (11日前更新) は同一file+alert_typeで24時間以内に送信済み"* ]]
    [[ "$output" == *"SKIP: context_freshness — 全ALERT行が同一file+alert_typeの24時間dedup対象。"* ]]
    [ "$(inbox_call_count)" -eq 1 ]
}

@test "dedup is keyed by alert_type so ALERT after WARN is sent" {
    write_context_gate "WARN: codd.md (11日前更新)"
    GATE_IMPROVEMENT_NOW=1770000000 run_trigger
    [ "$status" -eq 0 ]

    write_context_gate "ALERT: codd.md (15日前更新)"
    GATE_IMPROVEMENT_NOW=1770000300 run_trigger
    [ "$status" -eq 0 ]
    [[ "$output" == *"SENT: context_freshness"* ]]
    [ "$(inbox_call_count)" -eq 2 ]
}

@test "same file+alert_type after 24h sends again" {
    write_context_gate "WARN: codd.md (11日前更新)"
    GATE_IMPROVEMENT_NOW=1770000000 run_trigger
    [ "$status" -eq 0 ]

    GATE_IMPROVEMENT_NOW=1770086401 run_trigger
    [ "$status" -eq 0 ]
    [[ "$output" == *"SENT: context_freshness"* ]]
    [ "$(inbox_call_count)" -eq 2 ]
}

@test "exit code alert without ALERT line includes output snippet instead of detail-not-captured" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh" <<'SH'
#!/usr/bin/env bash
echo "plain failure without alert prefix"
exit 1
SH
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh"

    GATE_IMPROVEMENT_NOW=1770000000 run_trigger

    [ "$status" -eq 0 ]
    [[ "$output" == *"SENT: p_average_freshness"* ]]
    [[ "$output" != *"ALERT detail not captured"* ]]
    grep -q 'exit_code=1; output_snippet=plain failure without alert prefix' "$TEST_TMPDIR/logs/gate_alerts.yaml"
}
