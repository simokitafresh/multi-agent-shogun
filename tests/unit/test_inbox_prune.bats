#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/inbox_prune.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts/lib" "$TEST_ROOT/queue/inbox" "$TEST_ROOT/archive/inbox"
    cp "$PROJECT_ROOT/scripts/inbox_prune.sh" "$TEST_ROOT/scripts/inbox_prune.sh"
    cp "$PROJECT_ROOT/scripts/lib/lock_path.sh" "$TEST_ROOT/scripts/lib/lock_path.sh"
    chmod +x "$TEST_ROOT/scripts/inbox_prune.sh"
}

teardown() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -r -- "$TEST_ROOT"
}

@test "pruned report_received is archived and last five read messages remain" {
    {
        echo 'messages:'
        for i in 1 2 3 4 5 6 7 8; do
            type=notice
            from=karo
            [ "$i" -ne 2 ] || { type=report_received; from=kagemaru; }
            printf -- "- content: 'message %s'\n  from: '%s'\n  id: 'msg_%s'\n  read: true\n  timestamp: '2026-07-15T12:0%s:00'\n  type: '%s'\n" "$i" "$from" "$i" "$i" "$type"
        done
        printf -- "- content: 'unread'\n  from: 'gunshi'\n  id: 'msg_unread'\n  read: false\n  timestamp: '2026-07-15T12:09:00'\n  type: 'notice'\n"
    } > "$TEST_ROOT/queue/inbox/karo.yaml"

    run bash "$TEST_ROOT/scripts/inbox_prune.sh" karo
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARCHIVED+PRUNED: karo 3 messages"* ]]

    python3 - "$TEST_ROOT" <<'PY'
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
inbox = yaml.safe_load((root / "queue/inbox/karo.yaml").read_text())
archive_path = next((root / "archive/inbox").glob("karo_*.yaml"))
archive = yaml.safe_load(archive_path.read_text())
assert [m["id"] for m in inbox["messages"]] == ["msg_unread", "msg_4", "msg_5", "msg_6", "msg_7", "msg_8"]
assert [m["id"] for m in archive["messages"]] == ["msg_1", "msg_2", "msg_3"]
assert archive["messages"][1]["type"] == "report_received"
PY
}

@test "symlinked inbox uses canonical writer lock" {
    mailbox="$TEST_ROOT/runtime-inbox"
    mkdir -p "$mailbox"
    rmdir "$TEST_ROOT/queue/inbox"
    ln -s "$mailbox" "$TEST_ROOT/queue/inbox"
    {
        echo 'messages:'
        for i in 1 2 3 4 5 6; do
            printf -- "- content: 'm%s'\n  from: 'karo'\n  id: 'msg_%s'\n  read: true\n  timestamp: '2026-07-15T12:00:00'\n  type: 'notice'\n" "$i" "$i"
        done
    } > "$mailbox/karo.yaml"

    ready="$TEST_ROOT/lock-ready"
    ( flock -x 9; : > "$ready"; sleep 2 ) 9>"$mailbox/karo.yaml.lock" &
    holder=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$ready" ] && break; sleep 0.02; done
    run timeout 0.2 bash "$TEST_ROOT/scripts/inbox_prune.sh" karo
    [ "$status" -eq 124 ]
    wait "$holder"
    [ "$(grep -c '^  read: true' "$mailbox/karo.yaml")" -eq 6 ]
}
