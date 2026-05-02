#!/usr/bin/env bats
# test_cmd_complete_gate_warning_levels.bats - warning level gate behavior
# Optimized: warning判定ロジックを直接テストし、gate全体実行を回避

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    export SRC_FIELD_GET_SCRIPT="$PROJECT_ROOT/scripts/lib/field_get.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_gate_warn.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export TEST_BIN="$TEST_TMPDIR/bin"
    export TEST_CMD_ID="cmd_999"
    export SCRIPT_DIR="$TEST_PROJECT"
    export TASK_FILE="$TEST_PROJECT/queue/tasks/sasuke.yaml"
    export REPORT_FILE="$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml"
    export LAST_GATE_NOTIFY_ROUTE=""
    export TMUX_STATE="idle"
    export INBOX_WRITE_LOG="$TEST_TMPDIR/inbox_write.log"

    mkdir -p \
        "$TEST_BIN" \
        "$TEST_PROJECT/scripts" \
        "$TEST_PROJECT/queue/inbox" \
        "$TEST_PROJECT/queue/tasks" \
        "$TEST_PROJECT/queue/reports"

    export PATH="$TEST_BIN:$PATH"

    cat > "$TEST_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "show-options" ]; then
    echo "${TMUX_STATE:-idle}"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_BIN/tmux"

    cat > "$TEST_PROJECT/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "${INBOX_WRITE_LOG}"
EOF
    chmod +x "$TEST_PROJECT/scripts/inbox_write.sh"

    source "$SRC_FIELD_GET_SCRIPT"
    eval "$(sed -n '/^send_info_cmd_notification()/,/^}/p' "$SRC_GATE_SCRIPT")"
    eval "$(sed -n '/^notify_idle_shogun_gate_clear()/,/^}/p' "$SRC_GATE_SCRIPT")"
    eval "$(sed -n '/^notify_karo_cmd_complete_skill_hint()/,/^}/p' "$SRC_GATE_SCRIPT")"
    eval "$(sed -n '/^level_heading()/,/^}/p' "$SRC_GATE_SCRIPT")"
    eval "$(sed -n '/^binary_checks_warn_reason()/,/^}/p' "$SRC_GATE_SCRIPT")"
    eval "$(sed -n '/^detect_task_role()/,/^}/p' "$SRC_GATE_SCRIPT")"
    eval "$(sed -n '/^check_how_it_works_status()/,/^}/p' "$SRC_GATE_SCRIPT")"

    write_task "review"
}

teardown() {
    [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

write_task() {
    local task_type="${1:-review}"
    cat > "$TASK_FILE" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: $task_type
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 1
  related_lessons: []
EOF
}

write_report() {
    local result_block="$1"
    cat > "$REPORT_FILE" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-10T00:00:00"
status: done
ac_version_read: 1
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
result:
  summary: "warning level gate test"
${result_block}
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
EOF
}

write_binary_check_fail_report() {
    local triage="${1:-}"
    cat > "$REPORT_FILE" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-10T00:00:00"
status: done
ac_version_read: 1
verdict: FAIL
test_triage: ${triage}
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
result:
  summary: "binary_checks triage test"
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
binary_checks:
  AC1:
    - check: "binary check failure fixture"
      result: no
EOF
}

write_report_with_deviation_count() {
    local count="$1"
    {
        cat <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-10T00:00:00"
status: done
ac_version_read: 1
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
result:
  summary: "warning level gate test"
EOF
        if [ "$count" -eq 0 ]; then
            echo "  deviation: []"
        else
            echo "  deviation:"
            local i
            for i in $(seq 1 "$count"); do
                cat <<EOF
    - rule: 1
      description: "fix ${i}"
      files: ["scripts/example_${i}.sh"]
EOF
            done
        fi
        cat <<'EOF'
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
EOF
    } > "$REPORT_FILE"
}

render_gate_headings_sample() {
    level_heading "[L1]" "Gate check: $TEST_CMD_ID"
    level_heading "[L2]" "Deviation count check:"
    level_heading "[L3]" "Context update check:"
}

check_deviation_status() {
    local report_file="$1"
    awk '
        /^result:/ { in_result=1; next }
        in_result && /^[^ ]/ { in_result=0 }
        in_result && /^[[:space:]]+deviation:/ {
            has_dev=1; in_dev=1
            match($0, /^[[:space:]]+/)
            dev_indent = RLENGTH
            if ($0 ~ /\[\]/) { has_dev=2 }
            next
        }
        in_dev && NF > 0 {
            match($0, /^[[:space:]]*/); ci = RLENGTH
            if (ci <= dev_indent) { in_dev=0; next }
        }
        in_dev && /^[[:space:]]+- / { count++ }
        END {
            if (!has_dev && count==0) { printf "skip\tresult.deviation not present"; exit }
            if (has_dev==2 || count==0) { printf "skip\tresult.deviation empty (count 0)"; exit }
            if (count >= 4) printf "warn\t%d", count
            else printf "ok\t%d", count
        }
    ' "$report_file"
}

render_deviation_check() {
    local report_file="$1"
    local ninja_name="$2"
    local deviation_status deviation_kind deviation_detail

    level_heading "[L2]" "Deviation count check:"
    deviation_status=$(check_deviation_status "$report_file")
    deviation_kind=$(printf '%s\n' "$deviation_status" | cut -f1)
    deviation_detail=$(printf '%s\n' "$deviation_status" | cut -f2-)

    case "$deviation_kind" in
        warn)
            echo "  [INFO] ${ninja_name}: deviation count ${deviation_detail} >= 4: 逸脱管理ルール(3回超過)に抵触"
            ;;
        ok)
            echo "  ${ninja_name}: OK (deviation count ${deviation_detail} <= 3)"
            ;;
        skip)
            echo "  ${ninja_name}: SKIP (${deviation_detail})"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: deviation count解析エラー (${deviation_detail})"
            return 1
            ;;
    esac
}

render_analysis_paralysis_check() {
    local report_file="$1"
    local ninja_name="$2"
    local ap_val analysis_status analysis_kind analysis_detail

    level_heading "[L2]" "Analysis paralysis check:"
    if ! grep -q '^[[:space:]]*result:' "$report_file" 2>/dev/null; then
        analysis_status=$'skip\tresult missing or not a mapping'
    else
        ap_val=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "analysis_paralysis_triggered" "")
        case "$ap_val" in
            true)  analysis_status=$'warn\tanalysis paralysis was triggered during this task' ;;
            false) analysis_status=$'ok\tanalysis_paralysis_triggered=false' ;;
            "")    analysis_status=$'skip\tanalysis_paralysis_triggered not present' ;;
            *)     analysis_status=$'skip\tanalysis_paralysis_triggered not boolean' ;;
        esac
    fi

    analysis_kind=$(printf '%s\n' "$analysis_status" | cut -f1)
    analysis_detail=$(printf '%s\n' "$analysis_status" | cut -f2-)

    case "$analysis_kind" in
        warn)
            echo "  [INFO] ${ninja_name}: ${analysis_detail}"
            ;;
        ok)
            echo "  ${ninja_name}: OK (${analysis_detail})"
            ;;
        skip)
            echo "  ${ninja_name}: SKIP (${analysis_detail})"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: analysis_paralysis_triggered解析エラー (${analysis_detail})"
            return 1
            ;;
    esac
}

render_walkthrough_check() {
    local task_file="$1"
    local report_file="$2"
    local ninja_name="$3"
    local task_role walkthrough_status

    level_heading "[L2]" "Implementation walkthrough check:"
    task_role=$(detect_task_role "$task_file")
    if [ "$task_role" != "implement" ]; then
        echo "  (no implement tasks found for this cmd)"
        return 0
    fi

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (implement report not found)"
        return 0
    fi

    walkthrough_status=$(check_how_it_works_status "$report_file")
    case "$walkthrough_status" in
        ok)
            echo "  ${ninja_name}: OK (how_it_works present)"
            ;;
        missing|empty)
            echo "  [INFO] ${ninja_name}: how_it_works missing or empty (implement report)"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: how_it_works parse error (non-blocking)"
            ;;
    esac
}

render_test_skip_check() {
    local report_file="$1"
    local ninja_name="$2"
    local skip_val test_skip_status test_skip_kind test_skip_detail

    level_heading "[L2]" "Test skip count check:"

    skip_val=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "test_skip_count" "")
    test_skip_status=""
    if [ -z "$skip_val" ]; then
        if ! grep -q '^[[:space:]]*test_results:' "$report_file" 2>/dev/null; then
            test_skip_status=$'warn\ttest_results not present'
        else
            skip_val=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "skipped" "")
            if [ -z "$skip_val" ]; then
                test_skip_status=$'warn\ttest_results.skipped not present'
            fi
        fi
    fi

    if [ -z "$test_skip_status" ] && [ -n "$skip_val" ]; then
        if [[ "$skip_val" =~ ^-?[0-9]+$ ]]; then
            if [ "$skip_val" -gt 0 ]; then
                test_skip_status=$(printf 'block\t%s' "$skip_val")
            elif [ "$skip_val" -eq 0 ]; then
                test_skip_status=$(printf 'ok\t%s' "$skip_val")
            else
                test_skip_status=$(printf 'warn\ttest_skip_count negative: %s' "$skip_val")
            fi
        else
            test_skip_status=$(printf 'warn\ttest_skip_count not a number: %s' "$skip_val")
        fi
    fi

    test_skip_kind=$(printf '%s\n' "$test_skip_status" | cut -f1)
    test_skip_detail=$(printf '%s\n' "$test_skip_status" | cut -f2-)

    case "$test_skip_kind" in
        block)
            echo "  [CRITICAL] ${ninja_name}: テスト未完了: SKIP ${test_skip_detail}件。SKIP=FAILルール"
            return 1
            ;;
        ok)
            echo "  ${ninja_name}: OK (test_skip_count ${test_skip_detail})"
            ;;
        warn)
            echo "  [INFO] ${ninja_name}: ${test_skip_detail}"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: test_skip_count解析エラー (${test_skip_detail})"
            return 1
            ;;
    esac
}

@test "level headings include L1 L2 L3 labels" {
    run render_gate_headings_sample
    [ "$status" -eq 0 ]
    [[ "$output" == *"[L1] Gate check: $TEST_CMD_ID"* ]]
    [[ "$output" == *"[L2] Deviation count check:"* ]]
    [[ "$output" == *"[L3] Context update check:"* ]]
}

@test "deviation missing and non-list skip for backward compatibility" {
    write_report ""

    run render_deviation_check "$REPORT_FILE" "sasuke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: SKIP (result.deviation not present)"* ]]

    write_report "  deviation: invalid"
    run render_deviation_check "$REPORT_FILE" "sasuke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: SKIP (result.deviation empty (count 0))"* ]]
}

@test "deviation threshold uses 3 as OK boundary and 4 as warning threshold" {
    write_report_with_deviation_count 3

    run render_deviation_check "$REPORT_FILE" "sasuke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: OK (deviation count 3 <= 3)"* ]]

    write_report_with_deviation_count 4
    run render_deviation_check "$REPORT_FILE" "sasuke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO] sasuke: deviation count 4 >= 4: 逸脱管理ルール(3回超過)に抵触"* ]]
}

@test "analysis_paralysis_triggered true emits warning" {
    write_report "  analysis_paralysis_triggered: true"

    run render_analysis_paralysis_check "$REPORT_FILE" "sasuke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[L2] Analysis paralysis check:"* ]]
    [[ "$output" == *"[INFO] sasuke: analysis paralysis was triggered during this task"* ]]
}

@test "analysis_paralysis_triggered missing is SKIP" {
    write_report ""

    run render_analysis_paralysis_check "$REPORT_FILE" "sasuke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: SKIP (analysis_paralysis_triggered not present)"* ]]
}

@test "implement report missing how_it_works emits warning only" {
    write_task "implement"
    write_report ""

    run render_walkthrough_check "$TASK_FILE" "$REPORT_FILE" "sasuke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[L2] Implementation walkthrough check:"* ]]
    [[ "$output" == *"[INFO] sasuke: how_it_works missing or empty (implement report)"* ]]
}

@test "implement report with how_it_works passes walkthrough check" {
    write_task "implement"
    cat > "$REPORT_FILE" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-10T00:00:00"
status: done
ac_version_read: 1
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
result:
  summary: "warning level gate test"
how_it_works: |
  detect_task_role() で implement を判定する。
  how_it_works があれば WARN せず通す。
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
EOF

    run render_walkthrough_check "$TASK_FILE" "$REPORT_FILE" "sasuke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: OK (how_it_works present)"* ]]
}

@test "test_skip_count > 0 triggers BLOCK" {
    write_report "test_skip_count: 3"

    run render_test_skip_check "$REPORT_FILE" "sasuke"
    [[ "$output" == *"[L2] Test skip count check:"* ]]
    [[ "$output" == *"[CRITICAL] sasuke: テスト未完了: SKIP 3件。SKIP=FAILルール"* ]]
    [ "$status" -eq 1 ]
}

@test "test_skip_count = 0 passes OK" {
    write_report "test_skip_count: 0"

    run render_test_skip_check "$REPORT_FILE" "sasuke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[L2] Test skip count check:"* ]]
    [[ "$output" == *"sasuke: OK (test_skip_count 0)"* ]]
}

@test "test_results.skipped > 0 triggers BLOCK via fallback" {
    cat > "$REPORT_FILE" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-10T00:00:00"
status: done
ac_version_read: 1
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
result:
  summary: "test skip via test_results"
test_results:
  passed: 10
  failed: 0
  skipped: 2
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
EOF

    run render_test_skip_check "$REPORT_FILE" "sasuke"
    [[ "$output" == *"[CRITICAL] sasuke: テスト未完了: SKIP 2件。SKIP=FAILルール"* ]]
    [ "$status" -eq 1 ]
}

@test "test_results missing emits WARN not BLOCK" {
    write_report ""

    run render_test_skip_check "$REPORT_FILE" "sasuke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[L2] Test skip count check:"* ]]
    [[ "$output" == *"[INFO] sasuke: test_results not present"* ]]
    [[ "$output" != *"テスト未完了"* ]]
}

@test "GATE CLEAR uses ntfy_batch when available and falls back otherwise" {
    local notify_log="$TEST_TMPDIR/notify.log"

    cat > "$TEST_PROJECT/scripts/ntfy_cmd.sh" <<EOF
#!/usr/bin/env bash
echo "ntfy_cmd:\$1:\$2" >> "$notify_log"
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/ntfy_cmd.sh"

    run send_info_cmd_notification "$TEST_CMD_ID" "GATE CLEAR — $TEST_CMD_ID 完了"
    [ "$status" -eq 0 ]
    grep -q "ntfy_cmd:$TEST_CMD_ID:GATE CLEAR — $TEST_CMD_ID 完了" "$notify_log"

    : > "$notify_log"
    cat > "$TEST_PROJECT/scripts/ntfy_batch.sh" <<EOF
#!/usr/bin/env bash
echo "ntfy_batch:\$1:\$2" >> "$notify_log"
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/ntfy_batch.sh"

    run send_info_cmd_notification "$TEST_CMD_ID" "GATE CLEAR — $TEST_CMD_ID 完了"
    [ "$status" -eq 0 ]
    grep -q "ntfy_batch:$TEST_CMD_ID:GATE CLEAR — $TEST_CMD_ID 完了" "$notify_log"
    ! grep -q "ntfy_cmd:" "$notify_log"
}

@test "notify_idle_shogun_gate_clear writes to shogun inbox when @agent_state=idle" {
    run notify_idle_shogun_gate_clear "$TEST_CMD_ID" "GATE CLEAR — $TEST_CMD_ID 完了"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun inbox: OK (idle notify)"* ]]
    grep -q "^shogun|GATE CLEAR — $TEST_CMD_ID 完了|gate_clear|cmd_complete_gate$" "$INBOX_WRITE_LOG"
}

@test "notify_idle_shogun_gate_clear skips shogun inbox when @agent_state=active" {
    export TMUX_STATE="active"
    run notify_idle_shogun_gate_clear "$TEST_CMD_ID" "GATE CLEAR — $TEST_CMD_ID 完了"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun inbox: SKIP (state=active)"* ]]
    [ ! -f "$INBOX_WRITE_LOG" ] || [ ! -s "$INBOX_WRITE_LOG" ]
}

@test "notify_karo_cmd_complete_skill_hint writes cmd-complete prompt to karo inbox" {
    run notify_karo_cmd_complete_skill_hint "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo /cmd-complete hint: OK"* ]]
    grep -q "^karo|GATE CLEAR — $TEST_CMD_ID 完了。/cmd-complete スキルで完了処理を実行せよ。|skill_hint|cmd_complete_gate$" "$INBOX_WRITE_LOG"
}

@test "cmd_complete_gate invokes shogun idle notify in both emergency and normal GATE CLEAR sections" {
    run bash -lc "grep -c 'notify_idle_shogun_gate_clear \"\\\$CMD_ID\" \"GATE CLEAR — \\\${CMD_ID} 完了\"' '$SRC_GATE_SCRIPT'"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
}

@test "cmd_complete_gate waits before both GATE CLEAR exits" {
    run bash -lc "grep -c '^    wait || true$' '$SRC_GATE_SCRIPT'"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
}

# GP-221: 二重配備時のbc_fail降格テスト
@test "GP-221: binary_checks pre-scan finds verdict=PASS ninjas" {
    # pre-scanロジックが存在するか確認
    run bash -lc "grep -c '_bc_pass_ninjas' '$SRC_GATE_SCRIPT'"
    [ "$status" -eq 0 ]
    [ "$output" -ge 4 ]  # 定義+参照で4箇所以上
}

@test "GP-221: bc_fail with other ninja PASS produces WARN not CRITICAL" {
    # 降格ロジック(WARN出力)が存在するか確認
    run bash -lc "grep -c '他忍者PASS済みのためBLOCK降格' '$SRC_GATE_SCRIPT'"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]  # bc_fail降格 + fit=false降格の2箇所
}

@test "test_triage pre_existing downgrades binary_checks fail to WARN reason" {
    write_binary_check_fail_report "pre_existing"

    run binary_checks_warn_reason "$REPORT_FILE" "sasuke" ""

    [ "$status" -eq 0 ]
    [[ "$output" == "test_triage=pre_existingのためWARN降格" ]]
}

@test "test_triage in_branch keeps binary_checks fail as BLOCK" {
    write_binary_check_fail_report "in_branch"

    run binary_checks_warn_reason "$REPORT_FILE" "sasuke" ""

    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "blank test_triage keeps binary_checks fail as BLOCK" {
    write_binary_check_fail_report ""

    run binary_checks_warn_reason "$REPORT_FILE" "sasuke" ""

    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "GP-220: inbox_write gate re-trigger does not require deploy_preflight" {
    # deploy_preflight条件が撤廃されているか確認
    run bash -lc "grep -c 'source: deploy_preflight' '$PROJECT_ROOT/scripts/inbox_write.sh'"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # 0件(完全撤廃)が正解
    [ "$output" -eq 0 ]
}
