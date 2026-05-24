#!/usr/bin/env bats
# test_cmd_save.bats — cmd_save.sh ユニットテスト（Check 6: GP重複チェック中心）
# Optimized: フル実行→関数直接呼び出し方式（python3/tmux/git呼び出し回避）

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    # 消火キーワードパターンをロード (Check 3 q9で使用)
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/scripts/lib/firefighting_keywords.sh"
    export FIREFIGHTING_PATTERN

    # 各チェック関数をsed -nで抽出+eval (setup_fileで1回のみ実行)

    # check_impl_push_ac: Check 11 — 既存関数をそのまま抽出
    eval "$(sed -n '/^check_impl_push_ac()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f check_impl_push_ac

    # check_ac_must_should_mix: Check 11.3 — AC推奨/必須混在検出
    eval "$(sed -n '/^check_ac_must_should_mix()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f check_ac_must_should_mix

    # check_gp_duplicate: Check 6インラインセクションを関数化
    eval "check_gp_duplicate() {
$(sed -n '/^# --- Check 6:/,/^# --- Check 7:/{/^# --- Check 7:/d;p}' "$SRC_SAVE_SCRIPT")
}"
    export -f check_gp_duplicate

    # check_3_7_checklist: Check 3.7インラインセクションを関数化
    eval "check_3_7_checklist() {
$(sed -n '/# --- Check 3.7:/,/^    fi/{p;/^    fi/q}' "$SRC_SAVE_SCRIPT")
}"
    export -f check_3_7_checklist

    # check_q4_depth: q4_depthインラインセクションを関数化
    eval "check_q4_depth() {
$(sed -n '/^[[:space:]]*# q4_depth:/,/^[[:space:]]*# q5_verified_source:/{/^[[:space:]]*# q5_verified_source:/d;p}' "$SRC_SAVE_SCRIPT")
}"
    export -f check_q4_depth

    # check_quality_gate が依存する helper 群
    eval "$(sed -n '/^trim_inline_yaml_scalar()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^path_exists_for_cmd_source()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^parent_exists_for_cmd_source()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^display_parent_for_cmd_source()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block_cache()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_has_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_get_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_primary_cmd_targets()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^is_gate_or_hook_addition_cmd()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^q11_has_existing_alternative_verification()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_assumption_source_files()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^extract_guard_list_from_files()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^q11_has_guard_duplicate_check()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_q11_guard_list()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_gate_hook_action_conversion()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_lord_instruction_ac_alignment_info()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_assumption_claims_missing_dates()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_negative_claims_missing_grep_evidence()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_bulletin_count_claims_missing_grep_evidence()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_measurement_env_info()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_lord_30min_cost_question()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_deferral_language_warn()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^extract_acceptance_criteria_block()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_action_immediate_verification()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^extract_command_text_block()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_numeric_derivation_source_evidence()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^numeric_derivation_source_evidence_exists()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_numeric_literal_derivation_source_info()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_self_reread_red_flag()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_bundle_red_flag()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_cmd_text_pipe_danger()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^is_db_operation_command_text()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_db_backup_ac_warn()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^build_warn_note()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_key()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_message()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^record_warn_reason()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^record_block_reason()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_save_caller_check_name()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^abort_if_block_immediate()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f trim_inline_yaml_scalar path_exists_for_cmd_source parent_exists_for_cmd_source display_parent_for_cmd_source load_cmd_block load_cmd_block_cache cmd_block_has_field cmd_block_get_field collect_primary_cmd_targets is_gate_or_hook_addition_cmd q11_has_existing_alternative_verification collect_assumption_source_files extract_guard_list_from_files q11_has_guard_duplicate_check collect_q11_guard_list check_gate_hook_action_conversion check_lord_instruction_ac_alignment_info collect_assumption_claims_missing_dates collect_negative_claims_missing_grep_evidence collect_bulletin_count_claims_missing_grep_evidence check_measurement_env_info check_lord_30min_cost_question check_deferral_language_warn extract_acceptance_criteria_block check_action_immediate_verification extract_command_text_block collect_numeric_derivation_source_evidence numeric_derivation_source_evidence_exists check_numeric_literal_derivation_source_info check_self_reread_red_flag check_bundle_red_flag check_cmd_text_pipe_danger is_db_operation_command_text check_db_backup_ac_warn build_warn_note warn_note_key warn_note_message record_warn_reason record_block_reason cmd_save_caller_check_name abort_if_block_immediate

    # This unit suite validates local check output, not historical WARN analytics.
    # Avoid spawning Python for every record_warn_reason() call.
    count_same_warn_pattern() { echo 0; }
    export -f count_same_warn_pattern

    # テストハーネスではQUEUE_FILEが単純なので、CMD_BLOCK読込のみpure bash化してI/O起動コストを削る
    load_cmd_block() {
        if [[ "$CMD_BLOCK_LOADED" -eq 1 ]]; then
            [[ "$CMD_BLOCK_FOUND" -eq 1 ]]
            return $?
        fi

        _setup_cmd_block "$CMD_ID"
        [[ "$CMD_BLOCK_FOUND" -eq 1 ]]
    }
    export -f load_cmd_block

    # check_quality_gate: Check 3インラインセクション(質問ゲートブロック)を関数化 + 成功時OK出力
    local _qg_start _qg_end
    _qg_start=$(grep -n '# --- Check 3: quality_gate' "$SRC_SAVE_SCRIPT" | head -1 | cut -d: -f1)
    _qg_end=$(grep -n '# --- Check 4:' "$SRC_SAVE_SCRIPT" | head -1 | cut -d: -f1)
    _qg_end=$((_qg_end - 1))
    eval "check_quality_gate() {
local WARN_COUNT=0
$(sed -n "${_qg_start},${_qg_end}p" "$SRC_SAVE_SCRIPT")
if [[ \"\${BLOCK_COUNT:-0}\" -gt 0 ]]; then
    return 1
fi
echo \"保存確認OK: \${CMD_ID}\"
}"
    export -f check_quality_gate

    # check_20_assumptions: Check 20インラインセクション（assumptions検査）を関数化
    eval "check_20_assumptions() {
local WARN_COUNT=0
$(sed -n '/^# --- Check 20:/,/^# --- Check 21:/{/^# --- Check 21:/d;p}' "$SRC_SAVE_SCRIPT")
if [[ \"\${BLOCK_COUNT:-0}\" -gt 0 ]]; then
    return 1
fi
echo \"OK\"
}"
    export -f check_20_assumptions

    # 共有テンポラリディレクトリ(setup_fileで1回のみ作成)
    export TEST_SHARED_TMP
    TEST_SHARED_TMP="$(mktemp -d)"
    mkdir -p "${TEST_SHARED_TMP}/queue/archive/cmds" "${TEST_SHARED_TMP}/docs/research"
    cat > "${TEST_SHARED_TMP}/docs/research/cmd_save_test_deploy_task.md" <<'DOC'
scripts/deploy_task.sh
deploy_task.sh
DOC
    printf 'entries:\n' > "${TEST_SHARED_TMP}/cmd_design_quality.yaml"
    printf 'lessons:\n' > "${TEST_SHARED_TMP}/lessons_shogun.yaml"
    export QUEUE_FILE="${TEST_SHARED_TMP}/queue/shogun_to_karo.yaml"
    export PROJECT_DIR="$TEST_SHARED_TMP"
    export QUALITY_LOG_FILE="${TEST_SHARED_TMP}/cmd_design_quality.yaml"
    export CMD_SAVE_SHOGUN_LESSONS_FILE="${TEST_SHARED_TMP}/lessons_shogun.yaml"
}

teardown_file() {
    rm -rf "$TEST_SHARED_TMP"
}

setup() {
    # 共有tmpdirを再利用 — per-testのmktemp/mkdirオーバーヘッドを排除
    export CMD_ID="cmd_test"
    export CMD_BLOCK=""
    export CMD_BLOCK_NC=""
    export CMD_BLOCK_LOADED=0
    export CMD_BLOCK_FOUND=0
    export CMD_BLOCK_CACHE_LOADED=0
    export CMD_SAVE_ACCUMULATE_BLOCKS=0
    export BLOCK_COUNT=0
    export QUALITY_LOG_FILE="${TEST_SHARED_TMP}/cmd_design_quality.yaml"
    export CMD_SAVE_SHOGUN_LESSONS_FILE="${TEST_SHARED_TMP}/lessons_shogun.yaml"
    declare -ga BLOCK_REASONS=()
    declare -ga WARN_REASONS=()
    declare -gA CMD_BLOCK_CACHE=()
    # --jobs 8並列実行時の競合を回避するためQUEUE_FILEをテストごとに一意化
    export QUEUE_FILE="${TEST_SHARED_TMP}/queue/shogun_to_karo_${BATS_TEST_NUMBER}.yaml"
}

teardown() { true; }

# --- ヘルパー: QUEUE_FILE書き込み ---
create_queue_file() {
    cat > "$QUEUE_FILE"
}

# --- ヘルパー: CMD_BLOCK/CMD_BLOCK_NCをQUEUE_FILEから設定 ---
_setup_cmd_block() {
    local cid="${1:-$CMD_ID}"
    local line found=0
    CMD_BLOCK_LOADED=1
    CMD_BLOCK_FOUND=0
    CMD_BLOCK_CACHE_LOADED=0
    declare -gA CMD_BLOCK_CACHE=()

    CMD_BLOCK=""
    CMD_BLOCK_NC=""
    while IFS= read -r line; do
        if (( found == 0 )); then
            [[ "$line" == "  ${cid}:" ]] && found=1
            continue
        fi

        [[ "$line" =~ ^\ \ cmd_[0-9]+: ]] && break
        CMD_BLOCK+="${line}"$'\n'
        [[ "$line" =~ ^[[:space:]]*# ]] || CMD_BLOCK_NC+="${line}"$'\n'
    done < "$QUEUE_FILE"

    CMD_BLOCK="${CMD_BLOCK%$'\n'}"
    CMD_BLOCK_NC="${CMD_BLOCK_NC%$'\n'}"
    [[ -n "$CMD_BLOCK" ]] && CMD_BLOCK_FOUND=1
    export CMD_BLOCK CMD_BLOCK_NC
}

@test "q12_lord_30min_cost missing emits binary cost warning" {
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_CACHE_LOADED=0
    CMD_BLOCK_NC='    quality_gate:
      q1_firefighting: "no — test"
      q2_learning: "奪わない — test"
      q3_next_quality: "上がる — test"'
    export CMD_BLOCK_FOUND CMD_BLOCK_CACHE_LOADED CMD_BLOCK_NC

    run bash -c 'declare -gA CMD_BLOCK_CACHE=(); check_lord_30min_cost_question 2>&1'

    [ "$status" -eq 0 ]
    [[ "$output" == *"q12_lord_30min_cost未記入"* ]]
    [[ "$output" == *"この判断は殿に30分コストを課すか"* ]]
}

@test "q12_lord_30min_cost non-binary emits warning" {
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_CACHE_LOADED=0
    CMD_BLOCK_NC='    quality_gate:
      q12_lord_30min_cost: "確認する"'
    export CMD_BLOCK_FOUND CMD_BLOCK_CACHE_LOADED CMD_BLOCK_NC

    run bash -c 'declare -gA CMD_BLOCK_CACHE=(); check_lord_30min_cost_question 2>&1'

    [ "$status" -eq 0 ]
    [[ "$output" == *"q12_lord_30min_costが二値でない"* ]]
}

@test "deferral language emits warn with hit lines" {
    CMD_BLOCK_NC='    title: "改善cmd"
    command: "非致命的なので後で対応する"'
    export CMD_BLOCK_NC

    run bash -c 'check_deferral_language_warn "$CMD_BLOCK_NC" 2>&1'

    [ "$status" -eq 0 ]
    [[ "$output" == *"先送り表現を検出"* ]]
    [[ "$output" == *"非致命的なので後で対応する"* ]]
}

# --- Check 6: GP重複検出 ---

@test "Check6: GP番号一致でWARN出力" {
    create_queue_file << 'YAML'
commands:
  cmd_1001:
    command: "GP-031対応の修正"
    status: delegated
  cmd_1002:
    command: "GP-031+GP-033統合修正"
    status: pending
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_1002"; export CMD_ID
    run check_gp_duplicate
    echo "$output" >&2
    # GP-031がcmd_1001(delegated)と重複 → WARN
    [[ "$output" == *"GP-031"* ]]
    [[ "$output" == *"cmd_1001"* ]]
}

@test "Check10.5: command/purpose内のpipe文字でWARN出力" {
    create_queue_file << 'YAML'
commands:
  cmd_pipe:
    title: "infra — pipe warning"
    purpose: "deploy_task.shで alpha | beta を保持する"
    command: |
      scripts/deploy_task.sh --direct saizo cmd_pipe || echo failed
    status: pending
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_pipe"; export CMD_ID
    load_cmd_block
    run check_cmd_text_pipe_danger
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: cmdテキスト内にパイプ文字"* ]]
}

@test "Check21.2: DB操作cmdならバックアップAC WARNを出力" {
    create_queue_file << 'YAML'
commands:
  cmd_test:
    command: |
      backend migrationを追加し、ALTER TABLE users ADD COLUMN role TEXTを実行する
    acceptance_criteria:
      - "AC1: migrationが適用される"
YAML

    load_cmd_block
    run check_db_backup_ac_warn
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: DB操作cmdを検出"* ]]
    [[ "$output" == *"変更前バックアップ実行済みであること"* ]]
}

@test "AC1: 引用記号なしのWHYでもq8_WHY引用WARNを出さない" {
    local q8_tmpdir q8_queue q8_archive q8_quality q8_lock q8_last q8_lessons q8_autolearn q8_lord q8_chronicle
    q8_tmpdir="$(mktemp -d "$BATS_TMPDIR/cmd_save_q8relax.XXXXXX")"
    q8_queue="$q8_tmpdir/shogun_to_karo.yaml"
    q8_archive="$q8_tmpdir/archive"
    q8_quality="$q8_tmpdir/cmd_design_quality.yaml"
    q8_lock="$q8_tmpdir/shogun_to_karo.lock"
    q8_last="$q8_tmpdir/cmd_save_last_cmd.txt"
    q8_lessons="$q8_tmpdir/lessons_shogun.yaml"
    q8_autolearn="$q8_tmpdir/preflight_autolearn.txt"
    q8_lord="$q8_tmpdir/lord_conversation.jsonl"
    q8_chronicle="$q8_tmpdir/cmd-chronicle.md"
    mkdir -p "$q8_archive"

    cat > "$q8_queue" <<'YAML'
commands:
  cmd_q8relax:
    id: cmd_q8relax
    title: "infra — q8 WHY検出緩和テスト"
    purpose: "WHYが明示されていれば引用記号なしでも不要WARNを出さない"
    project: infra
    depends_on: none
    task_type: impl
    origin: "[[test_q8_relax]] -> [[WHY引用偽陽性]] -> [[回帰テスト]]"
    command: "q8_why_what の回帰確認"
    acceptance_criteria:
      - "AC1: q8 WHY引用WARNが出ない"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "WHY文面の語彙差で偽陽性を出さない"
      q3_next_quality: "q8の意図確認が引用記号依存にならない"
      q4_depth: "shallow"
      q5_verified_source: "code_reading + isolated_test"
      q6_not_hiding: "no — q8の偽陽性除去であり問題の隠蔽ではない"
      q7_definition_verified: "yes — q8はWHY/WHATの明示だけを要件とする"
      q8_why_what: "WHY: 学習ループを強化する必要がある → WHAT: q8の引用依存を外す → WHEN: 引用記号なしWHYの回帰を検証する時 → WHERE: tests/unit/test_cmd_save.bats → WHO: 将軍cmd保存ゲートを使う将軍 → HOW: q8 WHY引用WARNを出さず保存確認OKまで通す。複利: 正の複利"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。q8 WHY引用WARNが残っていないことを未確認"
      q_ambiguity: "none"
    assumptions:
      - claim: "2026-04-24時点で q8 WHY引用チェックの有無は cmd_save.sh の出力で判定できる"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    run env \
        CMD_SAVE_QUEUE_FILE="$q8_queue" \
        CMD_SAVE_ARCHIVE_CMD_DIR="$q8_archive" \
        CMD_QUALITY_LOG_FILE="$q8_quality" \
        CMD_SAVE_LOCK_FILE="$q8_lock" \
        CMD_SAVE_LAST_CMD_FILE="$q8_last" \
        CMD_SAVE_SHOGUN_LESSONS_FILE="$q8_lessons" \
        CMD_SAVE_PREFLIGHT_AUTOLEARN_FILE="$q8_autolearn" \
        CMD_SAVE_LORD_CONVERSATION_FILE="$q8_lord" \
        CMD_SAVE_CMD_CHRONICLE_FILE="$q8_chronicle" \
        bash "$SRC_SAVE_SCRIPT" cmd_q8relax

    rm -rf "$q8_tmpdir"

    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK"* ]]
    [[ "$output" != *"q8 WHYに殿の指示引用がありません"* ]]
    [[ "$output" != *"q8_WHY引用"* ]]
}

@test "Check21.2: 非DB cmdならバックアップAC WARNなし" {
    create_queue_file << 'YAML'
commands:
  cmd_test:
    command: |
      dashboard.mdの表示文言を更新する
    acceptance_criteria:
      - "AC1: 表示文言が更新される"
YAML

    load_cmd_block
    run check_db_backup_ac_warn
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "Check6: GP番号なしcmdはスキップ" {
    create_queue_file << 'YAML'
commands:
  cmd_1001:
    command: "GP-031対応の修正"
    status: delegated
  cmd_1010:
    command: "inbox_write.shのリファクタリング"
    status: pending
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_1010"; export CMD_ID
    run check_gp_duplicate
    echo "$output" >&2
    # GP番号なし → Check 6スキップ → WARNなし
    [ "$status" -eq 0 ]
    [[ "$output" != *"GP-"* ]]
}

@test "Check6: status=completedのcmdは無視" {
    create_queue_file << 'YAML'
commands:
  cmd_1001:
    command: "GP-031対応の修正"
    status: completed
  cmd_1002:
    command: "GP-031の追加修正"
    status: pending
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_1002"; export CMD_ID
    run check_gp_duplicate
    echo "$output" >&2
    # cmd_1001はcompleted → GP重複WARNなし
    [ "$status" -eq 0 ]
    [[ "$output" != *"GP-031"*"cmd_1001"* ]]
}

@test "Check6: status=in_progressのcmdで検出" {
    create_queue_file << 'YAML'
commands:
  cmd_1001:
    command: "GP-042対応"
    status: in_progress
  cmd_1002:
    command: "GP-042の再実装"
    status: pending
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_1002"; export CMD_ID
    run check_gp_duplicate
    echo "$output" >&2
    [[ "$output" == *"GP-042"* ]]
    [[ "$output" == *"cmd_1001"* ]]
    [[ "$output" == *"in_progress"* ]]
}

@test "Check6: 複数GP番号で部分一致検出" {
    create_queue_file << 'YAML'
commands:
  cmd_1001:
    command: "GP-031修正"
    status: delegated
  cmd_1002:
    command: "GP-031+GP-033+GP-034統合"
    status: pending
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_1002"; export CMD_ID
    run check_gp_duplicate
    echo "$output" >&2
    # GP-031のみ重複、GP-033/034は重複なし
    [[ "$output" == *"GP-031"* ]]
    [[ "$output" != *"GP-033"*"cmd_1001"* ]]
}

@test "Check6: 非BLOCKのため保存確認OKで終了" {
    create_queue_file << 'YAML'
commands:
  cmd_1001:
    command: "GP-031対応"
    status: delegated
  cmd_1002:
    command: "GP-031の再実装"
    status: pending
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_1002"; export CMD_ID
    run check_gp_duplicate
    echo "$output" >&2
    # GP重複WARNは出るが、非BLOCKなので終了コード0
    [ "$status" -eq 0 ]
}

# --- Check 3.7: チェックリスト参照cmdのWARNING ---

@test "Check3.7: チェックリスト参照cmdでWARNING出力" {
    CMD_BLOCK_NC="チェックリストStep6実行 — 本番DB登録"
    export CMD_BLOCK_NC
    run check_3_7_checklist
    echo "$output" >&2
    [[ "$output" == *"チェックリスト参照cmd"* ]]
    [[ "$output" == *"隣接Step"* ]]
    # WARNINGだが非BLOCKなので終了コード0
    [ "$status" -eq 0 ]
}

@test "Check3.7: チェックリスト参照なしcmdはWARNなし" {
    CMD_BLOCK_NC="inbox_write.shのリファクタリング"
    export CMD_BLOCK_NC
    run check_3_7_checklist
    echo "$output" >&2
    [[ "$output" != *"チェックリスト参照cmd"* ]]
    [ "$status" -eq 0 ]
}

# --- Check1-5: quality_gate ---

@test "Check1-5: 既存チェックに影響なし（正常系）" {
    create_queue_file << 'YAML'
commands:
  cmd_9999:
    id: cmd_9999
    command: "テスト用cmdブロック"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
      q8_why_what: "WHY: テスト用 → WHAT: テストcmd 1件作成"
      q11_not_already_done: "未達成。grep 'q11_not_already_done' scripts/cmd_save.sh で未実装を確認"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_9999"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK: cmd_9999"* ]]
}

@test "Check1-5: q11_not_already_done未記入で必須項目BLOCK" {
    create_queue_file << 'YAML'
commands:
  cmd_9998:
    id: cmd_9998
    command: "q11未記入のテスト"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
      q8_why_what: "WHY: テスト用 → WHAT: テストcmd 1件作成"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_9998"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: 必須項目 1件 未記入。全て記入してからcmd_save.shを再実行せよ"* ]]
    [[ "$output" == *"未記入: q11_not_already_done"* ]]
}

@test "Check1-5: q11_not_already_done記入済みならPASS" {
    create_queue_file << 'YAML'
commands:
  cmd_9997:
    id: cmd_9997
    command: "q11記入済みのテスト"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
      q8_why_what: "WHY: テスト用 → WHAT: テストcmd 1件作成"
      q11_not_already_done: "未達成。grep 'BLOCK: q11_not_already_done' scripts/cmd_save.sh で未実装を確認"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_9997"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK: cmd_9997"* ]]
    [[ "$output" != *"BLOCK: q11_not_already_done未記入"* ]]
}

@test "Check1-5: q11自動検索でdeploy_task関連docsをINFO表示" {
    create_queue_file << 'YAML'
commands:
  cmd_9996:
    id: cmd_9996
    command: |
      bash scripts/deploy_task.sh hayate "タスクYAMLを読んで作業開始せよ。" task_assigned karo
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
      q8_why_what: "WHY: q11補助情報の確認 → WHAT: deploy_task.sh関連docs表示を確認"
      q11_not_already_done: "未達成。docs/research自動検索INFOは未実装だったため追加対象と確認"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_9996"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: 関連する既存成果物を検出:"* ]]
    [[ "$output" == *"scripts/deploy_task.sh → docs/research/"* ]]
}

@test "Check1-5: q11自動検索はスクリプト名なしなら追加表示なし" {
    create_queue_file << 'YAML'
commands:
  cmd_9995:
    id: cmd_9995
    command: "既存成果物の有無を文章で確認するだけ"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
      q8_why_what: "WHY: q11補助情報の非表示確認 → WHAT: スクリプト名なしcmd 1件確認"
      q11_not_already_done: "未達成。commandにスクリプト名を含まないケースを作成した"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_9995"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"INFO: 関連する既存成果物を検出:"* ]]
}

@test "Check1-5: gate追加cmdでq11に既存代替の現物確認なしならBLOCK" {
    create_queue_file << 'YAML'
commands:
  cmd_9994:
    id: cmd_9994
    title: "gate追加でLS009をgate化"
    purpose: "cmd_save.shへ新規gateを追加して各論パッチ検出を強制する"
    command: "bash scripts/cmd_save.sh 9994"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — q11 WARNの局所回帰確認のみ"
      q5_verified_source: "scripts/cmd_save.sh L1-L2900 code_reading + structure_verified(抽出関数でq11 WARN分岐確認)"
      q8_why_what: "WHY: LS009再発防止 → WHAT: gate追加cmdのq11記載品質を点検"
      q11_not_already_done: "未達成。grep 'q11_existing_alternative_verification' scripts/cmd_save.sh で未実装を確認"
    assumptions:
      - claim: "2026-04-24時点でテスト前提は固定"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_9994"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 1 ]
    [[ "$output" == *"q11_existing_alternative_verification"* ]]
    [[ "$output" == *"BLOCK:"* ]]
}

@test "Check1-5: gate追加cmdでもq11に既存代替の現物確認があればBLOCKなし" {
    create_queue_file << 'YAML'
commands:
  cmd_9993:
    id: cmd_9993
    title: "gate追加でLS009をgate化"
    purpose: "cmd_save.shへ新規gateを追加して各論パッチ検出を強制する"
    command: "bash scripts/cmd_save.sh 9993"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — q11 WARN抑止の局所回帰確認のみ"
      q5_verified_source: "scripts/cmd_save.sh L1-L2900 code_reading + structure_verified(抽出関数でq11 WARN抑止分岐確認)"
      q8_why_what: "WHY: 既存代替確認済みの正常系確認 → WHAT: q11 WARN抑止を確認"
      q11_not_already_done: "未達成。既存代替は scripts/cmd_save.sh 内の既存WARN群を rg -n 'record_warn_reason' で現物確認済み。今回追加差分のみ未達成"
    assumptions:
      - claim: "2026-04-24時点でテスト前提は固定"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_9993"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"q11_existing_alternative_verification"* ]]
}

@test "Check1-5: Guard一覧表示時にq11重複確認なしならBLOCK" {
    mkdir -p "$TEST_SHARED_TMP/scripts/hooks"
    cat > "$TEST_SHARED_TMP/scripts/hooks/sample_guard_hook.sh" <<'EOF'
# === Guard 1: existing deny ===
echo existing
EOF
    create_queue_file << 'YAML'
commands:
  cmd_guard_block:
    id: cmd_guard_block
    title: "強化 — 新規hook追加"
    purpose: "sample hookへ新規Guardを追加して重複を防ぐ"
    command: "scripts/hooks/sample_guard_hook.shに新規Guardを追加する"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — Guard一覧BLOCKの局所回帰確認のみ"
      q5_verified_source: "scripts/hooks/sample_guard_hook.sh code_reading + structure_verified"
      q8_why_what: "WHY: 既存Guard見落としを防ぐ → WHAT: assumptions sourceのGuard一覧を表示して重複確認を強制"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。grep -n sample_guard_hook scripts/hooks/sample_guard_hook.sh で現物確認"
    assumptions:
      - claim: "2026-05-19時点でsample hookにGuard見出しがある"
        source: "scripts/hooks/sample_guard_hook.sh code_reading"
        trust: "verified"
YAML

    CMD_ID="cmd_guard_block"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 1 ]
    [[ "$output" == *"INFO: assumptions source Guard一覧(# === Guard):"* ]]
    [[ "$output" == *"scripts/hooks/sample_guard_hook.sh:1 # === Guard 1"* ]]
    [[ "$output" == *"q11_guard_duplicate_verification"* ]]
}

@test "Check1-5: Guard一覧表示時にq11重複確認ありならGuard BLOCKなし" {
    mkdir -p "$TEST_SHARED_TMP/scripts/hooks"
    cat > "$TEST_SHARED_TMP/scripts/hooks/sample_guard_hook.sh" <<'EOF'
# === Guard 1: existing deny ===
echo existing
EOF
    create_queue_file << 'YAML'
commands:
  cmd_guard_pass:
    id: cmd_guard_pass
    title: "強化 — 新規hook追加"
    purpose: "sample hookへ新規Guardを追加して重複を防ぐ"
    command: "scripts/hooks/sample_guard_hook.shに新規Guardを追加し、不備をBLOCKする"
    acceptance_criteria:
      - "AC1: 重複時はBLOCKする"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — Guard一覧PASSの局所回帰確認のみ"
      q5_verified_source: "scripts/hooks/sample_guard_hook.sh code_reading + structure_verified"
      q8_why_what: "WHY: 既存Guard見落としを防ぐ → WHAT: assumptions sourceのGuard一覧を表示して重複確認を強制"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。Guard一覧を確認し、既存Guardとの重複なしを確認。grep -n '=== Guard' scripts/hooks/sample_guard_hook.sh で現物確認済み"
    assumptions:
      - claim: "2026-05-19時点でsample hookにGuard見出しがある"
        source: "scripts/hooks/sample_guard_hook.sh code_reading"
        trust: "verified"
YAML

    CMD_ID="cmd_guard_pass"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: assumptions source Guard一覧(# === Guard):"* ]]
    [[ "$output" != *"q11_guard_duplicate_verification"* ]]
}

@test "cmd_2612: gate追加cmdで行動変換キーワードがないならWARNING" {
    create_queue_file << 'YAML'
commands:
  cmd_2612_warn:
    id: cmd_2612_warn
    title: "強化 — 新規gate追加"
    purpose: "cmd_save.shへ新規gateを追加してWARN止まりの設計を検出する"
    command: |
      scripts/cmd_save.shに新規gateを追加する
      WARNメッセージを表示する
    acceptance_criteria:
      - "AC1: WARN表示のみのgate追加cmdを起票すると新チェックがWARN"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — 行動変換WARNの局所回帰確認のみ"
      q5_verified_source: "scripts/cmd_save.sh code_reading + tests/unit/test_cmd_save.bats isolated_test"
      q8_why_what: "WHY: WARN止まりのgate追加は行動を変えない → WHAT: 行動変換語なしをWARN"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。grep -rn gate_hook_action_conversion scripts/cmd_save.sh → 0件。代替なし。新規gateとして実装する"
    assumptions:
      - claim: "2026-05-09時点でfixtureはcmd_save.shのquality_gate抽出範囲内"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_2612_warn"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"gate/hook追加cmdに行動変換キーワードがありません"* ]]
    [[ "$output" == *"BLOCK / exit 1"* ]]
}

@test "cmd_2612: gate追加cmdでもACにBLOCK/exit 1があれば行動変換WARNINGなし" {
    create_queue_file << 'YAML'
commands:
  cmd_2612_pass:
    id: cmd_2612_pass
    title: "強化 — 新規gate追加"
    purpose: "cmd_save.shへ新規gateを追加してWARN止まりの設計を検出する"
    command: |
      scripts/cmd_save.shに新規gateを追加する
    acceptance_criteria:
      - "AC1: 行動変換不足時はBLOCK(exit 1)候補を明示する"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — 行動変換WARN抑止の局所回帰確認のみ"
      q5_verified_source: "scripts/cmd_save.sh code_reading + tests/unit/test_cmd_save.bats isolated_test"
      q8_why_what: "WHY: 行動変換まで設計済みのgate追加はWARN不要 → WHAT: BLOCK/exit 1入りACで抑止"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。grep -rn gate_hook_action_conversion scripts/cmd_save.sh → 0件。代替なし。新規gateとして実装する"
    assumptions:
      - claim: "2026-05-09時点でfixtureはcmd_save.shのquality_gate抽出範囲内"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_2612_pass"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"gate/hook追加cmdに行動変換キーワードがありません"* ]]
}

@test "cmd_2837: q8の偵察のみ/コード変更なしは縮小表現WARNINGなし" {
    create_queue_file << 'YAML'
commands:
  cmd_2837_q8_fp:
    id: cmd_2837_q8_fp
    title: "偵察 — q8縮小表現FP確認"
    purpose: "コード変更なしの偵察cmdでq8縮小表現が誤発火しないことを確認する"
    command: |
      logsを分析する
    acceptance_criteria:
      - "AC1: 偵察結果が記録されている"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — q8縮小表現FPの局所回帰確認のみ"
      q5_verified_source: "tests/unit/test_cmd_save.bats isolated_test"
      q8_why_what: "WHY: 偵察の非破壊性を説明する → WHAT: 偵察のみ。コード変更なし → WHEN: cmd保存時 → WHERE: tests/unit/test_cmd_save.bats → WHO: 将軍 → HOW: q8縮小表現の例外を確認する。複利: 正の複利"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。rg q8_縮小表現 scripts/cmd_save.sh で既存チェック確認済み"
    assumptions:
      - claim: "2026-05-17時点でfixtureはq8縮小表現チェック対象"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_2837_q8_fp"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"q8_縮小表現"* ]]
}

@test "cmd_3025: scope_mode=focusedならq8のだけ表現は縮小表現WARNINGなし" {
    create_queue_file << 'YAML'
commands:
  cmd_3025_q8_focused:
    id: cmd_3025_q8_focused
    title: "強化 — q8縮小表現focused除外"
    scope_mode: focused
    purpose: "scope_mode=focusedのcmdでは限定表現が正当なためq8縮小表現WARNを出さない"
    command: |
      scripts/cmd_save.shのq8縮小表現判定だけを修正する
    acceptance_criteria:
      - "AC1: focusedでq8縮小表現WARNが出ない"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — q8 focused除外の局所回帰確認"
      q5_verified_source: "tests/unit/test_cmd_save.bats isolated_test"
      q8_why_what: "WHY: focused cmdは対象限定が正当 → WHAT: q8縮小表現判定だけを修正する → WHEN: cmd保存時 → WHERE: scripts/cmd_save.sh → WHO: 将軍 → HOW: scope_mode=focusedを除外条件に入れる。複利: 正の複利"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。rg -nF scope_mode scripts/cmd_save.sh でq8除外未接続を確認"
    assumptions:
      - claim: "2026-05-24時点でscope_mode=focusedはq8縮小表現チェックの正当除外対象"
        source: "queue/tasks/kagemaru.yaml"
        trust: "verified"
YAML

    CMD_ID="cmd_3025_q8_focused"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"q8_縮小表現"* ]]
}

@test "cmd_3025: scope_mode未設定ならq8のだけ表現は縮小表現WARNINGを維持する" {
    create_queue_file << 'YAML'
commands:
  cmd_3025_q8_unset:
    id: cmd_3025_q8_unset
    title: "検証 — q8縮小表現従来挙動"
    purpose: "scope_mode未設定のcmdでは限定表現が従来通りq8縮小表現WARNになる"
    command: |
      scripts/cmd_save.shのq8縮小表現WARNを検証する
    acceptance_criteria:
      - "AC1: scope_mode未設定でq8縮小表現WARNが出る"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — q8 focused除外のTP回帰確認"
      q5_verified_source: "tests/unit/test_cmd_save.bats isolated_test"
      q8_why_what: "WHY: 不明な限定は範囲縮小として検出する → WHAT: q8縮小表現判定だけを検証する → WHEN: cmd保存時 → WHERE: scripts/cmd_save.sh → WHO: 将軍 → HOW: scope_mode未設定では既存WARNを維持する。複利: 正の複利"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。rg q8_縮小表現 scripts/cmd_save.sh で既存チェック確認済み"
    assumptions:
      - claim: "2026-05-24時点でscope_mode未設定はq8縮小表現チェックの除外対象ではない"
        source: "queue/tasks/kagemaru.yaml"
        trust: "verified"
YAML

    CMD_ID="cmd_3025_q8_unset"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"q8_why_whatのWHATに縮小表現を検出"* ]]
}

@test "cmd_2837: q8の代表/一部は正当WARNINGを維持する" {
    create_queue_file << 'YAML'
commands:
  cmd_2837_q8_tp:
    id: cmd_2837_q8_tp
    title: "検証 — q8縮小表現TP確認"
    purpose: "代表サンプルだけに縮小するcmdでq8縮小表現が発火することを確認する"
    command: |
      代表サンプルのみ検証する
    acceptance_criteria:
      - "AC1: 代表サンプルの結果が記録されている"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — q8縮小表現TPの局所回帰確認のみ"
      q5_verified_source: "tests/unit/test_cmd_save.bats isolated_test"
      q8_why_what: "WHY: パラメータ空間縮小を検出する → WHAT: 代表サンプルのみ検証する → WHEN: cmd保存時 → WHERE: tests/unit/test_cmd_save.bats → WHO: 将軍 → HOW: q8縮小表現をWARN化する。複利: 正の複利"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。rg q8_縮小表現 scripts/cmd_save.sh で既存チェック確認済み"
    assumptions:
      - claim: "2026-05-17時点でfixtureはq8縮小表現チェック対象"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_2837_q8_tp"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"q8_why_whatのWHATに縮小表現を検出"* ]]
}

@test "cmd_2803: dict形式ACのdescriptionに自動実行があれば行動変換WARNINGなし" {
    create_queue_file << 'YAML'
commands:
  cmd_2803_dict_ac:
    id: cmd_2803_dict_ac
    title: "強化 — 新規gate追加"
    purpose: "cmd_save.shへ新規gateを追加してWARN止まりの設計を検出する"
    command: |
      scripts/cmd_save.shに新規gateを追加する
    acceptance_criteria:
      AC1:
        description: "行動変換不足時は自動実行フローへ接続される"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — dict形式AC description抽出の局所回帰確認のみ"
      q5_verified_source: "scripts/cmd_save.sh code_reading + tests/unit/test_cmd_save.bats isolated_test"
      q8_why_what: "WHY: dict形式ACのdescriptionを行動変換判定に含める → WHAT: 自動実行入りdescriptionでWARN抑止"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。grep -rn gate_hook_action_conversion scripts/cmd_save.sh → 既存gateあり。dict形式AC抽出のみ未達成"
    assumptions:
      - claim: "2026-05-16時点でdict形式ACはdescription配下に本文を持つ"
        source: "queue/tasks/kagemaru.yaml"
        trust: "verified"
YAML

    CMD_ID="cmd_2803_dict_ac"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"gate/hook追加cmdに行動変換キーワードがありません"* ]]
}

@test "cmd_2628: gate/hook追加cmdなら既存強制フロー候補INFOを表示する" {
    create_queue_file << 'YAML'
commands:
  cmd_2628_info:
    id: cmd_2628_info
    title: "強化 — 新規gate追加"
    purpose: "cmd_save.shへ新規gateを追加して未記入を自動検出する"
    command: |
      scripts/cmd_save.shに新規gateを追加する
    acceptance_criteria:
      - "AC1: 行動変換不足時はBLOCK(exit 1)候補を明示する"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — 既存強制フロー候補INFOの局所回帰確認のみ"
      q5_verified_source: "scripts/cmd_save.sh code_reading + tests/unit/test_cmd_save.bats isolated_test"
      q8_why_what: "WHY: 新規gate/hook作成前に既存フロー接続を促す → WHAT: INFOで候補を表示"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。grep -rn gate_hook_action_conversion scripts/cmd_save.sh → 0件。代替なし。新規gateとして実装する"
    assumptions:
      - claim: "2026-05-10時点でfixtureはcmd_save.shのquality_gate抽出範囲内"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_2628_info"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: gate/hook追加cmdです。既存強制フロー候補を先に検討してください"* ]]
    [[ "$output" == *"cmd_save.sh"* ]]
    [[ "$output" == *"startup gate"* ]]
    [[ "$output" == *"deploy_task.sh"* ]]
    [[ "$output" == *"inbox_write.sh"* ]]
    [[ "$output" == *"gate_report_format.sh"* ]]
}

@test "cmd_2628: 非gate/hook cmdなら既存強制フロー候補INFOを表示しない" {
    create_queue_file << 'YAML'
commands:
  cmd_2628_no_info:
    id: cmd_2628_no_info
    title: "改善 — dashboard表示文言の調整"
    purpose: "dashboard.mdの表示文言を調整する"
    command: |
      dashboard生成スクリプトの表示文言を調整する
    acceptance_criteria:
      - "AC1: 表示文言が更新されている"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — 非対象cmdのINFO非表示確認のみ"
      q5_verified_source: "tests/unit/test_cmd_save.bats isolated_test"
      q8_why_what: "WHY: gate/hook追加以外で騒がしくしない → WHAT: 非対象cmdではINFO非表示"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "現物確認済み。既存表示文言をgrepで確認した"
    assumptions:
      - claim: "2026-05-10時点でfixtureはcmd_save.shのquality_gate抽出範囲内"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_2628_no_info"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"既存強制フロー候補"* ]]
}

@test "cmd_2631: q8指示引用あり+ACに引用キーワード含むならINFOを表示しない" {
    create_queue_file << 'YAML'
commands:
  cmd_2631_match:
    id: cmd_2631_match
    title: "強化 — 指示範囲整合"
    purpose: "殿の指示範囲とACの整合を確認する"
    command: |
      scripts/cmd_save.shに指示範囲整合INFOを追加する
    acceptance_criteria:
      - "AC1: WF選別のL0-L2パイプラインを確認する"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — 指示引用とAC一致の局所確認"
      q5_verified_source: "tests/unit/test_cmd_save.bats isolated_test"
      q8_why_what: "WHY: 殿指示「WF選別のL0-L2パイプラインをやれ」 → WHAT: AC整合を確認。複利: 先走り減少"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "現物確認済み。既存チェックなし"
    assumptions:
      - claim: "2026-05-10時点で本fixtureは引用キーワード一致ケース"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_2631_match"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"q8_why_whatの殿指示引用とACキーワード"* ]]
}

@test "cmd_2631: q8指示引用あり+ACに引用キーワードがなければINFOを表示する" {
    create_queue_file << 'YAML'
commands:
  cmd_2631_mismatch:
    id: cmd_2631_mismatch
    title: "強化 — 指示範囲整合"
    purpose: "殿の指示範囲とACの整合を確認する"
    command: |
      scripts/cmd_save.shに指示範囲整合INFOを追加する
    acceptance_criteria:
      - "AC1: dashboard表示文言を調整する"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — 指示引用とAC不一致の局所確認"
      q5_verified_source: "tests/unit/test_cmd_save.bats isolated_test"
      q8_why_what: "WHY: 殿指示「WF選別のL0-L2パイプラインをやれ」 → WHAT: AC整合を確認。複利: 先走り減少"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "現物確認済み。既存チェックなし"
    assumptions:
      - claim: "2026-05-10時点で本fixtureは引用キーワード不一致ケース"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_2631_mismatch"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: q8_why_whatの殿指示引用とACキーワードの整合を確認してください"* ]]
    [[ "$output" == *"WF選別"* ]]
    [[ "$output" == *"LS-A08"* ]]
}

@test "cmd_2631: q8指示引用なしならスキップする" {
    create_queue_file << 'YAML'
commands:
  cmd_2631_no_quote:
    id: cmd_2631_no_quote
    title: "強化 — 指示範囲整合"
    purpose: "殿の指示範囲とACの整合を確認する"
    command: |
      scripts/cmd_save.shに指示範囲整合INFOを追加する
    acceptance_criteria:
      - "AC1: dashboard表示文言を調整する"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow — 引用なしスキップの局所確認"
      q5_verified_source: "tests/unit/test_cmd_save.bats isolated_test"
      q8_why_what: "WHY: 指示範囲とAC整合を確認する → WHAT: 引用なしではスキップ。複利: 偽陽性なし"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "現物確認済み。既存チェックなし"
    assumptions:
      - claim: "2026-05-10時点で本fixtureは引用なしケース"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_2631_no_quote"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"q8_why_whatの殿指示引用とACキーワード"* ]]
}

@test "cmd_2655: q8がWHY/WHATのみならWHEN/HOW不足WARNを表示する" {
    create_queue_file << 'YAML'
commands:
  cmd_2655_missing_when_how:
    id: cmd_2655_missing_when_how
    title: "強化 — q8 WHEN/HOW検査"
    purpose: "q8_why_whatにWHEN/HOWがないcmdを検出する"
    command: |
      scripts/cmd_save.shにq8 WHEN/HOW不足WARNを追加する
    acceptance_criteria:
      - "AC1: WHY+WHATのみならWHEN/HOW不足WARNを表示する"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "WHEN/HOW欠落をcmd保存時に検出する"
      q3_next_quality: "cmd設計の発動条件と機能方法が明確になる"
      q4_depth: "shallow — q8 WHEN/HOW不足の局所確認"
      q5_verified_source: "tests/unit/test_cmd_save.bats isolated_test"
      q6_not_hiding: "no — 設計欠落を可視化するgate追加"
      q7_definition_verified: "yes — q8ラベルの有無を文字列検査する"
      q8_why_what: "WHY: 殿原則を環境に埋め込む → WHAT: q8検査にWHEN/HOW不足WARNを追加する。複利: 正の複利"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。grep -n quality_gate_q8_when_how scripts/cmd_save.sh で未実装を確認"
    assumptions:
      - claim: "2026-05-10時点でq8値はcmd_block_get_fieldで1行文字列として取得できる"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_2655_missing_when_how"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: q8_why_whatにWHEN/HOWが不足しています"* ]]
}

@test "cmd_2655: q8にWHY/WHAT/WHEN/HOWが揃えばWHEN/HOW不足WARNを表示しない" {
    create_queue_file << 'YAML'
commands:
  cmd_2655_full_when_how:
    id: cmd_2655_full_when_how
    title: "強化 — q8 WHEN/HOW検査"
    purpose: "q8_why_whatにWHEN/HOWがあるcmdはWARNしない"
    command: |
      scripts/cmd_save.shにq8 WHEN/HOW不足WARNを追加する
    acceptance_criteria:
      - "AC1: WHY+WHAT+WHEN+HOWならWHEN/HOW不足WARNを表示しない"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "WHEN/HOW欠落をcmd保存時に検出する"
      q3_next_quality: "cmd設計の発動条件と機能方法が明確になる"
      q4_depth: "shallow — q8 WHEN/HOW充足の局所確認"
      q5_verified_source: "tests/unit/test_cmd_save.bats isolated_test"
      q6_not_hiding: "no — 設計欠落を可視化するgate追加"
      q7_definition_verified: "yes — q8ラベルの有無を文字列検査する"
      q8_why_what: "WHY: 殿原則を環境に埋め込む → WHAT: q8検査にWHEN/HOW不足WARNを追加する → WHEN: cmd保存時にq8を読む時 → HOW: WHENとHOWのラベルを文字列検査して不足時だけWARNする。複利: 正の複利"
      q10_knowledge_boundary: "tests/unit/test_cmd_save.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。grep -n quality_gate_q8_when_how scripts/cmd_save.sh で未実装を確認"
    assumptions:
      - claim: "2026-05-10時点でq8値はcmd_block_get_fieldで1行文字列として取得できる"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_2655_full_when_how"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN: q8_why_whatにWHEN/HOWが不足しています"* ]]
}

@test "Check1-5: quality_gate未記入でBLOCK" {
    create_queue_file << 'YAML'
commands:
  cmd_8888:
    id: cmd_8888
    command: "quality_gate無しcmd"
    status: pending
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8888"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
}

@test "Check1-5: 消火cmd+q9なしでBLOCK" {
    create_queue_file << 'YAML'
commands:
  cmd_8801:
    id: cmd_8801
    title: "infra — CI赤修正"
    command: "FAILしているhookを修正"
    status: pending
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + structure_verified"
      q8_why_what: "WHY: 消火cmd検証 → WHAT: q9必須化を確認"
      q11_not_already_done: "未達成。title確認で消火cmd、q9未記入のため未完成と判断"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8801"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"q9_firefighting_root_cause未記入"* ]]
}

@test "Check1-5: 消火cmd+q9ありでPASS" {
    create_queue_file << 'YAML'
commands:
  cmd_8802:
    id: cmd_8802
    title: "infra — hotfix"
    command: |
      障害復旧のため修復する
    status: pending
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + structure_verified"
      q8_why_what: "WHY: 消火cmd検証 → WHAT: q9付きcmd 1件確認"
      q11_not_already_done: "未達成。q9付き正常系ケースを新規作成した"
      q9_firefighting_root_cause: "root_cause: 分岐条件の整理不足で再発した | prevention: gateで真因記入と再発防止記載を強制する"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8802"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK: cmd_8802"* ]]
}

@test "Check1-5: 消火cmd+q9あるがroot_cause欠落でBLOCK" {
    create_queue_file << 'YAML'
commands:
  cmd_8804:
    id: cmd_8804
    title: "infra — CI赤修正"
    command: "FAILしているテストを修正"
    status: pending
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + structure_verified"
      q8_why_what: "WHY: 消火cmd検証 → WHAT: q9形式不備検出確認"
      q11_not_already_done: "未達成。q9をTBDにしておりroot_cause欠落ケースを再現した"
      q9_firefighting_root_cause: "TBD"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8804"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"root_cause:"* ]]
}

@test "Check1-5: 消火cmd+q9あるがroot_cause短すぎでBLOCK" {
    create_queue_file << 'YAML'
commands:
  cmd_8806:
    id: cmd_8806
    title: "infra — hotfix復旧"
    command: "障害を修復"
    status: pending
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + structure_verified"
      q8_why_what: "WHY: 消火cmd検証 → WHAT: q9短文検出確認"
      q11_not_already_done: "未達成。root_cause を短文TBDにしてBLOCK対象を維持した"
      q9_firefighting_root_cause: "root_cause: TBD | prevention: gateで真因記入を強制する"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8806"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"root_causeが短すぎる"* ]]
}

@test "Check1-5: 消火cmd+q9あるがprevention欠落でBLOCK" {
    create_queue_file << 'YAML'
commands:
  cmd_8805:
    id: cmd_8805
    title: "infra — hotfix復旧"
    command: "壊れた機能を修復"
    status: pending
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + structure_verified"
      q8_why_what: "WHY: 消火cmd検証 → WHAT: prevention欠落検出確認"
      q11_not_already_done: "未達成。prevention欠落の異常系ケースを新規作成した"
      q9_firefighting_root_cause: "root_cause: テスト不足"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8805"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"prevention:"* ]]
}

@test "Check1-5: 消火cmd+q9あるがprevention短すぎでBLOCK" {
    create_queue_file << 'YAML'
commands:
  cmd_8807:
    id: cmd_8807
    title: "infra — CI赤修正"
    command: "FAILした機能を復旧"
    status: pending
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + structure_verified"
      q8_why_what: "WHY: 消火cmd検証 → WHAT: prevention短文検出確認"
      q11_not_already_done: "未達成。prevention をTBDにして短文BLOCKケースを再現した"
      q9_firefighting_root_cause: "root_cause: 分岐条件が未定義だった | prevention: TBD"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8807"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"preventionが短すぎる"* ]]
}

@test "Check1-5: 非消火cmd+q9なしでPASS" {
    create_queue_file << 'YAML'
commands:
  cmd_8803:
    id: cmd_8803
    title: "infra — 学習ループ改善"
    command: "gateの可視化を追加"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + structure_verified"
      q8_why_what: "WHY: 学習ループ改善 → WHAT: gate可視化 1件追加"
      q11_not_already_done: "未達成。gate可視化追加の正常系ケースを新規作成した"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8803"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK: cmd_8803"* ]]
}

@test "Check1-5: title非消火+command消火+q9なしでPASS（偽陽性排除）" {
    create_queue_file << 'YAML'
commands:
  cmd_8808:
    id: cmd_8808
    title: "infra — gate強化"
    command: |
      FAILしているCIを修正し障害を復旧する
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + structure_verified"
      q8_why_what: "WHY: gate強化 → WHAT: title限定検出の偽陽性排除確認"
      q11_not_already_done: "未達成。title限定判定の偽陽性排除ケースを新規作成した"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8808"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK: cmd_8808"* ]]
}

@test "Check1-5: titleにバグ含有+q9なしでBLOCK" {
    create_queue_file << 'YAML'
commands:
  cmd_8809:
    id: cmd_8809
    title: "infra — バグ修正"
    command: "挙動差分を調査する"
    status: pending
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + structure_verified"
      q8_why_what: "WHY: バグ系キーワード検証 → WHAT: q9必須BLOCKを確認"
      q11_not_already_done: "未達成。titleにバグを含めた異常系ケースを新規作成した"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8809"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"q9_firefighting_root_cause未記入"* ]]
}

@test "Check1-5: q9 preventionが気をつける系ならWARNING" {
    create_queue_file << 'YAML'
commands:
  cmd_8810:
    id: cmd_8810
    title: "infra — broken pipe修正"
    command: "壊れた通知を復旧する"
    status: pending
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + structure_verified"
      q8_why_what: "WHY: prevention意志依存検証 → WHAT: WARNING出力を確認"
      q11_not_already_done: "未達成。prevention意志依存WARNINGの確認ケースを新規作成した"
      q9_firefighting_root_cause: "root_cause: 判定観点が曖昧でレビュー時に見落とした | prevention: 次回は気をつけるよう共有する"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8810"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: q9のpreventionが意志依存"* ]]
}

@test "Check1-5: q9 preventionがgate追加なら意志依存WARNINGなし" {
    create_queue_file << 'YAML'
commands:
  cmd_8811:
    id: cmd_8811
    title: "infra — 不具合修正"
    command: "再発防止まで実装する"
    status: pending
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + structure_verified"
      q8_why_what: "WHY: prevention仕組み化検証 → WHAT: gate追加時はWARNINGを出さない"
      q11_not_already_done: "未達成。gate追加による正常系 prevention ケースを新規作成した"
      q9_firefighting_root_cause: "root_cause: q9判定語彙が不足し検知から漏れた | prevention: title判定に不具合を追加しgateで再発を防ぐ"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8811"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK: cmd_8811"* ]]
    [[ "$output" != *"WARNING: q9のpreventionが意志依存"* ]]
}

@test "Check1-5: q9 preventionが気をつけて（活用形）ならWARNING" {
    create_queue_file << 'YAML'
commands:
  cmd_8812:
    id: cmd_8812
    title: "infra — 不具合修正"
    command: "パターンを更新する"
    status: pending
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + structure_verified"
      q8_why_what: "WHY: 活用形検証 → WHAT: 気をつけて形でWARNINGを確認"
      q11_not_already_done: "未達成。気をつけて活用形のWARNINGケースを新規作成した"
      q9_firefighting_root_cause: "root_cause: 判定観点が曖昧でレビュー時に見落とした | prevention: 次回は気をつけてレビューする"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8812"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: q9のpreventionが意志依存"* ]]
}

@test "Check1-5: q9 preventionが注意して（活用形）ならWARNING" {
    create_queue_file << 'YAML'
commands:
  cmd_8813:
    id: cmd_8813
    title: "infra — 不具合修正"
    command: "パターンを更新する"
    status: pending
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + structure_verified"
      q8_why_what: "WHY: 活用形検証 → WHAT: 注意して形でWARNINGを確認"
      q11_not_already_done: "未達成。注意して活用形のWARNINGケースを新規作成した"
      q9_firefighting_root_cause: "root_cause: 確認手順が曖昧だった | prevention: 毎回注意してチェックリストを確認する"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8813"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: q9のpreventionが意志依存"* ]]
}

@test "Check1-5: q9 preventionが意識して（活用形）ならWARNING" {
    create_queue_file << 'YAML'
commands:
  cmd_8814:
    id: cmd_8814
    title: "infra — 不具合修正"
    command: "パターンを更新する"
    status: pending
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + structure_verified"
      q8_why_what: "WHY: 活用形検証 → WHAT: 意識して形でWARNINGを確認"
      q11_not_already_done: "未達成。意識して活用形のWARNINGケースを新規作成した"
      q9_firefighting_root_cause: "root_cause: レビュー観点が欠けていた | prevention: 品質を意識してレビューを実施する"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8814"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: q9のpreventionが意志依存"* ]]
}

@test "Check1-5: q9 preventionがgateを追加して自動検出する（仕組み系）なら意志依存WARNINGなし" {
    create_queue_file << 'YAML'
commands:
  cmd_8815:
    id: cmd_8815
    title: "infra — 不具合修正"
    command: "パターンを更新する"
    status: pending
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + structure_verified"
      q8_why_what: "WHY: 仕組み系偽陽性排除検証 → WHAT: gate追加で自動検出する旨はWARNINGなし"
      q11_not_already_done: "未達成。自動検出する prevention 正常系ケースを新規作成した"
      q9_firefighting_root_cause: "root_cause: 検知パターンが語幹未対応だった | prevention: gateを追加して自動検出する"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_8815"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK: cmd_8815"* ]]
    [[ "$output" != *"WARNING: q9のpreventionが意志依存"* ]]
}

# --- Check 11: impl cmd post-deploy verification AC検出 ---

@test "Check11: dm-signal+impl ACにpush/deploy無しでWARN" {
    create_queue_file << 'YAML'
commands:
  cmd_3001:
    id: cmd_3001
    acceptance_criteria:
    - "AC1: engine.pyのcalculate関数を修正"
    - "AC2: テスト実行+git commit"
    project: dm-signal
    task_type: impl
    command: "engine.py修正"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_3001"; export CMD_ID
    _setup_cmd_block "$CMD_ID"
    run check_impl_push_ac
    echo "$output" >&2
    # push/deploy/verify/本番確認がACにない → WARN
    [[ "$output" == *"デプロイ後の本番動作確認"* ]]
    [[ "$output" == *"ACN: git push後"* ]]
    [[ "$output" == *"cmd_1491"* ]]
    # 非BLOCKなので終了コード0
    [ "$status" -eq 0 ]
}

@test "Check11: dm-signal+impl ACにpush有りでWARNなし" {
    create_queue_file << 'YAML'
commands:
  cmd_3002:
    id: cmd_3002
    acceptance_criteria:
    - "AC1: engine.pyのcalculate関数を修正"
    - "AC2: git push後、本番確認"
    project: dm-signal
    task_type: impl
    command: "engine.py修正+push"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_3002"; export CMD_ID
    _setup_cmd_block "$CMD_ID"
    run check_impl_push_ac
    echo "$output" >&2
    # ACにpushがある → WARNなし
    [[ "$output" != *"デプロイ後の本番動作確認"* ]]
    [ "$status" -eq 0 ]
}

@test "Check11: dm-signal+impl ACにデプロイ有りでWARNなし" {
    create_queue_file << 'YAML'
commands:
  cmd_3003:
    id: cmd_3003
    acceptance_criteria:
    - "AC1: engine.pyの修正"
    - "AC2: Renderデプロイ完了を確認"
    project: dm-signal
    task_type: impl
    command: "engine.py修正"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_3003"; export CMD_ID
    _setup_cmd_block "$CMD_ID"
    run check_impl_push_ac
    echo "$output" >&2
    [[ "$output" != *"デプロイ後の本番動作確認"* ]]
    [ "$status" -eq 0 ]
}

@test "Check11: dm-signal+impl ACに本番動作確認有りでWARNなし" {
    create_queue_file << 'YAML'
commands:
  cmd_3004:
    id: cmd_3004
    acceptance_criteria:
    - "AC1: engine.pyの修正+テスト"
    - "AC2: 本番動作確認。エンドポイントにアクセスし変更反映を確認"
    project: dm-signal
    task_type: impl
    command: "engine.py修正"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_3004"; export CMD_ID
    _setup_cmd_block "$CMD_ID"
    run check_impl_push_ac
    echo "$output" >&2
    [[ "$output" != *"デプロイ後の本番動作確認"* ]]
    [ "$status" -eq 0 ]
}

@test "Check11: project=infraのimplはスキップ" {
    create_queue_file << 'YAML'
commands:
  cmd_3005:
    id: cmd_3005
    acceptance_criteria:
    - "AC1: gate追加"
    - "AC2: テスト+commit"
    project: infra
    task_type: impl
    command: "gate追加"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_3005"; export CMD_ID
    _setup_cmd_block "$CMD_ID"
    run check_impl_push_ac
    echo "$output" >&2
    # infraはCheck11対象外
    [[ "$output" != *"デプロイ後の本番動作確認"* ]]
    [ "$status" -eq 0 ]
}

@test "Check11: dm-signal+reconはスキップ" {
    create_queue_file << 'YAML'
commands:
  cmd_3006:
    id: cmd_3006
    acceptance_criteria:
    - "AC1: コード調査"
    project: dm-signal
    task_type: recon
    command: "調査"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_3006"; export CMD_ID
    _setup_cmd_block "$CMD_ID"
    run check_impl_push_ac
    echo "$output" >&2
    # reconはCheck11対象外
    [[ "$output" != *"デプロイ後の本番動作確認"* ]]
    [ "$status" -eq 0 ]
}

@test "Check11: commandにpushがあってもACに無ければWARN" {
    create_queue_file << 'YAML'
commands:
  cmd_3007:
    id: cmd_3007
    acceptance_criteria:
    - "AC1: engine.py修正"
    - "AC2: テスト+commit"
    project: dm-signal
    task_type: impl
    command: "engine.py修正してgit push"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
    assumptions:
      - claim: "テスト用前提確認済み"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"
YAML

    CMD_ID="cmd_3007"; export CMD_ID
    _setup_cmd_block "$CMD_ID"
    run check_impl_push_ac
    echo "$output" >&2
    # commandにpushがあるがACにはない → WARN出力
    [[ "$output" == *"デプロイ後の本番動作確認"* ]]
    [ "$status" -eq 0 ]
}

# --- Check3-q4: q4_depth ---

@test "Check3-q4: q4_depth=deepでWARNING表示" {
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_CACHE_LOADED=0
    declare -gA CMD_BLOCK_CACHE=()
    CMD_BLOCK_NC=$'    quality_gate:\n      q4_depth: "deep — 全忍者投入の万全偵察"'
    export CMD_BLOCK_NC CMD_BLOCK_FOUND CMD_BLOCK_CACHE_LOADED
    run check_q4_depth
    echo "$output" >&2
    [[ "$output" == *"q4_depth=deep/medium"* ]]
    [[ "$output" == *"時間コスト"* ]]
    # 非BLOCKなので終了コード0
    [ "$status" -eq 0 ]
}

@test "Check3-q4: q4_depth=mediumでWARNING表示" {
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_CACHE_LOADED=0
    declare -gA CMD_BLOCK_CACHE=()
    CMD_BLOCK_NC=$'    quality_gate:\n      q4_depth: "medium — 2忍者並列"'
    export CMD_BLOCK_NC CMD_BLOCK_FOUND CMD_BLOCK_CACHE_LOADED
    run check_q4_depth
    echo "$output" >&2
    [[ "$output" == *"q4_depth=deep/medium"* ]]
    [[ "$output" == *"時間コスト"* ]]
    [ "$status" -eq 0 ]
}

@test "Check3-q4: q4_depth=shallowでWARNINGなし" {
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_CACHE_LOADED=0
    declare -gA CMD_BLOCK_CACHE=()
    CMD_BLOCK_NC=$'    quality_gate:\n      q4_depth: "shallow — 1忍者で完結"'
    export CMD_BLOCK_NC CMD_BLOCK_FOUND CMD_BLOCK_CACHE_LOADED
    run check_q4_depth
    echo "$output" >&2
    [[ "$output" != *"q4_depth=deep/medium"* ]]
    [[ "$output" != *"時間コスト"* ]]
    [ "$status" -eq 0 ]
}

@test "Check3-q4: q4_depth未記入で従来WARNING表示" {
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_CACHE_LOADED=0
    declare -gA CMD_BLOCK_CACHE=()
    CMD_BLOCK_NC='    q1_firefighting: "no"'
    export CMD_BLOCK_NC CMD_BLOCK_FOUND CMD_BLOCK_CACHE_LOADED
    run check_q4_depth
    echo "$output" >&2
    [[ "$output" == *"q4_depth未記入"* ]]
    [[ "$output" != *"q4_depth=deep/medium"* ]]
    [ "$status" -eq 0 ]
}

# --- Check 11.3: AC推奨/必須混在検出 (GP-173) ---

@test "Check11.3: ACに推奨キーワードでBLOCK" {
    CMD_BLOCK="test"
    CMD_BLOCK_NC='acceptance_criteria:
    - "AC1: flock修正を実施する"
    - "AC2: リトライロジックを追加する（推奨）"
    - "AC3: テスト実行しPASS確認"'
    export CMD_BLOCK CMD_BLOCK_NC
    run check_ac_must_should_mix
    echo "$output" >&2
    [[ "$output" == *"推奨事項が混在"* ]]
    [[ "$output" == *"notesに分離"* ]]
    [ "$status" -eq 1 ]
}

@test "Check11.3: ACにoptionalでBLOCK" {
    CMD_BLOCK="test"
    CMD_BLOCK_NC='acceptance_criteria:
    - "AC1: implement core fix"
    - "AC2: add retry logic (optional)"'
    export CMD_BLOCK CMD_BLOCK_NC
    run check_ac_must_should_mix
    echo "$output" >&2
    [[ "$output" == *"推奨事項が混在"* ]]
    [ "$status" -eq 1 ]
}

@test "Check11.3: ACにできればでBLOCK" {
    CMD_BLOCK="test"
    CMD_BLOCK_NC='acceptance_criteria:
    - "AC1: 修正実施"
    - "AC2: できればログ出力も追加"'
    export CMD_BLOCK CMD_BLOCK_NC
    run check_ac_must_should_mix
    echo "$output" >&2
    [[ "$output" == *"推奨事項が混在"* ]]
    [ "$status" -eq 1 ]
}

@test "Check11.3: クリーンACでWARNなし" {
    CMD_BLOCK="test"
    CMD_BLOCK_NC='acceptance_criteria:
    - "AC1: flock修正を実施する"
    - "AC2: テスト実行しPASS確認"'
    export CMD_BLOCK CMD_BLOCK_NC
    run check_ac_must_should_mix
    echo "$output" >&2
    [[ "$output" != *"推奨事項が混在"* ]]
    [ "$status" -eq 0 ]
}

@test "Check11.3: ACセクションなしでWARNなし" {
    CMD_BLOCK="test"
    CMD_BLOCK_NC='title: "テストcmd"
notes: "なし"'
    export CMD_BLOCK CMD_BLOCK_NC
    run check_ac_must_should_mix
    echo "$output" >&2
    [[ "$output" != *"推奨事項が混在"* ]]
    [ "$status" -eq 0 ]
}

@test "Check11.3: CMD_BLOCK空でスキップ" {
    CMD_BLOCK=""
    CMD_BLOCK_NC=""
    export CMD_BLOCK CMD_BLOCK_NC
    run check_ac_must_should_mix
    echo "$output" >&2
    [[ "$output" != *"推奨事項が混在"* ]]
    [ "$status" -eq 0 ]
}

@test "Check11.3: nice to haveでBLOCK" {
    CMD_BLOCK="test"
    CMD_BLOCK_NC='acceptance_criteria:
    - "AC1: core fix"
    - "AC2: nice to have: add logging"'
    export CMD_BLOCK CMD_BLOCK_NC
    run check_ac_must_should_mix
    echo "$output" >&2
    [[ "$output" == *"推奨事項が混在"* ]]
    [ "$status" -eq 1 ]
}

@test "Check11.3: 望ましいでBLOCK" {
    CMD_BLOCK="test"
    CMD_BLOCK_NC='acceptance_criteria:
    - "AC1: 修正実施"
    - "AC2: パフォーマンス改善が望ましい"'
    export CMD_BLOCK CMD_BLOCK_NC
    run check_ac_must_should_mix
    echo "$output" >&2
    [[ "$output" == *"推奨事項が混在"* ]]
    [ "$status" -eq 1 ]
}

# --- Check 16: 行動→即確認原則 ---

@test "Check16: multiline block AC本文の確認キーワードでWARNしない" {
    CMD_BLOCK_NC='acceptance_criteria:
      description: |
        AC1: Check16の対象行を修正する
        AC2: multiline block形式のACでWARN非発火を確認する
quality_gate:
  q1_firefighting: "no"'
    export CMD_BLOCK_NC
    run check_action_immediate_verification
    echo "$output" >&2
    [[ "$output" != *"全ACが行動のみ"* ]]
    [ "$status" -eq 0 ]
}

@test "Check16: multiline block AC本文に確認キーワードなしならWARNする" {
    CMD_BLOCK_NC='acceptance_criteria:
      description: |
        AC1: Check16の対象行を修正する
        AC2: テストを追加する
quality_gate:
  q1_firefighting: "no"'
    export CMD_BLOCK_NC
    run check_action_immediate_verification
    echo "$output" >&2
    [[ "$output" == *"全ACが行動のみ"* ]]
    [ "$status" -eq 0 ]
}

@test "Check16: flat list AC本文のverifyキーワードでWARNしない" {
    CMD_BLOCK_NC='acceptance_criteria:
    - "AC1: implement fix"
    - "AC2: verify regression test passes"
quality_gate:
  q1_firefighting: "no"'
    export CMD_BLOCK_NC
    run check_action_immediate_verification
    echo "$output" >&2
    [[ "$output" != *"全ACが行動のみ"* ]]
    [ "$status" -eq 0 ]
}

# --- Check 20: assumptionsフィールド検査 ---

@test "Check20.0: AC数3以上かつassumptions欠落→inline checkはOK" {
    CMD_BLOCK='description: AC1
description: AC2
description: AC3'
    CMD_BLOCK_NC="$CMD_BLOCK"
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" == *"OK"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.1: trust:unverified含む→BLOCK" {
    CMD_BLOCK='description: AC1
description: AC2
description: AC3
assumptions:
  - claim: "未確認前提"
    source: "想像"
    trust: "unverified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" == *"BLOCK: 未検証前提あり"* ]]
    [ "$status" -eq 1 ]
}

@test "Check20.2: trust:verified+実在パス→PASS" {
    local FAKE_WD2
    FAKE_WD2="$(mktemp -d)"
    mkdir -p "$FAKE_WD2/config" "$FAKE_WD2/scripts"
    touch "$FAKE_WD2/scripts/cmd_save.sh"
    cat > "$FAKE_WD2/config/projects.yaml" << YAML
current_project: testpj2
projects:
  - id: testpj2
    path: "$FAKE_WD2"
YAML
    CMD_BLOCK='description: AC1
description: AC2
description: AC3
project: testpj2
assumptions:
  - claim: "cmd_save.shは存在する"
    source: "scripts/cmd_save.sh code_reading"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$FAKE_WD2"
    run check_20_assumptions
    echo "$output" >&2
    rm -rf "$FAKE_WD2"
    [[ "$output" != *"BLOCK"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.3: trust:verified+不在パス→BLOCK" {
    # tmpdir配下に存在しないパスをsourceに指定
    local FAKE_WD
    FAKE_WD="$(mktemp -d)"
    # config/projects.yaml にfake projectを作成してWDをFAKE_WDに設定
    mkdir -p "$FAKE_WD/config"
    cat > "$FAKE_WD/config/projects.yaml" << YAML
current_project: fake
projects:
  - id: fake
    path: "$FAKE_WD"
YAML
    CMD_BLOCK='description: AC1
description: AC2
description: AC3
project: fake
assumptions:
  - claim: "存在しないファイルの前提"
    source: "nonexistent/path.sh code_reading"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$FAKE_WD"
    run check_20_assumptions
    echo "$output" >&2
    rm -rf "$FAKE_WD"
    [[ "$output" == *"BLOCK: assumptions sourceのファイルパスが存在しません"* ]]
    [ "$status" -eq 1 ]
}

@test "Check20.3b: trust:verified+絶対パス→PROJECT_DIR二重結合せずPASS" {
    local FAKE_WD
    FAKE_WD="$(mktemp -d)"
    mkdir -p "$FAKE_WD/config" "$FAKE_WD/external"
    touch "$FAKE_WD/external/source.sh"
    cat > "$FAKE_WD/config/projects.yaml" << YAML
current_project: fake
projects:
  - id: fake
    path: "$FAKE_WD"
YAML
    CMD_BLOCK="description: AC1
description: AC2
description: AC3
project: fake
assumptions:
  - claim: \"絶対パスsourceは存在する\"
    source: \"$FAKE_WD/external/source.sh code_reading\"
    trust: \"verified\""
    CMD_BLOCK_NC="$CMD_BLOCK"
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$FAKE_WD"
    run check_20_assumptions
    echo "$output" >&2
    rm -rf "$FAKE_WD"
    [[ "$output" != *"BLOCK: assumptions sourceのファイルパスが存在しません"* ]]
    [[ "$output" != *"$FAKE_WD/$FAKE_WD"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.4: AC数2かつassumptions欠落→PASS" {
    CMD_BLOCK='description: AC1
description: AC2'
    CMD_BLOCK_NC="$CMD_BLOCK"
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [ "$status" -eq 0 ]
}

@test "Check20.5: assumptions claimに日付なし→WARNING" {
    CMD_BLOCK='description: AC1
description: AC2
description: AC3
assumptions:
  - claim: "既存代替の確認は完了している"
    source: "tests/unit/test_cmd_save.bats"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" == *"assumptions claimに日付がありません"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.6: assumptions claimに日付あり→WARNINGなし" {
    CMD_BLOCK='description: AC1
description: AC2
description: AC3
assumptions:
  - claim: "2026-04-24時点で既存代替の確認は完了している"
    source: "tests/unit/test_cmd_save.bats"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" != *"assumptions claimに日付がありません"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.7: 否定的前提キーワードあり+grep証跡あり→PASS" {
    CMD_BLOCK='project: infra
purpose: "未実装の入口防止を追加"
description: AC1
description: AC2
description: AC3
assumptions:
  - claim: "2026-05-10時点で grep -rn '\''premise.*evidence'\'' scripts/cmd_save.sh scripts/gates/ → 0件"
    source: "code_reading"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" != *"否定的前提キーワードを検出"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.8: 否定的assumptions.claimあり+grep証跡なし→WARNING" {
    CMD_BLOCK='purpose: "入口防止を追加"
description: AC1
description: AC2
description: AC3
assumptions:
  - claim: "2026-05-10時点で既存代替は未実装"
    source: "tests/unit/test_cmd_save.bats"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" == *"否定的前提キーワードを検出"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.9: 否定的前提キーワードなし→スキップ" {
    CMD_BLOCK='purpose: "入口防止を追加"
description: AC1
description: AC2
description: AC3
assumptions:
  - claim: "2026-05-10時点で既存代替の確認は完了している"
    source: "tests/unit/test_cmd_save.bats"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" != *"否定的前提キーワードを検出"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.10: q11_not_already_done内の否定キーワードは検出対象外" {
    CMD_BLOCK='purpose: "入口防止を追加"
description: AC1
description: AC2
description: AC3
quality_gate:
  q11_not_already_done: "未達成。既存代替は存在しないが、この欄は不在確認なので正常"
assumptions:
  - claim: "2026-05-10時点で既存代替の確認は完了している"
    source: "tests/unit/test_cmd_save.bats"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" != *"否定的前提キーワードを検出"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.10b: cmd本文の問題説明だけなら否定的前提WARNINGなし" {
    CMD_BLOCK='purpose: "未対応の入口防止を追加"
description: AC1
description: AC2
description: AC3
assumptions:
  - claim: "2026-05-17時点で既存代替の確認は完了している"
    source: "tests/unit/test_cmd_save.bats"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" != *"否定的前提キーワードを検出"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.10c: assumptions.claim内の否定語はgrep証跡なしならWARNING" {
    CMD_BLOCK='purpose: "入口防止を追加"
description: AC1
description: AC2
description: AC3
assumptions:
  - claim: "2026-05-17時点で既存代替は存在しない"
    source: "tests/unit/test_cmd_save.bats"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" == *"否定的前提キーワードを検出"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.11: 環境差異キーワードあり+measurement_envなし→INFO" {
    CMD_BLOCK='purpose: "ローカル検証と本番Renderの差異見落としを防ぐ"
command: |
  localで再現した結果をproductionへ適用する
acceptance_criteria:
  description: |
    AC1: 環境差異の確認を促す
assumptions:
  - claim: "2026-05-10時点で本テストfixtureはmeasurement_envなしケース"
    source: "tests/unit/test_cmd_save.bats"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" == *"measurement_envフィールドの記入を検討してください"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.12: 環境差異キーワードあり+measurement_envあり→INFOなし" {
    CMD_BLOCK='purpose: "ローカル検証と本番Renderの差異見落としを防ぐ"
measurement_env: "local=WSL2 / production=Render。差異の影響なし"
command: |
  localで再現した結果をproductionへ適用する
acceptance_criteria:
  description: |
    AC1: 環境差異の確認を促す
assumptions:
  - claim: "2026-05-10時点で本テストfixtureはmeasurement_envありケース"
    source: "tests/unit/test_cmd_save.bats"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" != *"measurement_envフィールドの記入を検討してください"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.13: 環境差異キーワードなし→measurement_env INFOなし" {
    CMD_BLOCK='purpose: "説明文のtypoを修正する"
command: |
  docsの表記を直す
acceptance_criteria:
  description: |
    AC1: 表記が修正されている
assumptions:
  - claim: "2026-05-10時点で本テストfixtureは環境差異キーワードなしケース"
    source: "tests/unit/test_cmd_save.bats"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" != *"measurement_envフィールドの記入を検討してください"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.14: bulletin由来の件数claimにgrep検証結果なし→WARNING" {
    CMD_BLOCK='project: infra
purpose: "掲示板報告をもとにcmdを起票する"
description: AC1
description: AC2
description: AC3
assumptions:
  - claim: "2026-05-15時点で掲示板報告由来の未処理が4件ある"
    source: "tests/unit/test_cmd_save.bats"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" == *"bulletin由来の件数claimを検出しました"* ]]
    [[ "$output" == *"grep/rg検証結果"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.15: bulletin由来の件数claimにgrep検証結果あり→WARNINGなし" {
    CMD_BLOCK='project: infra
purpose: "掲示板報告をもとにcmdを起票する"
description: AC1
description: AC2
description: AC3
assumptions:
  - claim: "2026-05-15時点で grep -n '\''blt_target'\'' queue/bulletin_board.yaml → 4件。掲示板報告由来の未処理が4件ある"
    source: "tests/unit/test_cmd_save.bats"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" != *"bulletin由来の件数claimを検出しました"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.15b: bulletin由来の件数claimにblt_ID参照あり→WARNINGなし" {
    # source fileの存在チェック(Check20 AC2)を通すためにテスト用ファイルを作成
    mkdir -p "$PROJECT_ROOT/queue"
    touch "$PROJECT_ROOT/queue/bulletin_board.yaml"
    CMD_BLOCK='project: infra
purpose: "掲示板報告をもとにcmdを起票する"
description: AC1
description: AC2
description: AC3
assumptions:
  - claim: "2026-05-15時点でblt_target_20260515の掲示板報告由来の未処理が4件ある"
    source: "queue/bulletin_board.yaml"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" != *"bulletin由来の件数claimを検出しました"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.16: bulletin由来でない件数claim→WARNINGなし" {
    CMD_BLOCK='purpose: "通常ログの件数を確認する"
description: AC1
description: AC2
description: AC3
assumptions:
  - claim: "2026-05-15時点で通常ログの未処理が4件ある"
    source: "logs/example.log"
    trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" != *"bulletin由来の件数claimを検出しました"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.5-TB1: 計測キーワードあり+timeout_minutesあり→WARNINGなし" {
    CMD_BLOCK='    purpose: "GS計測の再実行時間を確認する"
    timeout_minutes: 30
    command: |
      grid_search のbenchmarkを実行する
    acceptance_criteria:
      description: |
        AC1: 計測結果を報告する
    assumptions:
      - claim: "2026-05-10時点で本テストfixtureはtimeout_minutesありケース"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" != *"timeout_minutes未記入"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.5-TB2: 計測キーワードあり+timeout_minutesなし→WARNING" {
    CMD_BLOCK='    purpose: "GS計測の再実行時間を確認する"
    command: |
      grid_search のbenchmarkを実行する
    acceptance_criteria:
      description: |
        AC1: 計測結果を報告する
    assumptions:
      - claim: "2026-05-10時点で本テストfixtureはtimeout_minutesなしケース"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" == *"timeout_minutes未記入"* ]]
    [ "$status" -eq 0 ]
}

@test "Check20.5-TB3: 対象キーワードなし→タイムボックスチェックはスキップ" {
    CMD_BLOCK='    purpose: "説明文のtypoを修正する"
    command: |
      docsの表記を直す
    acceptance_criteria:
      description: |
        AC1: 表記が修正されている
    assumptions:
      - claim: "2026-05-10時点で本テストfixtureは対象キーワードなしケース"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK CMD_BLOCK_NC PROJECT_DIR="$PROJECT_ROOT"
    run check_20_assumptions
    echo "$output" >&2
    [[ "$output" != *"timeout_minutes未記入"* ]]
    [ "$status" -eq 0 ]
}

@test "Check21.1: 数値あり+算出元あり→INFOなし" {
    CMD_BLOCK_NC='purpose: "数値算出元の提案を追加"
command: |
  scripts/cmd_save.sh の L3450 近傍へ追加
acceptance_criteria:
  description: |
    AC1: 118件の入力を確認する
quality_gate:
  q5_verified_source: "structure_verified — rg -n '\''Check 21'\'' scripts/cmd_save.sh → 1件(2026-05-10)"
assumptions:
  - claim: "2026-05-10時点で rg -n '\''Check 21'\'' scripts/cmd_save.sh → 1件"
    source: "scripts/cmd_save.sh"
    trust: "verified"'
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK_NC CMD_BLOCK_FOUND CMD_BLOCK_LOADED
    run check_numeric_literal_derivation_source_info
    echo "$output" >&2
    [[ "$output" != *"数値リテラル"* ]]
    [ "$status" -eq 0 ]
}

@test "Check21.1: 数値あり+算出元なし→INFO" {
    CMD_BLOCK_NC='purpose: "数値算出元の提案を追加"
command: |
  scripts/cmd_save.sh の L3450 近傍へ追加
acceptance_criteria:
  description: |
    AC1: 118件の入力を確認する
quality_gate:
  q5_verified_source: "structure_verified — scripts/cmd_save.shを確認"
assumptions:
  - claim: "2026-05-10時点で既存構造を確認した"
    source: "scripts/cmd_save.sh"
    trust: "verified"'
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK_NC CMD_BLOCK_FOUND CMD_BLOCK_LOADED
    run check_numeric_literal_derivation_source_info
    echo "$output" >&2
    [[ "$output" == *"INFO: AC/command内に数値リテラルを検出"* ]]
    [[ "$output" == *"算出元コマンド+結果"* ]]
    [ "$status" -eq 0 ]
}

@test "Check21.1: 数値なし→スキップ" {
    CMD_BLOCK_NC='purpose: "相対条件で確認する"
command: |
  scripts/cmd_save.sh の関連箇所へ追加
acceptance_criteria:
  description: |
    AC1: 関連入力を確認する
quality_gate:
  q5_verified_source: "structure_verified — scripts/cmd_save.shを確認"
assumptions:
  - claim: "2026-05-10時点で既存構造を確認した"
    source: "scripts/cmd_save.sh"
    trust: "verified"'
    CMD_BLOCK_FOUND=1
    CMD_BLOCK_LOADED=1
    export CMD_BLOCK_NC CMD_BLOCK_FOUND CMD_BLOCK_LOADED
    run check_numeric_literal_derivation_source_info
    echo "$output" >&2
    [ -z "$output" ]
    [ "$status" -eq 0 ]
}
