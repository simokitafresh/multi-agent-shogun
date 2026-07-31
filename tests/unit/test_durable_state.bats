#!/usr/bin/env bats
# cmd_4200 AC2 contract tests for scripts/lib/durable_state.sh / durable_state.py.
# All state lives under an isolated per-test root; production queue/log/WAL is
# never touched (isolation contract, cmd_4200 kagemaru AC2).

setup() {
    ROOT_DIR="${BATS_TEST_DIRNAME}/../.."
    DS="$ROOT_DIR/scripts/lib/durable_state.sh"
    STATE_ROOT="$(mktemp -d)"
}

teardown() {
    rm -rf "$STATE_ROOT"
}

fence_of() {
    python3 -c "import json,sys; print(json.loads(sys.argv[1])['fence_token'])" "$1"
}

# test_necessity: generationはWAL lock内CAS incrementのみで採番され、mutation直前に
# current fenceと一致しないmutationは成功0件で拒否される不変量を守る。
@test "stale fence mutation is rejected with zero successful applies" {
    run bash "$DS" begin "$STATE_ROOT" cmd subj att1 payloadhash1 ""
    [ "$status" -eq 0 ]
    old_fence="$(fence_of "$output")"

    run bash "$DS" begin "$STATE_ROOT" cmd subj att2 payloadhash2 ""
    [ "$status" -eq 0 ]
    new_fence="$(fence_of "$output")"
    [ "$new_fence" -eq $((old_fence + 1)) ]

    run bash "$DS" mutate "$STATE_ROOT" cmd subj "$old_fence" prepared
    [ "$status" -ne 0 ]

    run bash "$DS" read "$STATE_ROOT" cmd subj
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"phase\": \"intended\""* ]]
    [[ "$output" == *"\"fence_token\": $new_fence"* ]]
}

# test_necessity: intended->prepared->published->(terminal|rolled_back)以外の
# 遷移は全て拒否される不変量を守る。
@test "transitions outside the defined phase graph are rejected" {
    run bash "$DS" begin "$STATE_ROOT" cmd subj att1 payloadhash1 ""
    [ "$status" -eq 0 ]
    fence="$(fence_of "$output")"

    run bash "$DS" mutate "$STATE_ROOT" cmd subj "$fence" terminal CLEAR
    [ "$status" -ne 0 ]

    run bash "$DS" mutate "$STATE_ROOT" cmd subj "$fence" published
    [ "$status" -ne 0 ]
}

# test_necessity: terminalまたはrolled_backに達した世代への再実行(同一generation)は
# 拒否される不変量を守る。
@test "re-execution against an already-terminal generation is rejected" {
    run bash "$DS" begin "$STATE_ROOT" cmd subj att1 payloadhash1 ""
    [ "$status" -eq 0 ]
    fence="$(fence_of "$output")"

    run bash "$DS" mutate "$STATE_ROOT" cmd subj "$fence" prepared
    [ "$status" -eq 0 ]
    run bash "$DS" mutate "$STATE_ROOT" cmd subj "$fence" published
    [ "$status" -eq 0 ]
    run bash "$DS" mutate "$STATE_ROOT" cmd subj "$fence" terminal CLEAR
    [ "$status" -eq 0 ]

    run bash "$DS" mutate "$STATE_ROOT" cmd subj "$fence" prepared
    [ "$status" -ne 0 ]
}

# test_necessity: terminal_result="queued"は常に拒否される不変量を守る。
@test "queued terminal_result is always rejected" {
    run bash "$DS" begin "$STATE_ROOT" cmd subj att1 payloadhash1 ""
    [ "$status" -eq 0 ]
    fence="$(fence_of "$output")"
    run bash "$DS" mutate "$STATE_ROOT" cmd subj "$fence" prepared
    [ "$status" -eq 0 ]
    run bash "$DS" mutate "$STATE_ROOT" cmd subj "$fence" published
    [ "$status" -eq 0 ]

    run bash "$DS" mutate "$STATE_ROOT" cmd subj "$fence" terminal queued
    [ "$status" -ne 0 ]

    run bash "$DS" read "$STATE_ROOT" cmd subj
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"phase\": \"published\""* ]]
}
