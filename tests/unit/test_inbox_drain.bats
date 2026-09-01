#!/usr/bin/env bats

setup() {
    ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$ROOT/scripts/lib" "$ROOT/queue/inbox"
    cp "$BATS_TEST_DIRNAME/../../scripts/inbox_drain.sh" "$ROOT/scripts/inbox_drain.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/inbox_read.sh" "$ROOT/scripts/inbox_read.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/inbox_mark_read.sh" "$ROOT/scripts/inbox_mark_read.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/lock_path.sh" "$ROOT/scripts/lib/lock_path.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/yaml_field_set.sh" "$ROOT/scripts/lib/yaml_field_set.sh"
    INBOX="$ROOT/queue/inbox/alpha.yaml"
}

read_inbox() {
    SHOGUN_ROOT="$ROOT" \
        INBOX_READ_RECEIPT_DIR="$ROOT/logs/inbox_read_receipts" \
        bash "$ROOT/scripts/inbox_read.sh" alpha >/dev/null
}

write_inbox() {
    printf '%s\n' \
      'messages:' \
      '- id: m1' '  type: task_assigned' '  from: karo' '  content: first' '  read: false' \
      '- id: m2' '  type: info' '  from: gunshi' '  content: second' '  read: false' >"$INBOX"
}

@test "drain outputs every unread record and marks each id once" {
    write_inbox
    read_inbox
    run env INBOX_DRAIN_ROOT_OVERRIDE="$ROOT" bash "$ROOT/scripts/inbox_drain.sh" alpha
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c '"id":')" -eq 2 ]
    [[ "$output" == *'"content": "first"'* ]]
    run grep -c 'read: true' "$INBOX"
    [ "$output" -eq 2 ]
    run env INBOX_DRAIN_ROOT_OVERRIDE="$ROOT" bash "$ROOT/scripts/inbox_drain.sh" alpha
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "concurrent drains and arrival have no lost update duplicate or missed unread" {
    write_inbox
    read_inbox
    env INBOX_DRAIN_ROOT_OVERRIDE="$ROOT" bash "$ROOT/scripts/inbox_drain.sh" alpha >"$ROOT/a.out" &
    p1=$!
    env INBOX_DRAIN_ROOT_OVERRIDE="$ROOT" bash "$ROOT/scripts/inbox_drain.sh" alpha >"$ROOT/b.out" &
    p2=$!
    wait "$p1"; wait "$p2"
    python3 - "$INBOX" <<'PY'
import fcntl, os, sys, tempfile, yaml
path = sys.argv[1]
with open(path + '.lock', 'a+') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    data = yaml.safe_load(open(path)) or {'messages': []}
    data['messages'].append({'id': 'late1', 'type': 'info', 'from': 'writer',
                             'content': 'late', 'read': False})
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    with os.fdopen(fd, 'w') as out: yaml.safe_dump(data, out, sort_keys=False)
    os.replace(tmp, path)
PY
    read_inbox
    cat "$ROOT/a.out" "$ROOT/b.out" >"$ROOT/all.out"
    [ "$(grep -c '"id": "m1"' "$ROOT/all.out")" -eq 1 ]
    [ "$(grep -c '"id": "m2"' "$ROOT/all.out")" -eq 1 ]
    run env INBOX_DRAIN_ROOT_OVERRIDE="$ROOT" bash "$ROOT/scripts/inbox_drain.sh" alpha
    [ "$status" -eq 0 ]
    [[ "$output" == *'late'* ]]
    run grep -c 'read: false' "$INBOX"
    [ "$output" -eq 0 ]
}

@test "drain lock failure preserves every unread message" {
    write_inbox
    source "$ROOT/scripts/lib/lock_path.sh"
    lock="$(lock_path "$INBOX.drain")"
    exec 8>>"$lock"; flock 8
    run env INBOX_DRAIN_ROOT_OVERRIDE="$ROOT" INBOX_DRAIN_LOCK_TIMEOUT=0 bash "$ROOT/scripts/inbox_drain.sh" alpha
    flock -u 8
    [ "$status" -eq 3 ]
    [[ "$output" == *'BLOCK: inbox drain lock busy'* ]]
    run grep -c 'read: false' "$INBOX"
    [ "$output" -eq 2 ]
}
