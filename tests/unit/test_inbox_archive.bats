#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SOURCE_SCRIPT="$PROJECT_ROOT/scripts/inbox_archive.sh"
    [ -f "$SOURCE_SCRIPT" ] || return 1
    python3 -c "import yaml" >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/inbox_archive.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts/lib" "$TEST_ROOT/queue/inbox" "$TEST_ROOT/archive/inbox"
    cp "$SOURCE_SCRIPT" "$TEST_ROOT/scripts/inbox_archive.sh"
    cp "$PROJECT_ROOT/scripts/lib/lock_path.sh" "$TEST_ROOT/scripts/lib/lock_path.sh"
    chmod +x "$TEST_ROOT/scripts/inbox_archive.sh"
    export TEST_SCRIPT="$TEST_ROOT/scripts/inbox_archive.sh"
}

teardown() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

@test "archives read messages and preserves unread messages on fast path" {
    cat > "$TEST_ROOT/queue/inbox/saizo.yaml" <<'YAML'
messages:
- content: 'first message'
  from: 'karo'
  id: 'msg_001'
  read: true
  timestamp: '2026-05-29T16:30:00'
  type: 'task_assigned'
- content: 'second message'
  from: 'karo'
  id: 'msg_002'
  read: false
  timestamp: '2026-05-29T16:31:00'
  type: 'task_assigned'
YAML

    run bash "$TEST_SCRIPT" saizo
    [ "$status" -eq 0 ]
    [[ "$output" == *"total=2, read=1, unread=1"* ]]
    [[ "$output" == *"Archived 1 messages"* ]]

    python3 - "$TEST_ROOT" <<'PY'
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
inbox = yaml.safe_load((root / "queue/inbox/saizo.yaml").read_text())
archive_files = list((root / "archive/inbox").glob("saizo_*.yaml"))
assert len(archive_files) == 1
archive = yaml.safe_load(archive_files[0].read_text())
assert [m["id"] for m in inbox["messages"]] == ["msg_002"]
assert [m["id"] for m in archive["messages"]] == ["msg_001"]
PY
}

@test "falls back safely for multiline content" {
    cat > "$TEST_ROOT/queue/inbox/saizo.yaml" <<'YAML'
messages:
- content: |-
    first line
    second line
  from: 'karo'
  id: 'msg_001'
  read: true
  timestamp: '2026-05-29T16:30:00'
  type: 'task_assigned'
YAML

    run bash "$TEST_SCRIPT" saizo
    [ "$status" -eq 0 ]
    [[ "$output" == *"Archived 1 messages"* ]]

    python3 - "$TEST_ROOT" <<'PY'
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
archive_files = list((root / "archive/inbox").glob("saizo_*.yaml"))
assert len(archive_files) == 1
archive = yaml.safe_load(archive_files[0].read_text())
assert archive["messages"][0]["content"] == "first line\nsecond line"
assert yaml.safe_load((root / "queue/inbox/saizo.yaml").read_text()) == {"messages": []}
PY
}

@test "symlinked inbox uses the canonical writer lock" {
    mailbox="$TEST_ROOT/runtime-inbox"
    mkdir -p "$mailbox"
    rm -r "$TEST_ROOT/queue/inbox"
    ln -s "$mailbox" "$TEST_ROOT/queue/inbox"
    cat > "$mailbox/saizo.yaml" <<'YAML'
messages:
- content: 'read message'
  from: 'karo'
  id: 'msg_lock'
  read: true
  timestamp: '2026-07-15T12:00:00'
  type: 'task_assigned'
YAML

    ready="$TEST_ROOT/lock-ready"
    ( flock -x 9; : > "$ready"; sleep 2 ) 9>"$mailbox/saizo.yaml.lock" &
    holder=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$ready" ] && break; sleep 0.02; done
    run timeout 0.2 bash "$TEST_SCRIPT" saizo
    [ "$status" -eq 124 ]
    wait "$holder"
    grep -q 'msg_lock' "$mailbox/saizo.yaml"
}
