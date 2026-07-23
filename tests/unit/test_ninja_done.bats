#!/usr/bin/env bats
# test_necessity: Valid parent_cmd identity reaches exactly its report and gate failure prevents notification; violation is BLOCK.

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
report="\${1:?report required}"
fingerprint="\$(sha256sum "\$report" | awk '{print \$1}')"
cache="\${report}.validated_fingerprints"
if [ -n "\${GATE_VALIDATED_FINGERPRINT:-}" ] &&
   [ "\$fingerprint" = "\$GATE_VALIDATED_FINGERPRINT" ] &&
   [ -f "\$cache" ] && grep -qxF "\$fingerprint" "\$cache"; then
    echo "PASS (fingerprint reuse)"
    exit 0
fi
printf 'full\n' >> "$TEST_ROOT/gate_full_calls.log"
if [ "\${GATE_SHOULD_FAIL:-0}" = "1" ]; then
    echo "FAIL: mocked gate" >&2
    exit 1
fi
printf '%s\n' "\$fingerprint" >"\$cache"
echo "PASS"
EOF
    chmod +x "$TEST_ROOT/scripts/gates/gate_report_format.sh"

    cat > "$TEST_ROOT/scripts/inbox_write.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_ROOT/inbox_write_calls.log"
printf '%s\n' "\${GATE_VALIDATED_FINGERPRINT:-}" >> "$TEST_ROOT/inbox_write_fingerprints.log"
if [ -n "\${INBOX_TEST_REPORT:-}" ]; then
    bash "$TEST_ROOT/scripts/gates/gate_report_format.sh" "\$INBOX_TEST_REPORT"
fi
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

@test "placeholder summary blocks terminal notification" {
    cat > "$TEST_ROOT/queue/reports/hayate_report_cmd_126.yaml" <<'EOF'
result:
  summary: "FILL_THIS"
EOF

    run bash "$TEST_ROOT/scripts/ninja_done.sh" hayate cmd_126
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
    grep -F "karo hayate、任務完了。報告YAML確認されたし。 report_received hayate notify_karo" \
        "$TEST_ROOT/inbox_write_calls.log"
}

@test "numeric and karo-direct parent_cmd identities both reach report_received" {
    for cmd_id in cmd_123 cmd_karo_hotfix_ninja_done_20260723; do
        cat > "$TEST_ROOT/queue/reports/hayate_report_${cmd_id}.yaml" <<'EOF'
result:
  summary: done
EOF
        run bash "$TEST_ROOT/scripts/ninja_done.sh" hayate "$cmd_id"
        [ "$status" -eq 0 ]
    done

    [ "$(grep -c ' report_received hayate notify_karo$' "$TEST_ROOT/inbox_write_calls.log")" -eq 2 ]
}

@test "unsafe parent_cmd identities are rejected before report lookup" {
    for cmd_id in "cmd_bad id" "cmd_bad/id" "cmd_bad.id" "cmd_../escape"; do
        run bash "$TEST_ROOT/scripts/ninja_done.sh" hayate "$cmd_id"
        [ "$status" -eq 1 ]
        [[ "$output" == *"cmd_[A-Za-z0-9_-]+"* ]]
    done
    [ ! -f "$TEST_ROOT/inbox_write_calls.log" ]
}

@test "archive fallback does not select a similar-suffix report" {
    mkdir -p "$TEST_ROOT/queue/archive/reports"
    cat > "$TEST_ROOT/queue/archive/reports/hayate_report_cmd_target_suffix_20200101.yaml" <<'EOF'
result:
  summary: wrong report
EOF

    run bash "$TEST_ROOT/scripts/ninja_done.sh" hayate cmd_target

    [ "$status" -eq 1 ]
    [[ "$output" == *"report YAML not found"* ]]
    [ ! -f "$TEST_ROOT/inbox_write_calls.log" ]
}

@test "one-byte report change forces downstream gate revalidation" {
    report="$TEST_ROOT/queue/reports/hayate_report_cmd_mutation.yaml"
    cat > "$report" <<'EOF'
result:
  summary: done
EOF
    cat > "$TEST_ROOT/scripts/inbox_write.sh" <<EOF
#!/usr/bin/env bash
printf '\\n' >> "\${INBOX_TEST_REPORT:?}"
bash "$TEST_ROOT/scripts/gates/gate_report_format.sh" "\$INBOX_TEST_REPORT"
EOF
    chmod +x "$TEST_ROOT/scripts/inbox_write.sh"

    run env INBOX_TEST_REPORT="$report" \
        bash "$TEST_ROOT/scripts/ninja_done.sh" hayate cmd_mutation

    [ "$status" -eq 0 ]
    [ "$(grep -c '^full$' "$TEST_ROOT/gate_full_calls.log")" -eq 2 ]
}

@test "notification carries the exact fingerprint validated by ninja_done" {
    report="$TEST_ROOT/queue/reports/hayate_report_cmd_127.yaml"
    cat > "$report" <<'EOF'
result:
  summary: done
EOF
    expected="$(sha256sum "$report" | awk '{print $1}')"

    run bash "$TEST_ROOT/scripts/ninja_done.sh" hayate cmd_127

    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_ROOT/inbox_write_fingerprints.log")" = "$expected" ]
}

@test "ninja_done to inbox_write validates an unchanged report exactly once" {
    report="$TEST_ROOT/queue/reports/hayate_report_cmd_128.yaml"
    cat > "$report" <<'EOF'
result:
  summary: done
EOF

    run env INBOX_TEST_REPORT="$report" \
        bash "$TEST_ROOT/scripts/ninja_done.sh" hayate cmd_128

    [ "$status" -eq 0 ]
    [ "$(grep -c '^full$' "$TEST_ROOT/gate_full_calls.log")" -eq 1 ]
    [[ "$output" == *"PASS (fingerprint reuse)"* ]]
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
