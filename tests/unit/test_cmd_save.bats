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
    eval "$(sed -n '/^load_cmd_block()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block_cache()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_has_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_get_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_primary_cmd_targets()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^is_gate_or_hook_addition_cmd()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^q11_has_existing_alternative_verification()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_assumption_claims_missing_dates()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_self_reread_red_flag()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_bundle_red_flag()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^build_warn_note()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_key()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_message()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^record_warn_reason()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^record_block_reason()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^abort_if_block_immediate()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f trim_inline_yaml_scalar load_cmd_block load_cmd_block_cache cmd_block_has_field cmd_block_get_field collect_primary_cmd_targets is_gate_or_hook_addition_cmd q11_has_existing_alternative_verification collect_assumption_claims_missing_dates check_self_reread_red_flag check_bundle_red_flag build_warn_note warn_note_key warn_note_message record_warn_reason record_block_reason abort_if_block_immediate

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

@test "Check1-5: gate追加cmdでq11に既存代替の現物確認なしならWARNING" {
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
    [ "$status" -eq 0 ]
    [[ "$output" == *"q11_existing_alternative_verification"* ]]
}

@test "Check1-5: gate追加cmdでもq11に既存代替の現物確認があればWARNINGなし" {
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
