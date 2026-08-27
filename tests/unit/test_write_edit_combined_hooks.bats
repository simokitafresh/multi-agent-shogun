#!/usr/bin/env bats
# test_necessity: Report/inbox direct edits are denied and Guard19 fires only when a same-day commit and a new uncommitted change overlap on one scripts file; violation is BLOCK.
# regression_justification: Guard19 previously treated commit-only and dirty-only normal work as duplication risk, producing 5/34 false positives.

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PRE_HOOK_SOURCE="$PROJECT_ROOT/.claude/hooks/pre-write-edit-combined.sh"
    export PRE_HOOK="$BATS_FILE_TMPDIR/pre-write-edit-combined.sh"
    cp "$PRE_HOOK_SOURCE" "$PRE_HOOK"
    chmod +x "$PRE_HOOK"
    export PRE_WRITE_SCRIPT_DIR_OVERRIDE="$PROJECT_ROOT"
    export SHARED_FIXTURE_ROOT="$BATS_FILE_TMPDIR/write-edit-combined-fixture"
    mkdir -p "$SHARED_FIXTURE_ROOT"
    printf '%s\n' 'scripts/gates/gate_report_format.sh' > "$SHARED_FIXTURE_ROOT/q11-reference.txt"
    : > "$SHARED_FIXTURE_ROOT/causal-index.tsv"
    cp "$PROJECT_ROOT/docs/research/cmd_save_gate_catalog.md" "$SHARED_FIXTURE_ROOT/cmd_save_gate_catalog.md"
    export Q11_SEARCH_ROOT_OVERRIDE="$SHARED_FIXTURE_ROOT"
    export G12B_CATALOG_OVERRIDE="$SHARED_FIXTURE_ROOT/cmd_save_gate_catalog.md"
    export MEMORY_DB_PREFLIGHT_DISABLE=1
    export GUARD19_GIT_ROOT_OVERRIDE="$SHARED_FIXTURE_ROOT"
    export CAUSAL_INDEX_DISABLE_SCRIPT=1
    export CAUSAL_INDEX_CACHE="$SHARED_FIXTURE_ROOT/causal-index.tsv"
    export POST_HOOK="$PROJECT_ROOT/.claude/hooks/post-write-edit-combined.sh"
    [ -f "$PRE_HOOK" ] || return 1
    [ -f "$POST_HOOK" ] || return 1

    # Guard16 only needs the immutable agent-name fixture. Resolve it once per
    # file instead of sourcing/scanning config in every hook subprocess.
    export G16_AGENT_NAMES_OVERRIDE
    G16_AGENT_NAMES_OVERRIDE="$(source "$PROJECT_ROOT/scripts/lib/agent_config.sh" && get_ninja_names)"
}

setup() {
    export TMP_DIR TMP_REPORT TMP_STK TMP_AUTOLEARN TMP_CMD_QUALITY TEST_AGENT_ID
    TMP_DIR="$BATS_TEST_TMPDIR/write-edit-combined"
    mkdir -p "$TMP_DIR/queue/reports"
    TMP_REPORT="$TMP_DIR/queue/reports/hanzo_report_cmd_100.yaml"
    TMP_STK="$TMP_DIR/queue/shogun_to_karo.yaml"
    TMP_AUTOLEARN="$TMP_DIR/preflight_autolearn.txt"
    TMP_CMD_QUALITY="$TMP_DIR/cmd_design_quality.yaml"
    TEST_AGENT_ID="bats_we_${BATS_TEST_NUMBER:-$$}_$$"
    printf 'result: ok\n' > "$TMP_REPORT"
    printf 'commands: {}\n' > "$TMP_STK"
    printf 'messages: []\n' > "$TMP_DIR/default_inbox.yaml"
    # 0-byte: cmd_save_block_top3()の[[ -s ]]チェックをfalseにしてPython yaml load(859KB,~1.5s)をスキップ
    touch "$TMP_CMD_QUALITY"
}

teardown() {
    rm -f "/tmp/claude_read_log_${TEST_AGENT_ID:-unknown}.txt"
}

_run_pre() {
    local payload="$1"
    run env MOCK_AGENT_ID="$TEST_AGENT_ID" G16_AGENT_NAMES_OVERRIDE="$G16_AGENT_NAMES_OVERRIDE" \
        PREFLIGHT_AUTOLEARN_FILE="$TMP_AUTOLEARN" CMD_DESIGN_QUALITY_FILE="$TMP_CMD_QUALITY" \
        GUARD_0D_INBOX_OVERRIDE="$TMP_DIR/default_inbox.yaml" Q11_SEARCH_ROOT_OVERRIDE="$Q11_SEARCH_ROOT_OVERRIDE" \
        G12B_CATALOG_OVERRIDE="$G12B_CATALOG_OVERRIDE" MEMORY_DB_PREFLIGHT_DISABLE="$MEMORY_DB_PREFLIGHT_DISABLE" \
        bash -c 'source "$2" <<<"$1"' _ "$payload" "$PRE_HOOK"
}

_run_post() {
    local payload="$1"
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$POST_HOOK"
}

_mark_read_for_current_agent() {
    local file_path="$1"
    printf '%s\n' "$file_path" > "/tmp/claude_read_log_${TEST_AGENT_ID}.txt"
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

@test "inbox direct Write is denied with flock-safe alternatives" {
    local inbox_file="$TMP_DIR/queue/inbox/hayate.yaml"
    mkdir -p "$(dirname "$inbox_file")"
    printf 'messages: []\n' > "$inbox_file"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$inbox_file"'"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *'inbox_write.sh'* ]]
    [[ "$output" == *'inbox_mark_read.sh'* ]]
}

@test "inbox direct Edit is denied through queue/inbox symlink" {
    local real_inbox="$TMP_DIR/real_inbox"
    mkdir -p "$real_inbox" "$TMP_DIR/queue"
    ln -s "$real_inbox" "$TMP_DIR/queue/inbox"
    export GUARD_INBOX_ROOT_OVERRIDE="$TMP_DIR/queue/inbox"
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_DIR"'/queue/inbox/karo.yaml"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *'symlink実体'* ]]
}

@test "inbox symlink real target is denied even when addressed by resolved path" {
    local real_inbox="$TMP_DIR/real_inbox"
    mkdir -p "$real_inbox" "$TMP_DIR/queue"
    ln -s "$real_inbox" "$TMP_DIR/queue/inbox"
    export GUARD_INBOX_ROOT_OVERRIDE="$TMP_DIR/queue/inbox"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$real_inbox"'/gunshi.yaml"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
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
    [[ "$output" == *'status:draft'* ]]
    [[ "$output" == *'draft→pending昇格'* ]]
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

@test "Guard 12b warns when cmd_save check function is added without catalog entry" {
    _mark_read_for_current_agent "$PROJECT_ROOT/scripts/cmd_save.sh"
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$PROJECT_ROOT"'/scripts/cmd_save.sh","new_string":"check_new_catalog_gap_for_test() {\n    return 0\n}\n"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'cmd_save_catalog_sync'* ]]
    [[ "$output" == *'カタログ追記が未確認'* ]]
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

@test "Guard 16: MultiEditのedits配列内repo絶対パス直書きもBLOCKする" {
    local sh_file="$TMP_DIR/test_multiedit.sh"
    _run_pre '{"tool_name":"MultiEdit","tool_input":{"file_path":"'"$sh_file"'","edits":[{"old_string":"old","new_string":"REPO='"$PROJECT_ROOT"'/scripts/lib/x.sh\n"}]}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'repoルートパス'* ]]
}

@test "Guard 16: .bash拡張子のrepo絶対パス直書きもBLOCKする" {
    local bash_file="$TMP_DIR/test_repo_path.bash"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$bash_file"'","content":"REPO='"$PROJECT_ROOT"'/scripts/lib/x.sh\n"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'repoルートパス'* ]]
}

@test "Guard 16: コメントだけのrepo絶対パスは許可する" {
    local sh_file="$TMP_DIR/test_comment_only.sh"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$sh_file"'","content":"# Location: '"$PROJECT_ROOT"'/scripts/example.sh\necho ok\n"}}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'BLOCK: 操作的オントロジー違反'* ]]
}

@test "Guard 16: camelCase toolInput/filePathでもrepo絶対パス直書きをBLOCKする" {
    local sh_file="$TMP_DIR/test_camel.sh"
    _run_pre '{"toolName":"Write","toolInput":{"filePath":"'"$sh_file"'","content":"REPO='"$PROJECT_ROOT"'/scripts/lib/x.sh\n"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'repoルートパス'* ]]
}

@test "Guard 16: model_detect.sh本体のモデル名リテラルはBLOCKしない" {
    local model_detect_file="$PROJECT_ROOT/scripts/lib/model_detect.sh"
    _mark_read_for_current_agent "$model_detect_file"
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$model_detect_file"'","new_string":"grep -E '\''(Opus|Sonnet|Haiku)[[:space:]]+[0-9]+'\''\n"}}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'BLOCK: 操作的オントロジー違反'* ]]
}

@test "Guard 17: config/projects.yaml projects path manual WriteをBLOCKする" {
    local projects_file="$TMP_DIR/config/projects.yaml"
    mkdir -p "$TMP_DIR/config"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$projects_file"'","content":"projects:\n  - id: infra\n    path: /home/simokitafresh/multi-agent-shogun\n"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'projects.yaml projects[].path変更は'* ]]
    [[ "$output" == *'手動Edit/Write禁止'* ]]
}

@test "Guard 17: config/projects.yaml path以外の手動WriteはBLOCKしない" {
    local projects_file="$TMP_DIR/config/projects.yaml"
    mkdir -p "$TMP_DIR/config"
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$projects_file"'","content":"projects:\n  - id: infra\n    name: infra\n"}}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'projects.yaml projects[].path変更は'* ]]
}

@test "Guard 17: config/cli_profiles.yaml launch_cmd manual EditをBLOCKする" {
    local profiles_file="$TMP_DIR/config/cli_profiles.yaml"
    mkdir -p "$TMP_DIR/config"
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$profiles_file"'","new_string":"profiles:\n  claude:\n    launch_cmd: /home/user/bin/claude\n"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'cli_profiles.yaml profiles[].launch_cmd変更は'* ]]
    [[ "$output" == *'/shogun-cli-switch'* ]]
}

@test "Guard 17: config/cli_profiles.yaml launch_cmd MultiEditもBLOCKする" {
    local profiles_file="$TMP_DIR/config/cli_profiles.yaml"
    mkdir -p "$TMP_DIR/config"
    _run_pre '{"tool_name":"MultiEdit","tool_input":{"file_path":"'"$profiles_file"'","edits":[{"old_string":"launch_cmd: old","new_string":"launch_cmd: codex --fast\n"}]}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *'cli_profiles.yaml profiles[].launch_cmd変更は'* ]]
}

@test "Guard 17: project_path.sh許可経路のBash payloadはPre Write/Edit hookでBLOCKしない" {
    _run_pre '{"tool_name":"Bash","tool_input":{"command":"source scripts/lib/project_path.sh && get_project_path infra"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Guard 17: shogun-cli-switch許可経路のBash payloadはPre Write/Edit hookでBLOCKしない" {
    _run_pre '{"tool_name":"Bash","tool_input":{"command":"bash scripts/switch_cli_mode.sh --help"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Guard 18: causal backlink target edit shows informational context" {
    local target_file="$TMP_DIR/docs/linked-target.md"
    local cache_file="$TMP_DIR/causal_index.tsv"
    mkdir -p "$TMP_DIR/docs"
    printf 'existing\n' > "$target_file"
    _mark_read_for_current_agent "$target_file"
    printf 'linked-target\tdocs/source-a.md\nlinked-target\tdocs/source-b.md\n' > "$cache_file"

    run bash -c 'printf "%s" "$1" | MOCK_AGENT_ID="$6" CAUSAL_INDEX_CACHE="$5" PREFLIGHT_AUTOLEARN_FILE="$3" CMD_DESIGN_QUALITY_FILE="$4" bash "$2"' _ \
        '{"tool_name":"Edit","tool_input":{"file_path":"'"$target_file"'","new_string":"updated\n"}}' \
        "$PRE_HOOK" "$TMP_AUTOLEARN" "$TMP_CMD_QUALITY" "$cache_file" "$TEST_AGENT_ID"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"additionalContext"'* ]]
    [[ "$output" == *'Guard18: 因果リンク影響範囲'* ]]
    [[ "$output" == *'docs/source-a.md'* ]]
    [[ "$output" == *'docs/source-b.md'* ]]
    [[ "$output" != *'"permissionDecision":"deny"'* ]]
}

@test "Guard 18: non backlink target edit stays silent" {
    local target_file="$TMP_DIR/docs/unlinked-target.md"
    local cache_file="$TMP_DIR/causal_index.tsv"
    mkdir -p "$TMP_DIR/docs"
    printf 'existing\n' > "$target_file"
    _mark_read_for_current_agent "$target_file"
    printf 'linked-target\tdocs/source-a.md\n' > "$cache_file"

    run bash -c 'printf "%s" "$1" | MOCK_AGENT_ID="$6" CAUSAL_INDEX_CACHE="$5" PREFLIGHT_AUTOLEARN_FILE="$3" CMD_DESIGN_QUALITY_FILE="$4" bash "$2"' _ \
        '{"tool_name":"Edit","tool_input":{"file_path":"'"$target_file"'","new_string":"updated\n"}}' \
        "$PRE_HOOK" "$TMP_AUTOLEARN" "$TMP_CMD_QUALITY" "$cache_file" "$TEST_AGENT_ID"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# === Guard 19: scripts配下 当日コミット履歴+未コミット差分表示 ===

_setup_guard19_repo() {
    local repo="$TMP_DIR/guard19_repo"
    mkdir -p "$repo/scripts"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test"
    printf '#!/bin/bash\necho v1\n' > "$repo/scripts/target.sh"
    git -C "$repo" add scripts/target.sh
    GIT_AUTHOR_DATE="2026-01-01T09:00:00" GIT_COMMITTER_DATE="2026-01-01T09:00:00" \
        git -C "$repo" commit -q -m "old baseline commit" >/dev/null
    printf '%s' "$repo"
}

@test "Guard 19: stays silent for same-day commit without a new uncommitted diff" {
    local repo gfl
    repo="$(_setup_guard19_repo)"
    gfl="$TMP_DIR/gate_fire_log.yaml"
    printf '#!/bin/bash\necho v2\n' > "$repo/scripts/target.sh"
    git -C "$repo" add scripts/target.sh
    GIT_AUTHOR_DATE="2026-03-05T02:31:00" GIT_COMMITTER_DATE="2026-03-05T02:31:00" \
        git -C "$repo" commit -q -m "same day duplicate fix" >/dev/null
    _mark_read_for_current_agent "$repo/scripts/target.sh"

    run bash -c 'printf "%s" "$1" | MOCK_AGENT_ID="$6" GUARD19_GIT_ROOT_OVERRIDE="$3" GUARD19_TODAY_OVERRIDE="$4" GATE_FIRE_LOG_FILE="$5" bash "$2"' _ \
        '{"tool_name":"Edit","tool_input":{"file_path":"'"$repo"'/scripts/target.sh","old_string":"v2","new_string":"v3"}}' \
        "$PRE_HOOK" "$repo" "2026-03-05" "$gfl" "$TEST_AGENT_ID"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$gfl" ]
}

@test "Guard 19: stays silent for uncommitted diff without a same-day commit" {
    local repo gfl
    repo="$(_setup_guard19_repo)"
    gfl="$TMP_DIR/gate_fire_log_b.yaml"
    printf '#!/bin/bash\necho dirty\n' > "$repo/scripts/target.sh"
    _mark_read_for_current_agent "$repo/scripts/target.sh"

    run bash -c 'printf "%s" "$1" | MOCK_AGENT_ID="$6" GUARD19_GIT_ROOT_OVERRIDE="$3" GUARD19_TODAY_OVERRIDE="$4" GATE_FIRE_LOG_FILE="$5" bash "$2"' _ \
        '{"tool_name":"Edit","tool_input":{"file_path":"'"$repo"'/scripts/target.sh","old_string":"v1","new_string":"v2"}}' \
        "$PRE_HOOK" "$repo" "2026-03-05" "$gfl" "$TEST_AGENT_ID"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$gfl" ]
}

@test "Guard 19: warns when same-day commit and uncommitted diff overlap" {
    local repo gfl
    repo="$(_setup_guard19_repo)"
    gfl="$TMP_DIR/gate_fire_log_overlap.yaml"
    printf '#!/bin/bash\necho v2\n' > "$repo/scripts/target.sh"
    git -C "$repo" add scripts/target.sh
    GIT_AUTHOR_DATE="2026-03-05T02:31:00" GIT_COMMITTER_DATE="2026-03-05T02:31:00" \
        git -C "$repo" commit -q -m "same day duplicate fix" >/dev/null
    printf '#!/bin/bash\necho dirty\n' > "$repo/scripts/target.sh"
    _mark_read_for_current_agent "$repo/scripts/target.sh"

    run bash -c 'printf "%s" "$1" | MOCK_AGENT_ID="$6" GUARD19_GIT_ROOT_OVERRIDE="$3" GUARD19_TODAY_OVERRIDE="$4" GATE_FIRE_LOG_FILE="$5" bash "$2"' _ \
        '{"tool_name":"Edit","tool_input":{"file_path":"'"$repo"'/scripts/target.sh","old_string":"dirty","new_string":"v3"}}' \
        "$PRE_HOOK" "$repo" "2026-03-05" "$gfl" "$TEST_AGENT_ID"

    [ "$status" -eq 0 ]
    [[ "$output" == *'Guard19: 当日変更履歴'* ]]
    [[ "$output" == *'same day duplicate fix'* ]]
    [[ "$output" == *'未コミット差分: あり'* ]]
    grep -q 'commits_today=1; uncommitted=yes' "$gfl"
}

@test "Guard 19: stays silent (no crash) when no same-day commit and no uncommitted diff" {
    local repo gfl
    repo="$(_setup_guard19_repo)"
    gfl="$TMP_DIR/gate_fire_log_c.yaml"
    _mark_read_for_current_agent "$repo/scripts/target.sh"

    run bash -c 'printf "%s" "$1" | MOCK_AGENT_ID="$6" GUARD19_GIT_ROOT_OVERRIDE="$3" GUARD19_TODAY_OVERRIDE="$4" GATE_FIRE_LOG_FILE="$5" bash "$2"' _ \
        '{"tool_name":"Edit","tool_input":{"file_path":"'"$repo"'/scripts/target.sh","old_string":"v1","new_string":"v1"}}' \
        "$PRE_HOOK" "$repo" "2026-03-05" "$gfl" "$TEST_AGENT_ID"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$gfl" ]
}

@test "Guard 19: non scripts path is ignored entirely" {
    local repo gfl
    repo="$(_setup_guard19_repo)"
    gfl="$TMP_DIR/gate_fire_log_d.yaml"
    mkdir -p "$repo/docs"
    printf 'note\n' > "$repo/docs/note.md"
    _mark_read_for_current_agent "$repo/docs/note.md"

    run bash -c 'printf "%s" "$1" | MOCK_AGENT_ID="$6" GUARD19_GIT_ROOT_OVERRIDE="$3" GUARD19_TODAY_OVERRIDE="$4" GATE_FIRE_LOG_FILE="$5" bash "$2"' _ \
        '{"tool_name":"Edit","tool_input":{"file_path":"'"$repo"'/docs/note.md","old_string":"note","new_string":"note2"}}' \
        "$PRE_HOOK" "$repo" "2026-03-05" "$gfl" "$TEST_AGENT_ID"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Guard 19: brand-new (untracked, not-yet-written) scripts file via Write does not crash" {
    local repo gfl
    repo="$(_setup_guard19_repo)"
    gfl="$TMP_DIR/gate_fire_log_e.yaml"

    run bash -c 'printf "%s" "$1" | MOCK_AGENT_ID="$5" GUARD19_GIT_ROOT_OVERRIDE="$3" GUARD19_TODAY_OVERRIDE="2026-03-05" GATE_FIRE_LOG_FILE="$4" bash "$2"' _ \
        '{"tool_name":"Write","tool_input":{"file_path":"'"$repo"'/scripts/brand_new.sh","content":"#!/bin/bash\necho new\n"}}' \
        "$PRE_HOOK" "$repo" "$gfl" "$TEST_AGENT_ID"

    [ "$status" -eq 0 ]
}

@test "Guard 19: repeated edits on the same day reuse the changed-files cache" {
    local repo gfl
    repo="$(_setup_guard19_repo)"
    gfl="$TMP_DIR/gate_fire_log_f.yaml"
    printf '#!/bin/bash\necho v2\n' > "$repo/scripts/target.sh"
    git -C "$repo" add scripts/target.sh
    GIT_AUTHOR_DATE="2026-03-05T02:31:00" GIT_COMMITTER_DATE="2026-03-05T02:31:00" \
        git -C "$repo" commit -q -m "same day duplicate fix" >/dev/null
    printf '#!/bin/bash\necho dirty\n' > "$repo/scripts/target.sh"
    _mark_read_for_current_agent "$repo/scripts/target.sh"

    run bash -c 'printf "%s" "$1" | MOCK_AGENT_ID="$6" GUARD19_GIT_ROOT_OVERRIDE="$3" GUARD19_TODAY_OVERRIDE="$4" GATE_FIRE_LOG_FILE="$5" bash "$2"' _ \
        '{"tool_name":"Edit","tool_input":{"file_path":"'"$repo"'/scripts/target.sh","old_string":"v2","new_string":"v3"}}' \
        "$PRE_HOOK" "$repo" "2026-03-05" "$gfl" "$TEST_AGENT_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *'same day duplicate fix'* ]]
    [ -f "$repo/.cache/guard19_today_changed_files.txt" ]

    run bash -c 'printf "%s" "$1" | MOCK_AGENT_ID="$6" GUARD19_GIT_ROOT_OVERRIDE="$3" GUARD19_TODAY_OVERRIDE="$4" GATE_FIRE_LOG_FILE="$5" bash "$2"' _ \
        '{"tool_name":"Edit","tool_input":{"file_path":"'"$repo"'/scripts/target.sh","old_string":"v2","new_string":"v4"}}' \
        "$PRE_HOOK" "$repo" "2026-03-05" "$gfl" "$TEST_AGENT_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *'same day duplicate fix'* ]]
}

@test "Guard 19: linked worktree preserves overlap detection" {
    local repo linked gfl
    repo="$(_setup_guard19_repo)"
    linked="$TMP_DIR/guard19_linked"
    git -C "$repo" worktree add -q -b guard19-linked "$linked"
    gfl="$TMP_DIR/gate_fire_log_linked.yaml"
    printf '#!/bin/bash\necho v2\n' > "$linked/scripts/target.sh"
    git -C "$linked" add scripts/target.sh
    GIT_AUTHOR_DATE="2026-03-05T02:31:00" GIT_COMMITTER_DATE="2026-03-05T02:31:00" \
        git -C "$linked" commit -q -m "linked same day fix" >/dev/null
    printf '#!/bin/bash\necho dirty\n' > "$linked/scripts/target.sh"
    _mark_read_for_current_agent "$linked/scripts/target.sh"

    run bash -c 'printf "%s" "$1" | MOCK_AGENT_ID="$6" GUARD19_GIT_ROOT_OVERRIDE="$3" GUARD19_TODAY_OVERRIDE="$4" GATE_FIRE_LOG_FILE="$5" bash "$2"' _ \
        '{"tool_name":"Edit","tool_input":{"file_path":"'"$linked"'/scripts/target.sh","old_string":"dirty","new_string":"v3"}}' \
        "$PRE_HOOK" "$linked" "2026-03-05" "$gfl" "$TEST_AGENT_ID"

    [ "$status" -eq 0 ]
    [[ "$output" == *'linked same day fix'* ]]
    grep -q 'commits_today=1; uncommitted=yes' "$gfl"
}
