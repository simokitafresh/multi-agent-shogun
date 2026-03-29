#!/usr/bin/env bats
# test_karo_workaround_validation.bats — cmd_1542 AC1+AC2 単体テスト
# AC1: validate_ninja_id() — ninja_id有効性チェック
# AC2: root_cause最小長+null/empty拒否

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../scripts" && pwd)/karo_workaround_log.sh"

setup() {
    export TMPDIR="${BATS_TMPDIR:-/tmp}"
    TEST_DIR=$(mktemp -d "$TMPDIR/wa_test.XXXXXX")

    # Create minimal repo structure
    mkdir -p "$TEST_DIR/config" "$TEST_DIR/queue/tasks" "$TEST_DIR/logs" "$TEST_DIR/scripts"

    # settings.yaml with known agents
    cat > "$TEST_DIR/config/settings.yaml" <<'YAML'
roles:
  agents:
    hayate:
      type: claude
      role: ninja
    hanzo:
      type: claude
      role: ninja
    kotaro:
      type: claude
      role: ninja
YAML

    # Task files
    touch "$TEST_DIR/queue/tasks/hayate.yaml"
    touch "$TEST_DIR/queue/tasks/hanzo.yaml"
    touch "$TEST_DIR/queue/tasks/kotaro.yaml"

    # Stub ntfy.sh and insight_write.sh to prevent real notifications
    cat > "$TEST_DIR/scripts/ntfy.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$TEST_DIR/scripts/ntfy.sh"
    cat > "$TEST_DIR/scripts/insight_write.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$TEST_DIR/scripts/insight_write.sh"

    # Copy the actual script, replacing REPO_ROOT discovery
    sed "s|REPO_ROOT=.*|REPO_ROOT=\"$TEST_DIR\"|" "$SCRIPT" > "$TEST_DIR/scripts/karo_workaround_log.sh"
    # Also fix SCRIPT_DIR to point to test scripts dir
    sed -i "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$TEST_DIR/scripts\"|" "$TEST_DIR/scripts/karo_workaround_log.sh"
    chmod +x "$TEST_DIR/scripts/karo_workaround_log.sh"

    TEST_SCRIPT="$TEST_DIR/scripts/karo_workaround_log.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================
# AC1: validate_ninja_id tests
# =============================================

@test "AC1: valid ninja_id (hayate) — no WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "test fix description"
    # Should NOT contain WARN about ninja_id
    [[ "$output" != *"有効なエージェント名ではない"* ]]
}

@test "AC1: valid ninja_id (karo) — no WARN" {
    run bash "$TEST_SCRIPT" cmd_test karo "test issue" "test fix description"
    [[ "$output" != *"有効なエージェント名ではない"* ]]
}

@test "AC1: invalid ninja_id — emits WARN" {
    run bash "$TEST_SCRIPT" cmd_test unknown_agent "test issue" "test fix description"
    [[ "$output" == *"有効なエージェント名ではない"* ]]
}

@test "AC1: invalid ninja_id (typo) — emits WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayat "test issue" "test fix description"
    [[ "$output" == *"有効なエージェント名ではない"* ]]
}

@test "AC1: valid ninja_id from tasks dir (kotaro) — no WARN" {
    run bash "$TEST_SCRIPT" cmd_test kotaro "test issue" "test fix description"
    [[ "$output" != *"有効なエージェント名ではない"* ]]
}

# =============================================
# AC2: root_cause (FIX) validation tests
# =============================================

@test "AC2: empty root_cause — emits WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" ""
    [[ "$output" == *"root_causeが無効値"* ]]
}

@test "AC2: null root_cause — emits WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "null"
    [[ "$output" == *"root_causeが無効値"* ]]
}

@test "AC2: None root_cause — emits WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "None"
    [[ "$output" == *"root_causeが無効値"* ]]
}

@test "AC2: NULL root_cause — emits WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "NULL"
    [[ "$output" == *"root_causeが無効値"* ]]
}

@test "AC2: none root_cause — emits WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "none"
    [[ "$output" == *"root_causeが無効値"* ]]
}

@test "AC2: 1-char root_cause — emits short WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "x"
    [[ "$output" == *"root_causeが短すぎる"* ]]
}

@test "AC2: 2-char root_cause — emits short WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "ab"
    [[ "$output" == *"root_causeが短すぎる"* ]]
}

@test "AC2: 3-char root_cause — no WARN (minimum met)" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "fix"
    [[ "$output" != *"root_causeが短すぎる"* ]]
    [[ "$output" != *"root_causeが無効値"* ]]
}

@test "AC2: valid root_cause — no WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "report_field_set.shでフォーマット修正"
    [[ "$output" != *"root_causeが短すぎる"* ]]
    [[ "$output" != *"root_causeが無効値"* ]]
}

# =============================================
# Clean mode should skip validation
# =============================================

@test "clean mode: skips root_cause validation" {
    run bash "$TEST_SCRIPT" --clean cmd_test hayate
    [[ "$output" != *"root_causeが無効値"* ]]
    [[ "$output" != *"root_causeが短すぎる"* ]]
    [[ "$output" == *"Clean:"* ]]
}
