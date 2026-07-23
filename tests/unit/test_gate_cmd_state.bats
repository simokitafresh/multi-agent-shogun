#!/usr/bin/env bats
# test_necessity: Pending cmd evidence must match a complete cmd ID token; substring evidence must remain ALERT because false delegation suppresses required work.

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/gate_cmd_state.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts/gates" "$TEST_ROOT/queue/inbox"
    cp "$BATS_TEST_DIRNAME/../../scripts/gates/gate_cmd_state.sh" \
        "$TEST_ROOT/scripts/gates/gate_cmd_state.sh"
    chmod +x "$TEST_ROOT/scripts/gates/gate_cmd_state.sh"
}

teardown() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

write_pending_cmd() {
    cat > "$TEST_ROOT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_41
    status: pending
    delegated_at:
YAML
    printf 'messages:\n' > "$TEST_ROOT/queue/inbox/karo.yaml"
    : > "$TEST_ROOT/dashboard.md"
    : > "$TEST_ROOT/queue/karo_snapshot.txt"
}

@test "cmd_41 exact evidence is WARN rather than ALERT" {
    write_pending_cmd
    printf -- '- content: cmd_41 delegated\n' >> "$TEST_ROOT/queue/inbox/karo.yaml"

    run bash "$TEST_ROOT/scripts/gates/gate_cmd_state.sh"

    [ "$status" -eq 2 ]
    [[ "$output" == *"WARN: cmd_41"* ]]
    [[ "$output" != *"ALERT: cmd_41"* ]]
}

@test "cmd_4131 and xcmd_41 evidence do not satisfy pending cmd_41" {
    write_pending_cmd
    printf -- '- content: cmd_4131 delegated\n' >> "$TEST_ROOT/queue/inbox/karo.yaml"
    printf 'active: xcmd_41\n' > "$TEST_ROOT/dashboard.md"
    printf 'ninja|hanzo|cmd_4131|done\n' > "$TEST_ROOT/queue/karo_snapshot.txt"

    run bash "$TEST_ROOT/scripts/gates/gate_cmd_state.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"ALERT: cmd_41"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}
