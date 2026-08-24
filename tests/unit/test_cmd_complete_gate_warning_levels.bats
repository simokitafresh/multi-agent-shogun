#!/usr/bin/env bats
# test_cmd_complete_gate_warning_levels.bats - warning level gate behavior
# Optimized: warning判定ロジックを直接テストし、gate全体実行を回避

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    export SRC_FIELD_GET_SCRIPT="$PROJECT_ROOT/scripts/lib/field_get.sh"
    export EXTRACTED_GATE_HELPERS="$BATS_FILE_TMPDIR/cmd_complete_gate_warning_helpers.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    {
        sed -n '/^dispatch_gate_notification_async()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^send_info_cmd_notification()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^gate_clear_notify_dedup_key()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^gate_clear_notify_flag_path()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^gate_clear_notify_historical_evidence()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^gate_clear_notify_claim()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^notify_shogun_gate_clear()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^notify_karo_cmd_complete_skill_hint()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^send_clear_notifications_once()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^karo_gate_block_unread_exists()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^notify_karo_gate_block()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^notify_karo_cmd_fail()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^log_skill_execution_pass()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^level_heading()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^binary_checks_warn_reason()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^detect_task_role()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^check_how_it_works_status()/,/^}/p' "$SRC_GATE_SCRIPT"
    } > "$EXTRACTED_GATE_HELPERS"
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
        "$TEST_PROJECT/logs" \
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
mkdir -p "${SCRIPT_DIR}/queue/inbox"
if [ "$1" = "shogun" ]; then
  {
    [ -s "${SCRIPT_DIR}/queue/inbox/shogun.yaml" ] || printf 'messages:\n'
    content=${2//\'/\'\'}
    from=${4//\'/\'\'}
    type=${3//\'/\'\'}
    printf -- "- content: '%s'\n  from: '%s'\n  id: 'msg_test'\n  read: false\n  timestamp: '2099-01-01T00:00:00'\n  type: '%s'\n" "$content" "$from" "$type"
  } >> "${SCRIPT_DIR}/queue/inbox/shogun.yaml"
fi
if [ "$1" = "karo" ] && { [ "$3" = "gate_block" ] || [ "$3" = "skill_hint" ]; }; then
  {
    [ -s "${SCRIPT_DIR}/queue/inbox/karo.yaml" ] || printf 'messages:\n'
    content=${2//\'/\'\'}
    from=${4//\'/\'\'}
    type=${3//\'/\'\'}
    printf -- "- content: '%s'\n  from: '%s'\n  id: 'msg_test_%s'\n  read: false\n  timestamp: '2099-01-01T00:00:00'\n  type: '%s'\n" "$content" "$from" "$$" "$type"
  } >> "${SCRIPT_DIR}/queue/inbox/karo.yaml"
fi
EOF
    chmod +x "$TEST_PROJECT/scripts/inbox_write.sh"

    source "$SRC_FIELD_GET_SCRIPT"
    source "$EXTRACTED_GATE_HELPERS"

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
    for _ in {1..20}; do [ -s "$notify_log" ] && break; sleep 0.02; done
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
    for _ in {1..20}; do [ -s "$notify_log" ] && break; sleep 0.02; done
    grep -q "ntfy_batch:GATE CLEAR — $TEST_CMD_ID 完了:" "$notify_log"
    ! grep -q "ntfy_cmd:" "$notify_log"
}

@test "notify_shogun_gate_clear writes to shogun inbox when @agent_state=idle" {
    run notify_shogun_gate_clear "$TEST_CMD_ID" "GATE CLEAR — $TEST_CMD_ID 完了"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun inbox: OK (gate clear notify)"* ]]
    grep -q "^shogun|GATE CLEAR — $TEST_CMD_ID 完了|gate_clear|cmd_complete_gate$" "$INBOX_WRITE_LOG"
}

@test "notify_shogun_gate_clear writes to shogun inbox when @agent_state=active" {
    export TMUX_STATE="active"
    run notify_shogun_gate_clear "$TEST_CMD_ID" "GATE CLEAR — $TEST_CMD_ID 完了"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun inbox: OK (gate clear notify)"* ]]
    grep -q "^shogun|GATE CLEAR — $TEST_CMD_ID 完了|gate_clear|cmd_complete_gate$" "$INBOX_WRITE_LOG"
}

@test "notify_shogun_gate_clear dedups hotfix full id followed by short id" {
    run notify_shogun_gate_clear "cmd_karo_hotfix_ga167_lesson_health_unclassified_202607021805" "GATE CLEAR — cmd_karo_hotfix_ga167_lesson_health_unclassified_202607021805 完了"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun inbox: OK (gate clear notify)"* ]]

    run notify_shogun_gate_clear "cmd_karo_hotfix_ga167" "GATE CLEAR — cmd_karo_hotfix_ga167 完了"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun inbox: SKIP (gate clear notify dedup)"* ]]
    [ "$(grep -c '^shogun|GATE CLEAR' "$INBOX_WRITE_LOG")" -eq 1 ]
}

@test "notify_shogun_gate_clear dedups timestamped hotfix id after short id" {
    run notify_shogun_gate_clear "cmd_karo_hotfix_cmd3655_unauthorized_contrast" "GATE CLEAR — cmd_karo_hotfix_cmd3655_unauthorized_contrast 完了"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun inbox: OK (gate clear notify)"* ]]

    run notify_shogun_gate_clear "cmd_karo_hotfix_cmd3655_unauthorized_contrast_202607021724" "GATE CLEAR — cmd_karo_hotfix_cmd3655_unauthorized_contrast_202607021724 完了"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun inbox: SKIP (gate clear notify dedup)"* ]]
    [ "$(grep -c '^shogun|GATE CLEAR' "$INBOX_WRITE_LOG")" -eq 1 ]
}

@test "notify_karo_cmd_complete_skill_hint writes cmd-complete prompt to karo inbox" {
    run notify_karo_cmd_complete_skill_hint "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo /cmd-complete hint: OK"* ]]
    grep -q "^karo|GATE CLEAR — $TEST_CMD_ID 完了。/cmd-complete スキルで完了処理を実行せよ。|skill_hint|cmd_complete_gate$" "$INBOX_WRITE_LOG"
}

@test "notify_karo_gate_block writes BLOCK reason and redeploy proposal to karo inbox" {
    run notify_karo_gate_block "$TEST_CMD_ID" "missing_gates:review_gate" "review_gate"
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo gate_block notify: OK"* ]]
    grep -q "^karo|$TEST_CMD_ID gate_result: BLOCK reason=missing_gates:review_gate missing=\\[review_gate\\]。再配備提案: BLOCK理由を確認し、該当忍者へ修正再配備せよ。|gate_block|cmd_complete_gate$" "$INBOX_WRITE_LOG"
}

@test "notify_karo_gate_block suppresses same cmd_id even when reason differs" {
    export LOG_DIR="$TEST_PROJECT/logs"
    append_line_locked() {
        printf '%s\n' "$2" >> "$1"
    }

    # 1回目: 送信OK
    run notify_karo_gate_block "$TEST_CMD_ID" "reason_one:hash_abc" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo gate_block notify: OK"* ]]
    [ "$(grep -c '^karo|' "$INBOX_WRITE_LOG")" -eq 1 ]

    # 2回目: reason違い連続発火 → 未読存在のためSKIP
    run notify_karo_gate_block "$TEST_CMD_ID" "reason_two:hash_def" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo gate_block notify: SKIP (dedup — already in inbox)"* ]]
    # INBOX_WRITE_LOG には1件のみ（2件目は送信されない）
    [ "$(grep -c '^karo|' "$INBOX_WRITE_LOG")" -eq 1 ]
    grep -q 'gate: "gate_block_dedup", result: SKIP' "$LOG_DIR/gate_fire_log.yaml"
    grep -q 'detector_fp_rate=tracked' "$LOG_DIR/gate_fire_log.yaml"
}

@test "notify_karo_gate_block sends again after previous gate_block is marked read" {
    # 1回目: 送信OK
    run notify_karo_gate_block "$TEST_CMD_ID" "reason_one" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo gate_block notify: OK"* ]]

    # 家老が既読処理済みをシミュレート
    sed -i 's/read: false/read: true/' "$TEST_PROJECT/queue/inbox/karo.yaml"

    # 2回目: 既読済みのため新規BLOCKは通知される
    run notify_karo_gate_block "$TEST_CMD_ID" "reason_two" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo gate_block notify: OK"* ]]
    [ "$(grep -c '^karo|' "$INBOX_WRITE_LOG")" -eq 2 ]
}

@test "notify_karo_gate_block does not dedup a different cmd_id with a shared prefix" {
    printf "messages:\n- content: '%s gate_result: BLOCK reason=existing'\n  read: false\n  type: gate_block\n" \
        "${TEST_CMD_ID}9" > "$TEST_PROJECT/queue/inbox/karo.yaml"

    run notify_karo_gate_block "$TEST_CMD_ID" "new_reason" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo gate_block notify: OK"* ]]
    [ "$(grep -c '^karo|' "$INBOX_WRITE_LOG")" -eq 1 ]
}

@test "notify_karo_cmd_fail writes FAIL report and redeploy proposal to karo inbox" {
    run notify_karo_cmd_fail "$TEST_CMD_ID" "sasuke" "$REPORT_FILE" "binary_checks_fail:AC1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo cmd_fail notify: OK"* ]]
    grep -q "^karo|$TEST_CMD_ID gate_result: FAIL ninja=sasuke report=$(basename "$REPORT_FILE") reason=binary_checks_fail:AC1。再配備提案: FAIL報告を確認し、修正タスクを再配備せよ。|gate_fail|cmd_complete_gate$" "$INBOX_WRITE_LOG"
}

@test "cmd_complete_gate queues post-CLEAR follow-up before terminal clear notifications" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys

text = open(sys.argv[1], encoding="utf-8").read()
clear = text.index('    echo "GATE CLEAR: cmd完了許可"')
queue_heading = text.index(
    '    echo "Durable writer/runtime publication (post-CLEAR follow-up):"',
    clear,
)
queue_call = text.index('    queue_postclear_publication_followup', queue_heading)
terminal_notify = text.index(
    'send_clear_notifications_once "$CMD_ID" "GATE CLEAR terminal"',
    queue_call,
)

# GATE CLEAR is durable before the post-CLEAR follow-up is queued, and the
# terminal notification follows the queue proof without waiting for external
# push/runtime completion.
assert clear < queue_heading < queue_call < terminal_notify
terminal_queue_section = text[queue_heading:terminal_notify]
assert 'publish_postclear_runtime_deltas' not in terminal_queue_section
assert text.count('send_clear_notifications_once "$CMD_ID" "GATE CLEAR terminal"') == 1
PY
    [ "$status" -eq 0 ]
}

@test "cmd_complete_gate invokes karo gate block notify in GATE BLOCK section" {
    run bash -lc "grep -c 'notify_karo_gate_block \"\\\$CMD_ID\" \"\\\$block_reason\" \"\\\$missing_list\"' '$SRC_GATE_SCRIPT'"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "cmd_complete_gate invokes karo cmd fail notify from FAIL verdict path" {
    run bash -lc "grep -c 'notify_karo_cmd_fail \"\\\$CMD_ID\" \"\\\$ninja_name\" \"\\\$report_file\" \"binary_checks_fail:' '$SRC_GATE_SCRIPT'"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "cmd_complete_gate records cmd-complete PASS in both GATE CLEAR sections" {
    run bash -lc "grep -c 'log_skill_execution_pass \"cmd-complete\" \"cmd_complete_gate\" \"\\\$CMD_ID\"' '$SRC_GATE_SCRIPT'"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
}

@test "GATE CLEAR cmd_quality_log runs synchronously and reports OK/WARN" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
start = text.index("Cmd quality log (GATE CLEAR):")
end = text.index("Gunshi verdict update to cmd_design_quality", start)
section = text[start:end]

assert 'review_approvals/karo_rework.seen' in section
assert '_quality_karo_rework="yes"' in section
assert "if bash \"$SCRIPT_DIR/scripts/cmd_quality_log.sh\" \"$CMD_ID\" \"CLEAR\" \"$_quality_karo_rework\" \"0\" >> \"$LOG_DIR/cmd_complete_gate_async.log\" 2>&1; then" in section
assert "cmd_quality_log: OK" in section
assert "[INFO] cmd_quality_log: WARN (logging failed, non-blocking)" in section
assert "cmd_quality_log: queued (async)" not in section
PY
    [ "$status" -eq 0 ]
}

@test "log_skill_execution_pass writes PASS to skill_execution_log" {
    mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/skills/cmd-complete"
    cat > "$SCRIPT_DIR/scripts/skill_execution_log.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" >> "$SKILL_EXECUTION_LOG_FILE"
EOF
    chmod +x "$SCRIPT_DIR/scripts/skill_execution_log.sh"
    export SKILL_EXECUTION_LOG_FILE="$TEST_TMPDIR/skill_execution_log.txt"
    export SKILL_EXECUTION_PASS_LOG_ASYNC=0
    export AGENT_ID="karo"

    run log_skill_execution_pass "cmd-complete" "cmd_complete_gate" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    for _ in {1..20}; do
        [ -f "$SKILL_EXECUTION_LOG_FILE" ] && break
        sleep 0.05
    done
    grep -q "^cmd-complete|karo|PASS|cmd_complete_gate PASS|cmd_complete_gate|$TEST_CMD_ID|$SCRIPT_DIR/skills/cmd-complete/SKILL.md$" "$SKILL_EXECUTION_LOG_FILE"
}

@test "cmd_complete_gate keeps emergency wait but normal clear exits after queueing async jobs" {
    run bash -lc "grep -c '^    wait || true$' '$SRC_GATE_SCRIPT'"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
    run bash -lc "grep -q 'async jobs: queued' '$SRC_GATE_SCRIPT'"
    [ "$status" -eq 0 ]
}

@test "cmd_complete_gate keeps existing harmful threshold auto-deprecate path" {
    run bash -lc "grep -c 'harmful >= 5 && harmful > helpful' '$SRC_GATE_SCRIPT'"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
}

@test "cmd_complete_gate adds useful rate threshold auto-deprecate path" {
    run bash -lc "grep -q 'Auto-deprecate check (useful rate threshold)' '$SRC_GATE_SCRIPT' && grep -q 'helpful \\* 5 <= total' '$SRC_GATE_SCRIPT' && grep -q 'total >= 10' '$SRC_GATE_SCRIPT' && grep -q 'AUTO-DEPRECATE(useful-rate)' '$SRC_GATE_SCRIPT'"
    [ "$status" -eq 0 ]
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

# ─── cmd_karo_hotfix_gate_clear_notify_dedup_20260728: 永続flag冪等境界のtest群 ───
# 旧dedup(live inboxのみgrep)はarchive後に失効し重複配送した(cmd_3513/3869/4122で実測)。
# queue/gates/{key}/notify_{recipient}.doneへ移行後の性質を隔離fixtureで検証する。

@test "notify_shogun_gate_clear suppresses resend after the live inbox message is archived away" {
    run notify_shogun_gate_clear "$TEST_CMD_ID" "GATE CLEAR — $TEST_CMD_ID 完了"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun inbox: OK (gate clear notify)"* ]]

    # inbox_archive.shが既読メッセージをlive inboxから退避する状況を模す
    rm -f "$TEST_PROJECT/queue/inbox/shogun.yaml"

    run notify_shogun_gate_clear "$TEST_CMD_ID" "GATE CLEAR — $TEST_CMD_ID 完了"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun inbox: SKIP (gate clear notify dedup)"* ]]
    [ "$(grep -c '^shogun|GATE CLEAR' "$INBOX_WRITE_LOG")" -eq 1 ]
}

@test "notify_karo_cmd_complete_skill_hint suppresses resend after the live inbox message is archived away" {
    run notify_karo_cmd_complete_skill_hint "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo /cmd-complete hint: OK"* ]]

    rm -f "$TEST_PROJECT/queue/inbox/karo.yaml"

    run notify_karo_cmd_complete_skill_hint "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo /cmd-complete hint: SKIP (dedup — already in inbox)"* ]]
    [ "$(grep -c '^karo|GATE CLEAR' "$INBOX_WRITE_LOG")" -eq 1 ]
}

@test "notify_shogun_gate_clear delivers once per distinct cmd_id without cross-suppression" {
    run notify_shogun_gate_clear "cmd_dedup_test_1001" "GATE CLEAR — cmd_dedup_test_1001 完了"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun inbox: OK (gate clear notify)"* ]]

    run notify_shogun_gate_clear "cmd_dedup_test_1002" "GATE CLEAR — cmd_dedup_test_1002 完了"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun inbox: OK (gate clear notify)"* ]]

    [ "$(grep -c '^shogun|GATE CLEAR — cmd_dedup_test_1001' "$INBOX_WRITE_LOG")" -eq 1 ]
    [ "$(grep -c '^shogun|GATE CLEAR — cmd_dedup_test_1002' "$INBOX_WRITE_LOG")" -eq 1 ]
}

@test "notify_shogun_gate_clear retries successfully after a prior send failure rolls back its own claim" {
    cat > "$TEST_PROJECT/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_PROJECT/scripts/inbox_write.sh"

    run notify_shogun_gate_clear "$TEST_CMD_ID" "GATE CLEAR — $TEST_CMD_ID 完了"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun inbox: WARN (gate clear notify failed, non-blocking)"* ]]
    [ ! -f "$(gate_clear_notify_flag_path shogun "$TEST_CMD_ID")" ]
    [ ! -s "$INBOX_WRITE_LOG" ]

    cat > "$TEST_PROJECT/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "${INBOX_WRITE_LOG}"
mkdir -p "${SCRIPT_DIR}/queue/inbox"
if [ "$1" = "shogun" ]; then
  {
    [ -s "${SCRIPT_DIR}/queue/inbox/shogun.yaml" ] || printf 'messages:\n'
    printf -- "- content: '%s'\n  from: '%s'\n  id: 'msg_test'\n  read: false\n  timestamp: '2099-01-01T00:00:00'\n  type: '%s'\n" "$2" "$4" "$3"
  } >> "${SCRIPT_DIR}/queue/inbox/shogun.yaml"
fi
EOF
    chmod +x "$TEST_PROJECT/scripts/inbox_write.sh"

    run notify_shogun_gate_clear "$TEST_CMD_ID" "GATE CLEAR — $TEST_CMD_ID 完了"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun inbox: OK (gate clear notify)"* ]]
    [ -f "$(gate_clear_notify_flag_path shogun "$TEST_CMD_ID")" ]
    [ "$(grep -c '^shogun|GATE CLEAR' "$INBOX_WRITE_LOG")" -eq 1 ]
}

@test "notify_shogun_gate_clear delivers exactly once for the same cmd_id under concurrent invocations" {
    local pids=()
    local i
    for i in 1 2 3 4 5 6 7 8; do
        ( notify_shogun_gate_clear "$TEST_CMD_ID" "GATE CLEAR — $TEST_CMD_ID 完了" >/dev/null 2>&1 ) &
        pids+=("$!")
    done
    for i in "${pids[@]}"; do
        wait "$i"
    done

    [ "$(grep -c '^shogun|GATE CLEAR' "$INBOX_WRITE_LOG")" -eq 1 ]
    [ -f "$(gate_clear_notify_flag_path shogun "$TEST_CMD_ID")" ]
}

@test "notify_karo_cmd_complete_skill_hint delivers exactly once for the same cmd_id under concurrent invocations" {
    local pids=()
    local i
    for i in 1 2 3 4 5 6 7 8; do
        ( notify_karo_cmd_complete_skill_hint "$TEST_CMD_ID" >/dev/null 2>&1 ) &
        pids+=("$!")
    done
    for i in "${pids[@]}"; do
        wait "$i"
    done

    [ "$(grep -c '^karo|GATE CLEAR' "$INBOX_WRITE_LOG")" -eq 1 ]
    [ -f "$(gate_clear_notify_flag_path karo "$TEST_CMD_ID")" ]
}

@test "gate_clear_notify_migration_backfill retroactively flags a cmd already delivered via the live inbox before this fix" {
    mkdir -p "$TEST_PROJECT/queue/inbox"
    cat > "$TEST_PROJECT/queue/inbox/shogun.yaml" <<EOF
messages:
- content: 'GATE CLEAR — $TEST_CMD_ID 完了'
  from: 'cmd_complete_gate'
  id: 'msg_pre_migration'
  read: true
  timestamp: '2026-07-01T00:00:00'
  type: 'gate_clear'
EOF
    [ ! -f "$(gate_clear_notify_flag_path shogun "$TEST_CMD_ID")" ]

    run notify_shogun_gate_clear "$TEST_CMD_ID" "GATE CLEAR — $TEST_CMD_ID 完了"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun inbox: SKIP (gate clear notify dedup)"* ]]
    [ ! -s "$INBOX_WRITE_LOG" ]
    [ -f "$(gate_clear_notify_flag_path shogun "$TEST_CMD_ID")" ]
}

@test "gate_clear_notify_migration_backfill retroactively flags a cmd already delivered via an archived inbox before this fix" {
    mkdir -p "$TEST_PROJECT/archive/inbox"
    cat > "$TEST_PROJECT/archive/inbox/karo_20260601.yaml" <<EOF
messages:
- content: 'GATE CLEAR — $TEST_CMD_ID 完了。/cmd-complete スキルで完了処理を実行せよ。'
  from: 'cmd_complete_gate'
  id: 'msg_pre_migration_archived'
  read: true
  timestamp: '2026-06-01T00:00:00'
  type: 'skill_hint'
EOF
    [ ! -f "$(gate_clear_notify_flag_path karo "$TEST_CMD_ID")" ]

    run notify_karo_cmd_complete_skill_hint "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo /cmd-complete hint: SKIP (dedup — already in inbox)"* ]]
    [ ! -s "$INBOX_WRITE_LOG" ]
    [ -f "$(gate_clear_notify_flag_path karo "$TEST_CMD_ID")" ]
}
