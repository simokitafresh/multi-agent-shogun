#!/usr/bin/env bats
# test_necessity: Symlinked inbox uses the canonical writer lock path, and block scalar body indentation never creates a message record boundary; violation is BLOCK.

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

@test "block scalar nested bullets preserve exact message boundaries and metadata" {
    cat > "$TEST_ROOT/queue/inbox/saizo.yaml" <<'YAML'
messages:
- content: |-
    heading
    - bullet one
      - nested bullet
    - id: not_a_message
    tail
  from: 'karo'
  id: 'msg_nested_read'
  read: true
  timestamp: '2026-07-19T14:35:20'
  type: 'task_assigned'
  action: 'task_start'
- content: 'keep unread'
  from: 'karo'
  id: 'msg_unread'
  read: false
  timestamp: '2026-07-19T14:36:20'
  type: 'task_assigned'
YAML

    run bash "$TEST_SCRIPT" saizo
    [ "$status" -eq 0 ]

    python3 - "$TEST_ROOT" <<'PY'
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
archive_path, = (root / "archive/inbox").glob("saizo_*.yaml")
archive = yaml.safe_load(archive_path.read_text())
inbox = yaml.safe_load((root / "queue/inbox/saizo.yaml").read_text())
assert len(archive["messages"]) == 1
assert archive["messages"][0] == {
    "content": "heading\n- bullet one\n  - nested bullet\n- id: not_a_message\ntail",
    "from": "karo", "id": "msg_nested_read", "read": True,
    "timestamp": "2026-07-19T14:35:20", "type": "task_assigned",
    "action": "task_start",
}

assert inbox["messages"] == [{
    "content": "keep unread", "from": "karo", "id": "msg_unread",
    "read": False, "timestamp": "2026-07-19T14:36:20", "type": "task_assigned",
}]
PY
}

@test "orphan-only repair requires one archived read source and preserves quarantine" {
    cat > "$TEST_ROOT/archive/inbox/saizo_20260719.yaml" <<'YAML'
messages:
- from: gunshi
  id: msg_source
  read: true
  timestamp: '2026-07-19T14:35:20'
  type: review_result
YAML
    cat > "$TEST_ROOT/queue/inbox/saizo.yaml" <<'YAML'
messages:
- content: |-
    split body
  action: notify_karo
- orphan: one
- orphan: two
YAML

    run bash "$TEST_SCRIPT" saizo --repair-orphans-from-archive msg_source
    [ "$status" -eq 0 ]
    [[ "$output" == *"valid_ids=0 invalid=3 archive_read_hits=1"* ]]
    python3 - "$TEST_ROOT" <<'PY'
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
assert yaml.safe_load((root / "queue/inbox/saizo.yaml").read_text()) == {"messages": []}
quarantines = list((root / "archive/inbox/quarantine").glob("*.yaml"))
assert len(quarantines) == 1
assert len(yaml.safe_load(quarantines[0].read_text())["messages"]) == 3
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
