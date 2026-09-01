#!/usr/bin/env bats
# test_necessity: 同一inboxの全mutation callerが1 lock identityへ収束し、append/mark-read競合でもlost update 0を守る。

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export FIXTURE_ROOT
    FIXTURE_ROOT="$(mktemp -d "$PROJECT_ROOT/.tmp_lock_path_test.XXXXXX")"

    mkdir -p "$FIXTURE_ROOT/scripts/lib" "$FIXTURE_ROOT/queue/inbox"
    cp "$PROJECT_ROOT/scripts/inbox_write.sh" "$FIXTURE_ROOT/scripts/inbox_write.sh"
    cp "$PROJECT_ROOT/scripts/inbox_read.sh" "$FIXTURE_ROOT/scripts/inbox_read.sh"
    cp "$PROJECT_ROOT/scripts/inbox_mark_read.sh" "$FIXTURE_ROOT/scripts/inbox_mark_read.sh"
    cp "$PROJECT_ROOT/scripts/lib/lock_path.sh" "$FIXTURE_ROOT/scripts/lib/lock_path.sh"
    cp "$PROJECT_ROOT/scripts/lib/report_completion_events.sh" "$FIXTURE_ROOT/scripts/lib/report_completion_events.sh"
    cp "$PROJECT_ROOT/scripts/lib/escalation_evidence.sh" "$FIXTURE_ROOT/scripts/lib/escalation_evidence.sh"
}

teardown() {
    find "$FIXTURE_ROOT" -depth -delete
}

mark_read_with_receipt() {
    local agent="$1"
    shift
    local attempt
    for attempt in {1..20}; do
        SHOGUN_ROOT="$FIXTURE_ROOT" \
            INBOX_READ_RECEIPT_DIR="$FIXTURE_ROOT/logs/inbox_read_receipts" \
            bash "$FIXTURE_ROOT/scripts/inbox_read.sh" "$agent" >/dev/null
        if INBOX_MARK_READ_ROOT_OVERRIDE="$FIXTURE_ROOT" \
            INBOX_MARK_READ_RECEIPT_DIR="$FIXTURE_ROOT/logs/inbox_read_receipts" \
            bash "$FIXTURE_ROOT/scripts/inbox_mark_read.sh" "$agent" "$@" >/dev/null; then
            return 0
        fi
    done
    return 1
}

@test "parallel append and mark-read preserve every message across repeated adversarial rounds" {
    local rounds=10 per_round=8 round i inbox metrics
    local submitted=0 saved=0 mark_targets=0 marked=0 lost_update=0 duplicate=0 parse_error=0

    for ((round=1; round<=rounds; round++)); do
        inbox="$FIXTURE_ROOT/queue/inbox/tobisaru.yaml"
        printf 'messages: []\n' > "$inbox"

        local old_ids=()
        for ((i=1; i<=per_round; i++)); do
            old_ids+=("msg_old_${round}_${i}")
            INBOX_WRITE_TEST=1 INBOX_MESSAGE_ID="msg_old_${round}_${i}" \
                bash "$FIXTURE_ROOT/scripts/inbox_write.sh" tobisaru \
                "old-${round}-${i}" wake_up fixture >/dev/null
        done

        mark_read_with_receipt tobisaru "${old_ids[@]}" &
        local mark_pid=$!
        local writer_pids=()
        for ((i=1; i<=per_round; i++)); do
            INBOX_WRITE_TEST=1 INBOX_MESSAGE_ID="msg_new_${round}_${i}" \
                bash "$FIXTURE_ROOT/scripts/inbox_write.sh" tobisaru \
                "new-${round}-${i}" wake_up fixture >/dev/null &
            writer_pids+=("$!")
        done
        wait "$mark_pid"
        for i in "${writer_pids[@]}"; do wait "$i"; done

        metrics="$(python3 - "$inbox" "$per_round" <<'PY'
import collections, sys, yaml
path, per_round = sys.argv[1], int(sys.argv[2])
try:
    data = yaml.safe_load(open(path, encoding="utf-8")) or {}
except Exception:
    print("0 0 0 0 1")
    raise SystemExit(0)
messages = data.get("messages", [])
ids = [str(m.get("id", "")) for m in messages if isinstance(m, dict)]
old = [m for m in messages if isinstance(m, dict) and str(m.get("id", "")).startswith("msg_old_")]
new = [m for m in messages if isinstance(m, dict) and str(m.get("id", "")).startswith("msg_new_")]
dups = sum(count - 1 for count in collections.Counter(ids).values() if count > 1)
marked = sum(m.get("read") is True for m in old)
lost = (per_round - len(old)) + (per_round - len(new))
print(len(messages), marked, lost, dups, 0)
PY
)"
        read -r round_saved round_marked round_lost round_duplicate round_parse <<< "$metrics"
        submitted=$((submitted + per_round * 2))
        saved=$((saved + round_saved))
        mark_targets=$((mark_targets + per_round))
        marked=$((marked + round_marked))
        lost_update=$((lost_update + round_lost))
        duplicate=$((duplicate + round_duplicate))
        parse_error=$((parse_error + round_parse))
    done

    echo "rounds=$rounds submitted=$submitted saved=$saved mark_targets=$mark_targets marked=$marked lost_update=$lost_update duplicate=$duplicate parse_error=$parse_error"
    [ "$saved" -eq "$submitted" ]
    [ "$marked" -eq "$mark_targets" ]
    [ "$lost_update" -eq 0 ]
    [ "$duplicate" -eq 0 ]
    [ "$parse_error" -eq 0 ]
}
