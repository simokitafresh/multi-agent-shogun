#!/usr/bin/env bats

# test_necessity: cmd_save/deploy_taskの10<estimated_minutes<=15契約を同一validatorへ固定し、入口間の判定乖離を防ぐ。

setup() {
    VALIDATOR="$BATS_TEST_DIRNAME/../../scripts/lib/time_contract_validator.py"
    TMP_YAML="$BATS_TEST_TMPDIR/time_contract.yaml"
}

write_entry() {
    local wrapper="$1"
    local split="$2"
    {
        printf '%b\n' "$wrapper"
        printf '%s\n' "    estimated_minutes: 15"
        printf '%s\n' "    acceptance_criteria:"
        printf '%s\n' "      - {id: AC1, description: boundary}"
        if [[ -n "$split" ]]; then
            printf '%s\n' "$split"
        fi
    } >"$TMP_YAML"
}

valid_split() {
    printf '%s\n' \
        "    split_decision:" \
        "      boundary_ac_ids: [AC1]" \
        "      integration_tasks: 1" \
        "      review_round_trips: 0"
}

@test "cmd_save形: split_decision欠落をBLOCKする" {
    write_entry "commands:\n  cmd_fixture:" ""

    run python3 "$VALIDATOR" --cmd-id cmd_fixture "$TMP_YAML"

    [ "$status" -eq 2 ]
    [[ "$output" == *"exactly boundary_ac_ids"* ]]
}

@test "deploy_task形: split_decision欠落をBLOCKする" {
    write_entry "task:" ""

    run python3 "$VALIDATOR" "$TMP_YAML"

    [ "$status" -eq 2 ]
    [[ "$output" == *"exactly boundary_ac_ids"* ]]
}

@test "cmd_save形: exact 3キーmappingをPASSする" {
    write_entry "commands:\n  cmd_fixture:" "$(valid_split)"

    run python3 "$VALIDATOR" --cmd-id cmd_fixture "$TMP_YAML"

    [ "$status" -eq 0 ]
    [[ "$output" == "PASS natural-boundary exception"* ]]
}

@test "deploy_task形: exact 3キーmappingをPASSする" {
    write_entry "task:" "$(valid_split)"

    run python3 "$VALIDATOR" "$TMP_YAML"

    [ "$status" -eq 0 ]
    [[ "$output" == "PASS natural-boundary exception"* ]]
}
