#!/usr/bin/env bats
# test_necessity: ledger operations must be published as one isolated batch while
# preserving writer-side root immutability and fail-close semantics.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIXTURE="$(mktemp -d --tmpdir="$HOME" publisher_ledger_bats.XXXXXX)"
    REMOTE="$FIXTURE/remote.git"; ORIGIN="$FIXTURE/origin"; PUBROOT="$FIXTURE/pubroot"; STATE="$FIXTURE/state"
    git init --bare -q "$REMOTE"; git init -q "$ORIGIN"
    git -C "$ORIGIN" config user.email test@example.invalid
    git -C "$ORIGIN" config user.name test
    mkdir -p "$ORIGIN/queue"
    printf 'insights:\n' > "$ORIGIN/queue/insights.yaml"
    git -C "$ORIGIN" add queue/insights.yaml
    git -C "$ORIGIN" commit -q -m base
    git -C "$ORIGIN" branch -M main
    git -C "$ORIGIN" remote add origin "$REMOTE"
    git -C "$ORIGIN" push -q -u origin main
    git clone -q "$REMOTE" "$PUBROOT"
    git -C "$PUBROOT" checkout -q -b main origin/main
    chmod +x "$ROOT/scripts/ledger_writer.sh"
}

teardown() {
    find "$FIXTURE" -depth -delete 2>/dev/null || true
}

@test "insight writer emits an op and publisher applies one active ledger commit" {
    run env SHOGUN_STATE_DIR="$STATE" INSIGHTS_FILE="$PUBROOT/queue/insights.yaml" \
        INSIGHT_AUTO_COMMIT=0 INSIGHT_SOURCE_REPEAT_THRESHOLD=0 \
        bash "$ROOT/scripts/insight_write.sh" "ledger consumer fixture entry" medium fixture
    [ "$status" -eq 0 ]
    before="$(sha256sum "$PUBROOT/queue/insights.yaml" | awk '{print $1}')"
    [ "$(find "$STATE/ledger_inbox/insights" -maxdepth 1 -type f -name '*.yaml' | wc -l)" -eq 1 ]

    run env SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$PUBROOT" \
        PUBLISHER_MODE=active PUBLISHER_ONCE=1 bash "$ROOT/scripts/publisher.sh" 2>&1
    [ "$status" -eq 0 ]
    after="$(sha256sum "$PUBROOT/queue/insights.yaml" | awk '{print $1}')"
    [ "$before" != "$after" ]
    grep -q 'ledger consumer fixture entry' "$PUBROOT/queue/insights.yaml"
    [ "$(find "$STATE/ledger_inbox/insights/applied" -maxdepth 1 -type f -name '*.yaml' | wc -l)" -eq 1 ]
    [ "$(find "$STATE/ledger_inbox/insights/rc" -maxdepth 1 -type f -name '*.yaml' 2>/dev/null | wc -l)" -eq 0 ]
    [ "$(git -C "$PUBROOT" status --porcelain -uno | wc -l)" -eq 0 ]
    [ "$(git -C "$PUBROOT" log -1 --format='%P' | wc -w)" -eq 1 ]
    git -C "$PUBROOT" log -1 --format='%B' | grep -q 'publisher: ledger batch n=1 ledgers=insights'
    git -C "$PUBROOT" log -1 --format='%B' | grep -q 'Published-By: publisher'
    [ "$(jq -r 'select(.kind=="ledger") | .kind' "$STATE/publish_queue/events.jsonl")" = ledger ]
    [ "$(stat -c '%a' "$ROOT/scripts/ledger_writer.sh")" = 755 ]
}

@test "mixed batch moves only the failed op to rc and leaves origin unchanged" {
    mkdir -p "$STATE/ledger_inbox/insights"
    entry='- id: INS-VALID\n  status: pending\n  insight: valid'
    hash="$(printf '%b\n' "$entry" | sha256sum | awk '{print $1}')"
    printf '%s\n' "{\"op\":\"append\",\"ledger\":\"insights\",\"id\":\"INS-VALID\",\"entry_hash\":\"$hash\",\"source_file\":\"$PUBROOT/queue/insights.yaml\",\"entry_text\":\"- id: INS-VALID\\n  status: pending\\n  insight: valid\\n\"}" > "$STATE/ledger_inbox/insights/20200101T000000000Z_000000000001.yaml"
    printf '%s\n' "{\"op\":\"append\",\"ledger\":\"insights\",\"id\":\"INS-BAD\",\"entry_hash\":\"bad\",\"source_file\":\"$PUBROOT/queue/insights.yaml\",\"entry_text\":\"- id: INS-BAD\\n  status: pending\\n\"}" > "$STATE/ledger_inbox/insights/20200101T000000000Z_000000000002.yaml"
    before="$(git --git-dir="$REMOTE" rev-parse refs/heads/main)"
    run env SHOGUN_STATE_DIR="$STATE" PUBLISHER_REPO_ROOT="$PUBROOT" \
        PUBLISHER_MODE=active PUBLISHER_ONCE=1 bash "$ROOT/scripts/publisher.sh" 2>&1
    [ "$status" -ne 0 ]
    [ "$(git --git-dir="$REMOTE" rev-parse refs/heads/main)" = "$before" ]
    [ "$(find "$STATE/ledger_inbox/insights/rc" -maxdepth 1 -type f -name '*000000000002.yaml' | wc -l)" -eq 1 ]
    [ "$(find "$STATE/ledger_inbox/insights/applied" -maxdepth 1 -type f -name '*000000000001.yaml' 2>/dev/null | wc -l)" -eq 0 ]
    [ "$(find "$STATE/ledger_inbox/insights" -maxdepth 1 -type f -name '*.yaml' | wc -l)" -ge 1 ]
    [ "$(jq -r 'select(.kind=="ledger") | .kind' "$STATE/publish_queue/events.jsonl" | wc -l)" -eq 1 ]
}
