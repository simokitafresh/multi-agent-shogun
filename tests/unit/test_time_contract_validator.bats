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

# test_necessity: 家老起票 task(hotfix)は speed_link 1 行と二値 AC を欠くと入口で BLOCK され、家老の判断に依らず我らの型が強制される(殿裁定 2026-08-29 01:25)。
@test "style: hotfix task は speed_link 欠落で BLOCK" {
    { printf '%s\n' "task:" "    task_type: hotfix" "    estimated_minutes: 10" "    acceptance_criteria:" "      - {id: AC1, description: guard の BLOCK 行が 0 件}"; } >"$TMP_YAML"
    run python3 "$VALIDATOR" "$TMP_YAML"
    [ "$status" -ne 0 ]; [[ "$output" == *"speed_link"* ]]
}
@test "style: 二値トークンの無い AC と報告のみ AC は BLOCK" {
    { printf '%s\n' "task:" "    task_type: hotfix" "    speed_link: fin_c の再走 2 分/件を切る" "    estimated_minutes: 10" "    acceptance_criteria:" "      - {id: AC1, description: 現状を一次再測定し差異を報告する}" "      - {id: AC2, description: 動作を改善する}"; } >"$TMP_YAML"
    run python3 "$VALIDATOR" "$TMP_YAML"
    [ "$status" -ne 0 ]; [[ "$output" == *"binary"* ]]; [[ "$output" == *"AC2"* ]]; [[ "$output" == *"reporting"* ]]; [[ "$output" == *"AC1"* ]]
}
@test "style: 型どおりの hotfix と自動 lane(exact/ci_fix) は PASS" {
    { printf '%s\n' "task:" "    task_type: hotfix" "    speed_link: deploy 1 件の未計測 18s を名指す" "    estimated_minutes: 10" "    acceptance_criteria:" "      - {id: AC1, description: TASK_MUTATION_PHASE 合計と wall の差が 1000ms 以下}"; } >"$TMP_YAML"
    run python3 "$VALIDATOR" "$TMP_YAML"; [ "$status" -eq 0 ]
    { printf '%s\n' "task:" "    task_type: exact" "    estimated_minutes: 10" "    acceptance_criteria:" "      - {id: AC1, description: insight を適用し bats FAIL0}"; } >"$TMP_YAML"
    run python3 "$VALIDATOR" "$TMP_YAML"; [ "$status" -eq 0 ]
}
