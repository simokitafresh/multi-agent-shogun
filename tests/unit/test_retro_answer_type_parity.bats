#!/usr/bin/env bats
# test_necessity: retro回答として扱うmessage type集合は送信側(inbox_write.sh)・判定側(retro_write.sh)・配備hold解除側(deploy_task.sh)の3箇所で完全一致していなければならず、1箇所だけの追加/削除は回答が機械判定に乗らない無音故障(holdが解けず次の配備がBLOCKされ続ける)を生む。

setup() {
    ROOT="$BATS_TEST_DIRNAME/../.."
}

sender_types() {
    sed -n '/^inbox_is_retro_answer_type() {/,/^}$/p' "$ROOT/scripts/inbox_write.sh" \
        | sed -n 's/^ *\(.*\)) return 0 ;;$/\1/p' | tr '|' '\n' | sed '/^$/d' | sort
}

judge_types() {
    sed -n '/message.get("type") not in {$/,/}:$/p' "$ROOT/scripts/retro_write.sh" \
        | grep -v 'message.get' | grep -oE '"[a-z_]+"' | tr -d '"' | sort
}

hold_release_types() {
    sed -n '/^deploy_task_retro_answer_type_allowed() {/,/^}$/p' "$ROOT/scripts/deploy_task.sh" \
        | grep -Eo 'infra_bug_suspected|infra_bug_report|infra_bug|retro_answer' \
        | sort -u
}

@test "sender judge and deploy hold release accept exactly the same retro answer types" {
    run bash -c "$(declare -f sender_types judge_types hold_release_types); ROOT='$ROOT'
        diff <(sender_types) <(judge_types) && diff <(sender_types) <(hold_release_types)"
    [ "$status" -eq 0 ]
}

@test "every site covers all four types ninjas actually used for retro answers" {
    for extractor in sender_types judge_types hold_release_types; do
        types="$(bash -c "$(declare -f sender_types judge_types hold_release_types); ROOT='$ROOT'; $extractor" | tr '\n' ' ')"
        for expected in infra_bug_suspected infra_bug_report infra_bug retro_answer; do
            [[ " $types " == *" $expected "* ]]
        done
    done
}

@test "no site silently narrows the set back to a single type" {
    for extractor in sender_types judge_types hold_release_types; do
        count="$(bash -c "$(declare -f sender_types judge_types hold_release_types); ROOT='$ROOT'; $extractor" | wc -l)"
        [ "$count" -eq 4 ]
    done
}
