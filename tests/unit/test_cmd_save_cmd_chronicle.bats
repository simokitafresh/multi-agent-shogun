#!/usr/bin/env bats
# test_cmd_save_cmd_chronicle.bats — cmd_save.sh cmd-chronicle forced search

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^show_cmd_chronicle_matches()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f show_cmd_chronicle_matches
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_save_chronicle.XXXXXX")"
    export CMD_CHRONICLE_FILE="$TEST_TMPDIR/cmd-chronicle.md"
    export CMD_SAVE_CHRONICLE_MAX_LINES=1200
    export CMD_SAVE_CHRONICLE_MAX_BYTES=2097152
    export CMD_BLOCK="present"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "title/purpose search emits related completed cmd from chronicle" {
    cat > "$CMD_CHRONICLE_FILE" <<'MD'
# CMD年代記

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_2645 | lord_conversation.jsonlに殿の裁定が蓄積されているが、cmd起票時に自動検索されない | infra | 05-10 | cmd_save.shに殿発言検索INFOを追加 |
| cmd_2000 | unrelated database cleanup | dm-signal | 04-01 | unrelated |
MD
    export CMD_BLOCK_NC='    title: "強化 — cmd_save.sh 類似過去cmd検索"
    purpose: "cmd起票時にcmd-chronicle.mdを自動検索し、過去cmdの見落としを防ぐ"'

    run bash -c 'show_cmd_chronicle_matches 2>&1'

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: [CHRONICLE] cmd履歴検索: completed 2件から関連"* ]]
    [[ "$output" == *"cmd_2645"* ]]
    [[ "$output" == *"cmd起票時に自動検索されない"* ]]
}

@test "missing chronicle file still proves forced search happened" {
    rm -f "$CMD_CHRONICLE_FILE"
    export CMD_BLOCK_NC='    title: "強化 — 任意のcmd"
    purpose: "任意の目的"'

    run bash -c 'show_cmd_chronicle_matches 2>&1'

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: [CHRONICLE] cmd履歴検索: cmd-chronicle.md不在のため0件"* ]]
}

@test "chronicle search is limited to configured recent lines" {
    cat > "$CMD_CHRONICLE_FILE" <<'MD'
# CMD年代記

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_1000 | 古いcmd_save検索改善 | infra | 05-01 | 古い一致 |
| cmd_1001 | unrelated recent | infra | 05-02 | unrelated |
MD
    export CMD_BLOCK_NC='    title: "cmd_save検索改善"
    purpose: "cmd_save検索改善"'
    export CMD_SAVE_CHRONICLE_MAX_LINES=1

    run bash -c 'show_cmd_chronicle_matches 2>&1'

    [ "$status" -eq 0 ]
    [[ "$output" == *"completed 1件"* ]]
    [[ "$output" != *"cmd_1000"* ]]
}
