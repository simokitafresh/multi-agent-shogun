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

# test_necessity: leaseは同時に1所有者のみ保持でき(executable_owner_count<=1)、
# 他ownerによる同時取得は拒否される不変量を守る。
@test "a held lease rejects acquisition by a different owner" {
    run bash "$DS" begin "$STATE_ROOT" cmd subj att1 payloadhash1 artifactQ
    [ "$status" -eq 0 ]

    run bash "$DS" lease-acquire "$STATE_ROOT" cmd subj ownerA 30
    [ "$status" -eq 0 ]

    run bash "$DS" lease-acquire "$STATE_ROOT" cmd subj ownerB 30
    [ "$status" -ne 0 ]
}

# test_necessity: 単一reconcilerはpublishedを観測artifact_hashが一致する時だけ
# terminalへroll-forwardし、不一致はrolled_backへ収束させる不変量を守る。
@test "reconcile rolls forward on artifact match and rolls back on mismatch" {
    run bash "$DS" begin "$STATE_ROOT" cmd match_subj att1 payloadhash1 artifactABC
    [ "$status" -eq 0 ]
    fence="$(fence_of "$output")"
    run bash "$DS" mutate "$STATE_ROOT" cmd match_subj "$fence" prepared
    [ "$status" -eq 0 ]
    run bash "$DS" mutate "$STATE_ROOT" cmd match_subj "$fence" published
    [ "$status" -eq 0 ]

    run bash "$DS" reconcile "$STATE_ROOT" cmd match_subj owner1 artifactABC
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"phase\": \"terminal\""* ]]

    run bash "$DS" begin "$STATE_ROOT" cmd mismatch_subj att1 payloadhash1 artifactXYZ
    [ "$status" -eq 0 ]
    fence2="$(fence_of "$output")"
    run bash "$DS" mutate "$STATE_ROOT" cmd mismatch_subj "$fence2" prepared
    [ "$status" -eq 0 ]
    run bash "$DS" mutate "$STATE_ROOT" cmd mismatch_subj "$fence2" published
    [ "$status" -eq 0 ]

    run bash "$DS" reconcile "$STATE_ROOT" cmd mismatch_subj owner1 artifact_WRONG
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"phase\": \"rolled_back\""* ]]
}

# test_necessity: terminal receiptはgeneration・artifact hash・side-effect ledger・
# current fenceの全一致時だけ返り、欠落・不一致(rolled_back含む)時は偽terminalを
# 返さず必ずnullになる不変量を守る。
@test "terminal receipt never returns a false terminal on mismatch or non-terminal phase" {
    run bash "$DS" begin "$STATE_ROOT" cmd rb_subj att1 payloadhash1 artifactABC
    [ "$status" -eq 0 ]
    fence="$(fence_of "$output")"
    run bash "$DS" mutate "$STATE_ROOT" cmd rb_subj "$fence" prepared
    [ "$status" -eq 0 ]
    run bash "$DS" mutate "$STATE_ROOT" cmd rb_subj "$fence" published
    [ "$status" -eq 0 ]

    run bash "$DS" terminal-receipt "$STATE_ROOT" cmd rb_subj "$fence"
    [ "$status" -eq 0 ]
    [ "$output" = "null" ]

    run bash "$DS" reconcile "$STATE_ROOT" cmd rb_subj owner1 artifact_WRONG
    [ "$status" -eq 0 ]

    run bash "$DS" terminal-receipt "$STATE_ROOT" cmd rb_subj "$fence"
    [ "$status" -eq 0 ]
    [ "$output" = "null" ]
}

# test_necessity: 同一idempotency_keyでの外部副作用は、順次リトライでも並列リトライでも
# 実行回数がちょうど1回に収束する不変量を守る(二重applied 0件)。
@test "outbox apply collapses repeated retries of the same key to exactly one side effect" {
    side_log="$STATE_ROOT/side_effect.log"
    run bash "$DS" outbox-reserve "$STATE_ROOT" "dup-key" deliver targetX payloadhashY
    [ "$status" -eq 0 ]

    for _ in 1 2 3; do
        run bash "$DS" outbox-apply "$STATE_ROOT" "dup-key" "$side_log"
        [ "$status" -eq 0 ]
    done
    for _ in 1 2 3 4 5; do
        bash "$DS" outbox-apply "$STATE_ROOT" "dup-key" "$side_log" >/dev/null &
    done
    wait

    [ -f "$side_log" ]
    lines="$(wc -l < "$side_log")"
    [ "$lines" -eq 1 ]
}

# test_necessity: 未reserveのidempotency_keyへのoutbox applyは拒否される不変量を守る。
@test "outbox apply without a prior reservation is rejected" {
    run bash "$DS" outbox-apply "$STATE_ROOT" "never-reserved-key" "$STATE_ROOT/side.log"
    [ "$status" -ne 0 ]
}

# test_necessity: shadow comparatorは正常fixtureで一致し、checksum改ざんのように
# naiveは読めるがcanonicalだけがfail-closeするfixtureでは一致を報告せず、
# 安全側(diverge)に倒れる不変量を守る。
@test "shadow comparator matches valid fixtures and fails closed on tampered checksum" {
    run bash "$DS" begin "$STATE_ROOT" cmd shadow_ok att1 payloadhash1 ""
    [ "$status" -eq 0 ]
    run bash "$DS" shadow-compare "$STATE_ROOT" cmd shadow_ok
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"result\": \"match\""* ]]

    run bash "$DS" begin "$STATE_ROOT" cmd shadow_bad att1 payloadhash1 ""
    [ "$status" -eq 0 ]
    python3 -c "
import json
p = '$STATE_ROOT/active/cmd/shadow_bad/state.json'
d = json.load(open(p))
d['checksum'] = 'deadbeef' * 8
json.dump(d, open(p, 'w'))
"
    run bash "$DS" shadow-compare "$STATE_ROOT" cmd shadow_bad
    [ "$status" -ne 0 ]
    [[ "$output" == *"\"result\": \"diverge\""* ]]
    [[ "$output" == *"\"naive_error\": null"* ]]
}
