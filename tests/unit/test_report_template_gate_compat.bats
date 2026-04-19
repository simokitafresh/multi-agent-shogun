#!/usr/bin/env bats
# test_report_template_gate_compat.bats
# Purpose: deploy_task.shの報告テンプレートがgate_report_format.shをPASSする形式で
#          生成されることを保証する。テンプレート退行を自動検出する抗体テスト。
# Origin: kotaro自己研鑽サイクル4 (deepdive Phase 5: 免疫記憶)

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export GATE_PY="$PROJECT_ROOT/scripts/gates/gate_report_format_combined.py"
    export GATE_AUTOFIX_SH="$PROJECT_ROOT/scripts/gates/gate_report_autofix.sh"
    export GATE_FORMAT_SH="$PROJECT_ROOT/scripts/gates/gate_report_format.sh"
    [ -f "$GATE_PY" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    export BASE_EMPTY_REPORT="$BATS_FILE_TMPDIR/base_empty_report.yaml"
    export BASE_FILLED_REPORT="$BATS_FILE_TMPDIR/base_filled_report.yaml"
    # Pre-generate shared fixtures once. Tests copy them into their workspace.
    _generate_filled_report "$BASE_EMPTY_REPORT" "empty"
    _generate_filled_report "$BASE_FILLED_REPORT" "filled"
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$BATS_FILE_TMPDIR/work"
    rm -rf "$TEST_TMPDIR"
    mkdir -p "$TEST_TMPDIR"
}

# Helper: generate a minimal report that follows the template structure
# Simulates a ninja filling in the template correctly
_generate_filled_report() {
    local outfile="$1"
    local lessons_useful="${2:-empty}"  # "empty" or "filled"

    cat > "$outfile" <<'EOF'
worker_id: test_ninja
task_id: cmd_test
parent_cmd: cmd_test
timestamp: "2026-01-01T00:00:00"
status: done
ac_version_read: abc12345
result:
  summary: "テスト完了"
  details: "テスト詳細"
purpose_validation:
  cmd_purpose: "テスト目的"
  fit: true
  purpose_gap: ""
files_modified:
  - path: scripts/test.sh
    change: "修正"
lesson_candidate:
  found: false
  no_lesson_reason: "テスト報告のため教訓なし"
  title: ""
  detail: ""
  project: infra
EOF

    if [ "$lessons_useful" = "filled" ]; then
        cat >> "$outfile" <<'EOF'
lessons_useful:
  - id: L074
    useful: true
    reason: "テストで使用"
  - id: L225
    useful: false
    reason: "本件スコープ外"
EOF
    else
        cat >> "$outfile" <<'EOF'
lessons_useful: []
EOF
    fi

    cat >> "$outfile" <<'EOF'
skill_candidate:
  found: false
decision_candidate:
  found: false
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
hook_failures:
  count: 0
  details: ""
binary_checks:
  AC1:
    - check: "テスト確認1"
      result: "yes"
  AC2:
    - check: "テスト確認2"
      result: "yes"
verdict: PASS
EOF
}

_prepare_report() {
    local outfile="$1"
    local lessons_useful="${2:-empty}"
    local source="$BASE_EMPTY_REPORT"

    if [ "$lessons_useful" = "filled" ]; then
        source="$BASE_FILLED_REPORT"
    fi

    cp "$source" "$outfile"
}

_run_gate() {
    run python3 "$GATE_PY" "$1"
}

_replace_section() {
    local file="$1"
    local section="$2"
    local replacement="${3-}"
    local tmp="$file.tmp"

    awk -v section="$section" -v replacement="$replacement" '
        BEGIN {
            replacement_len = split(replacement, replacement_lines, "\n")
            in_section = 0
            replaced = 0
        }
        function is_top_level(line) {
            return line ~ /^[A-Za-z_][A-Za-z0-9_]*:/
        }
        {
            if (!replaced && $0 ~ ("^" section ":")) {
                if (replacement != "") {
                    for (i = 1; i <= replacement_len; i++) {
                        print replacement_lines[i]
                    }
                }
                in_section = 1
                replaced = 1
                next
            }

            if (in_section) {
                if (is_top_level($0)) {
                    in_section = 0
                } else {
                    next
                }
            }

            print
        }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

@test "filled report with empty lessons_useful is rejected by gate (GP-064)" {
    # GP-088: gate checks task YAML for related_lessons — create one so empty [] is rejected
    mkdir -p "$TEST_TMPDIR/queue/tasks"
    cat > "$TEST_TMPDIR/queue/tasks/test_ninja.yaml" <<'TASK'
task:
  related_lessons:
    - id: L074
      summary: "test lesson"
TASK
    # Place report under queue/reports/ so dirname(dirname(report)) finds tasks/
    mkdir -p "$TEST_TMPDIR/queue/reports"
    _prepare_report "$TEST_TMPDIR/queue/reports/report.yaml" "empty"
    _run_gate "$TEST_TMPDIR/queue/reports/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"lessons_useful"* ]]
    [[ "$output" == *"empty list"* ]]
}

@test "filled report with populated lessons_useful passes gate" {
    _run_gate "$BASE_FILLED_REPORT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "GP/改善cmdはbefore/after/regression未記入でもWARNを出す" {
    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports"
    cat > "$TEST_TMPDIR/queue/tasks/test_ninja.yaml" <<'TASK'
task:
  title: "強化 — GP/改善にbefore/after退化計測を義務化"
  task_type: impl
TASK
    _prepare_report "$TEST_TMPDIR/queue/reports/test_ninja_report_cmd_1941.yaml" "filled"
    sed -i 's/parent_cmd: cmd_test/parent_cmd: cmd_1941/' "$TEST_TMPDIR/queue/reports/test_ninja_report_cmd_1941.yaml"
    _run_gate "$TEST_TMPDIR/queue/reports/test_ninja_report_cmd_1941.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"GP-199 WARN: before_metrics未記入"* ]]
    [[ "$output" == *"GP-199 WARN: after_metrics未記入"* ]]
    [[ "$output" == *"GP-199 WARN: regression未記入"* ]]
}

@test "通常cmdではbefore/after/regression WARNを出さない" {
    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports"
    cat > "$TEST_TMPDIR/queue/tasks/test_ninja.yaml" <<'TASK'
task:
  title: "通常実装"
  task_type: impl
TASK
    _prepare_report "$TEST_TMPDIR/queue/reports/test_ninja_report_cmd_test.yaml" "filled"
    _run_gate "$TEST_TMPDIR/queue/reports/test_ninja_report_cmd_test.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"GP-199 WARN"* ]]
}

@test "binary_checks as string is rejected by gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "empty"
    _replace_section "$TEST_TMPDIR/report.yaml" "binary_checks" 'binary_checks: "AC1: yes"'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"binary_checks"* ]]
}

@test "lessons_useful null is rejected by gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "empty"
    # Replace empty list with null
    sed -i 's/lessons_useful: \[\]/lessons_useful: null/' "$TEST_TMPDIR/report.yaml"
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"lessons_useful"* ]]
}

@test "lesson_candidate found=true without title is rejected" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "empty"
    _replace_section "$TEST_TMPDIR/report.yaml" "lesson_candidate" $'lesson_candidate:\n  found: true\n  title: ""\n  detail: "test"'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

@test "verdict CONDITIONAL_PASS is rejected by gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "empty"
    sed -i 's/verdict: PASS/verdict: CONDITIONAL_PASS/' "$TEST_TMPDIR/report.yaml"
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"verdict"* ]]
}

@test "verdict PASS passes gate" {
    _run_gate "$BASE_FILLED_REPORT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "binary_checks result PASS is rejected by gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "empty"
    sed -i '0,/result: "yes"/s//result: PASS/' "$TEST_TMPDIR/report.yaml"
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"binary_checks.AC1[0].result"* ]]
}

@test "binary_checks result yes passes gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "empty"
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "verdict FAIL passes gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    sed -i 's/verdict: PASS/verdict: FAIL/' "$TEST_TMPDIR/report.yaml"
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "verdict null is rejected by gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "empty"
    sed -i 's/verdict: PASS/verdict: null/' "$TEST_TMPDIR/report.yaml"
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"verdict"* ]]
}

@test "verdict empty string is rejected by gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "empty"
    sed -i 's/verdict: PASS/verdict: ""/' "$TEST_TMPDIR/report.yaml"
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"verdict"* ]]
}

@test "lessons_useful numbered dict is auto-fixed to list by autofix pre-step (GP-196)" {
    # GP-196: gate_report_format.shのpre-step autofixがnumbered dict→list変換を適用する
    # 旧: 変換なし→gate BLOCK。新: 変換あり→gate PASS
    _prepare_report "$TEST_TMPDIR/report.yaml" "empty"
    _replace_section "$TEST_TMPDIR/report.yaml" "lessons_useful" $'lessons_useful:\n  0:\n    id: L074\n    useful: true\n    reason: test'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    grep -q '^lessons_useful:$' "$TEST_TMPDIR/report.yaml"
    grep -q '^- id: L074$' "$TEST_TMPDIR/report.yaml"
    ! grep -q '^  0:$' "$TEST_TMPDIR/report.yaml"
}

@test "lessons_useful entry missing id is rejected by gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "empty"
    _replace_section "$TEST_TMPDIR/report.yaml" "lessons_useful" $'lessons_useful:\n  - useful: true\n    reason: test'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"missing \"id\""* ]]
}

@test "lessons_useful useful=string is rejected by gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "empty"
    _replace_section "$TEST_TMPDIR/report.yaml" "lessons_useful" $'lessons_useful:\n  - id: L074\n    useful: '\''yes'\''\n    reason: test'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"useful="* ]]
    [[ "$output" == *"must be true or false"* ]]
}

@test "lessons_useful FILL_THIS in useful is rejected by gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "empty"
    _replace_section "$TEST_TMPDIR/report.yaml" "lessons_useful" $'lessons_useful:\n  - id: L074\n    useful: FILL_THIS\n    reason: test'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"FILL_THIS"* ]]
}

@test "binary_checks AC value as string is rejected by gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "empty"
    _replace_section "$TEST_TMPDIR/report.yaml" "binary_checks" $'binary_checks:\n  AC1: yes\n  AC2:\n    - check: ok\n      result: yes'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"binary_checks.AC1"* ]]
    [[ "$output" == *"must be list"* ]]
}

@test "binary_checks AC value as dict is rejected by gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "empty"
    _replace_section "$TEST_TMPDIR/report.yaml" "binary_checks" $'binary_checks:\n  AC1:\n    check: ok\n    result: yes'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"binary_checks.AC1"* ]]
    [[ "$output" == *"must be list"* ]]
}

@test "lesson_candidate found=false without no_lesson_reason is rejected" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "empty"
    _replace_section "$TEST_TMPDIR/report.yaml" "lesson_candidate" $'lesson_candidate:\n  found: false'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"no_lesson_reason"* ]]
}

# --- GP-065: files_modified type validation ---
@test "files_modified as dict is rejected by gate (GP-065)" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _replace_section "$TEST_TMPDIR/report.yaml" "files_modified" $'files_modified:\n  0: path/to/file.py'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"files_modified"* ]]
    [[ "$output" == *"dict"* ]]
}

@test "files_modified as null is rejected by gate (GP-065)" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _replace_section "$TEST_TMPDIR/report.yaml" "files_modified" 'files_modified: null'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"files_modified"* ]]
}

@test "files_modified as string passes gate (GP-065)" {
    _run_gate "$BASE_FILLED_REPORT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# --- GP-071: Template state detection (quality_fix_request skip) ---
# inbox_write.sh内のテンプレート状態検出Pythonロジックを直接テスト

# Helper: run the template detection logic extracted from inbox_write.sh
_detect_template_state() {
    local report_file="$1"
    local verdict
    verdict="$(awk -F': ' '/^verdict:/{print $2; exit}' "$report_file")"

    if [ -z "$verdict" ] || [ "$verdict" = '""' ] || [ "$verdict" = "null" ]; then
        echo "yes"
        return 0
    fi

    if awk '
        /^binary_checks:/ { in_binary_checks = 1; next }
        in_binary_checks && /^[A-Za-z_][A-Za-z0-9_]*:/ { in_binary_checks = 0 }
        in_binary_checks && /result:[[:space:]]*.*FILL_THIS/ { found = 1 }
        END { exit(found ? 0 : 1) }
    ' "$report_file"; then
        echo "yes"
        return 0
    fi

    echo "no"
}

# Helper: generate a template-state report (as deploy_task.sh produces)
_generate_template_report() {
    local outfile="$1"
    cat > "$outfile" <<'EOF'
worker_id: test_ninja
task_id: ""
parent_cmd: cmd_test
timestamp: ""
status: pending
ac_version_read: abc12345
result:
  summary: ""
  details: ""
purpose_validation:
  cmd_purpose: ""
  fit: true
  purpose_gap: ""
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: ""
  title: ""
  detail: ""
  project: infra
lessons_useful:
  - id: L074
    useful: false
    reason: ''
skill_candidate:
  found: false
decision_candidate:
  found: false
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
hook_failures:
  count: 0
  details: ""
binary_checks:
  AC1:
  - check: "FILL_THIS残存時にquality_fix_requestが発火しないことを確認したか"
    result: ""
verdict: ""
EOF
}

@test "GP-071: template state detected when verdict is empty" {
    _generate_template_report "$TEST_TMPDIR/report.yaml"
    run _detect_template_state "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "yes" ]
}

@test "GP-071: template state detected when FILL_THIS in binary_checks result" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _replace_section "$TEST_TMPDIR/report.yaml" "binary_checks" $'binary_checks:\n  AC1:\n    - check: test check\n      result: FILL_THIS'
    run _detect_template_state "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "yes" ]
}

@test "GP-071: non-template detected when verdict=PASS and no FILL_THIS" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    run _detect_template_state "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "no" ]
}

@test "GP-071: non-template detected when verdict=FAIL and no FILL_THIS" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    sed -i 's/verdict: PASS/verdict: FAIL/' "$TEST_TMPDIR/report.yaml"
    run _detect_template_state "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "no" ]
}

# --- Fix 22-26: MISSING field restoration via autofix ---

# === Fix22-28: 消火撤去テスト (2026-03-25) ===
# 旧: autofixがMISSINGフィールドにデフォルト値挿入(消火) → gateがPASS → 家老workaround
# 新: autofixはMISSINGを放置 → gate_report_format.shがBLOCK → 忍者が修正 → 品質向上

@test "Fix22-28撤去: binary_checks MISSING → autofixせず残存 → gate FAIL" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _replace_section "$TEST_TMPDIR/report.yaml" "binary_checks"
    # autofix does NOT restore MISSING fields
    run bash "$GATE_AUTOFIX_SH" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *"binary_checks MISSING"* ]]
    # gate catches it
    run bash "$GATE_FORMAT_SH" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"binary_checks"* ]]
}

@test "Fix22-28撤去: verdict MISSING → autofixせず残存 → gate FAIL" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    sed -i '/^verdict:/d' "$TEST_TMPDIR/report.yaml"
    run bash "$GATE_AUTOFIX_SH" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *"verdict MISSING"* ]]
    run bash "$GATE_FORMAT_SH" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

@test "Fix22-28撤去: files_modified MISSING → autofixせず → gate FAIL" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _replace_section "$TEST_TMPDIR/report.yaml" "files_modified"
    run bash "$GATE_AUTOFIX_SH" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *"files_modified MISSING"* ]]
    run bash "$GATE_FORMAT_SH" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"files_modified"* ]]
}

@test "Fix6撤去: lessons_useful MISSING → autofixせず → gate FAIL" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _replace_section "$TEST_TMPDIR/report.yaml" "lessons_useful"
    # Fix6撤去(cmd_1888): autofix does NOT restore lessons_useful — gate_report_format.sh BLOCKs
    run bash "$GATE_AUTOFIX_SH" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *"lessons_useful MISSING"* ]]
    run bash "$GATE_FORMAT_SH" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"lessons_useful: MISSING"* ]]
}

@test "Fix22-28撤去: lesson_candidate MISSING → autofixせず → gate FAIL" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _replace_section "$TEST_TMPDIR/report.yaml" "lesson_candidate"
    run bash "$GATE_AUTOFIX_SH" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *"lesson_candidate MISSING"* ]]
    run bash "$GATE_FORMAT_SH" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"lesson_candidate"* ]]
}

@test "GP-071: template state when verdict is null" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    sed -i 's/^verdict: PASS$/verdict: null/' "$TEST_TMPDIR/report.yaml"
    run _detect_template_state "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "yes" ]
}

# === self_gate_check value validation (cmd_cycle_001) ===

# Helper: add self_gate_check to a filled report
_add_self_gate_check() {
    local outfile="$1"
    local lesson_ref="${2:-PASS}"
    local lesson_candidate="${3:-PASS}"
    local status_valid="${4:-PASS}"
    local purpose_fit="${5:-PASS}"
    cat >> "$outfile" <<EOF
self_gate_check:
  lesson_ref: "${lesson_ref}"
  lesson_candidate: "${lesson_candidate}"
  status_valid: "${status_valid}"
  purpose_fit: "${purpose_fit}"
EOF
}

@test "self_gate_check result=ok is rejected by gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _add_self_gate_check "$TEST_TMPDIR/report.yaml" "ok" "PASS" "PASS" "PASS"
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"self_gate_check.lesson_ref"* ]]
    [[ "$output" == *"ok"* ]]
}

@test "self_gate_check result=PASS passes gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _add_self_gate_check "$TEST_TMPDIR/report.yaml" "PASS" "PASS" "PASS" "PASS"
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "self_gate_check result=FAIL passes gate (FAIL is valid value)" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _add_self_gate_check "$TEST_TMPDIR/report.yaml" "PASS" "FAIL" "PASS" "PASS"
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "self_gate_check absent does not cause gate failure (impl tasks)" {
    # BASE_FILLED_REPORT has no self_gate_check — simulates impl task
    _run_gate "$BASE_FILLED_REPORT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# === Fix5 Step3復活テスト: 散文binary_checksをlist構造に変換 ===
# cmd_1496でFix5 Step3復活: 散文テキストをcheck名に使用しresult='yes'固定でlist化
# 旧Step3(YES/NO推定)とは異なり、文字列をそのままcheck名に使うため情報捏造なし

@test "Fix5-Step3復活: binary_checks散文 → autofixでlist変換" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _replace_section "$TEST_TMPDIR/report.yaml" "binary_checks" $'binary_checks:\n  AC1: API接続確認済み、全てPASS、問題なし'
    # Fix5 Step3(cmd_1496復活): autofix converts prose to [{check: prose, result: 'yes'}]
    run bash "$GATE_AUTOFIX_SH" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    grep -q '^binary_checks:$' "$TEST_TMPDIR/report.yaml"
    grep -q '^  AC1:$' "$TEST_TMPDIR/report.yaml"
    grep -q '^  - check: API接続確認済み、全てPASS、問題なし$' "$TEST_TMPDIR/report.yaml"
    grep -q "^    result: 'yes'$" "$TEST_TMPDIR/report.yaml"
}

# === GP-104撤去テスト: GP-091 YAML parse修復がautofixされないことを確認 ===
# 消火パターン: YAML parse errorをダミーコンテンツで修復(壊れたYAMLを偽装)
# 期待: autofixはUNFIXABLEで終了

# === GP-106撤去テスト: ac_version_read自動補完がautofixされないことを確認 ===
# 消火パターン: ac_version_read欠落→タスクYAMLから自動補完(attestation無力化)
# 期待: autofixは補完せず、ac_version_readは空のまま

@test "GP-106撤去: ac_version_read欠落 → autofixせず → gate FAIL" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    # ac_version_readを消去
    sed -i '/^ac_version_read:/d' "$TEST_TMPDIR/report.yaml"
    # autofixが補完しないことを確認
    run bash "$GATE_AUTOFIX_SH" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    run bash -c "grep -qE '^ac_version_read:' '$TEST_TMPDIR/report.yaml' && echo FILLED || echo MISSING"
    [[ "$output" == *"MISSING"* ]]
    # format gateがBLOCKすることを確認
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

@test "GP-104撤去: YAML parse error → autofix UNFIXABLE (ダミーコンテンツ生成なし)" {
    # 意図的にYAML parse errorを起こす(lesson_candidate scalar + orphaned children)
    cat > "$TEST_TMPDIR/broken.yaml" <<'BROKEN'
worker_id: test_ninja
parent_cmd: cmd_test
lesson_candidate: "some string value"
  found: true
  title: "orphaned"
verdict: PASS
BROKEN
    run bash "$GATE_AUTOFIX_SH" "$TEST_TMPDIR/broken.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"UNFIXABLE"* ]]
    [[ "$output" == *"YAML parse error"* ]]
}

# === GP-108テスト: FIXヒント完全化+重複排除 ===

@test "GP-108: lesson_candidate found=false no_reason → FIX hint表示" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _replace_section "$TEST_TMPDIR/report.yaml" "lesson_candidate" $'lesson_candidate:\n  found: false'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no_lesson_reason"* ]]
    [[ "$output" == *"FIX (lesson_candidate)"* ]]
}

@test "GP-108: self_gate_check as string → FIX hint表示" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    echo 'self_gate_check: "all good"' >> "$TEST_TMPDIR/report.yaml"
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"self_gate_check: is str"* ]]
    [[ "$output" == *"FIX (self_gate_check)"* ]]
}

@test "GP-108: lessons_useful null → FIX hint表示" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _replace_section "$TEST_TMPDIR/report.yaml" "lessons_useful" 'lessons_useful: null'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"lessons_useful: null"* ]]
    [[ "$output" == *"FIX (lessons_useful)"* ]]
}

@test "GP-108: ヒント重複排除 — 3つのreason emptyで1つのFIX hint" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _replace_section "$TEST_TMPDIR/report.yaml" "lessons_useful" $'lessons_useful:\n  - id: L001\n    useful: true\n    reason: ""\n  - id: L002\n    useful: true\n    reason: ""\n  - id: L003\n    useful: false\n    reason: ""'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    # 3つのエラーがセミコロン区切りで1行に出る
    local error_count
    error_count=$(echo "$output" | grep -o "reason is empty" | wc -l)
    [ "$error_count" -ge 3 ]
    # FIXヒントは1つだけ（[N]で正規化）
    local hint_count
    hint_count=$(echo "$output" | grep -c "FIX (lessons_useful" || true)
    [ "$hint_count" -eq 1 ]
    # ヒントに[N]が含まれる
    [[ "$output" == *"lessons_useful[N]"* ]]
    [[ "$output" == *'L246のreturn 1罠と一致し、set -e呼出元確認の指針として有用'* ]]
    [[ "$output" == *'今回の変更では未使用。対象箇所と無関係'* ]]
}

# --- GP-163: verdict=PASS + empty binary_checks result contradiction (cmd_1663) ---

@test "GP-163: verdict=PASS with empty BC result is rejected by gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _replace_section "$TEST_TMPDIR/report.yaml" "binary_checks" $'binary_checks:\n  AC1:\n    - check: "テスト確認1"\n      result: "yes"\n  AC2:\n    - check: "矛盾検出確認"\n      result: ""'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"verdict: PASS but binary_checks contain empty result"* ]]
}

@test "GP-163: verdict=PASS with null BC result is rejected by gate" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _replace_section "$TEST_TMPDIR/report.yaml" "binary_checks" $'binary_checks:\n  AC1:\n    - check: "テスト確認"\n      result: null\n  AC2:\n    - check: "テスト確認2"\n      result: "yes"'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"verdict: PASS but binary_checks contain empty result"* ]]
}

@test "GP-163: verdict=PASS with all results filled passes gate" {
    _run_gate "$BASE_FILLED_REPORT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "GP-163: verdict=FAIL with empty BC result does not trigger contradiction error" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    _replace_section "$TEST_TMPDIR/report.yaml" "binary_checks" $'binary_checks:\n  AC1:\n    - check: "テスト確認1"\n      result: "yes"\n  AC2:\n    - check: "矛盾検出確認"\n      result: ""'
    sed -i 's/^verdict: PASS$/verdict: FAIL/' "$TEST_TMPDIR/report.yaml"
    _run_gate "$TEST_TMPDIR/report.yaml"
    # verdict=FAILなので矛盾エラーは出ない（ただし空resultの個別エラーは出る）
    [[ "$output" != *"verdict: PASS but binary_checks contain empty result"* ]]
}

# --- GP-202: files_modified×parent_cmdプレフィックス不一致WARN (LK069/cmd_1948事故) ---

@test "GP-202: files_modifiedにparent_cmdプレフィックスが0件 → WARN表示" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    # parent_cmd=cmd_testだがfiles_modifiedにcmd_testを含まないファイルのみ
    sed -i 's/^parent_cmd: cmd_test$/parent_cmd: cmd_1948/' "$TEST_TMPDIR/report.yaml"
    _replace_section "$TEST_TMPDIR/report.yaml" "files_modified" $'files_modified:\n  - path: scripts/oneshot/cmd_1947_l3_ew_combo_stability.py\n    change: modified\n  - path: outputs/analysis/cmd_1947_l3_onebody_stability.csv\n    change: modified'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [[ "$output" == *"GP-202 WARN"* ]]
    [[ "$output" == *"cmd_1948"* ]]
}

@test "GP-202: files_modifiedにparent_cmdプレフィックスが含まれる → WARN非表示" {
    _prepare_report "$TEST_TMPDIR/report.yaml" "filled"
    sed -i 's/^parent_cmd: cmd_test$/parent_cmd: cmd_1948/' "$TEST_TMPDIR/report.yaml"
    _replace_section "$TEST_TMPDIR/report.yaml" "files_modified" $'files_modified:\n  - path: outputs/analysis/cmd_1948_l3_1body_1x1.csv\n    change: modified\n  - path: scripts/oneshot/cmd_1948_nbody_1x1.py\n    change: modified'
    _run_gate "$TEST_TMPDIR/report.yaml"
    [[ "$output" != *"GP-202 WARN"* ]]
}
