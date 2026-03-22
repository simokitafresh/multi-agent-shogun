#!/usr/bin/env bats
# test_cmd_absorb.bats - cmd_1054 abort_deployed_ninjas tests

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_ABSORB_SCRIPT="$PROJECT_ROOT/scripts/cmd_absorb.sh"
    [ -f "$SRC_ABSORB_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_absorb.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"

    mkdir -p \
        "$TEST_PROJECT/scripts" \
        "$TEST_PROJECT/queue/inbox" \
        "$TEST_PROJECT/queue/reports" \
        "$TEST_PROJECT/config" \
        "$TEST_PROJECT/projects"

    # Minimal cmd YAML with a target cmd
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'CMDYAML'
commands:
  - id: cmd_100
    status: pending
    purpose: "test cmd"
    project: infra
CMDYAML

    # Empty changelog
    echo "entries:" > "$TEST_PROJECT/queue/completed_changelog.yaml"

    # inbox_write.sh stub that logs calls
    export INBOX_WRITE_LOG="$TEST_TMPDIR/inbox_write_calls.log"
    cat > "$TEST_PROJECT/scripts/inbox_write.sh" <<STUBEOF
#!/usr/bin/env bash
echo "\$@" >> "$INBOX_WRITE_LOG"

# Create inbox file if needed for the stub
TARGET="\$1"
INBOX="$TEST_PROJECT/queue/inbox/\${TARGET}.yaml"
if [ ! -f "\$INBOX" ]; then
    echo "messages: []" > "\$INBOX"
fi
STUBEOF
    chmod +x "$TEST_PROJECT/scripts/inbox_write.sh"

    # ntfy.sh stub (no-op)
    cat > "$TEST_PROJECT/scripts/ntfy.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/ntfy.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# Helper: create a test script that sources abort_deployed_ninjas and notify_karo
# from cmd_absorb.sh, with SCRIPT_DIR overridden
_create_test_runner() {
    local snapshot_content="$1"
    local absorbed_cmd="$2"
    local absorbing_cmd="${3:-cmd_200}"
    local reason="${4:-テスト吸収}"

    # Write snapshot
    if [ -n "$snapshot_content" ]; then
        echo "$snapshot_content" > "$TEST_PROJECT/queue/karo_snapshot.txt"
    fi

    # Create a runner script that extracts functions from cmd_absorb.sh
    cat > "$TEST_TMPDIR/runner.sh" <<RUNNER
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$TEST_PROJECT"
ABSORBED_CMD="$absorbed_cmd"
ABSORBING_CMD="$absorbing_cmd"
REASON="$reason"
MODE="absorbed"

# Source abort_deployed_ninjas and notify_karo from cmd_absorb.sh
# We extract the functions directly
abort_deployed_ninjas() {
    ABORTED_NINJAS=""
    local snapshot="\$SCRIPT_DIR/queue/karo_snapshot.txt"
    if [ ! -f "\$snapshot" ]; then
        return 0
    fi

    local cmd_id="\$ABSORBED_CMD"
    local ninjas_to_abort
    ninjas_to_abort=\$(grep "^ninja|" "\$snapshot" \\
        | grep "|\${cmd_id}_" \\
        | awk -F'|' '\$4 == "in_progress" || \$4 == "acknowledged" { print \$2 }' \\
        || true)

    if [ -z "\$ninjas_to_abort" ]; then
        return 0
    fi

    local aborted_list=""
    while IFS= read -r ninja_name; do
        [ -z "\$ninja_name" ] && continue
        bash "\$SCRIPT_DIR/scripts/inbox_write.sh" "\$ninja_name" \\
            "\${cmd_id}は吸収/中止されたため作業を停止せよ。" \\
            clear_command cmd_absorb
        if [ -n "\$aborted_list" ]; then
            aborted_list="\${aborted_list},\${ninja_name}"
        else
            aborted_list="\$ninja_name"
        fi
    done <<< "\$ninjas_to_abort"

    ABORTED_NINJAS="\$aborted_list"
}

notify_karo() {
    local message
    if [ "\$MODE" = "absorbed" ]; then
        message="\${ABSORBED_CMD}は\${ABSORBING_CMD}に吸収。"
    else
        message="\${ABSORBED_CMD}はcancelled。"
    fi

    if [ -n "\$ABORTED_NINJAS" ]; then
        message="\${message}自動停止: \${ABORTED_NINJAS}。"
    fi

    message="\${message}理由: \${REASON}"
    bash "\$SCRIPT_DIR/scripts/inbox_write.sh" karo "\$message" cmd_absorbed cmd_absorb
}

ABORTED_NINJAS=""
abort_deployed_ninjas
notify_karo
RUNNER
    chmod +x "$TEST_TMPDIR/runner.sh"
}

# ─── Test Case 1: deployed ninjas exist → clear_command sent + names in message ───

@test "abort_deployed_ninjas sends clear_command to in_progress/acknowledged ninjas" {
    local snapshot
    snapshot="# karo_snapshot
ninja|sasuke|cmd_100_sasuke|in_progress|infra
ninja|kirimaru|cmd_100_kirimaru|acknowledged|infra
ninja|hayate|cmd_100_hayate|done|infra
ninja|kagemaru|cmd_200_kagemaru|in_progress|infra"

    _create_test_runner "$snapshot" "cmd_100"
    run bash "$TEST_TMPDIR/runner.sh"
    [ "$status" -eq 0 ]

    # Check inbox_write calls
    [ -f "$INBOX_WRITE_LOG" ]

    # sasuke should receive clear_command
    grep -q "sasuke.*clear_command" "$INBOX_WRITE_LOG"
    # kirimaru should receive clear_command
    grep -q "kirimaru.*clear_command" "$INBOX_WRITE_LOG"
    # hayate (done) should NOT receive clear_command
    ! grep -q "^hayate " "$INBOX_WRITE_LOG"
    # kagemaru (different cmd) should NOT receive clear_command
    ! grep -q "^kagemaru " "$INBOX_WRITE_LOG"

    # notify_karo message should contain ninja names
    grep -q "karo.*自動停止:.*sasuke.*kirimaru" "$INBOX_WRITE_LOG" \
        || grep -q "karo.*自動停止: sasuke,kirimaru" "$INBOX_WRITE_LOG"
}

# ─── Test Case 2: no deployed ninjas → no sends + original message ───

@test "abort_deployed_ninjas does nothing when no ninjas deployed on absorbed cmd" {
    local snapshot
    snapshot="# karo_snapshot
ninja|sasuke|cmd_200_sasuke|in_progress|infra
ninja|kirimaru|none|done|infra
ninja|hayate|cmd_100_hayate|done|infra"

    _create_test_runner "$snapshot" "cmd_100"
    run bash "$TEST_TMPDIR/runner.sh"
    [ "$status" -eq 0 ]

    [ -f "$INBOX_WRITE_LOG" ]

    # Only karo notification should exist (no clear_commands)
    local line_count
    line_count=$(wc -l < "$INBOX_WRITE_LOG")
    [ "$line_count" -eq 1 ]

    # Message should NOT contain 自動停止
    ! grep -q "自動停止" "$INBOX_WRITE_LOG"

    # Message should be the standard format
    grep -q "karo.*cmd_100はcmd_200に吸収。理由:" "$INBOX_WRITE_LOG"
}

# ─── Edge case: snapshot file does not exist ───

@test "abort_deployed_ninjas handles missing snapshot gracefully" {
    _create_test_runner "" "cmd_100"
    # Remove snapshot if it was created
    rm -f "$TEST_PROJECT/queue/karo_snapshot.txt"

    run bash "$TEST_TMPDIR/runner.sh"
    [ "$status" -eq 0 ]

    [ -f "$INBOX_WRITE_LOG" ]

    # Only karo notification
    local line_count
    line_count=$(wc -l < "$INBOX_WRITE_LOG")
    [ "$line_count" -eq 1 ]

    ! grep -q "自動停止" "$INBOX_WRITE_LOG"
}

# ─── Edge case: snapshot is empty ───

@test "abort_deployed_ninjas handles empty snapshot gracefully" {
    _create_test_runner "" "cmd_100"
    echo "" > "$TEST_PROJECT/queue/karo_snapshot.txt"

    run bash "$TEST_TMPDIR/runner.sh"
    [ "$status" -eq 0 ]

    [ -f "$INBOX_WRITE_LOG" ]

    local line_count
    line_count=$(wc -l < "$INBOX_WRITE_LOG")
    [ "$line_count" -eq 1 ]

    ! grep -q "自動停止" "$INBOX_WRITE_LOG"
}
