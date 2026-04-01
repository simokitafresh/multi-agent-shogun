#!/usr/bin/env bats
# test_cmd_complete_gate_stk_status.bats - cmd_1561: update_status()関数単体テスト
# Optimized: gate全体実行→関数直接呼び出し（33s TIMEOUT→<1s）

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    export SRC_YAML_FIELD_SET="$PROJECT_ROOT/scripts/lib/yaml_field_set.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    [ -f "$SRC_YAML_FIELD_SET" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/stk_status.XXXXXX")"
    export SCRIPT_DIR="$TEST_TMPDIR"
    export YAML_FILE="$TEST_TMPDIR/queue/shogun_to_karo.yaml"

    mkdir -p "$TEST_TMPDIR/queue" "$TEST_TMPDIR/scripts/lib"

    # yaml_field_set依存
    cp "$SRC_YAML_FIELD_SET" "$TEST_TMPDIR/scripts/lib/yaml_field_set.sh"
    chmod +x "$TEST_TMPDIR/scripts/lib/yaml_field_set.sh"

    # update_status関数をsource + yaml_field_set
    source "$SRC_YAML_FIELD_SET"
    eval "$(sed -n '/^update_status()/,/^}/p' "$SRC_GATE_SCRIPT")"
}

teardown() {
    [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "GATE CLEAR sets STK status to done (mapping format)" {
    cat > "$YAML_FILE" <<EOF
commands:
  cmd_999:
    purpose: "STK status update test"
    project: infra
    status: delegated
    timestamp: "2026-03-04T21:25:00+09:00"
EOF

    run update_status "cmd_999"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS UPDATED"* ]]

    run grep "status: done" "$YAML_FILE"
    [ "$status" -eq 0 ]
}

@test "GATE CLEAR sets STK status to done (list format)" {
    cat > "$YAML_FILE" <<EOF
commands:
  - id: cmd_999
    purpose: "STK status update test"
    project: infra
    status: delegated
    delegated_at: "2026-03-04T21:25:00"
EOF

    run update_status "cmd_999"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS UPDATED"* ]]

    run grep "status: done" "$YAML_FILE"
    [ "$status" -eq 0 ]
}

@test "GATE CLEAR skips update when STK status already done" {
    cat > "$YAML_FILE" <<EOF
commands:
  cmd_999:
    purpose: "STK status already done test"
    project: infra
    status: done
    timestamp: "2026-03-04T21:25:00+09:00"
EOF

    run update_status "cmd_999"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS ALREADY COMPLETED"* ]]
}
