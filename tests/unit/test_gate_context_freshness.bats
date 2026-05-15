#!/usr/bin/env bats
# gate_context_freshness.sh regression tests

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_context_freshness.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/context"

    cat > "$TEST_TMPDIR/scripts/ntfy.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$TEST_TMPDIR/ntfy_calls.log"
exit 0
SH
    chmod +x "$TEST_TMPDIR/scripts/ntfy.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
    unset CONTEXT_FRESHNESS_ROOT CONTEXT_FRESHNESS_CHECK_SCRIPT CONTEXT_FRESHNESS_NTFY_SCRIPT
    unset CONTEXT_FRESHNESS_TODAY CONTEXT_FRESHNESS_GATE_DISABLE_CACHE
    unset CONTEXT_FRESHNESS_ALERT_STATE_DIR CONTEXT_FRESHNESS_ALERT_NOW CONTEXT_FRESHNESS_ALERT_DEBOUNCE_SECONDS
}

write_context_file() {
    local rel_path="$1"
    local last_updated="$2"
    mkdir -p "$TEST_TMPDIR/$(dirname "$rel_path")"
    cat > "$TEST_TMPDIR/$rel_path" <<EOF
<!-- last_updated: ${last_updated} cmd_test -->

# ${rel_path}
EOF
}

run_gate() {
    CONTEXT_FRESHNESS_ROOT="$TEST_TMPDIR" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$TEST_TMPDIR/scripts/context_freshness_check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT="$TEST_TMPDIR/scripts/ntfy.sh" \
    CONTEXT_FRESHNESS_TODAY="2026-05-11" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="${CONTEXT_FRESHNESS_ALERT_STATE_DIR:-$TEST_TMPDIR/alert_state}" \
    CONTEXT_FRESHNESS_ALERT_NOW="${CONTEXT_FRESHNESS_ALERT_NOW:-1770000000}" \
    run bash "$PROJECT_ROOT/scripts/gates/gate_context_freshness.sh"
}

@test "ALERT output includes update command templates for stale top 3" {
    cat > "$TEST_TMPDIR/scripts/context_freshness_check.sh" <<'SH'
#!/usr/bin/env bash
cat <<'OUT'
WARN: context/oldest.md last_updated 40日前。更新要否を確認せよ
WARN: context/second.md last_updated 30日前。更新要否を確認せよ
WARN: context/third.md last_updated 20日前。更新要否を確認せよ
WARN: context/fourth.md last_updated 18日前。更新要否を確認せよ
OUT
SH
    chmod +x "$TEST_TMPDIR/scripts/context_freshness_check.sh"
    write_context_file context/oldest.md 2026-04-01
    write_context_file context/second.md 2026-04-11
    write_context_file context/third.md 2026-04-21
    write_context_file context/fourth.md 2026-04-23

    run_gate

    [ "$status" -eq 1 ]
    [[ "$output" == *"--- 更新cmdテンプレート TOP3 ---"* ]]
    [[ "$output" == *"cmd_ctx_oldest_20260511"* ]]
    [[ "$output" == *"cmd_ctx_second_20260511"* ]]
    [[ "$output" == *"cmd_ctx_third_20260511"* ]]
    [[ "$output" != *"cmd_ctx_fourth_20260511"* ]]
    [[ "$output" == *"AC3: bash scripts/gates/gate_context_freshness.sh 実行時に context/oldest.md がALERT対象から外れる"* ]]
}

@test "first ALERT sends ntfy and logs sent to stderr" {
    cat > "$TEST_TMPDIR/scripts/context_freshness_check.sh" <<'SH'
#!/usr/bin/env bash
cat <<'OUT'
WARN: context/stale.md last_updated 30日前。更新要否を確認せよ
OUT
SH
    chmod +x "$TEST_TMPDIR/scripts/context_freshness_check.sh"
    write_context_file context/stale.md 2026-04-11

    run_gate

    [ "$status" -eq 1 ]
    [[ "$output" == *"[gate_context_freshness] ntfy sent: stale.md(30日)"* ]]
    [ "$(wc -l < "$TEST_TMPDIR/ntfy_calls.log")" -eq 1 ]
    [[ "$(cat "$TEST_TMPDIR/ntfy_calls.log")" == *"【将軍】context鮮度ALERT: stale.md(30日)"* ]]
}

@test "same ALERT within 60 minutes skips ntfy and logs skip to stderr" {
    cat > "$TEST_TMPDIR/scripts/context_freshness_check.sh" <<'SH'
#!/usr/bin/env bash
cat <<'OUT'
WARN: context/stale.md last_updated 30日前。更新要否を確認せよ
OUT
SH
    chmod +x "$TEST_TMPDIR/scripts/context_freshness_check.sh"
    write_context_file context/stale.md 2026-04-11

    CONTEXT_FRESHNESS_ALERT_NOW=1770000000 run_gate
    [ "$status" -eq 1 ]

    CONTEXT_FRESHNESS_ALERT_NOW=1770000300 run_gate

    [ "$status" -eq 1 ]
    [[ "$output" == *"[gate_context_freshness] ntfy skip: same ALERT sent 300s ago (<3600s): stale.md(30日)"* ]]
    [ "$(wc -l < "$TEST_TMPDIR/ntfy_calls.log")" -eq 1 ]
}

@test "WARN-only output does not include update command templates" {
    cat > "$TEST_TMPDIR/scripts/context_freshness_check.sh" <<'SH'
#!/usr/bin/env bash
cat <<'OUT'
WARN: context/warn-only.md last_updated 9日前。更新要否を確認せよ
OUT
SH
    chmod +x "$TEST_TMPDIR/scripts/context_freshness_check.sh"
    write_context_file context/warn-only.md 2026-05-02

    run_gate

    [ "$status" -eq 2 ]
    [[ "$output" == *"WARN: warn-only.md (9日前更新)"* ]]
    [[ "$output" != *"--- 更新cmdテンプレート TOP3 ---"* ]]
}
