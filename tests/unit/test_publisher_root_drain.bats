#!/usr/bin/env bats

# test_necessity: root commits must reach origin only through the publisher
# lock, while divergence and a clean no-op remain fail-closed and observable.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIXTURE="$(mktemp -d --tmpdir="$HOME" publisher_root_drain_bats.XXXXXX)"
    REMOTE="$FIXTURE/remote.git"
    WORK="$FIXTURE/work"
    PUBROOT="$FIXTURE/pubroot"
    STATE="$FIXTURE/state"
    LOG="$FIXTURE/publisher_daemon.log"
    INBOX_LOG="$FIXTURE/inbox.log"

    git init --bare -q "$REMOTE"
    git init -q "$WORK"
    git -C "$WORK" config user.email test@example.invalid
    git -C "$WORK" config user.name test
    printf 'base\n' > "$WORK/payload.txt"
    git -C "$WORK" add payload.txt
    git -C "$WORK" commit -q -m base
    git -C "$WORK" branch -M main
    git -C "$WORK" remote add origin "$REMOTE"
    git -C "$WORK" push -q -u origin main
    git clone -q "$REMOTE" "$PUBROOT"
    git -C "$PUBROOT" checkout -q -b main origin/main
    git -C "$PUBROOT" config user.email test@example.invalid
    git -C "$PUBROOT" config user.name test

    cat > "$FIXTURE/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${INBOX_LOG:?}"
EOF
    chmod +x "$FIXTURE/inbox_write.sh"
    export SHOGUN_STATE_DIR="$STATE"
    export PUBLISHER_INBOX_WRITER="$FIXTURE/inbox_write.sh"
    export INBOX_LOG
    export PUBLISHER_DAEMON_LOG="$LOG"
}

teardown() {
    find "$FIXTURE" -depth -delete 2>/dev/null || true
}

# test_necessity: tracked dirty content must fail-close before root drain and
# the exact dirty path must remain observable for diagnosis.
@test "tracked dirty root blocks drain and records the dirty path" {
    printf 'committed\n' > "$PUBROOT/payload.txt"
    git -C "$PUBROOT" add payload.txt
    git -C "$PUBROOT" commit -q -m committed
    ahead="$(git -C "$PUBROOT" rev-parse HEAD)"
    printf 'dirty-not-committed\n' > "$PUBROOT/payload.txt"

    run bash -c 'source "$1/scripts/lib/publisher_root_drain.sh"; publisher_root_drain "$2"' _ "$ROOT" "$PUBROOT"
    [ "$status" -eq 32 ]
    [ "$(git --git-dir="$REMOTE" rev-parse refs/heads/main)" != "$ahead" ]
    grep -q "publisher: root drain BLOCK tracked_dirty_paths=payload.txt" "$LOG"
    [ "$(grep -c "publisher: root drain BLOCK tracked_dirty_paths=" "$LOG")" -eq 1 ]
    [ ! -f "$INBOX_LOG" ] || [ "$(wc -l < "$INBOX_LOG" | tr -d ' ')" -eq 0 ]
}

# test_necessity: a non-fast-forward root/remote relationship must not push or
# alter origin, and must emit exactly one task_supplement notification.
@test "divergence fails closed without pushing and notifies karo" {
    printf 'local\n' > "$PUBROOT/payload.txt"
    git -C "$PUBROOT" add payload.txt
    git -C "$PUBROOT" commit -q -m local
    local_head="$(git -C "$PUBROOT" rev-parse HEAD)"

    git -C "$WORK" fetch -q origin
    printf 'remote\n' > "$WORK/payload.txt"
    git -C "$WORK" add payload.txt
    git -C "$WORK" commit -q -m remote
    git -C "$WORK" push -q origin main
    remote_head="$(git -C "$WORK" rev-parse HEAD)"

    run bash -c 'source "$1/scripts/lib/publisher_root_drain.sh"; publisher_root_drain "$2"' _ "$ROOT" "$PUBROOT"
    [ "$status" -ne 0 ]
    [ "$(git --git-dir="$REMOTE" rev-parse refs/heads/main)" = "$remote_head" ]
    [ "$(grep -c "publisher: root drain BLOCK divergence" "$LOG")" -eq 1 ]
    [ "$(wc -l < "$INBOX_LOG" | tr -d ' ')" -eq 1 ]
    grep -q 'karo publisher: root drain BLOCK divergence' "$INBOX_LOG"
    grep -q 'task_supplement publisher_root_drain notify_karo' "$INBOX_LOG"
    [ "$local_head" != "$remote_head" ]
}

# test_necessity: an already synchronized root must not invoke push or notify,
# but the no-op remains observable in the daemon log.
@test "synchronized root is a no-op" {
    run bash -c 'source "$1/scripts/lib/publisher_root_drain.sh"; publisher_root_drain "$2"' _ "$ROOT" "$PUBROOT"
    [ "$status" -eq 0 ]
    grep -q 'publisher: root drain no-op head=' "$LOG"
    [ "$(grep -c 'publisher: root drain push=' "$LOG" || true)" -eq 0 ]
    [ ! -f "$INBOX_LOG" ] || [ "$(wc -l < "$INBOX_LOG" | tr -d ' ')" -eq 0 ]
}
