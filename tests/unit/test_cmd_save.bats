#!/usr/bin/env bats
# test_cmd_save.bats — cmd_save.sh ユニットテスト（Check 6: GP重複チェック中心）
# Optimized: フル実行→関数直接呼び出し方式（python3/tmux/git呼び出し回避）

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

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
$(sed -n '/# q4_depth: 段階的導入/,/^    fi/{p;/^    fi/q}' "$SRC_SAVE_SCRIPT")
}"
    export -f check_q4_depth

    # check_quality_gate: Check 3インラインセクション(質問ゲートブロック)を関数化 + 成功時OK出力
    local _qg_start _qg_end
    _qg_start=$(grep -n '# --- Check 3: quality_gate' "$SRC_SAVE_SCRIPT" | head -1 | cut -d: -f1)
    _qg_end=$(grep -n '# --- Check 4:' "$SRC_SAVE_SCRIPT" | head -1 | cut -d: -f1)
    _qg_end=$((_qg_end - 1))
    eval "check_quality_gate() {
local WARN_COUNT=0
$(sed -n "${_qg_start},${_qg_end}p" "$SRC_SAVE_SCRIPT")
echo \"保存確認OK: \${CMD_ID}\"
}"
    export -f check_quality_gate

    # 共有テンポラリディレクトリ(setup_fileで1回のみ作成)
    export TEST_SHARED_TMP
    TEST_SHARED_TMP="$(mktemp -d)"
    mkdir -p "${TEST_SHARED_TMP}/queue/archive/cmds"
    export QUEUE_FILE="${TEST_SHARED_TMP}/queue/shogun_to_karo.yaml"
}

teardown_file() {
    rm -rf "$TEST_SHARED_TMP"
}

setup() {
    # 共有tmpdirを再利用 — per-testのmktemp/mkdirオーバーヘッドを排除
    export CMD_ID="cmd_test"
    export CMD_BLOCK=""
    export CMD_BLOCK_NC=""
}

teardown() { true; }

# --- ヘルパー: QUEUE_FILE書き込み ---
create_queue_file() {
    cat > "$QUEUE_FILE"
}

# --- ヘルパー: CMD_BLOCK/CMD_BLOCK_NCをQUEUE_FILEから設定 ---
_setup_cmd_block() {
    local cid="${1:-$CMD_ID}"
    CMD_BLOCK=$(awk "/^  ${cid}:/{found=1; next} found && /^  cmd_/{exit} found{print}" "$QUEUE_FILE")
    CMD_BLOCK_NC=$(echo "$CMD_BLOCK" | grep -v '^\s*#' || true)
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
YAML

    CMD_ID="cmd_9999"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK: cmd_9999"* ]]
}

@test "Check1-5: quality_gate未記入でBLOCK" {
    create_queue_file << 'YAML'
commands:
  cmd_8888:
    id: cmd_8888
    command: "quality_gate無しcmd"
    status: pending
YAML

    CMD_ID="cmd_8888"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
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
    CMD_BLOCK_NC='    q4_depth: "deep — 全忍者投入の万全偵察"'
    export CMD_BLOCK_NC
    run check_q4_depth
    echo "$output" >&2
    [[ "$output" == *"q4_depth=deep/medium"* ]]
    [[ "$output" == *"時間コスト"* ]]
    # 非BLOCKなので終了コード0
    [ "$status" -eq 0 ]
}

@test "Check3-q4: q4_depth=mediumでWARNING表示" {
    CMD_BLOCK_NC='    q4_depth: "medium — 2忍者並列"'
    export CMD_BLOCK_NC
    run check_q4_depth
    echo "$output" >&2
    [[ "$output" == *"q4_depth=deep/medium"* ]]
    [[ "$output" == *"時間コスト"* ]]
    [ "$status" -eq 0 ]
}

@test "Check3-q4: q4_depth=shallowでWARNINGなし" {
    CMD_BLOCK_NC='    q4_depth: "shallow — 1忍者で完結"'
    export CMD_BLOCK_NC
    run check_q4_depth
    echo "$output" >&2
    [[ "$output" != *"q4_depth=deep/medium"* ]]
    [[ "$output" != *"時間コスト"* ]]
    [ "$status" -eq 0 ]
}

@test "Check3-q4: q4_depth未記入で従来WARNING表示" {
    CMD_BLOCK_NC='    q1_firefighting: "no"'
    export CMD_BLOCK_NC
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
