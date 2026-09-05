#!/usr/bin/env bats
# test_necessity: U3 must validate C2a, create a parent-1 publisher commit,
# and keep dry-run origin unchanged while the watchdog checks pid plus event freshness.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIXTURE="$(mktemp -d --tmpdir="$HOME" publisher_bats.XXXXXX)"
    REMOTE="$FIXTURE/remote.git"; WORK="$FIXTURE/work"; PUBROOT="$FIXTURE/pubroot"; STATE="$FIXTURE/state"
    git init --bare -q "$REMOTE"; git init -q "$WORK"
    git -C "$WORK" config user.email test@example.invalid; git -C "$WORK" config user.name test
    printf 'base\n' > "$WORK/payload.txt"
    printf 'base-unrelated\n' > "$WORK/unrelated.txt"
    git -C "$WORK" add payload.txt unrelated.txt
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
cmd_id: cmd_test_publisher
parent_cmd: cmd_test_publisher
publish_attempts: 0
EOF
    key="$(printf '%s' "queue/reports/$(basename "$FIXTURE/request.yaml")" | sha256sum | cut -d' ' -f1)"
    approval_dir="$ROOT/queue/gates/cmd_test_publisher/review_approvals/reports/$key"
    mkdir -p "$approval_dir"
    : > "$approval_dir/gunshi.yaml"
    : > "$approval_dir/karo.yaml"
    export SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$WORK" PUBLISHER_MODE=dry-run
    cat > "$FIXTURE/inbox_write.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${INBOX_WRITE_STUB_LOG:?}"
EOF
    chmod +x "$FIXTURE/inbox_write.sh"
    export PUBLISHER_INBOX_WRITER="$FIXTURE/inbox_write.sh" INBOX_WRITE_STUB_LOG="$FIXTURE/inbox.log"
}

teardown() {
    find "$FIXTURE" -depth -delete 2>/dev/null || true
    find "$ROOT/queue/gates/cmd_test_publisher" -depth -delete 2>/dev/null || true
}

@test "dry-run validates C2a, creates no origin update, and records event" {
    bash "$ROOT/scripts/publisher_queue.sh" enqueue "$FIXTURE/request.yaml" >/dev/null
    before="$(git --git-dir="$REMOTE" rev-parse refs/heads/main)"
    run env SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$WORK" PUBLISHER_ONCE=1 bash "$ROOT/scripts/publisher.sh"
    [ "$status" -eq 0 ]
    after="$(git --git-dir="$REMOTE" rev-parse refs/heads/main)"; [ "$before" = "$after" ]
    [ "$(jq -r 'select(.kind=="dry_run_publish") | .kind' "$STATE/publish_queue/events.jsonl")" = dry_run_publish ]
    [ "$(find "$STATE/publish_queue/done" -name '*.request' | wc -l)" -eq 1 ]
}

# test_necessity: c2a telemetry is fail-open and must not replace the single
# EXIT cleanup/rc contract. Both a clone failure and a successful merge must
# leave exactly one source-specific telemetry attempt.
@test "c2a telemetry failure preserves merge rc cleanup and PASS/FAIL attempts" {
    local base="$FIXTURE/c2a-contract"
    mkdir -p "$base/root/scripts/lib" "$base/tmp" "$base/success/tmp" "$base/failure/tmp"
    cp "$ROOT/scripts/publisher_c2a_merge.sh" "$base/root/scripts/publisher_c2a_merge.sh"
    chmod +x "$base/root/scripts/publisher_c2a_merge.sh"
    cat > "$base/root/scripts/lib/defense_overhead_writer.sh" <<'EOF'
defense_overhead_write() {
    printf '%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" >> "${TEST_LEDGER:?}"
    return "${TEST_WRITER_RC:-0}"
}
EOF

    git init --bare -q "$base/remote.git"
    git init -q "$base/root"
    git -C "$base/root" config user.email test@example.invalid
    git -C "$base/root" config user.name test
    printf 'base\n' > "$base/root/state"
    git -C "$base/root" add state
    git -C "$base/root" commit -q -m base
    git -C "$base/root" branch -M main
    git -C "$base/root" remote add origin "$base/remote.git"
    git -C "$base/root" push -q -u origin main
    printf 'source\n' > "$base/root/new-file"
    git -C "$base/root" add new-file
    git -C "$base/root" commit -q -m source
    local source_sha
    source_sha="$(git -C "$base/root" rev-parse HEAD)"

    # Successful merge with a writer that always fails: source rc stays zero.
    TEST_LEDGER="$base/success/events" TEST_WRITER_RC=3 TMPDIR="$base/success/tmp" PUBLISHER_C2A_MERGE_NOLOCK=1 \
      run bash "$base/root/scripts/publisher_c2a_merge.sh" cmd_c2a_success "$source_sha"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$base/success/events")" -eq 1 ]
    grep -q '^publisher_c2a|c2a_merge_total|[0-9][0-9]*|PASS|' "$base/success/events"
    [ "$(find "$base/success/tmp" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 0 ]

    # Failed clone with the same telemetry failure: the original nonzero rc
    # must remain visible and cleanup must still remove the worktree.
    git -C "$base/root" remote set-url origin "$base/missing.git"
    TEST_LEDGER="$base/failure/events" TEST_WRITER_RC=3 TMPDIR="$base/failure/tmp" PUBLISHER_C2A_MERGE_NOLOCK=1 \
      run bash "$base/root/scripts/publisher_c2a_merge.sh" cmd_c2a_failure "$source_sha"
    [ "$status" -ne 0 ]
    [ "$(wc -l < "$base/failure/events")" -eq 1 ]
    grep -q '^publisher_c2a|c2a_merge_total|[0-9][0-9]*|FAIL|' "$base/failure/events"
    [ "$(find "$base/failure/tmp" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 0 ]
}

# test_necessity: isolated publication must clone from the local publisher
# root with an object reference, then fetch only the remote delta from origin.
@test "isolated publication uses a local reference clone before origin fetch" {
    mkdir -p "$FIXTURE/bin"
    cat > "$FIXTURE/bin/git" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${GIT_CALL_LOG:?}"
exec /usr/bin/git "$@"
EOF
    chmod +x "$FIXTURE/bin/git"
    export GIT_CALL_LOG="$FIXTURE/git-calls"
    bash "$ROOT/scripts/publisher_queue.sh" enqueue "$FIXTURE/request.yaml" >/dev/null
    run env PATH="$FIXTURE/bin:$PATH" SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$PUBROOT" PUBLISHER_INBOX_WRITER="$FIXTURE/inbox_write.sh" PUBLISHER_ONCE=1 bash "$ROOT/scripts/publisher.sh"
    [ "$status" -eq 0 ]
    clone_line="$(grep -- 'clone --no-checkout' "$GIT_CALL_LOG")"
    [[ "$clone_line" == *"--reference"* ]]
    [[ "$clone_line" == *"$PUBROOT"* ]]
    [[ "$clone_line" != *"$REMOTE"* ]]
    [ "$(grep -c -- '-C .* fetch origin' "$GIT_CALL_LOG")" -ge 1 ]
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

# test_necessity: a tip whose changed blob already equals the manifest's
# expected blob is an idempotent publication and must not create a second
# publisher commit or an RC.
@test "already published tip is an idempotent no-op" {
    git -C "$WORK" push -q origin main
    bash "$ROOT/scripts/publisher_queue.sh" enqueue "$FIXTURE/request.yaml" >/dev/null
    run env SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$PUBROOT" PUBLISHER_INBOX_WRITER="$FIXTURE/inbox_write.sh" PUBLISHER_ONCE=1 bash "$ROOT/scripts/publisher.sh"
    [ "$status" -eq 0 ]
    [ "$(find "$STATE/publish_queue/done" -name '*.request' | wc -l)" -eq 1 ]
    [ "$(find "$STATE/publish_queue/rc" -name '*.request' | wc -l)" -eq 0 ]
    [ "$(jq -r 'select(.kind=="already_published") | .reason' "$STATE/publish_queue/events.jsonl")" = "published_sha=$(git --git-dir="$REMOTE" rev-parse refs/heads/main)" ]
    [ ! -f "$FIXTURE/inbox.log" ] || [ "$(wc -l < "$FIXTURE/inbox.log")" -eq 0 ]
}

# test_necessity: a missing artifact must be retired only when an explicitly
# recorded publication identity is reachable from the fetched canonical tip.
@test "missing artifact uses a published_sha ancestor as an idempotent no-op" {
    find "$STATE/publish_queue/artifacts/task_u3" -depth -delete
    printf "published_sha: '%s'\n" "$BASE" >> "$FIXTURE/request.yaml"
    bash "$ROOT/scripts/publisher_queue.sh" enqueue "$FIXTURE/request.yaml" >/dev/null
    run env SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$PUBROOT" PUBLISHER_INBOX_WRITER="$FIXTURE/inbox_write.sh" PUBLISHER_ONCE=1 bash "$ROOT/scripts/publisher.sh"
    [ "$status" -eq 0 ]
    [ "$(find "$STATE/publish_queue/done" -name '*.request' | wc -l)" -eq 1 ]
    [ "$(find "$STATE/publish_queue/rc" -name '*.request' | wc -l)" -eq 0 ]
    jq -e 'select(.kind=="already_published" and (.reason|contains("identity=published_sha:")) and (.reason|contains("artifact=missing")))' "$STATE/publish_queue/events.jsonl" >/dev/null
    [ ! -f "$FIXTURE/inbox.log" ] || [ "$(wc -l < "$FIXTURE/inbox.log")" -eq 0 ]
}

# test_necessity: a commit reachable only from local main is not proof of
# publication and must remain an rc31 fail-close.
@test "missing artifact keeps rc31 when identity is local-main-only" {
    printf 'local-only\n' > "$PUBROOT/local-only.txt"
    git -C "$PUBROOT" add local-only.txt; git -C "$PUBROOT" commit -q -m local-only
    local_only="$(git -C "$PUBROOT" rev-parse HEAD)"
    find "$STATE/publish_queue/artifacts/task_u3" -depth -delete
    printf "report_commit: '%s'\n" "$local_only" >> "$FIXTURE/request.yaml"
    bash "$ROOT/scripts/publisher_queue.sh" enqueue "$FIXTURE/request.yaml" >/dev/null
    run env SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$PUBROOT" PUBLISHER_INBOX_WRITER="$FIXTURE/inbox_write.sh" PUBLISHER_ONCE=1 bash "$ROOT/scripts/publisher.sh"
    [ "$status" -ne 0 ]
    [ "$(find "$STATE/publish_queue/rc" -name '*.request' | wc -l)" -eq 1 ]
    [ "$(jq -r 'select(.kind=="already_published") | .kind' "$STATE/publish_queue/events.jsonl")" = "" ]
    [ "$(jq -r 'select(.kind=="git_fail") | .rc' "$STATE/publish_queue/events.jsonl" | tail -n1)" = "31" ]
}

# test_necessity: malformed publication identities must not be treated as
# canonical ancestry evidence when the artifact is absent.
@test "missing artifact keeps rc31 for an unknown identity" {
    find "$STATE/publish_queue/artifacts/task_u3" -depth -delete
    printf 'published_sha: not-a-commit\n' >> "$FIXTURE/request.yaml"
    bash "$ROOT/scripts/publisher_queue.sh" enqueue "$FIXTURE/request.yaml" >/dev/null
    run env SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$PUBROOT" PUBLISHER_INBOX_WRITER="$FIXTURE/inbox_write.sh" PUBLISHER_ONCE=1 bash "$ROOT/scripts/publisher.sh"
    [ "$status" -ne 0 ]
    [ "$(find "$STATE/publish_queue/rc" -name '*.request' | wc -l)" -eq 1 ]
    [ "$(jq -r 'select(.kind=="already_published") | .kind' "$STATE/publish_queue/events.jsonl")" = "" ]
    [ "$(jq -r 'select(.kind=="git_fail") | .rc' "$STATE/publish_queue/events.jsonl" | tail -n1)" = "31" ]
}

# test_necessity: a fetch failure leaves missing-artifact requests fail-closed
# even when their identity would otherwise be a valid commit.
@test "missing artifact keeps rc31 when origin fetch fails" {
    find "$STATE/publish_queue/artifacts/task_u3" -depth -delete
    printf "published_sha: '%s'\n" "$BASE" >> "$FIXTURE/request.yaml"
    bash "$ROOT/scripts/publisher_queue.sh" enqueue "$FIXTURE/request.yaml" >/dev/null
    git -C "$PUBROOT" remote set-url origin "$FIXTURE/missing-remote.git"
    run env SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$PUBROOT" PUBLISHER_INBOX_WRITER="$FIXTURE/inbox_write.sh" PUBLISHER_ONCE=1 bash "$ROOT/scripts/publisher.sh"
    [ "$status" -ne 0 ]
    [ "$(find "$STATE/publish_queue/rc" -name '*.request' | wc -l)" -eq 1 ]
    [ "$(jq -r 'select(.kind=="already_published") | .kind' "$STATE/publish_queue/events.jsonl")" = "" ]
    [ "$(jq -r 'select(.kind=="git_fail") | .rc' "$STATE/publish_queue/events.jsonl" | tail -n1)" = "31" ]
}

# test_necessity: a non-conflicting patch must apply against the isolated tip
# even when an unrelated file advanced after the request was captured.
@test "restore applies patch to an advanced tip without a conflict" {
    printf 'unrelated\n' > "$PUBROOT/remote.txt"
    git -C "$PUBROOT" add remote.txt; git -C "$PUBROOT" commit -q -m unrelated
    git -C "$PUBROOT" push -q origin main
    bash "$ROOT/scripts/publisher_queue.sh" enqueue "$FIXTURE/request.yaml" >/dev/null
    run env SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$PUBROOT" PUBLISHER_INBOX_WRITER="$FIXTURE/inbox_write.sh" PUBLISHER_ONCE=1 bash "$ROOT/scripts/publisher.sh"
    [ "$status" -eq 0 ]
    [ "$(jq -r 'select(.kind=="dry_run_publish") | .kind' "$STATE/publish_queue/events.jsonl")" = dry_run_publish ]
    [ "$(jq -r 'select(.kind=="restore_rc") | .kind' "$STATE/publish_queue/events.jsonl" | wc -l)" -eq 0 ]
}

# test_necessity: publisher failure notifications must use a wake-up type
# accepted by the karo inbox allowlist rather than the blocked investigation lane.
@test "publisher notifications use an allowed wake type" {
    bash "$ROOT/scripts/publisher_queue.sh" enqueue "$FIXTURE/request.yaml" >/dev/null
    printf 'remote-change\n' > "$PUBROOT/payload.txt"
    git -C "$PUBROOT" add payload.txt; git -C "$PUBROOT" commit -q -m remote-change
    git -C "$PUBROOT" push -q origin main
    run env SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$PUBROOT" PUBLISHER_INBOX_WRITER="$FIXTURE/inbox_write.sh" PUBLISHER_ONCE=1 bash "$ROOT/scripts/publisher.sh"
    [ "$status" -ne 0 ]
    grep -Eq ' (task_assigned|report_received|task_done|report_completed|report_done|report_ready|task_failed) publisher notify_karo$' "$FIXTURE/inbox.log"
}

# test_necessity: publisher failure notifications in test mode must use the
# isolated inbox root even when the caller's configured root points at a live
# queue symlink (T3-S-64 regression).
@test "test-mode publisher notifications stay in test inbox" {
    local live_root="$BATS_TEST_TMPDIR/live-root" isolated_root="$BATS_TEST_TMPDIR/test-root"
    mkdir -p "$live_root/queue" "$live_root/live-inbox" "$isolated_root/scripts"
    ln -s "$live_root/live-inbox" "$live_root/queue/inbox"
    ln -s "$ROOT/scripts/lib" "$isolated_root/scripts/lib"
    bash "$ROOT/scripts/publisher_queue.sh" enqueue "$FIXTURE/request.yaml" >/dev/null
    printf 'remote-change\n' > "$PUBROOT/payload.txt"
    git -C "$PUBROOT" add payload.txt; git -C "$PUBROOT" commit -q -m remote-change
    git -C "$PUBROOT" push -q origin main

    run env SHOGUN_TEST_MODE=1 SHOGUN_TEST_INBOX_ROOT="$isolated_root" \
        INBOX_WRITE_ROOT_OVERRIDE="$live_root" \
        SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$PUBROOT" \
        PUBLISHER_INBOX_WRITER="$ROOT/scripts/inbox_write.sh" PUBLISHER_ONCE=1 \
        bash "$ROOT/scripts/publisher.sh"
    [ "$status" -ne 0 ]
    [ -f "$isolated_root/queue/inbox/karo.yaml" ]
    grep -q 'publisher C2a RC' "$isolated_root/queue/inbox/karo.yaml"
    [ ! -e "$live_root/queue/inbox/karo.yaml" ]
}

# test_necessity: production mode must preserve the configured inbox root so
# real publisher failures continue to notify Karo through the live lane.
@test "production publisher notifications retain the configured inbox root" {
    local live_root="$BATS_TEST_TMPDIR/live-root"
    mkdir -p "$live_root/queue" "$live_root/live-inbox"
    ln -s "$live_root/live-inbox" "$live_root/queue/inbox"
    bash "$ROOT/scripts/publisher_queue.sh" enqueue "$FIXTURE/request.yaml" >/dev/null
    printf 'remote-change\n' > "$PUBROOT/payload.txt"
    git -C "$PUBROOT" add payload.txt; git -C "$PUBROOT" commit -q -m remote-change
    git -C "$PUBROOT" push -q origin main

    run env -u SHOGUN_TEST_MODE -u SHOGUN_TEST_INBOX_ROOT -u INBOX_WRITE_ROOT_OVERRIDE \
        INBOX_WRITE_MAILBOX_ROOT="$live_root" \
        SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$PUBROOT" \
        PUBLISHER_INBOX_WRITER="$ROOT/scripts/inbox_write.sh" PUBLISHER_ONCE=1 \
        bash "$ROOT/scripts/publisher.sh"
    [ "$status" -ne 0 ]
    [ -f "$live_root/queue/inbox/karo.yaml" ]
    grep -q 'publisher C2a RC' "$live_root/queue/inbox/karo.yaml"
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

# test_necessity: a cleanup_isolated failure after the push has already
# landed (e.g. a concurrent git gc lock on the isolated clone) must not
# revert the request to rc/ with zero done receipts and a failure
# notification — push is the terminal success boundary
# (cmd_karo_hotfix_publisher_postpush_cleanup).
@test "active publish tolerates a post-push cleanup_isolated failure" {
    export PUBLISHER_REPO_ROOT="$PUBROOT" PUBLISHER_MODE=active
    mkdir -p "$FIXTURE/bin"
    cat > "$FIXTURE/bin/find" <<'EOF'
#!/bin/bash
case " $* " in
    *" -delete "*)
        case "$1" in
            *"/.git/publisher-isolated."*)
                echo "find: cannot delete '$1': Resource temporarily unavailable" >&2
                exit 1
                ;;
        esac
        ;;
esac
exec /usr/bin/find "$@"
EOF
    chmod +x "$FIXTURE/bin/find"
    bash "$ROOT/scripts/publisher_queue.sh" enqueue "$FIXTURE/request.yaml" >/dev/null
    run env PATH="$FIXTURE/bin:$PATH" SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$PUBROOT" PUBLISHER_INBOX_WRITER="$FIXTURE/inbox_write.sh" PUBLISHER_MODE=active PUBLISHER_ONCE=1 bash "$ROOT/scripts/publisher.sh"
    [ "$status" -eq 0 ]
    [ "$(git -C "$PUBROOT" rev-parse HEAD)" = "$(git -C "$PUBROOT" rev-parse origin/main)" ]
    [ "$(find "$STATE/publish_queue/done" -name '*.request' | wc -l)" -eq 1 ]
    [ ! -d "$STATE/publish_queue/rc" ] || [ "$(find "$STATE/publish_queue/rc" -name '*.request' | wc -l)" -eq 0 ]
    [ ! -s "$FIXTURE/inbox.log" ]
    [ "$(jq -r 'select(.kind=="published") | .kind' "$STATE/publish_queue/events.jsonl")" = published ]
}

# test_necessity: a tracked dirty path with a configured .gitattributes driver
# must be integrated against the incoming published tip and leave HEAD there.
@test "active root sync integrates a dirty overlapping path with its merge driver" {
    printf 'payload.txt merge=test-driver\n' > "$PUBROOT/.gitattributes"
    git -C "$PUBROOT" config merge.test-driver.driver 'cp %B %A'
    printf 'local-dirty\n' > "$PUBROOT/payload.txt"
    git -C "$WORK" push -q origin HEAD
    git -C "$PUBROOT" fetch -q origin
    tip="$(git -C "$PUBROOT" rev-parse origin/main)"

    run bash -c 'PUBLISHER_LIB_ONLY=1 PUBLISHER_REPO_ROOT="$1" source "$2/scripts/publisher.sh"; sync_root "$1" "$3"' _ "$PUBROOT" "$ROOT" "$tip"
    [ "$status" -eq 0 ]
    [ "$(git -C "$PUBROOT" rev-parse HEAD)" = "$tip" ]
    [ "$(<"$PUBROOT/payload.txt")" = "published" ]
}

# test_necessity: a tracked dirty path outside the incoming publication must
# retain its exact bytes while an overlapping path is merged by its driver.
@test "active root sync preserves a dirty non-overlapping path" {
    printf 'payload.txt merge=test-driver\n' > "$PUBROOT/.gitattributes"
    git -C "$PUBROOT" config merge.test-driver.driver 'cp %B %A'
    printf 'local-overlap\n' > "$PUBROOT/payload.txt"
    printf 'local-unrelated\n' > "$PUBROOT/unrelated.txt"
    before_payload="$(sha256sum "$PUBROOT/payload.txt" | awk '{print $1}')"
    before_unrelated="$(sha256sum "$PUBROOT/unrelated.txt" | awk '{print $1}')"
    git -C "$WORK" push -q origin HEAD
    git -C "$PUBROOT" fetch -q origin
    tip="$(git -C "$PUBROOT" rev-parse origin/main)"

    run bash -c 'PUBLISHER_LIB_ONLY=1 PUBLISHER_REPO_ROOT="$1" source "$2/scripts/publisher.sh"; sync_root "$1" "$3"' _ "$PUBROOT" "$ROOT" "$tip"
    [ "$status" -eq 0 ]
    [ "$(git -C "$PUBROOT" rev-parse HEAD)" = "$tip" ]
    [ "$(sha256sum "$PUBROOT/payload.txt" | awk '{print $1}')" != "$before_payload" ]
    [ "$(sha256sum "$PUBROOT/unrelated.txt" | awk '{print $1}')" = "$before_unrelated" ]
    [ "$(<"$PUBROOT/payload.txt")" = "published" ]
    [ "$(<"$PUBROOT/unrelated.txt")" = "local-unrelated" ]
}

# test_necessity: an overlapping tracked dirty path without an explicitly
# configured driver must fail closed and preserve both the ref and local data.
@test "active root sync skips dirty overlap when no merge driver is configured" {
    printf 'local-dirty\n' > "$PUBROOT/payload.txt"
    git -C "$WORK" push -q origin HEAD
    git -C "$PUBROOT" fetch -q origin
    tip="$(git -C "$PUBROOT" rev-parse origin/main)"
    base="$(git -C "$PUBROOT" rev-parse HEAD)"

    run bash -c 'PUBLISHER_LIB_ONLY=1 PUBLISHER_REPO_ROOT="$1" source "$2/scripts/publisher.sh"; sync_root "$1" "$3"' _ "$PUBROOT" "$ROOT" "$tip"
    [ "$status" -eq 32 ]
    [ "$(git -C "$PUBROOT" rev-parse HEAD)" = "$base" ]
    [ "$(<"$PUBROOT/payload.txt")" = "local-dirty" ]
    [[ "$output" == *"no_driver paths=payload.txt"* ]]
}

# test_necessity: a concurrent writer moving root HEAD between the head
# capture and update-ref's compare-and-swap must be classified explicitly,
# not fall through to the reason-less "unknown" default (38/39 current-format
# root_sync_skipped events on 2026-09-03 06:01-07:34 were reason=unknown
# before this fix, per the ff/no-overlap branch's update-ref call).
@test "active root sync classifies a lost HEAD race as head_moved, not unknown" {
    git -C "$WORK" push -q origin HEAD
    git -C "$PUBROOT" fetch -q origin
    tip="$(git -C "$PUBROOT" rev-parse origin/main)"
    base="$(git -C "$PUBROOT" rev-parse HEAD)"

    run bash -c '
        PUBLISHER_LIB_ONLY=1 PUBLISHER_REPO_ROOT="$1" source "$2/scripts/publisher.sh"
        git() {
            if [ "$1" = -C ] && [ "$3" = update-ref ] && [ "$4" = HEAD ]; then
                echo "fatal: simulated CAS loss" >&2
                return 1
            fi
            command git "$@"
        }
        sync_root "$1" "$3"
    ' _ "$PUBROOT" "$ROOT" "$tip"
    [ "$status" -eq 32 ]
    [ "$(git -C "$PUBROOT" rev-parse HEAD)" = "$base" ]
    [[ "$output" == *"head_moved"* ]]
    [[ "$output" != *"reason=unknown"* ]]
}

# test_necessity: the same CAS-loss classification must also apply inside the
# driver 3-way branch (the branch most commonly overlapping in production),
# and the locally merged dirty content must not be discarded when the skip
# is reported.
@test "active root sync classifies a lost HEAD race during driver merge as head_moved" {
    printf 'payload.txt merge=test-driver\n' > "$PUBROOT/.gitattributes"
    git -C "$PUBROOT" config merge.test-driver.driver 'cp %B %A'
    printf 'local-dirty\n' > "$PUBROOT/payload.txt"
    git -C "$WORK" push -q origin HEAD
    git -C "$PUBROOT" fetch -q origin
    tip="$(git -C "$PUBROOT" rev-parse origin/main)"
    base="$(git -C "$PUBROOT" rev-parse HEAD)"

    run bash -c '
        PUBLISHER_LIB_ONLY=1 PUBLISHER_REPO_ROOT="$1" source "$2/scripts/publisher.sh"
        git() {
            if [ "$1" = -C ] && [ "$3" = update-ref ] && [ "$4" = HEAD ]; then
                echo "fatal: simulated CAS loss" >&2
                return 1
            fi
            command git "$@"
        }
        sync_root "$1" "$3"
    ' _ "$PUBROOT" "$ROOT" "$tip"
    [ "$status" -eq 32 ]
    [ "$(git -C "$PUBROOT" rev-parse HEAD)" = "$base" ]
    [ "$(<"$PUBROOT/payload.txt")" = "local-dirty" ]
    [[ "$output" == *"head_moved"* ]]
    [[ "$output" != *"reason=unknown"* ]]
}

# test_necessity: local HEAD diverging from the incoming tip (not an
# ancestor) must stay reported as not_descendant, distinct from head_moved,
# and must not touch the root's ref or worktree.
@test "active root sync reports not_descendant when local HEAD diverges from tip" {
    printf 'root-local\n' > "$PUBROOT/rootlocal.txt"
    git -C "$PUBROOT" add rootlocal.txt
    git -C "$PUBROOT" commit -q -m root-local
    git -C "$WORK" push -q origin HEAD
    git -C "$PUBROOT" fetch -q origin
    tip="$(git -C "$PUBROOT" rev-parse origin/main)"
    head="$(git -C "$PUBROOT" rev-parse HEAD)"

    run bash -c 'PUBLISHER_LIB_ONLY=1 PUBLISHER_REPO_ROOT="$1" source "$2/scripts/publisher.sh"; sync_root "$1" "$3"' _ "$PUBROOT" "$ROOT" "$tip"
    [ "$status" -eq 32 ]
    [ "$(git -C "$PUBROOT" rev-parse HEAD)" = "$head" ]
    [[ "$output" == *"not_descendant"* ]]
}

# test_necessity: every externally visible publisher daemon line must retain
# its JST timestamp prefix so logs can be assigned to a publication window.
@test "publisher daemon output lines start with JST ISO timestamps" {
    run bash -c 'PUBLISHER_LIB_ONLY=1 source "$1/scripts/publisher.sh"; printf "first\n\nlast\n" | publisher_timestamp_stream' _ "$ROOT"
    [ "$status" -eq 0 ]
    [ "$(printf "%s\n" "$output" | grep -Ec "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+09:00 ")" -eq 3 ]
}
