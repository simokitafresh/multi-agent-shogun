#!/usr/bin/env bats
# test_cmd_save_lord_conversation.bats — cmd_save.sh lord_conversation forced search

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^show_lord_conversation_matches()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f show_lord_conversation_matches
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_save_lord_conv.XXXXXX")"
    export LORD_CONVERSATION_FILE="$TEST_TMPDIR/lord_conversation.jsonl"
    export CMD_BLOCK="present"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "title/purpose search emits related inbound lord utterance" {
    cat > "$LORD_CONVERSATION_FILE" <<'JSONL'
{"ts":"2026-05-10T01:01:26+09:00","source":"terminal","direction":"inbound","summary":"2623と2624が混乱している可能性があるな","detail":"2623と2624が混乱している可能性があるな","agent":"lord"}
{"ts":"2026-05-10T01:02:00+09:00","source":"terminal","direction":"outbound","summary":"cmd_2624を再起票する","detail":"cmd_2624を再起票する","agent":"shogun"}
{"ts":"2026-05-10T01:03:00+09:00","source":"terminal","direction":"inbound","summary":"全く別の話題","detail":"全く別の話題","agent":"lord"}
JSONL
    export CMD_BLOCK_NC='    title: "強化 — cmd_2624 混乱防止"
    purpose: "cmd_2623とcmd_2624の混乱を防ぐ"'

    run bash -c 'show_lord_conversation_matches 2>&1'

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: [LORD] 殿発言検索: inbound 2件から関連"* ]]
    [[ "$output" == *"2623と2624が混乱している可能性があるな"* ]]
    [[ "$output" != *"cmd_2624を再起票する"* ]]
}

@test "missing lord conversation file still proves forced search happened" {
    rm -f "$LORD_CONVERSATION_FILE"
    export CMD_BLOCK_NC='    title: "強化 — 任意のcmd"
    purpose: "任意の目的"'

    run bash -c 'show_lord_conversation_matches 2>&1'

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: [LORD] 殿発言検索: lord_conversation.jsonl不在のため0件"* ]]
}

