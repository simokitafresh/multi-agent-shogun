#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

init_test_root() {
    export TEST_ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p \
        "$TEST_ROOT/scripts/gates" \
        "$TEST_ROOT/queue/reports" \
        "$TEST_ROOT/queue/archive/reports"

    cp "$PROJECT_ROOT/scripts/ninja_done.sh" "$TEST_ROOT/scripts/ninja_done.sh"

    cat > "$TEST_ROOT/scripts/gates/gate_report_format.sh" <<EOF
#!/usr/bin/env bash
if [ "\${GATE_SHOULD_FAIL:-0}" = "1" ]; then
    echo "FAIL: mocked gate" >&2
    exit 1
fi
echo "PASS"
EOF
    chmod +x "$TEST_ROOT/scripts/gates/gate_report_format.sh"

    cat > "$TEST_ROOT/scripts/inbox_write.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_ROOT/inbox_write_calls.log"
EOF
    chmod +x "$TEST_ROOT/scripts/inbox_write.sh"
}

setup() {
    init_test_root
}

@test "help flag exits 0 without touching gate or inbox" {
    run bash "$TEST_ROOT/scripts/ninja_done.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: bash scripts/ninja_done.sh"* ]]
    [ ! -f "$TEST_ROOT/inbox_write_calls.log" ]
}

@test "missing arguments exits 1 with usage" {
    run bash "$TEST_ROOT/scripts/ninja_done.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: bash scripts/ninja_done.sh"* ]]
}

@test "empty summary blocks notification" {
    cat > "$TEST_ROOT/queue/reports/hayate_report_cmd_123.yaml" <<'EOF'
result:
  summary: ""
EOF

    run bash "$TEST_ROOT/scripts/ninja_done.sh" hayate cmd_123
    [ "$status" -eq 1 ]
    [[ "$output" == *"result.summary is empty"* ]]
    [ ! -f "$TEST_ROOT/inbox_write_calls.log" ]
}

@test "archived report with block summary is accepted" {
    cat > "$TEST_ROOT/queue/archive/reports/hayate_report_cmd_124_20260416.yaml" <<'EOF'
result:
  summary: >-
    archived summary
EOF

    run bash "$TEST_ROOT/scripts/ninja_done.sh" hayate cmd_124
    [ "$status" -eq 0 ]
    [ -f "$TEST_ROOT/inbox_write_calls.log" ]
    grep -F "karo hayate、任務完了。報告YAML確認されたし。 report_received hayate" \
        "$TEST_ROOT/inbox_write_calls.log"
}

@test "gate failure prevents inbox notification" {
    cat > "$TEST_ROOT/queue/reports/hayate_report_cmd_125.yaml" <<'EOF'
result:
  summary: done
EOF

    run env GATE_SHOULD_FAIL=1 bash "$TEST_ROOT/scripts/ninja_done.sh" hayate cmd_125
    [ "$status" -eq 1 ]
    [[ "$output" == *"gate_report_format.sh FAIL"* ]]
    [ ! -f "$TEST_ROOT/inbox_write_calls.log" ]
}
