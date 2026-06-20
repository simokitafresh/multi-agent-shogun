#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PRE_HOOK="$PROJECT_ROOT/.claude/hooks/pre-write-edit-combined.sh"
    export POST_HOOK="$PROJECT_ROOT/.claude/hooks/post-write-edit-combined.sh"
    [ -f "$PRE_HOOK" ] || return 1
    [ -f "$POST_HOOK" ] || return 1
}

setup() {
    export TMP_DIR TMP_REPORT TMP_STK TMP_AUTOLEARN TMP_CMD_QUALITY
    TMP_DIR="$(mktemp -d)"
    mkdir -p "$TMP_DIR/queue/reports"
    TMP_REPORT="$TMP_DIR/queue/reports/hanzo_report_cmd_100.yaml"
    TMP_STK="$TMP_DIR/queue/shogun_to_karo.yaml"
    TMP_AUTOLEARN="$TMP_DIR/preflight_autolearn.txt"
    TMP_CMD_QUALITY="$TMP_DIR/cmd_design_quality.yaml"
    printf 'result: ok\n' > "$TMP_REPORT"
    printf 'commands: {}\n' > "$TMP_STK"
    # 0-byte: cmd_save_block_top3()の[[ -s ]]チェックをfalseにしてPython yaml load(859KB,~1.5s)をスキップ
    touch "$TMP_CMD_QUALITY"
}

teardown() {
    rm -rf "$TMP_DIR"
}

_run_pre() {
    local payload="$1"
    run bash -c 'printf "%s" "$1" | PREFLIGHT_AUTOLEARN_FILE="$3" CMD_DESIGN_QUALITY_FILE="$4" bash "$2"' _ "$payload" "$PRE_HOOK" "$TMP_AUTOLEARN" "$TMP_CMD_QUALITY"
}

_run_post() {
    local payload="$1"
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$POST_HOOK"
}

@test "pre combined hook denies report yaml writes" {
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$TMP_REPORT"'"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *'報告YAMLへの直接Write/Edit禁止'* ]]
    [[ "$output" == *'report_field_set.sh'* ]]
}

@test "pre combined hook writes deny reason to stderr for Codex direct hook path" {
    local out_file="$BATS_TEST_TMPDIR/stdout.txt"
    local err_file="$BATS_TEST_TMPDIR/stderr.txt"
    run env PRE_HOOK="$PRE_HOOK" TMP_REPORT="$TMP_REPORT" OUT_FILE="$out_file" ERR_FILE="$err_file" bash -c '
        printf "%s" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP_REPORT\"}}" \
            | bash "$PRE_HOOK" >"$OUT_FILE" 2>"$ERR_FILE"
        rc=$?
        printf "stdout:\n"
        cat "$OUT_FILE"
        printf "\nstderr:\n"
        cat "$ERR_FILE"
        exit "$rc"
    '
    [ "$status" -eq 2 ]
    [[ "$output" == *'stdout:'*'"permissionDecision":"deny"'* ]]
    [[ "$output" == *'stderr:'*'report_field_set.sh'* ]]
}

@test "pre combined hook denies report yaml edits" {
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_REPORT"'"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *'報告YAMLへの直接Write/Edit禁止'* ]]
    [[ "$output" == *'bash scripts/report_field_set.sh'* ]]
}

@test "pre combined hook allows report_field_set bash path" {
    _run_pre '{"tool_name":"Bash","tool_input":{"command":"bash scripts/report_field_set.sh queue/reports/hanzo_report_cmd_100.yaml result.summary ok"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "pre combined hook allows non-report new file" {
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"/tmp/combined_new_file.txt"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "pre combined hook shows shogun_to_karo edit checklist" {
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"hookEventName"'* ]]
    [[ "$output" == *'"PreToolUse"'* ]]
    [[ "$output" == *'起票前確認11問'* ]]
    [[ "$output" == *'対象現物を確認したか'* ]]
    [[ "$output" == *'既存代替で足りないことを確認したか'* ]]
    [[ "$output" == *'cmd_save.sh関連チェック名を確認したか'* ]]
    [[ "$output" == *'environment_changeのpatternを対象fileでgrep確認したか'* ]]
    [[ "$output" == *'semantic_search.shで関連概念を検索したか'* ]]
    [[ "$output" == *'bash scripts/semantic_search.sh'* ]]
    [[ "$output" == *'既知キーワードgrepだけでは見落とす関連概念を確認せよ'* ]]
    [[ "$output" == *'rg -nF'*'対象ファイル'* ]]
}

@test "pre combined hook shows quality_gate template with q8 5W1H labels" {
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'quality_gate template (cmd_save.sh必須フィールド)'* ]]
    for field in \
        q1_firefighting q2_learning q3_next_quality q4_depth \
        q5_verified_source q6_not_hiding \
        q7_definition_verified q8_why_what \
        q9_firefighting_root_cause q10_knowledge_boundary \
        q11_not_already_done q_ambiguity timeout_minutes
    do
        [[ "$output" == *"$field"* ]]
    done
    [[ "$output" == *'WHY:'* ]]
    [[ "$output" == *'WHAT:'* ]]
    [[ "$output" == *'WHEN:'* ]]
    [[ "$output" == *'WHERE:'* ]]
    [[ "$output" == *'WHO:'* ]]
    [[ "$output" == *'HOW:'* ]]
    [[ "$output" == *'複利:'* ]]
}

@test "pre combined hook shows environment_change structured template and cautions" {
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'environment_change template (cmd_save.sh構造化形式)'* ]]
    [[ "$output" == *'environment_change: \"type=gate|lesson|hook; file=対象ファイルパス; pattern=grepで検証可能な既存文字列\"'* ]]
    [[ "$output" == *'1行テキスト形式必須'* ]]
    [[ "$output" == *'patternは実装済みの既存文字列のみ'* ]]
    [[ "$output" == *'grep確認したか'* ]]
    [[ "$output" == *'バックスラッシュ・パイプ禁止'* ]]
}

@test "pre combined hook shows dynamic preflight autolearn items" {
    printf '%s\n' '2026-05-02T00:00:00Z check=quality_gate_q8_compound_question count=3 warn=q8_複利の問い cmd=cmd_test' > "$TMP_AUTOLEARN"
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'動的追加確認(preflight_autolearn)'* ]]
    [[ "$output" == *'quality_gate_q8_compound_question'* ]]
    [[ "$output" == *'count=3'* ]]
}

@test "pre combined hook auto shows q11 grep results for gate hook script paths" {
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'","new_string":"commands:\n  cmd_test:\n    purpose: gate追加\n    command: bash scripts/gates/gate_report_format.sh queue/reports/x.yaml\n"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'自動grep結果(q11コピー用)'* ]]
    [[ "$output" == *'scripts/gates/gate_report_format.sh'* ]]
    [[ "$output" == *'command: rg -nF'*'scripts/gates/gate_report_format.sh'* ]]
    [[ "$output" == *'count:'* ]]
}

@test "pre combined hook does not show q11 grep results without gate hook script paths" {
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'","new_string":"commands:\n  cmd_test:\n    purpose: 通常cmd\n    command: echo ok\n"}}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'自動grep結果(q11コピー用)'* ]]
}

@test "pre combined hook blocks autolearned pipe danger in purpose" {
    printf '%s\n' '2026-05-03T15:32:46Z check=check_cmd_text_pipe_danger count=1 warn=cmd_text_pipe_danger cmd=cmd_2548' > "$TMP_AUTOLEARN"
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'","new_string":"commands:\n  cmd_test:\n    purpose: grep foo | wc -l\n    command: echo ok\n"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *'check_cmd_text_pipe_dangerはpreflight_autolearnで昇格済み'* ]]
}

@test "pre combined hook blocks autolearned pipe danger in command block" {
    printf '%s\n' '2026-05-03T15:32:46Z check=check_cmd_text_pipe_danger count=1 warn=cmd_text_pipe_danger cmd=cmd_2548' > "$TMP_AUTOLEARN"
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'","new_string":"commands:\n  cmd_test:\n    purpose: safe\n    command: |\n      rg foo | wc -l\n    project: infra\n"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *'purpose/commandにパイプ文字(|)を検出'* ]]
}

@test "pre combined hook allows pipe content when pipe danger is not autolearned" {
    printf '%s\n' '2026-05-02T00:00:00Z check=quality_gate_q8_compound_question count=3 warn=q8_複利の問い cmd=cmd_test' > "$TMP_AUTOLEARN"
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'","new_string":"commands:\n  cmd_test:\n    purpose: grep foo | wc -l\n    command: echo ok\n"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'動的追加確認(preflight_autolearn)'* ]]
    [[ "$output" != *'"permissionDecision":"deny"'* ]]
}

@test "pre combined hook warns when quality_gate q5 is filled but q5_verified_source is missing" {
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'","new_string":"commands:\n  cmd_test:\n    purpose: q5 pair regression\n    quality_gate:\n      q5: \"structure_verified\"\n      q1_firefighting: \"no\"\n    command: echo ok\n"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'WARN(q5_verified_source必須フィールド対)'* ]]
    [[ "$output" == *'quality_gate.q5 が記入済みだが q5_verified_source が空/未記入'* ]]
}

@test "pre combined hook warns when quality_gate q5 is filled but q5_verified_source is empty" {
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'","new_string":"commands:\n  cmd_test:\n    purpose: q5 pair empty regression\n    quality_gate:\n      q5: \"structure_verified\"\n      q5_verified_source: \"\"\n    command: echo ok\n"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'WARN(q5_verified_source必須フィールド対)'* ]]
    [[ "$output" == *'cmd_save.sh到達前に q5_verified_source'* ]]
}

@test "pre combined hook does not warn when quality_gate q5 and q5_verified_source are both filled" {
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'","new_string":"commands:\n  cmd_test:\n    purpose: q5 pair complete\n    quality_gate:\n      q5: \"structure_verified\"\n      q5_verified_source: \"tests/unit/test_write_edit_combined_hooks.bats isolated_test\"\n    command: echo ok\n"}}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'WARN(q5_verified_source必須フィールド対)'* ]]
}

@test "pre combined hook does not show checklist for other edit targets" {
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/combined_other_file.txt"}}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'対象現物を確認したか'* ]]
    [[ "$output" != *'既存代替で足りないことを確認したか'* ]]
    [[ "$output" != *'cmd_save.sh関連チェック名を確認したか'* ]]
}

@test "post combined hook exits cleanly for unrelated payload" {
    _run_post '{"tool_name":"Write","tool_input":{"file_path":"/tmp/combined_new_file.txt"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "post combined hook warns on report yaml edits" {
    _run_post '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_REPORT"'"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"hookEventName":"PostToolUse"'* ]]
    [[ "$output" == *'報告YAMLへの直接Edit/Write検出'* ]]
}

@test "Guard 0d: 全件gate_clearのみなら起票を許可する" {
    local fake_inbox="$TMP_DIR/fake_inbox_gc_only.yaml"
    printf 'messages:\n- content: "cmd_3345 GATE CLEAR"\n  from: karo\n  id: msg_gc1\n  read: false\n  timestamp: "2026-06-13T00:00:00"\n  type: gate_clear\n- content: "cmd_3346 GATE CLEAR"\n  from: karo\n  id: msg_gc2\n  read: false\n  timestamp: "2026-06-13T00:00:01"\n  type: gate_clear\n' > "$fake_inbox"
    run bash -c 'printf "%s" "$1" | PREFLIGHT_AUTOLEARN_FILE="$3" CMD_DESIGN_QUALITY_FILE="$4" GUARD_0D_INBOX_OVERRIDE="$5" bash "$2"' _ \
        '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'"}}' \
        "$PRE_HOOK" "$TMP_AUTOLEARN" "$TMP_CMD_QUALITY" "$fake_inbox"
    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"deny"'* ]]
}

@test "Guard 0d: 指示系type混在なら起票をBLOCKする" {
    local fake_inbox="$TMP_DIR/fake_inbox_mixed.yaml"
    printf 'messages:\n- content: "cmd_3345 GATE CLEAR"\n  from: karo\n  id: msg_gc1\n  read: false\n  timestamp: "2026-06-13T00:00:00"\n  type: gate_clear\n- content: "新タスク配備"\n  from: karo\n  id: msg_ta1\n  read: false\n  timestamp: "2026-06-13T00:00:01"\n  type: task_assigned\n' > "$fake_inbox"
    run bash -c 'printf "%s" "$1" | PREFLIGHT_AUTOLEARN_FILE="$3" CMD_DESIGN_QUALITY_FILE="$4" GUARD_0D_INBOX_OVERRIDE="$5" bash "$2"' _ \
        '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'"}}' \
        "$PRE_HOOK" "$TMP_AUTOLEARN" "$TMP_CMD_QUALITY" "$fake_inbox"
    [ "$status" -eq 2 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *'Read toolで全文読み'* ]]
    [[ "$output" == *'指示系'* ]]
}

@test "Guard 16: 忍者名3件直書きでBLOCKする" {
    local sh_file="$TMP_DIR/test_agents.sh"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$sh_file"'","content":"TARGETS=\"hayate hanzo saizo\"\necho $TARGETS\n"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'BLOCK: 操作的オントロジー違反'* ]]
    [[ "$output" == *'エージェント名'* ]]
}

@test "Guard 16: 忍者名2件は許可する" {
    local sh_file="$TMP_DIR/test_agents2.sh"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$sh_file"'","content":"echo hayate hanzo\n"}}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'BLOCK: 操作的オントロジー違反'* ]]
}

@test "Guard 16: get_ninja_names使用で忍者名直書きを許可する" {
    local sh_file="$TMP_DIR/test_agents3.sh"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$sh_file"'","content":"names=$(get_ninja_names)\nfor n in $names; do echo $n; done\n"}}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'BLOCK: 操作的オントロジー違反'* ]]
}

@test "Guard 16: get_ninja_names使用と忍者名直書き混在はBLOCKする" {
    local sh_file="$TMP_DIR/test_agents_mixed.sh"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$sh_file"'","content":"names=$(get_ninja_names)\nfor n in hayate hanzo saizo; do echo $n; done\n"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'SSOT参照もあるが直書きが残っている'* ]]
    [[ "$output" == *'エージェント名'* ]]
}

@test "Guard 16: repo絶対パス直書きでBLOCKする" {
    local sh_file="$TMP_DIR/test_repo_path.sh"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$sh_file"'","content":"REPO='"$PROJECT_ROOT"'/scripts/lib/something.sh\necho $REPO\n"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'BLOCK: 操作的オントロジー違反'* ]]
    [[ "$output" == *'repoルートパス'* ]]
}

@test "Guard 16: SCRIPT_DIR使用でrepoパス直書きを許可する" {
    local sh_file="$TMP_DIR/test_repo_ok.sh"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$sh_file"'","content":"REPO=$SCRIPT_DIR/scripts/lib/something.sh\necho $REPO\n"}}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'BLOCK: 操作的オントロジー違反'* ]]
}

@test "Guard 16: SCRIPT_DIR使用とrepo絶対パス直書き混在はBLOCKする" {
    local sh_file="$TMP_DIR/test_repo_mixed.sh"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$sh_file"'","content":"REPO=$SCRIPT_DIR/scripts/lib/something.sh\nLEGACY='"$PROJECT_ROOT"'/scripts/legacy.sh\n"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'SSOT参照もあるが直書きが残っている'* ]]
    [[ "$output" == *'repoルートパス'* ]]
}

@test "Guard 16: user-home絶対パス直書きでBLOCKする" {
    local sh_file="$TMP_DIR/test_home_path.sh"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$sh_file"'","content":"BIN='"$HOME"'/bin/claude\necho $BIN\n"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'BLOCK: 操作的オントロジー違反'* ]]
    [[ "$output" == *'user-homeパス'* ]]
}

@test "Guard 16: HOME変数使用でhomeパス直書きを許可する" {
    local sh_file="$TMP_DIR/test_home_ok.sh"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$sh_file"'","content":"BIN=$HOME/bin/claude\necho $BIN\n"}}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'BLOCK: 操作的オントロジー違反'* ]]
}

@test "Guard 16: HOME変数使用とuser-home絶対パス直書き混在はBLOCKする" {
    local sh_file="$TMP_DIR/test_home_mixed.sh"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$sh_file"'","content":"BIN=$HOME/bin/claude\nLEGACY='"$HOME"'/bin/claude\n"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'SSOT参照もあるが直書きが残っている'* ]]
    [[ "$output" == *'user-homeパス'* ]]
}

@test "Guard 16: Pythonのrepo絶対パス直書きもBLOCKする" {
    local py_file="$TMP_DIR/test_repo_path.py"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$py_file"'","content":"REPO = \"'"$PROJECT_ROOT"'\"\nprint(REPO)\n"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'repoルートパス'* ]]
}

@test "Guard 16: Pythonのos.environ使用とhome絶対パス直書き混在はBLOCKする" {
    local py_file="$TMP_DIR/test_home_mixed.py"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$py_file"'","content":"import os\nhome = os.environ.get(\"HOME\")\nlegacy = \"'"$HOME"'/bin/claude\"\n"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'SSOT参照もあるが直書きが残っている'* ]]
    [[ "$output" == *'user-homeパス'* ]]
}
