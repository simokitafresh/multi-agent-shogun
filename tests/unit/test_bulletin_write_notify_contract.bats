#!/usr/bin/env bats

# test_necessity: bulletin通知が宛先pane状態に依らず1回配送される不変量

setup() {
    TEST_ROOT="$(mktemp -d)"
    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/queue" "$TEST_ROOT/logs"
    cp "$BATS_TEST_DIRNAME/../../scripts/bulletin_write.sh" "$TEST_ROOT/scripts/bulletin_write.sh"
    cat > "$TEST_ROOT/scripts/inbox_write_fixture.sh" <<'SH'
#!/bin/bash
printf '%s\n' "$1|$3|$4|$5" >> "$BULLETIN_NOTIFY_CAPTURE"
SH
    chmod +x "$TEST_ROOT/scripts/inbox_write_fixture.sh"
    export BULLETIN_NOTIFY_CAPTURE="$TEST_ROOT/capture"
}

teardown() {
    rm -r -- "$TEST_ROOT"
}

@test "ninja-authored bulletins use trusted transport identity and each deliver once" {
    for fixture_id in $(seq 1 13); do
        run env \
            BULLETIN_NOTIFY=shogun \
            BULLETIN_INBOX_WRITE="$TEST_ROOT/scripts/inbox_write_fixture.sh" \
            BULLETIN_NOTIFY_FAILURE_LOG="$TEST_ROOT/logs/failures.yaml" \
            bash "$TEST_ROOT/scripts/bulletin_write.sh" saizo "contract probe $fixture_id" false info
        [ "$status" -eq 0 ]
    done

    [ "$(wc -l < "$BULLETIN_NOTIFY_CAPTURE")" -eq 13 ]
    [ "$(sort -u "$BULLETIN_NOTIFY_CAPTURE")" = "shogun|bulletin_notify|bulletin_write|bulletin_notify" ]
    [ ! -s "$TEST_ROOT/logs/failures.yaml" ]
}

# test_necessity: 数値を含むレビュー依頼は途中laneであり、最終計測報告の3点セットを要求しない。
@test "commander review request with numeric references is delivered without measurement evidence bundle" {
    run env \
        BULLETIN_NOTIFY=shogun \
        BULLETIN_INBOX_WRITE="$TEST_ROOT/scripts/inbox_write_fixture.sh" \
        BULLETIN_NOTIFY_FAILURE_LOG="$TEST_ROOT/logs/failures.yaml" \
        bash "$TEST_ROOT/scripts/bulletin_write.sh" karo \
        "関連: cmd_simple_review。将軍レビュー依頼。v3.9の実測7項目を検分されたし。" false info

    [ "$status" -eq 0 ]
    [ "$(wc -l < "$BULLETIN_NOTIFY_CAPTURE")" -eq 1 ]
}

# test_necessity: レビュー依頼でない数値結果報告には従来どおり3点セットを要求する。
@test "commander numeric result report still requires measurement evidence bundle" {
    run env \
        BULLETIN_NOTIFY=shogun \
        BULLETIN_INBOX_WRITE="$TEST_ROOT/scripts/inbox_write_fixture.sh" \
        BULLETIN_NOTIFY_FAILURE_LOG="$TEST_ROOT/logs/failures.yaml" \
        bash "$TEST_ROOT/scripts/bulletin_write.sh" karo \
        "関連: cmd_numeric_result。修正後5件PASS。" false info

    [ "$status" -ne 0 ]
    [[ "$output" == *"3点セットの欠落要素あり"* ]]
    [ ! -e "$BULLETIN_NOTIFY_CAPTURE" ]
}
