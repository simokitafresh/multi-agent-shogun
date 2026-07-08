#!/usr/bin/env bats
# test_cmd_save_q11_fp_reduction.bats — q11既存代替確認の偽陽性回帰

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^cmd_text_matches_pattern()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^trim_inline_yaml_scalar()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block_cache()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_has_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_get_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^is_gate_or_hook_addition_cmd()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^q11_has_existing_alternative_verification()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_assumption_source_files()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^extract_guard_list_from_files()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^q11_has_guard_duplicate_check()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_q11_guard_list()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_gate_hook_action_conversion()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_gate_hook_fp_measurement_connection()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f cmd_text_matches_pattern trim_inline_yaml_scalar load_cmd_block_cache cmd_block_has_field cmd_block_get_field \
        is_gate_or_hook_addition_cmd q11_has_existing_alternative_verification \
        collect_assumption_source_files extract_guard_list_from_files q11_has_guard_duplicate_check \
        collect_q11_guard_list check_gate_hook_action_conversion check_gate_hook_fp_measurement_connection
    record_warn_reason() {
        WARN_COUNT=$(( ${WARN_COUNT:-0} + 1 ))
        WARN_REASONS+=("$1|$2")
    }
    export -f record_warn_reason
}

@test "Q11-TP-004: 真のgate新設cmdでFP計測接続記載がなければWARNINGする" {
    CMD_BLOCK_NC='    title: "強化 — 新規gate追加"
    scope_mode: EXACT
    purpose: "cmd_save.shへ新規gateを追加して未記入を自動検出する"
    command: "scripts/cmd_save.shに新規gateを追加し、不備があれば遮断する"
    quality_gate:
      q11_not_already_done: "未達成。grep -rn missing_required_field scripts/cmd_save.sh → 0件。代替なし。新規gateとして実装する"'
    export CMD_BLOCK_NC
    WARN_COUNT=0
    WARN_REASONS=()

    run check_gate_hook_fp_measurement_connection "$CMD_BLOCK_NC"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FP計測への接続記載がありません"* ]]
}

@test "Q11-TP-005: 真のgate新設cmdでdetector_fp_rate接続記載があればWARNINGしない" {
    CMD_BLOCK_NC='    title: "強化 — 新規gate追加"
    scope_mode: EXACT
    purpose: "cmd_save.shへ新規gateを追加して未記入を自動検出する"
    command: "scripts/cmd_save.shに新規gateを追加し、不備があれば遮断する。発報結果はscripts/detector_fp_rate.shでFP率計測へ接続する"
    quality_gate:
      q11_not_already_done: "未達成。grep -rn missing_required_field scripts/cmd_save.sh → 0件。代替なし。新規gateとして実装する"'
    export CMD_BLOCK_NC
    WARN_COUNT=0
    WARN_REASONS=()

    run check_gate_hook_fp_measurement_connection "$CMD_BLOCK_NC"
    [ "$status" -eq 0 ]
    [[ "$output" != *"FP計測への接続記載がありません"* ]]
}

setup() {
    export CMD_BLOCK_NC=""
    export CMD_BLOCK_FOUND=1
    export CMD_BLOCK_CACHE_LOADED=0
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d)"
    export PROJECT_DIR="$TEST_TMPDIR"
    declare -gA CMD_BLOCK_CACHE=()
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "Q11-FP-001: SCOUT cmdはgate文言を含んでも追加cmd扱いしない" {
    CMD_BLOCK_NC='    title: "偵察 — gate挙動確認"
    scope_mode: SCOUT
    scout_exempt: true
    purpose: "既存gateの偽陽性を観測する。コード変更なし"
    command: |
      logsを確認して偽陽性パターンを分析する
      is_gate_or_hook_addition_cmd() にscope_mode=SCOUT除外追加案を検討する'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 1 ]
}

@test "Q11-FP-001b: task_type=analysisはgate文言を含んでも追加cmd扱いしない" {
    CMD_BLOCK_NC='    title: "分析 — gate/hook FP調査"
    task_type: analysis
    purpose: "既存gateの偽陽性を分析する。コード変更なし"
    command: |
      logsを確認してgate_hook_action_conversionの修正方針をまとめる'
    CMD_BLOCK_CACHE['task_type']='analysis'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 1 ]
}

@test "Q11-FP-002: 既存gate精度改善cmdは詳細手順に追加語があっても追加cmd扱いしない" {
    CMD_BLOCK_NC='    title: "強化 — cmd_save.sh gate偽陽性一括修正"
    scope_mode: IMPL
    purpose: "既存gateの偽陽性率を下げる精度改善"
    command: |
      logs/cmd_design_quality.yamlの直近50件でFPを分析し共通根を修正せよ
      is_gate_or_hook_addition_cmd()にscope_mode=SCOUT除外追加'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 1 ]
}

@test "Q11-FP-002b: gate調査cmdは追加/実装語を含む修正方針でも追加cmd扱いしない" {
    CMD_BLOCK_NC='    title: "調査 — gate行動変換の修正方針"
    scope_mode: EXACT
    purpose: "gate/hook追加cmdの偽陽性を調査し修正方針を整理する"
    command: |
      is_gate_or_hook_addition_cmd()への除外条件追加案をレビューする'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 1 ]
}

@test "Q11-FP-003: 真のgate新設cmdは従来通り追加cmd扱いする" {
    CMD_BLOCK_NC='    title: "強化 — 新規gate追加"
    scope_mode: IMPL
    purpose: "cmd_save.shへ新規gateを追加して未記入を自動検出する"
    command: |
      bash scripts/cmd_save.sh 9994'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 0 ]
}

@test "Q11-FP-004: grep根拠+偽陽性修正文言があれば既存代替確認済みとみなす" {
    run q11_has_existing_alternative_verification \
        "yes — grep 'FP率.*一括' context/cmd-chronicle.md→0件(2026-04-25確認) 既存gateの偽陽性修正(精度改善)であり初回"
    [ "$status" -eq 0 ]
}

@test "Q11-FP-005: 既存道具の接続cmdはgate追加語があっても追加cmd扱いしない" {
    CMD_BLOCK_NC='    title: "強化 — スキル成長ループ完結(PASS記録統一+注意ポイント適用+定期自走化)"
    scope_mode: EXACT
    purpose: "PASS記録を統一し、注意ポイントを適用し、定期自走化で永続的にループを回す"
    command: "gate_report_format.shのPASS分岐にskill_execution_log.sh呼出しを追加。ninja_monitor.shのメインループに週1でskill_auto_improve.sh --apply を実行する条件分岐を追加"
    quality_gate:
      q11_not_already_done: "未達成。既存代替の現物確認結果: grep -c skill_execution_log scripts/gates/gate_report_format.sh → 0件。grep -rn skill_auto_improve scripts/ → skill_auto_improve.sh自身のみ。既存道具の接続であり新規gate追加ではない。代替なし"'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 1 ]
}

@test "Q11-FP-006: gate_fire_log等のファイル名内gateは追加cmd扱いしない" {
    CMD_BLOCK_NC='    title: "強化 — セマンティクスインデックス更新"
    scope_mode: EXACT
    purpose: "セマンティクスインデックスを更新してgate_fire_log解析の参照先を追加する"
    command: "context/semantic-map.mdにgate_fire_log解析ドキュメントへの参照を追加する"
    quality_gate:
      q11_not_already_done: "未達成。rg gate_fire_log context/semantic-map.mdで既存参照なしを確認"'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 1 ]
}

@test "Q11-FP-007: gate_result/gate_clear等の変数名内gateは追加cmd扱いしない" {
    CMD_BLOCK_NC='    title: "強化 — 結果ログの用語索引更新"
    scope_mode: EXACT
    purpose: "gate_resultとgate_clearの用語説明をセマンティクスインデックスへ追加する"
    command: "context/semantic-map.mdにgate_result/gate_clearの説明を追加する"
    quality_gate:
      q11_not_already_done: "未達成。rg gate_result context/semantic-map.mdで既存参照なしを確認"'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 1 ]
}

@test "Q11-TP-001: q11根拠なしの真のgate新設cmdは追加cmd扱いを維持する" {
    CMD_BLOCK_NC='    title: "強化 — 新規gate追加"
    scope_mode: EXACT
    purpose: "cmd_save.shへ新規gateを追加して未記入を自動検出する"
    command: "scripts/cmd_save.shに新規gateを追加する"
    quality_gate:
      q11_not_already_done: "未記入"'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 0 ]
}

@test "Q11-TP-002: grepで未存在確認済みの真の新規gateは追加cmd扱いを維持する" {
    CMD_BLOCK_NC='    title: "強化 — 新規gate追加"
    scope_mode: EXACT
    purpose: "cmd_save.shへ新規gateを追加して未記入を自動検出する"
    command: "scripts/cmd_save.shに新規gateを追加する"
    quality_gate:
      q11_not_already_done: "未達成。grep -rn missing_required_field scripts/cmd_save.sh → 0件。代替なし。新規gateとして実装する"'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 0 ]
}

@test "Q11-TP-003: action conversion同義語の遮断はWARNINGを出さない" {
    CMD_BLOCK_NC='    title: "強化 — 新規gate追加"
    scope_mode: EXACT
    purpose: "cmd_save.shへ新規gateを追加して未記入を自動検出する"
    command: "scripts/cmd_save.shに新規gateを追加し、不備があれば遮断する"
    quality_gate:
      q11_not_already_done: "未達成。grep -rn missing_required_field scripts/cmd_save.sh → 0件。代替なし。新規gateとして実装する"'
    export CMD_BLOCK_NC
    WARN_COUNT=0
    WARN_REASONS=()

    run check_gate_hook_action_conversion "$CMD_BLOCK_NC"
    [ "$status" -eq 0 ]
    [[ "$output" != *"gate/hook追加cmdに行動変換キーワードがありません"* ]]
}

@test "Q11-FP-008: 既存gateへの条件追加は新規gate追加cmd扱いしない" {
    CMD_BLOCK_NC='    title: "強化 — cmd_save.sh q11既存gate修正"
    scope_mode: EXACT
    purpose: "既存gateの誤判定率を下げる"
    command: "scripts/cmd_save.shの既存gateに条件追加し、既存判定ロジックを修正する"
    quality_gate:
      q11_not_already_done: "未達成。rg -n is_gate_or_hook_addition_cmd scripts/cmd_save.sh → 既存gateあり。新規gateではなく既存チェックへの条件追加で精度改善する"'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 1 ]
}

@test "Q11-FP-009: SKILL.md追従cmdはstartup gate文言と追加語があっても追加cmd扱いしない" {
    CMD_BLOCK_NC='    title: "強化 — SKILL.md 4件script追従"
    scope_mode: EXACT
    purpose: "startup gateでSKILL.md参照WARNが3セッション連続。scriptが更新されたがSKILL.mdが追従していない4件を更新する"
    command: "SKILL.md 4件を現script仕様へ追従更新し、対象script参照の説明を追加する"
    quality_gate:
      q11_not_already_done: "未達成。rg -n gate_skill_script_refs scripts/gates/gate_shogun_startup.sh で既存gateによる検出を確認。新規gate追加ではない"'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 1 ]
}

@test "Q11-FP-010: semantic_search追従cmdはhook文言と追加語があっても追加cmd扱いしない" {
    CMD_BLOCK_NC='    title: "強化 — 起票前確認にsemantic_searchを追従"
    scope_mode: EXACT
    purpose: "将軍がcmd起票時にsemantic_search.shを使っていないため、既存hookの起票前確認を10問へ更新する"
    command: "Guard 0の起票前確認にsemantic_search確認行を追加し、hookの表示文言を更新する"
    quality_gate:
      q11_not_already_done: "未達成。rg -n semantic_search .claude/hooks/pre-write-edit-combined.sh で既存hook内の未接続を確認。新規hook追加ではない"'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 1 ]
}

@test "Q11-FP-011: DB拡張cmdはgate文言と追加語があっても追加cmd扱いしない" {
    CMD_BLOCK_NC='    title: "強化 — memory DB events拡張"
    scope_mode: EXACT
    purpose: "conversationsテーブルだけでなく全ロールeventを統合するためDBを拡張し、gate/report/inboxイベントを格納する"
    command: "memory_db_init.shへeventsテーブルを追加し、gateイベントの取り込み列を拡張する"
    quality_gate:
      q11_not_already_done: "未達成。rg -n events scripts/memory_db_init.sh → 0件。DB拡張であり新規gate追加ではない"'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 1 ]
}

@test "Q11-GUARD-001: assumptions sourceからGuard一覧を抽出する" {
    mkdir -p "$TEST_TMPDIR/.claude/hooks"
    cat > "$TEST_TMPDIR/.claude/hooks/pre-write-edit-combined.sh" <<'EOF'
# === Guard 0: shogun_to_karo.yaml起票前確認 ===
echo guard0
# === Guard 3: report-deny (Edit/Write to report YAML) ===
echo guard3
EOF
    CMD_BLOCK_NC='    title: "強化 — 新規hook追加"
    scope_mode: EXACT
    purpose: "pre-write hookへ新規Guardを追加する"
    command: "pre-write hookに新規Guardを追加する"
    quality_gate:
      q11_not_already_done: "未記入"
    assumptions:
      - claim: "pre-write hookを確認"
        source: ".claude/hooks/pre-write-edit-combined.sh code_reading"
        trust: "verified"'
    export CMD_BLOCK_NC

    run collect_q11_guard_list "$CMD_BLOCK_NC"
    [ "$status" -eq 0 ]
    [[ "$output" == *".claude/hooks/pre-write-edit-combined.sh:1 # === Guard 0"* ]]
    [[ "$output" == *".claude/hooks/pre-write-edit-combined.sh:3 # === Guard 3"* ]]
}

@test "Q11-GUARD-002: Guard一覧表示時はq11の重複確認が必須" {
    run q11_has_guard_duplicate_check "未達成。grep -n report .claude/hooks/pre-write-edit-combined.sh → 0件"
    [ "$status" -eq 1 ]

    run q11_has_guard_duplicate_check "未達成。Guard一覧を確認し、既存Guardとの重複なしを確認。差分理由あり"
    [ "$status" -eq 0 ]
}
