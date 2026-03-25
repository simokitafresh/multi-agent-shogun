#!/usr/bin/env bats
# Minimal inbox_write unit test for cmd_438 AC4.

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SOURCE_SCRIPT="$PROJECT_ROOT/scripts/inbox_write.sh"
    [ -f "$SOURCE_SCRIPT" ] || return 1
    python3 -c "import yaml" >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/inbox_write_unit.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/queue/inbox"

    cp "$SOURCE_SCRIPT" "$TEST_ROOT/scripts/inbox_write.sh"
    chmod +x "$TEST_ROOT/scripts/inbox_write.sh"

    export TEST_SCRIPT="$TEST_ROOT/scripts/inbox_write.sh"
    export TARGET_INBOX="$TEST_ROOT/queue/inbox/kirimaru.yaml"
}

teardown() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

@test "inbox_write creates unread message with required fields" {
    run bash "$TEST_SCRIPT" "kirimaru" "unit test message" "task_assigned" "karo"
    [ "$status" -eq 0 ]
    [ -f "$TARGET_INBOX" ]

    INBOX_PATH="$TARGET_INBOX" python3 - <<'PY'
import os
import yaml

inbox_path = os.environ["INBOX_PATH"]
with open(inbox_path, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

messages = data.get("messages", [])
assert len(messages) == 1, f"expected 1 message, got {len(messages)}"
msg = messages[0]

for key in ("id", "from", "timestamp", "type", "content", "read"):
    assert key in msg, f"missing key: {key}"

assert msg["from"] == "karo"
assert msg["type"] == "task_assigned"
assert msg["content"] == "unit test message"
assert msg["read"] is False
PY
}

# ────────────────────────────────────────
# Git uncommitted check tests (cmd_cycle_001)
# ────────────────────────────────────────

# Helper: set up git repo + mocks for report_received tests
setup_git_test_env() {
    mkdir -p "$TEST_ROOT/scripts/lib" "$TEST_ROOT/scripts/gates"
    mkdir -p "$TEST_ROOT/queue/tasks" "$TEST_ROOT/queue/reports"

    git -C "$TEST_ROOT" init -q
    git -C "$TEST_ROOT" config user.name "test"
    git -C "$TEST_ROOT" config user.email "test@test.com"

    # Mock agent_config.sh (provides ninja names for report_received checks)
    cat > "$TEST_ROOT/scripts/lib/agent_config.sh" << 'MOCK'
get_ninja_names() { echo "testninja"; }
get_allowed_targets() { echo "karo shogun testninja gunshi"; }
MOCK

    # Mock gate scripts (always pass — focus on git uncommitted check)
    printf '#!/bin/bash\necho "NO-FIX-NEEDED"\n' > "$TEST_ROOT/scripts/gates/gate_report_autofix.sh"
    chmod +x "$TEST_ROOT/scripts/gates/gate_report_autofix.sh"
    printf '#!/bin/bash\necho "PASS: all checks passed"\n' > "$TEST_ROOT/scripts/gates/gate_report_format.sh"
    chmod +x "$TEST_ROOT/scripts/gates/gate_report_format.sh"

    # Task YAML for testninja
    cat > "$TEST_ROOT/queue/tasks/testninja.yaml" << 'YAML'
task:
  status: in_progress
  parent_cmd: cmd_test_001
  target_path: src/test_file.sh
  report_path: queue/reports/testninja_report_cmd_test_001.yaml
  report_filename: testninja_report_cmd_test_001.yaml
YAML

    # Valid report YAML (passes format gate)
    cat > "$TEST_ROOT/queue/reports/testninja_report_cmd_test_001.yaml" << 'YAML'
verdict: PASS
files_modified:
  - path: src/test_file.sh
    change: modified
binary_checks:
  AC1:
    - check: test check
      result: PASS
lesson_candidate:
  found: false
  no_lesson_reason: no lesson
result:
  summary: implementation complete
YAML

    # Create source file and initial commit
    mkdir -p "$TEST_ROOT/src"
    echo '#!/bin/bash' > "$TEST_ROOT/src/test_file.sh"
    git -C "$TEST_ROOT" add -A
    git -C "$TEST_ROOT" commit -q -m "initial"
}

# Wrapper to capture stderr in bats output
_run_inbox_write() {
    bash "$TEST_SCRIPT" "$@" 2>&1
}

@test "report_received: uncommitted changes in files_modified → BLOCKED" {
    setup_git_test_env

    # Modify file WITHOUT committing
    echo 'echo "modified"' >> "$TEST_ROOT/src/test_file.sh"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 1 ]
    [[ "$output" == *"git_uncommitted_gate"* ]]
    [[ "$output" == *"BLOCKED"* ]]
}

@test "report_received: all files committed → no BLOCK" {
    setup_git_test_env

    # All files committed — clean working tree
    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]

    # Verify message was delivered to inbox
    [ -f "$TEST_ROOT/queue/inbox/karo.yaml" ]
}

@test "report_received: only files_modified checked, not whole repo" {
    setup_git_test_env

    # Add another tracked file and commit
    echo '#!/bin/bash' > "$TEST_ROOT/src/another_file.sh"
    git -C "$TEST_ROOT" add -A
    git -C "$TEST_ROOT" commit -q -m "add another file"

    # Modify another_file.sh (NOT in files_modified) without committing
    echo 'echo modified' >> "$TEST_ROOT/src/another_file.sh"

    # src/test_file.sh is clean, src/another_file.sh is dirty but not in check scope
    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
}

