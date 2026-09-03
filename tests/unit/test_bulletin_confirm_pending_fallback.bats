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
}

teardown() { rm -rf "$TMP"; }

@test "pending append op is used when board lacks the entry; update is enqueued and closes for notify_targets" {
    export LEDGER_STUB_LOG="$TMP/stub.log"
    run env PUBLISHER_SINGLE=1 BULLETIN_LEDGER_PENDING_DIR="$TMP/pending" bash "$TMP/root/scripts/bulletin_confirm.sh" shogun blt_test_pending
    [ "$status" -eq 0 ]
    grep -q 'update bulletin blt_test_pending confirmed_by=\["shogun"\] status=closed --expect status=open' "$TMP/stub.log"
}

@test "unknown id with no pending op still errors" {
    export LEDGER_STUB_LOG="$TMP/stub.log"
    run env PUBLISHER_SINGLE=1 BULLETIN_LEDGER_PENDING_DIR="$TMP/pending" bash "$TMP/root/scripts/bulletin_confirm.sh" shogun blt_nope
    [ "$status" -ne 0 ]
    [[ "$output" == *"entry not found"* ]]
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
