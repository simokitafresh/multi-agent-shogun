#!/usr/bin/env bats
# test_necessity: U3 must validate C2a, create a parent-1 publisher commit,
# and keep dry-run origin unchanged while the watchdog checks pid plus event freshness.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIXTURE="$(mktemp -d --tmpdir="$HOME" publisher_bats.XXXXXX)"
    REMOTE="$FIXTURE/remote.git"; WORK="$FIXTURE/work"; PUBROOT="$FIXTURE/pubroot"; STATE="$FIXTURE/state"
    git init --bare -q "$REMOTE"; git init -q "$WORK"
    git -C "$WORK" config user.email test@example.invalid; git -C "$WORK" config user.name test
    printf 'base\n' > "$WORK/payload.txt"; git -C "$WORK" add payload.txt
    git -C "$WORK" commit -q -m base; git -C "$WORK" branch -M main
    git -C "$WORK" remote add origin "$REMOTE"; git -C "$WORK" push -q -u origin main
    BASE="$(git -C "$WORK" rev-parse HEAD)"
    printf 'published\n' > "$WORK/payload.txt"; git -C "$WORK" add payload.txt
    git -C "$WORK" commit -q -m source; SOURCE="$(git -C "$WORK" rev-parse HEAD)"
    git -C "$WORK" fetch -q origin
    git clone -q "$REMOTE" "$PUBROOT"
    git -C "$PUBROOT" config user.email test@example.invalid
    git -C "$PUBROOT" config user.name test
    git -C "$PUBROOT" checkout -q -b main origin/main
    mkdir -p "$STATE/publish_queue/artifacts/task_u3"
    git -C "$WORK" diff --binary "$BASE" "$SOURCE" -- > "$STATE/publish_queue/artifacts/task_u3/patch.diff"
    cat > "$STATE/publish_queue/artifacts/task_u3/manifest.yaml" <<EOF
source_sha: '$SOURCE'
source_tree: '$(git -C "$WORK" rev-parse "$SOURCE^{tree}")'
patch_sha: unused
base: '$BASE'
paths:
  - payload.txt
EOF
    cat > "$FIXTURE/request.yaml" <<EOF
task_id: task_u3
publish_attempts: 0
EOF
    export SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$WORK" PUBLISHER_MODE=dry-run
    cat > "$FIXTURE/inbox_write.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${INBOX_WRITE_STUB_LOG:?}"
EOF
    chmod +x "$FIXTURE/inbox_write.sh"
    export PUBLISHER_INBOX_WRITER="$FIXTURE/inbox_write.sh" INBOX_WRITE_STUB_LOG="$FIXTURE/inbox.log"
}

teardown() { find "$FIXTURE" -depth -delete 2>/dev/null || true; }

@test "dry-run validates C2a, creates no origin update, and records event" {
    bash "$ROOT/scripts/publisher_queue.sh" enqueue "$FIXTURE/request.yaml" >/dev/null
    before="$(git --git-dir="$REMOTE" rev-parse refs/heads/main)"
    run env SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$WORK" PUBLISHER_ONCE=1 bash "$ROOT/scripts/publisher.sh"
    [ "$status" -eq 0 ]
    after="$(git --git-dir="$REMOTE" rev-parse refs/heads/main)"; [ "$before" = "$after" ]
    [ "$(jq -r 'select(.kind=="dry_run_publish") | .kind' "$STATE/publish_queue/events.jsonl")" = dry_run_publish ]
    [ "$(find "$STATE/publish_queue/done" -name '*.request' | wc -l)" -eq 1 ]
}

@test "watchdog publisher health requires live pid and fresh event" {
    mkdir -p "$STATE/publish_queue"
    printf '%s\n' "$$" > "$STATE/publish_queue/publisher.pid"
    printf '{"ts":"%s","kind":"dry_run_publish"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE/publish_queue/events.jsonl"
    run bash -c 'DAEMON_WATCHDOG_LIB_ONLY=1 SHOGUN_STATE_DIR="$1" source "$2/scripts/daemon_watchdog.sh"; pid_cmdline_matches() { return 0; }; watchdog_publisher_healthy' _ "$STATE" "$ROOT"
    [ "$status" -eq 0 ]
}

@test "C2a mismatch moves request to rc and notifies karo" {
    bash "$ROOT/scripts/publisher_queue.sh" enqueue "$FIXTURE/request.yaml" >/dev/null
    printf 'remote-change\n' > "$PUBROOT/payload.txt"
    git -C "$PUBROOT" add payload.txt; git -C "$PUBROOT" commit -q -m remote-change
    git -C "$PUBROOT" push -q origin main
    run env SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$PUBROOT" PUBLISHER_INBOX_WRITER="$FIXTURE/inbox_write.sh" PUBLISHER_ONCE=1 bash "$ROOT/scripts/publisher.sh"
    [ "$status" -ne 0 ]
    [ "$(find "$STATE/publish_queue/rc" -name '*.request' | wc -l)" -eq 1 ]
    grep -q 'C2a RC' "$FIXTURE/inbox.log"
    [ "$(jq -r 'select(.kind=="c2a_rc") | .kind' "$STATE/publish_queue/events.jsonl")" = c2a_rc ]
}

@test "active publishes parent-one commit and synchronizes clean root" {
    export PUBLISHER_REPO_ROOT="$PUBROOT" PUBLISHER_MODE=active
    bash "$ROOT/scripts/publisher_queue.sh" enqueue "$FIXTURE/request.yaml" >/dev/null
    run env SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$PUBROOT" PUBLISHER_INBOX_WRITER="$FIXTURE/inbox_write.sh" PUBLISHER_MODE=active PUBLISHER_ONCE=1 bash "$ROOT/scripts/publisher.sh"
    [ "$status" -eq 0 ]
    [ "$(git -C "$PUBROOT" rev-parse HEAD)" = "$(git -C "$PUBROOT" rev-parse origin/main)" ]
    [ "$(git -C "$PUBROOT" status --porcelain -uno | wc -l)" -eq 0 ]
    [ "$(git -C "$PUBROOT" log -1 --format=%P | wc -w)" -eq 1 ]
    git -C "$PUBROOT" log -1 --format=%B | grep -q 'Published-By: publisher'
}
