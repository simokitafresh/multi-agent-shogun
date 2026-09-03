#!/usr/bin/env bats
# test_necessity: bulletin_confirm は board file に未適用(ledger pending)の entry でも append op から復元して confirm を enqueue する(T3-S-29 の不変量: notify が ledger 適用より先でも confirm が消えない)

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/root/queue" "$TMP/root/scripts/lib" "$TMP/pending"
    cp "$REPO/scripts/bulletin_confirm.sh" "$TMP/root/scripts/"
    cp "$REPO/scripts/lib/publisher_single_flag.sh" "$TMP/root/scripts/lib/"
    printf 'entries:\n' > "$TMP/root/queue/bulletin_board.yaml"
    cat > "$TMP/root/scripts/ledger_writer.sh" <<'STUB'
#!/usr/bin/env bash
printf 'STUB %s\n' "$*" >> "$LEDGER_STUB_LOG"
STUB
    chmod +x "$TMP/root/scripts/ledger_writer.sh"
    python3 - "$TMP/pending/20260903T090000000000000Z_000000000001.yaml" <<'PY'
import hashlib, json, sys
entry = ("- id: 'blt_test_pending'\n  content: 'hello'\n  posted_by: 'karo'\n  posted_at: '2026-09-03T18:00:00'\n"
         "  requires_confirmation: false\n  action_type: 'info'\n  actioned_by: ''\n  notify_targets:\n    - 'shogun'\n"
         "  confirmed_by: []\n  status: 'open'\n")
json.dump({"op": "append", "ledger": "bulletin", "id": "blt_test_pending", "entry_text": entry, "entry_hash": hashlib.sha256(entry.encode()).hexdigest()}, open(sys.argv[1], "w"))
PY
    # Isolate the T3-S-48 applied-ledger fallback from real production state;
    # without this, a test that omits BULLETIN_LEDGER_APPLIED_DIR would fall
    # back to scanning ~/.local/share/multi-agent-shogun's live ledger.
    export SHOGUN_STATE_DIR="$TMP/state"
}

teardown() { rm -rf "$TMP"; }

@test "pending append op is used when board lacks the entry; update is enqueued and closes for notify_targets" {
    export LEDGER_STUB_LOG="$TMP/stub.log"
    run env PUBLISHER_SINGLE=1 BULLETIN_LEDGER_PENDING_DIR="$TMP/pending" bash "$TMP/root/scripts/bulletin_confirm.sh" shogun blt_test_pending
    [ "$status" -eq 0 ]
    grep -q 'update bulletin blt_test_pending confirmed_by=\["shogun"\] status=closed --expect status=open' "$TMP/stub.log"
}

# AC2 fixture "双方missing" — no matching id on the board, in the pending
# queue, in the applied ledger (isolated SHOGUN_STATE_DIR, empty by setup),
# or on origin/main (no .git in $TMP/root): must still error, not fabricate.
@test "unknown id with no pending op still errors" {
    export LEDGER_STUB_LOG="$TMP/stub.log"
    run env PUBLISHER_SINGLE=1 BULLETIN_LEDGER_PENDING_DIR="$TMP/pending" bash "$TMP/root/scripts/bulletin_confirm.sh" shogun blt_nope
    [ "$status" -ne 0 ]
    [[ "$output" == *"entry not found"* ]]
}

# test_necessity: AC2 fixture "root present" — the entry already lives on the
# board itself; the T3-S-48 fallback chain must never be consulted (normal
# fast path stays unchanged when root and origin agree).
@test "entry already present on the board confirms via the normal path unchanged" {
    export LEDGER_STUB_LOG="$TMP/stub.log"
    cat > "$TMP/root/queue/bulletin_board.yaml" <<'YAML'
entries:
- id: 'blt_test_present'
  content: 'hello'
  posted_by: 'karo'
  posted_at: '2026-09-03T18:00:00'
  requires_confirmation: false
  action_type: 'info'
  actioned_by: ''
  notify_targets:
    - 'shogun'
  confirmed_by: []
  status: 'open'
YAML
    run env PUBLISHER_SINGLE=1 BULLETIN_LEDGER_PENDING_DIR="$TMP/pending" bash "$TMP/root/scripts/bulletin_confirm.sh" shogun blt_test_present
    [ "$status" -eq 0 ]
    grep -q 'update bulletin blt_test_present confirmed_by=\["shogun"\] status=closed --expect status=open' "$TMP/stub.log"
}

# test_necessity: T3-S-48 invariant — a task-worktree checkout (or a root
# behind an un-pulled push) never receives the single publisher's write
# directly to its own board file; the entry may already be committed+pushed
# to origin/main. AC2 fixture "root stale/origin present".
@test "origin/main-only entry is used when board and pending both lack it" {
    export LEDGER_STUB_LOG="$TMP/stub.log"
    git init -q -b main "$TMP/root"
    git -C "$TMP/root" config user.email test@example.com
    git -C "$TMP/root" config user.name test
    blob="$(cat <<'YAML' | git -C "$TMP/root" hash-object -w --stdin
entries:
- id: 'blt_test_origin'
  content: 'from origin'
  posted_by: 'karo'
  posted_at: '2026-09-03T18:00:00'
  requires_confirmation: false
  action_type: 'info'
  actioned_by: ''
  notify_targets:
    - 'shogun'
  confirmed_by: []
  status: 'open'
YAML
)"
    queue_tree="$(printf '100644 blob %s\tbulletin_board.yaml\n' "$blob" | git -C "$TMP/root" mktree)"
    root_tree="$(printf '040000 tree %s\tqueue\n' "$queue_tree" | git -C "$TMP/root" mktree)"
    commit="$(printf 'origin fixture\n' | git -C "$TMP/root" commit-tree "$root_tree")"
    git -C "$TMP/root" update-ref refs/remotes/origin/main "$commit"

    run env PUBLISHER_SINGLE=1 BULLETIN_LEDGER_PENDING_DIR="$TMP/pending" bash "$TMP/root/scripts/bulletin_confirm.sh" shogun blt_test_origin
    [ "$status" -eq 0 ]
    grep -q 'update bulletin blt_test_origin confirmed_by=\["shogun"\] status=closed --expect status=open' "$TMP/stub.log"
}

# test_necessity: same T3-S-48 invariant for the applied-op ledger source
# (SHOGUN_STATE_DIR is shared across worktrees, unlike the repo working tree).
@test "applied-ledger-only entry is used when board, pending, and origin all lack it" {
    export LEDGER_STUB_LOG="$TMP/stub.log"
    mkdir -p "$SHOGUN_STATE_DIR/ledger_inbox/bulletin/applied"
    python3 - "$SHOGUN_STATE_DIR/ledger_inbox/bulletin/applied/20260903T090000000000000Z_000000000002.yaml" <<'PY'
import hashlib, json, sys
entry = ("- id: 'blt_test_applied'\n  content: 'hello'\n  posted_by: 'karo'\n  posted_at: '2026-09-03T18:00:00'\n"
         "  requires_confirmation: false\n  action_type: 'info'\n  actioned_by: ''\n  notify_targets:\n    - 'shogun'\n"
         "  confirmed_by: []\n  status: 'open'\n")
json.dump({"op": "append", "ledger": "bulletin", "id": "blt_test_applied", "entry_text": entry, "entry_hash": hashlib.sha256(entry.encode()).hexdigest()}, open(sys.argv[1], "w"))
PY
    run env PUBLISHER_SINGLE=1 BULLETIN_LEDGER_PENDING_DIR="$TMP/pending" bash "$TMP/root/scripts/bulletin_confirm.sh" shogun blt_test_applied
    [ "$status" -eq 0 ]
    grep -q 'update bulletin blt_test_applied confirmed_by=\["shogun"\] status=closed --expect status=open' "$TMP/stub.log"
}

@test "ledger_writer update accepts a target that exists only as a pending append op" {
    # test_necessity: update(confirm/action) が append 未適用の同 id で enqueue できる(apply は順序保証、CAS は expected 欄)
    export SHOGUN_STATE_DIR="$TMP/state"
    mkdir -p "$SHOGUN_STATE_DIR/ledger_inbox/bulletin"
    cp "$TMP/pending/"*.yaml "$SHOGUN_STATE_DIR/ledger_inbox/bulletin/"
    run env LEDGER_SOURCE_FILE="$TMP/root/queue/bulletin_board.yaml" bash "$REPO/scripts/ledger_writer.sh" update bulletin blt_test_pending 'confirmed_by=["shogun"]' status=closed --expect status=open
    [ "$status" -eq 0 ]
    n=$(ls "$SHOGUN_STATE_DIR/ledger_inbox/bulletin/"*.yaml | wc -l)
    [ "$n" -eq 2 ]
    for f in $(ls "$SHOGUN_STATE_DIR/ledger_inbox/bulletin/"*.yaml | sort); do
        LEDGER_WRITER_NOTIFY=0 LEDGER_SOURCE_FILE="$TMP/root/queue/bulletin_board.yaml" bash "$REPO/scripts/ledger_writer.sh" apply "$f" >/dev/null
    done
    grep -q 'status: "closed"' "$TMP/root/queue/bulletin_board.yaml"
}
