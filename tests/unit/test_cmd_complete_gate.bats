#!/usr/bin/env bats
# test_cmd_complete_gate.bats - cmd_complete_gate.sh partial unit tests
# Optimized: gate全体実行をやめ、重い責務を関数/局所フェーズ単位で直接検証する

load '../helpers/cmd_gate_scaffold'

setup_file() {
    cmd_gate_setup_file
    export SRC_NORMALIZE_SCRIPT="$PROJECT_ROOT/scripts/lib/normalize_report.sh"
    [ -f "$SRC_NORMALIZE_SCRIPT" ] || return 1

    # Extract function bodies once to $BATS_FILE_TMPDIR (avoids per-test sed overhead)
    export GATE_HELPERS_FILE="$BATS_FILE_TMPDIR/gate_helpers.sh"
    {
        sed -n '/^record_block_reason()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^append_line_locked()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^log_gate_stderr_file()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^level_heading()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^check_context_update()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^auto_update_context_last_updated_for_changes()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^resolve_report_file()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^update_lesson_impact_tsv()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^append_lesson_tracking()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^binary_checks_warn_reason()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^is_lessons_useful_empty_warn_task_type()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^handle_empty_lessons_useful_check()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^_check_lc_found()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^preflight_gate_flags()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^collect_report_modified_files()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^collect_cmd_command_file_refs()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^collect_report_verified_existing_deps()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^check_command_files_modified_coverage()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^cmd_requires_cdp_production_check()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^run_cdp_production_check()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^append_codd_registry_entry()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^run_codd_propagate_update()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^normalize_block_reason_to_workaround_categories()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        sed -n '/^update_karo_workaround_resolutions()/,/^}/p' "$SRC_GATE_SCRIPT"
        printf '\n'
        SRC_GATE_SCRIPT="$SRC_GATE_SCRIPT" python3 - <<'PY'
import os
from pathlib import Path

text = Path(os.environ["SRC_GATE_SCRIPT"]).read_text(encoding="utf-8")
start = text.index("write_l6_horizontal_level5_insights()")
end = text.index("\n# ─── changelog自動記録関数", start)
print(text[start:end])
PY
    } > "$GATE_HELPERS_FILE"
}

@test "auto_resolve_cmd_related_insights resolves pending insights that mention cmd_id" {
    export INSIGHTS_FILE="$TEST_PROJECT/queue/insights.yaml"
    cat > "$INSIGHTS_FILE" <<EOF
insights:
- id: INS-CMD-MATCH
  ts: "2026-05-15T00:00:00+09:00"
  insight: "source_cmd=$TEST_CMD_ID のLevel5候補"
  priority: "medium"
  source: "cmd_complete_gate:l6_horizontal:$TEST_CMD_ID"
  status: pending
- id: INS-OTHER
  ts: "2026-05-15T00:00:01+09:00"
  insight: "別cmd"
  priority: "medium"
  source: "manual"
  status: pending
EOF
    cp "$PROJECT_ROOT/scripts/insight_write.sh" "$TEST_PROJECT/scripts/insight_write.sh"
    chmod +x "$TEST_PROJECT/scripts/insight_write.sh"

    run auto_resolve_cmd_related_insights "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"resolved: 1 cmd-related insight(s)"* ]]

    python3 - <<PY
import yaml
data = yaml.safe_load(open("$INSIGHTS_FILE"))
rows = {e["id"]: e for e in data["insights"]}
assert rows["INS-CMD-MATCH"]["status"] == "done"
assert rows["INS-OTHER"]["status"] == "pending"
PY
}

@test "auto_resolve_cmd_related_insights logs parser stderr for unreadable insights path" {
    export INSIGHTS_FILE="$TEST_PROJECT/queue/insights_as_dir.yaml"
    mkdir -p "$INSIGHTS_FILE"
    cp "$PROJECT_ROOT/scripts/insight_write.sh" "$TEST_PROJECT/scripts/insight_write.sh"
    chmod +x "$TEST_PROJECT/scripts/insight_write.sh"

    run auto_resolve_cmd_related_insights "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"resolved: 0 cmd-related insight(s)"* ]]
    grep -F "auto_resolve_cmd_related_insights parse:" "$TEST_PROJECT/logs/cmd_complete_gate_stderr.log"
}

@test "cmd_complete_gate protects shared file writes with lock_path flock" {
    run grep -F 'append_line_locked "$GATE_METRICS_LOG"' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]

    run grep -F '200>"$(lock_path "$tracking_file")"' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]

    run grep -F '200>"$(lock_path "$impact_file")"' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]

    run grep -F '200>"$(lock_path "$DASHBOARD")"' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]

    run grep -F '200>"$(lock_path "$_GV_DQ_FILE")"' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]

    run grep -F '200>"$(lock_path "$_DQ_FILE")"' "$SRC_GATE_SCRIPT"
    [ "$status" -eq 0 ]
}

setup() {
    cmd_gate_scaffold "cmd_gate_ctx"
    export SCRIPT_DIR="$TEST_PROJECT"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"
    export LOG_DIR="$TEST_PROJECT/logs"
    export CMD_ID="$TEST_CMD_ID"

    cp "$SRC_NORMALIZE_SCRIPT" "$TEST_PROJECT/scripts/lib/normalize_report.sh"
    chmod +x "$TEST_PROJECT/scripts/lib/normalize_report.sh"

    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: infra
    path: $TEST_PROJECT
EOF

    cat > "$TEST_PROJECT/tasks/lessons.md" <<'EOF'
# Lessons
- **status**: confirmed
EOF

    cat > "$TEST_PROJECT/queue/inbox/karo.yaml" <<'EOF'
messages:
  - id: msg_test
    read: false
EOF

    source "$SRC_FIELD_GET_SCRIPT"
    source "$SRC_LOCK_PATH_SCRIPT"
    # shellcheck source=/dev/null
    source "$GATE_HELPERS_FILE"

    ALL_CLEAR=true
    BLOCK_REASONS=()

    write_task_fixture "sasuke_report_${TEST_CMD_ID}.yaml"
}

_run_command_files_modified_coverage_with_state() {
    check_command_files_modified_coverage
    echo "ALL_CLEAR=$ALL_CLEAR"
    echo "BLOCK_REASONS=${BLOCK_REASONS[*]}"
}

_write_command_coverage_fixture() {
    local command_text="$1"
    local files_modified_block="$2"
    local target_path="${3:-}"

    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    export MATCHING_TASK_FILES_PROCESSED_COUNT=0
    export MATCHING_TASK_FILES_SKIPPED_COUNT=0
    export ALL_CLEAR=true
    BLOCK_REASONS=()

    cat > "$YAML_FILE" <<EOF
commands:
  $TEST_CMD_ID:
    command: "$command_text"
    target_path: "$target_path"
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
files_modified:
$files_modified_block
EOF
}

@test "command/files_modified coverage blocks when command target is missing from report" {
    _write_command_coverage_fixture \
        "scripts/cmd_complete_gate.sh と scripts/stop_check_inbox.sh を修正" \
        "  - path: tests/unit/test_cmd_complete_gate.bats
    change: modified"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" != *"missing: scripts/cmd_complete_gate.sh"* ]]
    [[ "$output" == *"missing: scripts/stop_check_inbox.sh"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
}

@test "command/files_modified coverage accepts full path and basename matches" {
    _write_command_coverage_fixture \
        "cmd_complete_gate.sh と scripts/stop_check_inbox.sh を修正" \
        "  - path: scripts/cmd_complete_gate.sh
    change: modified
  - path: hooks/stop_check_inbox.sh
    change: modified"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (command欄ファイル参照 全2件がfiles_modifiedに記載済み)"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
    [[ "$output" == *"BLOCK_REASONS="* ]]
}

@test "command/files_modified coverage accepts abbreviated test name by substring match" {
    mkdir -p "$TEST_PROJECT/tests/unit"
    touch "$TEST_PROJECT/tests/unit/test_semantic_index_update.bats"

    _write_command_coverage_fixture \
        "semantic_index_updateテストを高速化" \
        "  - file: tests/unit/test_semantic_index_update.bats
    change: modified" \
        "tests/unit"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (command欄ファイル参照 全1件がfiles_modifiedに記載済み)"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
    [[ "$output" == *"BLOCK_REASONS="* ]]
}

@test "command/files_modified coverage blocks unrelated file despite substring mode" {
    mkdir -p "$TEST_PROJECT/tests/unit"
    touch "$TEST_PROJECT/tests/unit/test_semantic_index_update.bats"

    _write_command_coverage_fixture \
        "semantic_index_updateテストを高速化" \
        "  - file: tests/unit/test_unrelated.bats
    change: modified" \
        "tests/unit"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" == *"missing: semantic_index_update"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
}

@test "command/files_modified coverage ignores read-only command refs when write target is reported" {
    _write_command_coverage_fixture \
        "scripts/build_instructions.sh を読んで skills/reset-layout/SKILL.md を更新" \
        "  - path: skills/reset-layout/SKILL.md
    change: modified" \
        "skills/reset-layout/SKILL.md"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (command欄ファイル参照 全1件がfiles_modifiedに記載済み)"* ]]
    [[ "$output" != *"missing: scripts/build_instructions.sh"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
    [[ "$output" == *"BLOCK_REASONS="* ]]
}

@test "command/files_modified coverage still blocks when write target is missing after read-only refs" {
    _write_command_coverage_fixture \
        "scripts/build_instructions.sh を読んで skills/reset-layout/SKILL.md を更新" \
        "  - path: scripts/build_instructions.sh
    change: read" \
        "skills/reset-layout/SKILL.md"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" == *"missing: skills/reset-layout/SKILL.md"* ]]
    [[ "$output" != *"missing: scripts/build_instructions.sh"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
}

@test "command/files_modified coverage skips for recon sentinel (no code change)" {
    _write_command_coverage_fixture \
        "memory_db_import.pyのsummary/detail書込み処理を特定する" \
        "  - path: 偵察のみ（コード変更なし）
    change: none"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP (files_modified=no-code-change sentinel"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "command/files_modified coverage blocks typo path even when file does not exist" {
    _write_command_coverage_fixture \
        "scripts/cmd_complete_gate.sh を修正" \
        "  - path: scripts/typo_nonexistent_file.sh
    change: modified"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
}

@test "command/files_modified coverage excludes execution-only refs (LG037 FP fix)" {
    _write_command_coverage_fixture \
        "SKILL.md 8件のスクリプト参照陳腐化を修正。note_draft.shを実行して確認。report_field_set.shを実行。gate_skill_script_refs.shで検証。" \
        "  - path: skills/reset-layout/SKILL.md
    change: modified"

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    [[ "$output" != *"missing: note_draft.sh"* ]]
    [[ "$output" != *"missing: report_field_set.sh"* ]]
    [[ "$output" != *"missing: gate_skill_script_refs.sh"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "command/files_modified coverage excludes verified_existing_dependency refs (LG037)" {
    _write_command_coverage_fixture \
        "scripts/cmd_complete_gate.sh と scripts/deploy_task.sh を修正" \
        "  - path: scripts/cmd_complete_gate.sh
    change: modified"

    # Add verified_existing_dependency to report
    cat >> "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
verified_existing_dependency:
  - path: scripts/deploy_task.sh
    reason: "実行のみ参照"
EOF

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" != *"missing: scripts/deploy_task.sh"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "command/files_modified coverage excludes verified_existing_dependency before target_path selection" {
    _write_command_coverage_fixture \
        "refactor-workorder-20260611.md を必読参照し、backend/app/api/main.py を修正" \
        "  - path: backend/app/api/main.py
    change: modified" \
        "refactor-workorder-20260611.md"

    cat >> "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
verified_existing_dependency:
  - path: /mnt/c/Python_app/DM-signal/.agent/task-force/refactor-workorder-20260611.md
    reason: "必読の権威文書。参照のみで変更対象ではない"
EOF

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK (command欄ファイル参照 全1件がfiles_modifiedに記載済み)"* ]]
    [[ "$output" != *"missing: refactor-workorder-20260611.md"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "command/files_modified coverage preserves true positive after verified_existing_dependency filtering" {
    _write_command_coverage_fixture \
        "refactor-workorder-20260611.md を必読参照し、backend/app/api/main.py と backend/app/api/portfolios.py を修正" \
        "  - path: backend/app/api/main.py
    change: modified" \
        "refactor-workorder-20260611.md"

    cat >> "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
verified_existing_dependency:
  - path: /mnt/c/Python_app/DM-signal/.agent/task-force/refactor-workorder-20260611.md
    reason: "必読の権威文書。参照のみで変更対象ではない"
EOF

    run _run_command_files_modified_coverage_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMAND_SCOPE_MISSING"* ]]
    [[ "$output" == *"missing: backend/app/api/portfolios.py"* ]]
    [[ "$output" != *"missing: refactor-workorder-20260611.md"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
}

@test "command/files_modified coverage accepts archived cmd_3289 through cmd_3293 readonly refs" {
    local cmd archive_cmd report_src report_name
    for cmd in cmd_3289 cmd_3290 cmd_3291 cmd_3292 cmd_3293; do
        case "$cmd" in
            cmd_3289)
                archive_cmd="$PROJECT_ROOT/queue/archive/cmds/cmd_3289_completed_20260611.yaml"
                report_src="$PROJECT_ROOT/queue/archive/reports/kagemaru_report_cmd_3289_20260611.yaml"
                ;;
            cmd_3290)
                archive_cmd="$PROJECT_ROOT/queue/archive/cmds/cmd_3290_done_20260611.yaml"
                report_src="$PROJECT_ROOT/queue/archive/reports/kagemaru_report_cmd_3290.yaml.bak"
                ;;
            cmd_3291)
                archive_cmd="$PROJECT_ROOT/queue/archive/cmds/cmd_3291_completed_20260611.yaml"
                report_src="$PROJECT_ROOT/queue/archive/reports/kagemaru_report_cmd_3291_20260611.yaml"
                ;;
            cmd_3292)
                archive_cmd="$PROJECT_ROOT/queue/archive/cmds/cmd_3292_completed_20260611.yaml"
                report_src="$PROJECT_ROOT/queue/archive/reports/kagemaru_report_cmd_3292_20260611.yaml"
                ;;
            cmd_3293)
                archive_cmd="$PROJECT_ROOT/queue/archive/cmds/cmd_3293_completed_20260611.yaml"
                report_src="$PROJECT_ROOT/queue/archive/reports/kagemaru_report_cmd_3293_20260611.yaml"
                ;;
        esac

        report_name="kagemaru_report_${cmd}.yaml"
        cp "$archive_cmd" "$TEST_PROJECT/queue/shogun_to_karo.yaml"
        cp "$report_src" "$TEST_PROJECT/queue/reports/$report_name"
        cat > "$TEST_PROJECT/queue/tasks/kagemaru.yaml" <<EOF
task:
  parent_cmd: $cmd
  report_filename: $report_name
EOF

        export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
        export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/kagemaru.yaml")
        export CMD_ID="$cmd"
        export ALL_CLEAR=true
        BLOCK_REASONS=()

        run _run_command_files_modified_coverage_with_state
        [ "$status" -eq 0 ]
        [[ "$output" != *"COMMAND_SCOPE_MISSING"* ]]
        [[ "$output" != *"BLOCK_REASONS=command_files_modified_mismatch"* ]]
    done
}

@test "preflight auto-registers found:true lesson candidate when lesson.done is missing" {
    rm -f "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done"
    export ALL_GATES=()
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    export MATCHING_TASK_FILES_PROCESSED_COUNT=0
    export MATCHING_TASK_FILES_SKIPPED_COUNT=0

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
lesson_candidate:
  found: true
  project: infra
  title: 自動登録テスト
  detail: preflight should auto-register this candidate.
EOF
    cat > "$TEST_PROJECT/scripts/auto_draft_lesson.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$TEST_PROJECT/auto_draft_calls.log"
mkdir -p "$TEST_PROJECT/queue/gates/$TEST_CMD_ID"
{
  echo "timestamp: 2026-05-24T00:00:00"
  echo "source: lesson_write"
} > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done"
EOF
    chmod +x "$TEST_PROJECT/scripts/auto_draft_lesson.sh"

    run preflight_gate_flags "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lesson: auto-registering found:true candidate (sasuke)"* ]]
    [[ "$output" == *"lesson: preflight OK (via auto_draft_lesson/lesson_write)"* ]]
    grep -q "sasuke_report_${TEST_CMD_ID}.yaml" "$TEST_PROJECT/auto_draft_calls.log"
    grep -Fx "source: lesson_write" "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done"
}

@test "preflight skips lesson auto-register when lesson.done already exists" {
    export ALL_GATES=()
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    export MATCHING_TASK_FILES_PROCESSED_COUNT=0
    export MATCHING_TASK_FILES_SKIPPED_COUNT=0

    cat > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done" <<'EOF'
timestamp: 2026-05-24T00:00:00
source: lesson_write
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
lesson_candidate:
  found: true
  project: infra
  title: 冪等テスト
  detail: auto_draft must not run when lesson.done exists.
EOF
    cat > "$TEST_PROJECT/scripts/auto_draft_lesson.sh" <<'EOF'
#!/usr/bin/env bash
printf 'called\n' >> "$TEST_PROJECT/auto_draft_calls.log"
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/auto_draft_lesson.sh"

    run preflight_gate_flags "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lesson: already exists (skip)"* ]]
    [ ! -f "$TEST_PROJECT/auto_draft_calls.log" ]
    grep -Fx "source: lesson_write" "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done"
}

@test "preflight uses lesson_check for found:false lesson candidate" {
    rm -f "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done"
    export ALL_GATES=()
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    export MATCHING_TASK_FILES_PROCESSED_COUNT=0
    export MATCHING_TASK_FILES_SKIPPED_COUNT=0

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
lesson_candidate:
  found: false
EOF
    cat > "$TEST_PROJECT/scripts/auto_draft_lesson.sh" <<'EOF'
#!/usr/bin/env bash
printf 'called\n' >> "$TEST_PROJECT/auto_draft_calls.log"
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/lesson_check.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$1" "$2" >> "$TEST_PROJECT/lesson_check_calls.log"
mkdir -p "$TEST_PROJECT/queue/gates/$1"
{
  echo "timestamp: 2026-05-24T00:00:00"
  echo "source: lesson_check"
} > "$TEST_PROJECT/queue/gates/$1/lesson.done"
EOF
    chmod +x "$TEST_PROJECT/scripts/auto_draft_lesson.sh" "$TEST_PROJECT/scripts/lesson_check.sh"

    run preflight_gate_flags "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lesson: preflight OK (via lesson_check)"* ]]
    [ ! -f "$TEST_PROJECT/auto_draft_calls.log" ]
    grep -q "$TEST_CMD_ID|preflight: no found:true lesson_candidate" "$TEST_PROJECT/lesson_check_calls.log"
    grep -Fx "source: lesson_check" "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done"
}

@test "lesson_done_missing is WARN and does not force ALL_CLEAR false" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
needle = "lesson_candidate found:true but lesson.done not found"
idx = text.index(needle)
branch_start = text.rfind("else", 0, idx)
branch_end = text.index("\n            fi", idx)
branch = text[branch_start:branch_end]

assert "WARN:" in branch, branch
assert "notify_karo_lesson_registration_reminder" in branch, branch
assert "record_block_reason" not in branch, branch
assert "ALL_CLEAR=false" not in branch, branch
PY
    [ "$status" -eq 0 ]
}

@test "lesson_done_missing WARN sends karo reminder via inbox_write" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index("notify_karo_lesson_registration_reminder()")
end = text.index("\n}\n", start) + 3
func = text[start:end]

assert 'inbox_write.sh" karo' in func, func
assert "lesson_registration_reminder" in func, func
assert "lesson.done未生成" in func, func
assert "dedup" in func, func
PY
    [ "$status" -eq 0 ]
}

@test "missing lesson gate is WARN and sends karo reminder" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
needle = 'if [ "$gate" = "lesson" ]; then'
idx = text.index(needle)
branch_end = text.index("\n        else", idx)
branch = text[idx:branch_end]

assert "WARN:" in branch, branch
assert "notify_karo_lesson_registration_reminder" in branch, branch
assert "record_block_reason" not in branch, branch
assert "ALL_CLEAR=false" not in branch, branch
PY
    [ "$status" -eq 0 ]
}

@test "non-lesson missing gates remain blocking" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
needle = 'if [ "$gate" = "lesson" ]; then'
idx = text.index(needle)
else_start = text.index("\n        else", idx)
branch_end = text.index("\n        fi", else_start)
branch = text[else_start:branch_end]

assert "[CRITICAL]" in branch, branch
assert 'record_block_reason "missing_gate:${gate}"' in branch, branch
assert "ALL_CLEAR=false" in branch, branch
PY
    [ "$status" -eq 0 ]
}

@test "resolve_report_file warns when auto unwrap returns empty status after flock timeout" {
    local report_file="$TEST_PROJECT/queue/reports/hayate_report_${TEST_CMD_ID}.yaml"
    local lock_file="${report_file}.lock"
    export SCRIPT_DIR="$TEST_PROJECT"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"
    export CMD_ID="$TEST_CMD_ID"

    cat > "$TASKS_DIR/hayate.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: hayate_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$report_file" <<'EOF'
report:
  worker_id: hayate
  status: completed
EOF

    (
        exec 200>"$lock_file"
        flock 200
        sleep 7
    ) &
    local lock_holder=$!
    sleep 0.2

    run resolve_report_file hayate "$TEST_CMD_ID"
    kill "$lock_holder" 2>/dev/null || true
    wait "$lock_holder" 2>/dev/null || true

    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto_unwrap] WARN: flock timeout on report YAML, skipping unwrap"* ]]
    [[ "$output" == *"[gate] WARN: report YAML unwrap returned unknown status '<empty>': $report_file"* ]]
    [[ "$output" == *"$report_file"* ]]
}

@test "CoDD registry append extracts target and before/after from report and spec" {
    mkdir -p "$TEST_PROJECT/docs/research"
    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")

    cat > "$TEST_PROJECT/docs/research/codd_refactor_registry.md" <<'EOF'
# CoDD Refactor Registry

| 日付 | 実施者 | 対象スクリプト/領域 | Phase到達 | Before→After | spec/after設計書パス |
|------|--------|---------------------|-----------|--------------|----------------------|
EOF
    cat > "$YAML_FILE" <<EOF
commands:
  $TEST_CMD_ID:
    title: "CoDD improvement"
    command: "CoDDで scripts/demo_gate.sh を改善"
EOF
    cat > "$TEST_PROJECT/docs/research/codd_spec_demo_${TEST_CMD_ID}.md" <<'EOF'
# CoDD spec

Target: `scripts/demo_gate.sh`
before median: 120ms
after median: 30ms
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
status: done
result:
  summary: "CoDD spec docs/research/codd_spec_demo_${TEST_CMD_ID}.md に基づき before 120ms after 30ms"
files_modified:
  - path: scripts/demo_gate.sh
EOF

    run append_codd_registry_entry "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: appended $TEST_CMD_ID"* ]]
    grep -q "scripts/demo_gate.sh" "$TEST_PROJECT/docs/research/codd_refactor_registry.md"
    grep -q "120ms → 30ms" "$TEST_PROJECT/docs/research/codd_refactor_registry.md"
    grep -q "$TEST_CMD_ID" "$TEST_PROJECT/docs/research/codd_refactor_registry.md"
}

@test "CoDD registry append prefers report real runtime fields over summary timings" {
    mkdir -p "$TEST_PROJECT/docs/research"
    export YAML_FILE="$TEST_PROJECT/queue/shogun_to_karo.yaml"
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")

    cat > "$TEST_PROJECT/docs/research/codd_refactor_registry.md" <<'EOF'
# CoDD Refactor Registry

| 日付 | 実施者 | 対象スクリプト/領域 | Phase到達 | Before→After | spec/after設計書パス |
|------|--------|---------------------|-----------|--------------|----------------------|
EOF
    cat > "$YAML_FILE" <<EOF
commands:
  $TEST_CMD_ID:
    title: "CoDD improvement"
    command: "CoDDで scripts/demo_gate.sh を改善"
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  assigned_to: sasuke
  target_path: scripts/demo_gate.sh
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
parent_cmd: $TEST_CMD_ID
status: done
before_real_ms: 80
after_real_ms: 70
result:
  summary: "単発time表示では 0.08s -> 0.07s と見えるが、台帳用real msを正とする"
files_modified:
  - path: scripts/demo_gate.sh
EOF

    run append_codd_registry_entry "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: appended $TEST_CMD_ID"* ]]
    grep -q "80ms → 70ms" "$TEST_PROJECT/docs/research/codd_refactor_registry.md"
    ! grep -q "0.08s → 0.07s" "$TEST_PROJECT/docs/research/codd_refactor_registry.md"
}

@test "run_codd_propagate_update executes codd propagate update after gate clear" {
    local codd_log="$TEST_TMPDIR/codd_args.log"
    local stub_codd="$TEST_TMPDIR/codd"
    cat > "$stub_codd" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$TEST_CODD_LOG"
echo "propagate done"
EOF
    chmod +x "$stub_codd"

    export CODD_BIN="$stub_codd"
    export CODD_PROPAGATE_PATH="$TEST_PROJECT"
    export TEST_CODD_LOG="$codd_log"

    run run_codd_propagate_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"CoDD propagate update (GATE CLEAR):"* ]]
    [[ "$output" == *"OK: codd propagate --path $TEST_PROJECT --update"* ]]
    [[ "$output" == *"propagate done"* ]]
    [ "$(cat "$codd_log")" = "propagate --path $TEST_PROJECT --update" ]
}

@test "run_codd_propagate_update warns but does not block when codd is missing" {
    export CODD_BIN="$TEST_TMPDIR/missing-codd"

    run run_codd_propagate_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN] codd executable not found (skip)"* ]]
}

@test "normalize_block_reason_to_workaround_categories maps gate BLOCK reasons to WA categories" {
    run normalize_block_reason_to_workaround_categories "report_format:hayate.yaml|hayate:binary_checks_fail|missing_gate:review_gate|commit_missing"
    [ "$status" -eq 0 ]
    [[ "$output" == *"report_yaml_format"* ]]
    [[ "$output" == *"gate_missing"* ]]
    [[ "$output" == *"commit_missing"* ]]
}

@test "update_karo_workaround_resolutions fills unresolved matching categories only" {
    export GATE_METRICS_LOG="$TEST_PROJECT/logs/gate_metrics.log"
    export KARO_WORKAROUNDS_FILE="$TEST_PROJECT/logs/karo_workarounds.yaml"
    export KARO_WORKAROUNDS_LOCK_FILE="$TEST_PROJECT/logs/karo_workarounds.lock"
    mkdir -p "$TEST_PROJECT/logs"

    cat > "$GATE_METRICS_LOG" <<EOF
2026-05-12T00:00:00	$TEST_CMD_ID	BLOCK	report_format:hayate_report.yaml	exact	unknown	unknown	none
2026-05-12T00:01:00	$TEST_CMD_ID	BLOCK	missing_gate:review_gate	exact	unknown	unknown	none
EOF
    cat > "$KARO_WORKAROUNDS_FILE" <<'EOF'
- cmd_id: cmd_old_report
  timestamp: '2026-05-12T00:00:00Z'
  ninja: hayate
  workaround: true
  category: report_yaml_format
  detail: 'report format workaround'
  root_cause: 'format gate failure'
  resolved_by_cmd: ''
- cmd_id: cmd_old_gate
  timestamp: '2026-05-12T00:00:00Z'
  ninja: kagemaru
  workaround: true
  category: gate_missing
  detail: 'review gate missing'
  root_cause: 'review gate not done'
  resolved_by_cmd: ''
- cmd_id: cmd_old_commit
  timestamp: '2026-05-12T00:00:00Z'
  ninja: saizo
  workaround: true
  category: commit_missing
  detail: 'commit missing'
  root_cause: 'commit not created'
  resolved_by_cmd: ''
- cmd_id: cmd_clean
  timestamp: '2026-05-12T00:00:00Z'
  ninja: kotaro
  workaround: false
  category: report_yaml_format
  detail: ''
  root_cause: ''
  resolved_by_cmd: ''
EOF

    run update_karo_workaround_resolutions "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Karo workaround resolution update (GATE CLEAR):"* ]]
    [[ "$output" == *"updated=2"* ]]
    grep -A7 "cmd_id: cmd_old_report" "$KARO_WORKAROUNDS_FILE" | grep -q "resolved_by_cmd: '$TEST_CMD_ID'"
    grep -A7 "cmd_id: cmd_old_gate" "$KARO_WORKAROUNDS_FILE" | grep -q "resolved_by_cmd: '$TEST_CMD_ID'"
    grep -A7 "cmd_id: cmd_old_commit" "$KARO_WORKAROUNDS_FILE" | grep -q "resolved_by_cmd: ''"
    grep -A7 "cmd_id: cmd_clean" "$KARO_WORKAROUNDS_FILE" | grep -q "resolved_by_cmd: ''"
}

@test "cmd_complete_gate wires workaround resolution update in normal and emergency CLEAR sections" {
    run bash -lc "grep -c 'update_karo_workaround_resolutions \"\\\$CMD_ID\"' '$SRC_GATE_SCRIPT'"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "write_l6_horizontal_level5_insights saves matching defense_level_under_5 candidate" {
    local insight_log="$TEST_TMPDIR/insights.log"
    cat > "$TEST_PROJECT/scripts/insight_write.sh" <<EOF
#!/usr/bin/env bash
printf '%s|%s|%s\n' "\$1" "\$2" "\$3" >> "$insight_log"
echo INSIGHT_TEST
EOF
    chmod +x "$TEST_PROJECT/scripts/insight_write.sh"

    cat > "$TEST_PROJECT/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_2600
  findings_summary: "ac_param_sufficiency WARNをBLOCKで止めているが、候補値自動提案は未実装"
  proposal:
    defense_level: 4
  causal_chain: "ac_param_sufficiency 手動確認"
- cmd_id: cmd_2601
  findings_summary: "unrelated Level4"
  proposal:
    defense_level: 4
EOF

    export CMD_TITLE="強化 — ac_param_sufficiency候補値自動提案(Level5化)"
    export CMD_PURPOSE="ac_param_sufficiency WARN時にcontextから候補値を自動表示する"
    export CMD_CHANGED_FILES="scripts/cmd_save.sh"

    run write_l6_horizontal_level5_insights "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L6 horizontal Level5 candidate scan"* ]]
    [[ "$output" == *"saved: 1 horizontal candidate(s)"* ]]
    grep -q "同パターンLevel5未満候補: source_cmd=$TEST_CMD_ID" "$insight_log"
    grep -q "candidate_level=4" "$insight_log"
    grep -q "cmd_complete_gate:l6_horizontal:$TEST_CMD_ID" "$insight_log"
}

@test "write_l6_horizontal_level5_insights matches Japanese command tokens" {
    local insight_log="$TEST_TMPDIR/insights.log"
    cat > "$TEST_PROJECT/scripts/insight_write.sh" <<EOF
#!/usr/bin/env bash
printf '%s|%s|%s\n' "\$1" "\$2" "\$3" >> "$insight_log"
echo INSIGHT_TEST
EOF
    chmod +x "$TEST_PROJECT/scripts/insight_write.sh"

    cat > "$TEST_PROJECT/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_2602
  findings_summary: "横展開スキャンで日本語トークン抽出が弱く候補検出できない"
  proposal:
    defense_level: 4
  causal_chain: "日本語トークン分割不足"
EOF

    export CMD_TITLE="L6横展開候補検出の日本語トークン分割改善"
    export CMD_PURPOSE="長文フレーズを分割し日本語cmdでも候補検出を機能させる"
    export CMD_CHANGED_FILES="scripts/cmd_complete_gate.sh"

    run write_l6_horizontal_level5_insights "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L6 horizontal Level5 candidate scan"* ]]
    [[ "$output" == *"saved: 1 horizontal candidate(s)"* ]]
    grep -q "matched=.*日本語" "$insight_log"
    grep -q "candidate_level=4" "$insight_log"
    grep -q "cmd_complete_gate:l6_horizontal:$TEST_CMD_ID" "$insight_log"
}

@test "write_l6_horizontal_level5_insights skips commands without Level5 signal" {
    local insight_log="$TEST_TMPDIR/insights.log"
    cat > "$TEST_PROJECT/scripts/insight_write.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$insight_log"
EOF
    chmod +x "$TEST_PROJECT/scripts/insight_write.sh"

    cat > "$TEST_PROJECT/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_2600
  findings_summary: "ordinary candidate"
  proposal:
    defense_level: 4
EOF

    export CMD_TITLE="通常修正"
    export CMD_PURPOSE="typoを直す"
    export CMD_CHANGED_FILES="scripts/cmd_save.sh"

    run write_l6_horizontal_level5_insights "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: no Level5-under horizontal candidates"* ]]
    [ ! -f "$insight_log" ]
}

@test "append_lesson_tracking filters fallback reports to current worker_id" {
    rm -f "$TEST_PROJECT/queue/tasks/"*.yaml
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_id: ${TEST_CMD_ID}_exact
  worker_id: hayate
  related_lessons:
    - id: L001
EOF
    cat > "$TEST_PROJECT/queue/reports/hayate_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: hayate
task_id: ${TEST_CMD_ID}_exact
parent_cmd: $TEST_CMD_ID
lessons_useful:
  - id: L001
EOF
    cat > "$TEST_PROJECT/queue/reports/hanzo_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: hanzo
task_id: ${TEST_CMD_ID}_stale
lessons_useful:
  - id: L999
EOF

    run append_lesson_tracking "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]
    tail -1 "$TEST_PROJECT/logs/lesson_tracking.tsv" | grep -q $'\thayate\tCLEAR\tL001\tL001\texact$'
}

@test "append_lesson_tracking detects exact and normal task_id suffixes" {
    rm -f "$TEST_PROJECT/queue/tasks/"*.yaml
    cat > "$TEST_PROJECT/queue/reports/hayate_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: hayate
task_id: ${TEST_CMD_ID}_exact
parent_cmd: $TEST_CMD_ID
lessons_useful:
  - id: L001
EOF

    run append_lesson_tracking "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]
    tail -1 "$TEST_PROJECT/logs/lesson_tracking.tsv" | grep -q $'\thayate\tCLEAR\tnone\tL001\texact$'

    : > "$TEST_PROJECT/logs/lesson_tracking.tsv"
    rm -f "$TEST_PROJECT/queue/reports/"*.yaml
    cat > "$TEST_PROJECT/queue/reports/hayate_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: hayate
task_id: ${TEST_CMD_ID}_normal
parent_cmd: $TEST_CMD_ID
lessons_useful:
  - id: L002
EOF

    run append_lesson_tracking "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]
    tail -1 "$TEST_PROJECT/logs/lesson_tracking.tsv" | grep -q $'\thayate\tCLEAR\tnone\tL002\tnormal$'
}

@test "append_lesson_tracking allows parent_cmd match even when current assignee differs" {
    rm -f "$TEST_PROJECT/queue/tasks/"*.yaml
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_id: ${TEST_CMD_ID}_exact
  worker_id: hayate
  related_lessons:
    - id: L001
EOF
    cat > "$TEST_PROJECT/queue/reports/hanzo_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: hanzo
task_id: ${TEST_CMD_ID}_normal
parent_cmd: $TEST_CMD_ID
lessons_useful:
  - id: L002
EOF

    run append_lesson_tracking "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]
    tail -1 "$TEST_PROJECT/logs/lesson_tracking.tsv" | grep -q $'\thanzo\tCLEAR\tL001\tL002\texact$'
}

@test "append_lesson_tracking fallback ignores stale reports with mismatched parent_cmd" {
    rm -f "$TEST_PROJECT/queue/tasks/"*.yaml
    cat > "$TEST_PROJECT/queue/reports/hayate_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: hayate
task_id: ${TEST_CMD_ID}_exact
parent_cmd: cmd_other
lessons_useful:
  - id: L999
EOF

    run append_lesson_tracking "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]
    tail -1 "$TEST_PROJECT/logs/lesson_tracking.tsv" | grep -q $'\tnone\tCLEAR\tnone\tnone\tunknown$'
}

@test "lessons_useful empty is WARN for scout and verify task types" {
    reset_gate_state

    handle_empty_lessons_useful_check "sasuke" "scout" "L001" > "$TEST_TMPDIR/lessons_useful_output.txt"
    output="$(cat "$TEST_TMPDIR/lessons_useful_output.txt")"
    [[ "$output" == *"[WARN] sasuke: lessons_useful空。task_type=scout のためBLOCK対象外"* ]]
    [ "$ALL_CLEAR" = true ]
    [ "${#BLOCK_REASONS[@]}" -eq 0 ]

    handle_empty_lessons_useful_check "sasuke" "verify" "L002" > "$TEST_TMPDIR/lessons_useful_output.txt"
    output="$(cat "$TEST_TMPDIR/lessons_useful_output.txt")"
    [[ "$output" == *"[WARN] sasuke: lessons_useful空。task_type=verify のためBLOCK対象外"* ]]
    [ "$ALL_CLEAR" = true ]
    [ "${#BLOCK_REASONS[@]}" -eq 0 ]
}

@test "lessons_useful empty remains BLOCK for exact task type" {
    reset_gate_state

    handle_empty_lessons_useful_check "sasuke" "exact" "L001,L002" > "$TEST_TMPDIR/lessons_useful_output.txt"
    output="$(cat "$TEST_TMPDIR/lessons_useful_output.txt")"
    [[ "$output" == *"[CRITICAL] sasuke: NG ← lessons_useful空"* ]]
    [ "$ALL_CLEAR" = false ]
    [ "${BLOCK_REASONS[0]}" = "sasuke:empty_lessons_useful:related=[L001,L002]" ]
}

@test "CDP production check is required for dm-signal frontend changed files" {
    export CMD_PROJECT="dm-signal"
    export CMD_CHANGED_FILES=$'backend/app.py\nfrontend/app/dashboard/page.tsx'
    mkdir -p "$TEST_PROJECT/scripts/cdp"
    cat > "$TEST_PROJECT/scripts/cdp/cdp_measure.sh" <<'EOF'
#!/usr/bin/env bash
echo "CDP_MEASURE:$*"
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/cdp/cdp_measure.sh"

    run run_cdp_production_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"REQUIRED: dm-signal frontend change detected"* ]]
    [[ "$output" == *"timeout: 900s"* ]]
    [[ "$output" == *"pages: home dashboard summary"* ]]
    [[ "$output" == *"CDP_MEASURE:$TEST_CMD_ID --pages home dashboard summary"* ]]
    [[ "$output" == *"CDP production check: OK"* ]]
}

@test "CDP production check skips non-frontend dm-signal changes" {
    export CMD_PROJECT="dm-signal"
    export CMD_CHANGED_FILES=$'backend/app.py\nscripts/tool.sh'

    run run_cdp_production_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP (project=dm-signal, frontend changes not detected)"* ]]
}

@test "CDP production check detects frontend paths from report files_modified" {
    export CMD_PROJECT="dm-signal"
    export CMD_CHANGED_FILES=""
    export MATCHING_TASK_FILES=("$TEST_PROJECT/queue/tasks/sasuke.yaml")
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_999
files_modified:
  - path: frontend/components/Widget.tsx
EOF
    mkdir -p "$TEST_PROJECT/scripts/cdp"
    cat > "$TEST_PROJECT/scripts/cdp/cdp_measure.sh" <<'EOF'
#!/usr/bin/env bash
echo "REPORT_CDP:$1"
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/cdp/cdp_measure.sh"

    run run_cdp_production_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"REQUIRED: dm-signal frontend change detected"* ]]
    [[ "$output" == *"REPORT_CDP:$TEST_CMD_ID"* ]]
}

teardown() {
    cmd_gate_teardown
}

reset_gate_state() {
    ALL_CLEAR=true
    BLOCK_REASONS=()
}

# Direct function-level triage decision helper (no full gate execution)
run_binary_checks_triage_decision() {
    local triage="${1:-}"
    local ninja_name="sasuke"
    local report_file="$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml"

    write_triage_report_fixture "$triage" "no"

    local has_fail
    has_fail=$(awk '
        /^binary_checks:/{in_bc=1; next}
        in_bc && /^[^ ]/{in_bc=0}
        in_bc && /result:/{
            val=$0; gsub(/.*result:[[:space:]]*/,"",val); gsub(/[[:space:]]*$/,"",val)
            if (val != "yes") { print "FAIL"; exit }
        }
    ' "$report_file")

    if [ "$has_fail" = "FAIL" ]; then
        local warn_reason
        warn_reason=$(binary_checks_warn_reason "$report_file" "$ninja_name" "" 2>/dev/null || true)
        if [ -n "$warn_reason" ]; then
            echo "[WARN] ${ninja_name}: binary_checks non-PASS"
            echo "  ${warn_reason}"
            echo "GATE CLEAR: cmd完了許可"
            return 0
        else
            echo "[CRITICAL] ${ninja_name}: NG ← binary_checks has non-PASS results"
            echo "GATE BLOCK: ${ninja_name}:binary_checks_fail"
            echo "  ${ninja_name}:binary_checks_fail"
            return 1
        fi
    fi

    echo "GATE CLEAR: cmd完了許可"
    return 0
}

is_cmd_task() {
    local task_file="$1"
    grep -q "parent_cmd: ${TEST_CMD_ID}" "$task_file" 2>/dev/null
}

resolve_report_file() {
    local ninja_name="$1"
    local explicit_path report_parent
    local task_file="$TASKS_DIR/${ninja_name}.yaml"

    if [ -f "$task_file" ]; then
        explicit_path=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "report_filename" "")
        if [ -n "$explicit_path" ] && [ -f "$SCRIPT_DIR/queue/reports/$explicit_path" ]; then
            echo "$SCRIPT_DIR/queue/reports/$explicit_path"
            return 0
        fi
    fi

    if [ -f "$SCRIPT_DIR/queue/reports/${ninja_name}_report_${TEST_CMD_ID}.yaml" ]; then
        echo "$SCRIPT_DIR/queue/reports/${ninja_name}_report_${TEST_CMD_ID}.yaml"
        return 0
    fi

    if [ -f "$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml" ]; then
        report_parent=$(FIELD_GET_NO_LOG=1 field_get "$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml" "parent_cmd" "")
        if [ "$report_parent" = "$TEST_CMD_ID" ]; then
            echo "$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"
            return 0
        fi
    fi

    return 1
}

write_task_fixture() {
    local report_filename="${1:-sasuke_report_${TEST_CMD_ID}.yaml}"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: review
  report_filename: $report_filename
  ac_version: 2
  related_lessons: []
EOF
}

write_triage_report_fixture() {
    local triage="${1:-}"
    local result="${2:-no}"
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-04T00:00:00"
status: done
ac_version_read: 2
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
  summary: "binary_checks triage fixture"
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
test_skip_count: 0
binary_checks:
  AC1:
    - check: "binary check triage fixture"
      result: ${result}
EOF
}

prepare_full_gate_triage_fixture() {
    local triage="${1:-}"
    write_cmd_yaml "without_context"
    write_task_fixture "sasuke_report_${TEST_CMD_ID}.yaml"
    write_triage_report_fixture "$triage" "no"

    cat > "$TEST_PROJECT/scripts/lib/normalize_report.sh" <<'EOF'
#!/usr/bin/env bash
echo "no normalization needed"
exit 1
EOF
    cat > "$TEST_PROJECT/scripts/gates/gate_report_autofix.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/gates/gate_report_format.sh" <<'EOF'
#!/usr/bin/env bash
echo "PASS"
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/gates/gate_dc_duplicate.sh" <<'EOF'
#!/usr/bin/env bash
echo "OK: no duplicate"
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/bulletin_write.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/ntfy_cmd.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/queue/inbox/gunshi.yaml" <<'EOF'
messages: []
EOF
    chmod +x \
        "$TEST_PROJECT/scripts/lib/normalize_report.sh" \
        "$TEST_PROJECT/scripts/gates/gate_report_autofix.sh" \
        "$TEST_PROJECT/scripts/gates/gate_report_format.sh" \
        "$TEST_PROJECT/scripts/gates/gate_dc_duplicate.sh" \
        "$TEST_PROJECT/scripts/inbox_write.sh" \
        "$TEST_PROJECT/scripts/bulletin_write.sh" \
        "$TEST_PROJECT/scripts/ntfy_cmd.sh"
}

write_cmd_yaml() {
    local mode="$1"
    if [ "$mode" = "with_context" ]; then
        cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  - id: $TEST_CMD_ID
    purpose: "context update gate test"
    project: infra
    status: delegated
    delegated_at: "2026-03-04T21:25:00"
    context_update:
      - context/infrastructure.md
EOF
    else
        cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  - id: $TEST_CMD_ID
    purpose: "context update gate test"
    project: infra
    status: delegated
    delegated_at: "2026-03-04T21:25:00"
EOF
    fi
}

write_context_file() {
    local last_updated_date="$1"
    cat > "$TEST_PROJECT/context/infrastructure.md" <<EOF
# Infra
<!-- last_updated: ${last_updated_date} cmd_000 test -->
EOF
}

write_report() {
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-04T00:00:00"
status: done
ac_version_read: 2
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
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

run_context_update_check() {
    reset_gate_state
    check_context_update "$TEST_CMD_ID"
    [ "$ALL_CLEAR" = true ]
}

run_context_freshness_nudge() {
    local context_warn_lines

    echo "Context freshness nudge (GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/context_freshness_check.sh" ]; then
        context_warn_lines=$(bash "$SCRIPT_DIR/scripts/context_freshness_check.sh" --cmd-warnings "$TEST_CMD_ID" 2>/dev/null || true)
        if [ -n "$context_warn_lines" ]; then
            while IFS= read -r warn_line; do
                [ -n "$warn_line" ] || continue
                echo "  ${warn_line}"
            done <<< "$context_warn_lines"
        else
            echo "  OK: no stale project context files"
        fi
    else
        echo "  [INFO] context_freshness_check.sh not found (skip)"
    fi
}

run_normalize_phase() {
    local task_file ninja_name report_file normalize_exit normalize_output

    export NORMALIZE_LOG="$SCRIPT_DIR/logs/normalize_report.log"
    echo "Normalize report candidates (B層):"
    for task_file in "$TASKS_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        is_cmd_task "$task_file" || continue
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name") || continue
        if [ -f "$report_file" ]; then
            normalize_exit=0
            normalize_output=$(bash "$SCRIPT_DIR/scripts/lib/normalize_report.sh" "$report_file" 2>&1) || normalize_exit=$?
            if [ "$normalize_exit" -eq 0 ]; then
                echo "  [INFO] ${ninja_name}: auto-fixed: ${normalize_output}"
            elif [ "$normalize_exit" -eq 1 ]; then
                echo "  ${ninja_name}: OK (no normalization needed)"
            else
                echo "  ${ninja_name}: ERROR — normalize_report.sh exit=${normalize_exit}: ${normalize_output}"
            fi
        fi
    done
}

run_report_format_validation() {
    local report_file task_file ninja_name gate_output

    REPORT_FORMAT_CHECKED=0
    REPORT_FORMAT_FAILED=0
    declare -A report_format_seen=()

    validate_report_format_file() {
        local candidate="$1"

        [ -n "$candidate" ] || return 0
        [ -f "$candidate" ] || return 0
        if [ -n "${report_format_seen["$candidate"]+x}" ]; then
            return 0
        fi

        report_format_seen["$candidate"]=1
        REPORT_FORMAT_CHECKED=$((REPORT_FORMAT_CHECKED + 1))
        "$SCRIPT_DIR/scripts/gates/gate_report_autofix.sh" "$candidate" 2>/dev/null || true
        gate_output=$("$SCRIPT_DIR/scripts/gates/gate_report_format.sh" "$candidate" 2>&1 || true)
        if echo "$gate_output" | grep -q "^FAIL"; then
            REPORT_FORMAT_FAILED=$((REPORT_FORMAT_FAILED + 1))
            echo "  [CRITICAL] $(basename "$candidate"): $gate_output"
        else
            echo "  $(basename "$candidate"): PASS"
        fi
    }

    level_heading "[L1]" "Report format validation (direct scan):"
    for task_file in "$TASKS_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        is_cmd_task "$task_file" || continue
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name") || continue
        validate_report_format_file "$report_file"
    done

    for report_file in "$SCRIPT_DIR/queue/reports/"*_report_${TEST_CMD_ID}.yaml; do
        [ -f "$report_file" ] || continue
        validate_report_format_file "$report_file"
    done

    if [ "$REPORT_FORMAT_CHECKED" -eq 0 ]; then
        echo "  (no report files found for ${TEST_CMD_ID})"
    elif [ "$REPORT_FORMAT_FAILED" -eq 0 ]; then
        echo "  OK (全${REPORT_FORMAT_CHECKED}件フォーマット検証PASS)"
    fi

    [ "$REPORT_FORMAT_FAILED" -eq 0 ]
}

@test "context_update present + stale last_updated: gate blocks" {
    write_cmd_yaml "with_context"
    write_context_file "2025-01-01"
    write_report

    run run_context_update_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"Context update check:"* ]]
    [[ "$output" == *"context_update:context/infrastructure.md:stale"* ]]
}

@test "context_update present + fresh last_updated: gate clears" {
    write_cmd_yaml "with_context"
    write_context_file "2026-03-05"
    write_report

    run run_context_update_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context update check:"* ]]
    [[ "$output" == *"OK: context/infrastructure.md: last_updated=2026-03-05 (cmd=2026-03-04)"* ]]
}

@test "context_update target without causal links section emits WARN" {
    write_cmd_yaml "with_context"
    write_context_file "2026-03-05"
    write_report

    run run_context_update_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"context_update:context/infrastructure.md:causal_links_section_missing"* ]]
}

@test "context md changes auto-update last_updated before context_update check" {
    write_cmd_yaml "with_context"
    write_context_file "2025-01-01"
    write_report
    git -C "$TEST_PROJECT" init -q
    git -C "$TEST_PROJECT" config user.email "test@example.invalid"
    git -C "$TEST_PROJECT" config user.name "Test User"
    git -C "$TEST_PROJECT" add context/infrastructure.md
    git -C "$TEST_PROJECT" commit -q -m "baseline"
    printf '\nnew context detail\n' >> "$TEST_PROJECT/context/infrastructure.md"
    CMD_CHANGED_FILES=""

    run auto_update_context_last_updated_for_changes "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    grep -q "last_updated: .* ${TEST_CMD_ID}" "$TEST_PROJECT/context/infrastructure.md"
}

@test "context_update missing: gate skips and keeps existing behavior" {
    write_cmd_yaml "without_context"
    write_context_file "2025-01-01"
    write_report

    run run_context_update_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context update check:"* ]]
    [[ "$output" == *"SKIP (context_update not set)"* ]]
}

@test "GATE CLEAR emits non-blocking context freshness warning when project context is stale" {
    write_cmd_yaml "without_context"
    write_context_file "2026-03-01"
    write_report
    git -C "$TEST_PROJECT" init -q
    git -C "$TEST_PROJECT" config user.email "test@example.invalid"
    git -C "$TEST_PROJECT" config user.name "Test User"
    git -C "$TEST_PROJECT" add context/infrastructure.md
    git -C "$TEST_PROJECT" commit -q -m "test source update for context/infrastructure.md"
    mkdir -p "$TEST_PROJECT/scripts"
    printf 'source update\n' > "$TEST_PROJECT/scripts/source_change.sh"
    git -C "$TEST_PROJECT" add scripts/source_change.sh
    git -C "$TEST_PROJECT" commit -q -m "test source update for infra script"

    run run_context_freshness_nudge
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context freshness nudge (GATE CLEAR):"* ]]
    [[ "$output" == *"ALERT: context/infrastructure.md source commits"* ]]
}

@test "lesson_impact rows keyed by subtask_id are updated on gate clear" {
    write_cmd_yaml "with_context"
    write_context_file "2026-03-05"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_id: subtask_test
  subtask_id: subtask_test
  assigned_to: sasuke
  task_type: review
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 2
  related_lessons:
    - id: L100
      summary: "first lesson"
    - id: L101
      summary: "second lesson"
EOF

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-04T00:00:00"
status: done
ac_version_read: 2
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful:
  - id: L100
    useful: true
    reason: 'test'
EOF

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-03-04T00:00:00	subtask_test	sasuke	L100	injected	pending	pending	infra	review	routine
2026-03-04T00:00:00	subtask_test	sasuke	L101	injected	pending	pending	infra	review	routine
2026-03-04T00:00:00	cmd_999	sasuke	L101	injected	pending	pending	infra	review	routine
EOF

    run update_lesson_impact_tsv "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]

    run grep -F $'subtask_test\tsasuke\tL100\tinjected\tUSEFUL\tyes' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]

    run grep -F $'subtask_test\tsasuke\tL101\tinjected\tNOT_USEFUL\tno' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]

    run grep -F $'cmd_999\tsasuke\tL101\tinjected\tNOT_USEFUL\tno' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
}

@test "lesson_impact update preserves score and traversal_depth columns" {
    write_cmd_yaml "with_context"
    write_context_file "2026-03-05"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_id: subtask_test
  subtask_id: subtask_test
  assigned_to: sasuke
  task_type: review
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
lessons_useful:
  - id: L100
    useful: true
    reason: 'test'
EOF

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-03-04T00:00:00	subtask_test	sasuke	L100	injected	pending	pending	infra	review	routine	5	1
EOF

    run update_lesson_impact_tsv "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]

    run grep -F $'timestamp\tcmd_id\tninja\tlesson_id\taction\tresult\treferenced\tproject\ttask_type\tbloom_level\tscore\ttraversal_depth' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]

    run grep -F $'subtask_test\tsasuke\tL100\tinjected\tUSEFUL\tyes\tinfra\treview\troutine\t5\t1' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
}

@test "lesson_impact update ignores extra TSV fields instead of crashing" {
    write_cmd_yaml "with_context"
    write_context_file "2026-03-05"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_id: subtask_test
  subtask_id: subtask_test
  assigned_to: sasuke
  task_type: review
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
EOF

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
lessons_useful:
  - id: L100
    useful: true
    reason: 'test'
EOF

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-03-04T00:00:00	subtask_test	sasuke	L100	injected	pending	pending	infra	review	routine	EXTRA_FIELD
EOF

    run update_lesson_impact_tsv "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LESSON_IMPACT: $TEST_CMD_ID updated rows=1"* ]]

    run grep -F $'subtask_test\tsasuke\tL100\tinjected\tUSEFUL\tyes\tinfra\treview\troutine' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    ! grep -q "EXTRA_FIELD" "$TEST_PROJECT/logs/lesson_impact.tsv"
}

@test "B層: normalize OK when report already dict format (exit 1)" {
    write_cmd_yaml "without_context"
    write_report

    run run_normalize_phase
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: OK (no normalization needed)"* ]]
}

@test "B層: normalize WARN when report has list-format lesson_candidate (exit 0)" {
    write_cmd_yaml "without_context"

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-04T00:00:00"
status: done
ac_version_read: 2
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
lesson_candidate:
  - "some lesson in list format"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
EOF

    run run_normalize_phase
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO] sasuke:"* ]]
    [[ "$output" == *"自動修正"* ]] || [[ "$output" == *"auto-fixed"* ]]
}

@test "B層: normalize ERROR when normalize_report.sh is missing (exit 127)" {
    write_cmd_yaml "without_context"
    write_report

    rm "$TEST_PROJECT/scripts/lib/normalize_report.sh"

    run run_normalize_phase
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: ERROR"* ]]
    [[ "$output" == *"normalize_report.sh exit=127"* ]]
}

@test "custom report_filename is included in direct report format validation" {
    write_cmd_yaml "without_context"

    cat > "$TEST_PROJECT/scripts/gates/gate_report_autofix.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/gates/gate_report_format.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == *"custom_gate_target.yaml" ]]; then
    echo "FAIL: custom report hit formatter"
    exit 1
fi
echo "PASS"
EOF
    chmod +x "$TEST_PROJECT/scripts/gates/gate_report_autofix.sh" "$TEST_PROJECT/scripts/gates/gate_report_format.sh"

    write_task_fixture "custom_gate_target.yaml"

    cat > "$TEST_PROJECT/queue/reports/custom_gate_target.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-04T00:00:00"
status: done
ac_version_read: 2
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
result:
  summary: "custom report"
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
    - check: "custom report validated"
      result: "yes"
EOF

    run run_report_format_validation
    [ "$status" -eq 1 ]
    [[ "$output" == *"custom_gate_target.yaml: FAIL: custom report hit formatter"* ]]
}

@test "test_triage pre_existing binary_checks fail is WARN and allows GATE CLEAR" {
    run run_binary_checks_triage_decision "pre_existing"

    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN] sasuke: binary_checks non-PASS"* ]]
    [[ "$output" == *"test_triage=pre_existingのためWARN降格"* ]]
    [[ "$output" == *"GATE CLEAR: cmd完了許可"* ]]
    [[ "$output" != *"sasuke:binary_checks_fail"* ]]
}

@test "test_triage in_branch binary_checks fail remains GATE BLOCK" {
    run run_binary_checks_triage_decision "in_branch"

    [ "$status" -eq 1 ]
    [[ "$output" == *"[CRITICAL] sasuke: NG ← binary_checks has non-PASS results"* ]]
    [[ "$output" == *"GATE BLOCK"* ]]
    [[ "$output" == *"sasuke:binary_checks_fail"* ]]
}

@test "blank test_triage binary_checks fail remains GATE BLOCK" {
    run run_binary_checks_triage_decision ""

    [ "$status" -eq 1 ]
    [[ "$output" == *"[CRITICAL] sasuke: NG ← binary_checks has non-PASS results"* ]]
    [[ "$output" == *"GATE BLOCK"* ]]
    [[ "$output" == *"sasuke:binary_checks_fail"* ]]
}

@test "draft lesson check ignores gate_auto_draft marker but keeps manual drafts blocking" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
assert '--source-marker "gate_auto_draft"' in text

start = text.index('own_draft_count=$(awk -v cmd="${CMD_ID}"')
end = text.index("' \"$DRAFT_LESSONS_FILE\"", start)
block = text[start:end]

assert r'- \*\*source\*\*:[[:space:]]*gate_auto_draft' in block
assert '&& !is_gate_auto_draft' in block
assert 'is_draft && is_own' in block
PY
    [ "$status" -eq 0 ]
}
