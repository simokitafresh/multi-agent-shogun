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

@test "direct deploy入口: PROJECT_DIR初期化前でも欠落をBLOCKする" {
    write_entry "task:" ""

    run bash -c '
        set -euo pipefail
        DEPLOY_TASK_LIB_ONLY=1 source "$1/scripts/deploy_task.sh"
        deploy_task_ten_min_contract_precheck "$2"
    ' _ "$BATS_TEST_DIRNAME/../.." "$TMP_YAML"

    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(TEN_MIN_CONTRACT)"* ]]
    [[ "$output" != *"PROJECT_DIR"* ]]
}

@test "direct deploy入口: PROJECT_DIR初期化前でも正規mappingをPASSする" {
    write_entry "task:" "$(valid_split)"

    run bash -c '
        set -euo pipefail
        DEPLOY_TASK_LIB_ONLY=1 source "$1/scripts/deploy_task.sh"
        deploy_task_ten_min_contract_precheck "$2"
    ' _ "$BATS_TEST_DIRNAME/../.." "$TMP_YAML"

    [ "$status" -eq 0 ]
    [[ "$output" == *"ten_min_contract: PASS natural-boundary exception"* ]]
    [[ "$output" != *"PROJECT_DIR"* ]]
}

# test_necessity: 観測窓(live後N時間の本番観測/証明)を long-runtime 例外の理由にした task は BLOCK され、忍者が 3600 秒級の機械的待ちに人質化されない(殿裁定 2026-08-29 00:49)。
@test "long-runtime例外: 観測窓を理由にするAC/理由はBLOCKされる" {
    {
        printf '%s\n' "task:"
        printf '%s\n' "    estimated_minutes: 60"
        printf '%s\n' "    acceptance_criteria:"
        printf '%s\n' "      - {id: AC1, description: live後1時間のgate_metricsでBLOCK行0を証明する}"
        printf '%s\n' "    execution_env:"
        printf '%s\n' "      long_runtime_reason: live1h証明を統合するため"
        printf '%s\n' "      measured_runtime_sec: 3600"
    } >"$TMP_YAML"
    run python3 "$VALIDATOR" "$TMP_YAML"
    [ "$status" -ne 0 ]
    [[ "$output" == *"observation window"* ]]
    [[ "$output" == *"AC1"* ]]
}

# test_necessity: 実装理由(観測窓でない)の long-runtime 例外は従来どおり PASS し、判定の反転が起きない。
@test "long-runtime例外: 実装理由はPASSのまま" {
    {
        printf '%s\n' "task:"
        printf '%s\n' "    estimated_minutes: 30"
        printf '%s\n' "    acceptance_criteria:"
        printf '%s\n' "      - {id: AC1, description: fixture 17本のbats契約を追加しFAIL0}"
        printf '%s\n' "    execution_env:"
        printf '%s\n' "      long_runtime_reason: compat fixture 17本のbats実行に25分かかるため"
        printf '%s\n' "      measured_runtime_sec: 1500"
    } >"$TMP_YAML"
    run python3 "$VALIDATOR" "$TMP_YAML"
    [ "$status" -eq 0 ]
    [[ "$output" == *"long-runtime exception"* ]]
}

# test_necessity: 次CI/次のrun/next CI run は忍者の将来観測を表すためBLOCKし、handoff・過去実績の同語彙は誤検出しない。
@test "long-runtime例外: 将来CI観測語彙3種はACでBLOCKされる" {
    {
        printf '%s\n' "task:"
        printf '%s\n' "    estimated_minutes: 30"
        printf '%s\n' "    acceptance_criteria:"
        printf '%s\n' "      - {id: AC1, description: 次CIでshard6 successを確認する}"
        printf '%s\n' "      - {id: AC2, description: 次の run でcompatibility successを確認する}"
        printf '%s\n' "      - {id: AC3, description: next CI run でshard successをverifyする}"
        printf '%s\n' "    execution_env:"
        printf '%s\n' "      long_runtime_reason: fixture実行に30分かかるため"
        printf '%s\n' "      measured_runtime_sec: 1800"
    } >"$TMP_YAML"
    run python3 "$VALIDATOR" "$TMP_YAML"
    [ "$status" -eq 2 ]
    [[ "$output" == *"hits=AC1, AC2, AC3"* ]]
}

# test_necessity: long_runtime_reason に将来CIの待機を隠して忍者を拘束する経路をBLOCKする。
@test "long-runtime例外: 将来CI観測語彙は理由でもBLOCKされる" {
    {
        printf '%s\n' "task:"
        printf '%s\n' "    estimated_minutes: 30"
        printf '%s\n' "    acceptance_criteria:"
        printf '%s\n' "      - {id: AC1, description: fixtureの互換性契約を検証する}"
        printf '%s\n' "    execution_env:"
        printf '%s\n' "      long_runtime_reason: next CI runの完走を待つため"
        printf '%s\n' "      measured_runtime_sec: 1800"
    } >"$TMP_YAML"
    run python3 "$VALIDATOR" "$TMP_YAML"
    [ "$status" -eq 2 ]
    [[ "$output" == *"hits=long_runtime_reason"* ]]
}

# test_necessity: 家老のpost_push_ci_proofへのhandoffは忍者の観測窓ではなく、将来語彙を含んでもPASSする。
@test "long-runtime例外: post_push_ci_proof handoffはPASSする" {
    {
        printf '%s\n' "task:"
        printf '%s\n' "    estimated_minutes: 30"
        printf '%s\n' "    acceptance_criteria:"
        printf '%s\n' "      - {id: AC1, description: 次CI success確認は家老post_push_ci_proofへのhandoffへ移管済み}"
        printf '%s\n' "    execution_env:"
        printf '%s\n' "      long_runtime_reason: fixture実行に30分かかるため"
        printf '%s\n' "      measured_runtime_sec: 1800"
    } >"$TMP_YAML"
    run python3 "$VALIDATOR" "$TMP_YAML"
    [ "$status" -eq 0 ]
    [[ "$output" == *"long-runtime exception"* ]]
}

# test_necessity: 完了済みCI runの実績記述は、同じ将来語彙を含んでも観測窓として扱わない。
@test "long-runtime例外: 過去CI実績文はPASSする" {
    {
        printf '%s\n' "task:"
        printf '%s\n' "    estimated_minutes: 30"
        printf '%s\n' "    acceptance_criteria:"
        printf '%s\n' "      - {id: AC1, description: \"過去CI実績: next CI run 33299727799 completed success cancelled=false\"}"
        printf '%s\n' "    execution_env:"
        printf '%s\n' "      long_runtime_reason: fixture実行に30分かかるため"
        printf '%s\n' "      measured_runtime_sec: 1800"
    } >"$TMP_YAML"
    run python3 "$VALIDATOR" "$TMP_YAML"
    [ "$status" -eq 0 ]
    [[ "$output" == *"long-runtime exception"* ]]
}

# test_necessity: 修正後などの説明に過去語が混ざっても、次CIの確認を要求するACはBLOCKする。
@test "long-runtime例外: 過去語を含む将来CI確認はBLOCKする" {
    {
        printf '%s\n' "task:"
        printf '%s\n' "    estimated_minutes: 30"
        printf '%s\n' "    acceptance_criteria:"
        printf '%s\n' "      - {id: AC1, description: 修正後の次CIでshard6 successを確認する}"
        printf '%s\n' "    execution_env:"
        printf '%s\n' "      long_runtime_reason: fixture実行に30分かかるため"
        printf '%s\n' "      measured_runtime_sec: 1800"
    } >"$TMP_YAML"
    run python3 "$VALIDATOR" "$TMP_YAML"
    [ "$status" -eq 2 ]
    [[ "$output" == *"hits=AC1"* ]]
}
