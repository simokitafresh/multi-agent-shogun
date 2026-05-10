#!/usr/bin/env bats
# test_deploy_task_ac_handling.bats
# Consolidated from:
#   test_deploy_task_ac_verify (8)
#   test_deploy_task_ac_version (35)
# Total: 43 tests

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_acv"
    # shellcheck disable=SC1090
    source "$TEST_PROJECT/scripts/lib/field_get.sh"

    # Default task for ac_version tests
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac_version test"
  task_type: review
  acceptance_criteria:
    - ac1: first
    - ac2: second
    - ac3: third
EOF

    # Extra directories for ac_verify tests (use TEST_TMPDIR directly)
    mkdir -p \
        "$TEST_TMPDIR/queue/tasks" \
        "$TEST_TMPDIR/queue/archive/cmds"

    # SCRIPT_DIR for verify_ac_consistency (ac_verify tests use TEST_TMPDIR)
    export SCRIPT_DIR="$TEST_TMPDIR"
    export LOG="/dev/null"

    # log stub
    log() { echo "[DEPLOY] $1" >&2; }
    export -f log

    # Extract verify_ac_consistency function for ac_verify tests
    eval "$(sed -n '/^verify_ac_consistency()/,/^}/p' "$SRC_DEPLOY_SCRIPT")"
}

teardown() {
    deploy_task_teardown
}

# ─── Helper functions for ac_version tests ───

task_file() {
    printf '%s\n' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
}

task_field_kind() {
    local field_name="$1"

    awk -v field="$field_name" '
        BEGIN {
            in_task = 0
            found = 0
        }
        /^task:[[:space:]]*$/ {
            in_task = 1
            next
        }
        in_task && /^[^[:space:]]/ {
            exit
        }
        !in_task {
            next
        }
        $0 ~ ("^  " field ":[[:space:]]*\\[[^]]*\\][[:space:]]*$") {
            print "list"
            found = 1
            exit
        }
        $0 ~ ("^  " field ":[[:space:]]*$") {
            print "list"
            found = 1
            exit
        }
        $0 ~ ("^  " field ":[[:space:]]+") {
            print "scalar"
            found = 1
            exit
        }
        END {
            if (!found) {
                print "missing"
            }
        }
    ' "$(task_file)"
}

task_list_to_pipe() {
    local value="$1"

    if [ -z "$value" ] || [ "$value" = "[]" ]; then
        printf '\n'
        return
    fi

    value="${value#[}"
    value="${value%]}"
    printf '%s\n' "$value" | sed -E 's/[[:space:]]*,[[:space:]]*/|/g'
}

task_list_field_value() {
    local field_name="$1"

    awk -v field="$field_name" '
        BEGIN {
            in_task = 0
            capture = 0
            first = 1
        }
        /^task:[[:space:]]*$/ {
            in_task = 1
            next
        }
        in_task && /^[^[:space:]]/ {
            exit
        }
        !in_task {
            next
        }
        capture {
            if ($0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) {
                exit
            }
            if ($0 ~ /^  -[[:space:]]*/) {
                item = $0
                sub(/^  -[[:space:]]*/, "", item)
                printf "%s%s", first ? "" : "|", item
                first = 0
            }
            next
        }
        $0 ~ ("^  " field ":[[:space:]]*\\[[^]]*\\][[:space:]]*$") {
            item = $0
            sub("^  " field ":[[:space:]]*\\[", "", item)
            sub("\\][[:space:]]*$", "", item)
            gsub(/[[:space:]]*,[[:space:]]*/, "|", item)
            print item
            exit
        }
        $0 ~ ("^  " field ":[[:space:]]*$") {
            capture = 1
        }
    ' "$(task_file)"
}

read_task_ac_version() {
    FIELD_GET_NO_LOG=1 field_get "$(task_file)" "ac_version" "" 2>/dev/null
}

read_task_report_path() {
    FIELD_GET_NO_LOG=1 field_get "$(task_file)" "report_path" "" 2>/dev/null
}

read_task_field() {
    local field_name="$1"
    local kind value

    kind="$(task_field_kind "$field_name")"
    case "$kind" in
        missing)
            printf '__missing__\n'
            ;;
        list)
            value="$(task_list_field_value "$field_name")"
            printf 'list\n'
            task_list_to_pipe "$value"
            ;;
        scalar)
            FIELD_GET_NO_LOG=1 field_get "$(task_file)" "$field_name" "" 2>/dev/null
            ;;
    esac
}

read_task_fields() {
    local field_name
    for field_name in "$@"; do
        FIELD_GET_NO_LOG=1 field_get "$(task_file)" "$field_name" "" 2>/dev/null
    done
}

read_related_detail() {
    local lesson_id="$1"
    TASK_FILE_ENV="$TEST_PROJECT/queue/tasks/sasuke.yaml" LESSON_ID_ENV="$lesson_id" python3 -c "
import os, yaml
with open(os.environ['TASK_FILE_ENV'], encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
related = (data.get('task') or {}).get('related_lessons') or []
target = os.environ['LESSON_ID_ENV']
for entry in related:
    if str(entry.get('id', '')) == target:
        print(str(entry.get('detail', '')))
        break
"
}

# ═══════════════════════════════════════════════════════════
# ac_verify tests (from test_deploy_task_ac_verify.bats)
# verify_ac_consistency: AC count/ID mismatch WARNING (cmd_1668)
# ═══════════════════════════════════════════════════════════

# ─── AC1: WARNING on count mismatch ───

@test "verify_ac_consistency: WARNING when task AC count differs from cmd source" {
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_500:
    acceptance_criteria:
    - 'AC1: first criterion'
    - 'AC2: second criterion'
    - 'AC3: third criterion'
    project: testproj
    purpose: test ac verify
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac verify count mismatch"
  task_type: impl
  parent_cmd: cmd_500
  task_id: cmd_500_impl
  worker_id: sasuke
  status: assigned
  acceptance_criteria:
  - id: AC1
    description: first criterion
  - id: AC2
    description: second criterion
  ac_version: aabbccdd
  _ac_task_id: cmd_500_impl
  _ac_worker_id: sasuke
EOF

    run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]

    [[ "$output" == *"[AC_VERIFY] WARNING: AC count mismatch"* ]]
    [[ "$output" == *"task=2"* ]]
    [[ "$output" == *"cmd_source=3"* ]]
}

@test "verify_ac_consistency: WARNING when task has more ACs than cmd source" {
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_501:
    acceptance_criteria:
    - 'AC1: only criterion'
    project: testproj
    purpose: test ac verify
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac verify extra ACs"
  task_type: impl
  parent_cmd: cmd_501
  task_id: cmd_501_impl
  worker_id: sasuke
  status: assigned
  acceptance_criteria:
  - id: AC1
    description: only criterion
  - id: AC2
    description: extra AC not in cmd
  - id: AC3
    description: another extra
  ac_version: aabbccdd
  _ac_task_id: cmd_501_impl
  _ac_worker_id: sasuke
EOF

    run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]

    [[ "$output" == *"[AC_VERIFY] WARNING: AC count mismatch"* ]]
}

# ─── AC1: WARNING on ID mismatch ───

@test "verify_ac_consistency: WARNING when AC IDs differ (same count)" {
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_502:
    acceptance_criteria:
    - id: AC1
      description: first
    - id: AC2
      description: second
    project: testproj
    purpose: test ac verify
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac verify id mismatch"
  task_type: impl
  parent_cmd: cmd_502
  task_id: cmd_502_impl
  worker_id: sasuke
  status: assigned
  acceptance_criteria:
  - id: AC1
    description: first
  - id: AC9
    description: wrong id
  ac_version: aabbccdd
  _ac_task_id: cmd_502_impl
  _ac_worker_id: sasuke
EOF

    run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]

    [[ "$output" == *"[AC_VERIFY] WARNING: AC id mismatch"* ]]
}

# ─── AC2: No WARNING on correct injection ───

@test "verify_ac_consistency: OK (no WARNING) when ACs match after overwrite" {
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_503:
    acceptance_criteria:
    - id: AC1
      description: first criterion
    - id: AC2
      description: second criterion
    project: testproj
    purpose: test ac verify
EOF

    # Fresh deploy (no _ac_task_id) → verify should show OK
    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac verify match"
  task_type: impl
  parent_cmd: cmd_503
  task_id: cmd_503_impl
  acceptance_criteria:
  - id: AC1
    description: first criterion
  - id: AC2
    description: second criterion
EOF

    run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]

    if [[ "$output" == *"[AC_VERIFY] WARNING"* ]]; then
        echo "Unexpected WARNING found in output: $output" >&2
        return 1
    fi

    [[ "$output" == *"[AC_VERIFY] OK"* ]]
}

@test "verify_ac_consistency: OK when ACs already match (no overwrite needed)" {
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_510:
    acceptance_criteria:
    - id: AC1
      description: first
    - id: AC2
      description: second
    project: testproj
    purpose: test
EOF

    # Same _ac_task_id/worker_id → overwrite skipped, but ACs already correct
    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac verify already correct"
  task_type: impl
  parent_cmd: cmd_510
  task_id: cmd_510_impl
  worker_id: sasuke
  status: assigned
  acceptance_criteria:
  - id: AC1
    description: first
  - id: AC2
    description: second
  ac_version: aabbccdd
  _ac_task_id: cmd_510_impl
  _ac_worker_id: sasuke
EOF

    run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]

    [[ "$output" == *"[AC_VERIFY] OK"* ]]
    if [[ "$output" == *"[AC_VERIFY] WARNING"* ]]; then
        echo "Unexpected WARNING: $output" >&2
        return 1
    fi
}

# ─── Edge: SKIP when no cmd source found ───

@test "verify_ac_consistency: SKIP when parent_cmd not in shogun_to_karo or archive" {
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands: {}
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac verify no source"
  task_type: impl
  parent_cmd: cmd_999
  task_id: cmd_999_impl
  worker_id: sasuke
  status: assigned
  acceptance_criteria:
  - id: AC1
    description: first
  ac_version: aabbccdd
  _ac_task_id: cmd_999_impl
  _ac_worker_id: sasuke
EOF

    run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]

    [[ "$output" == *"[AC_VERIFY] SKIP"* ]]
    if [[ "$output" == *"[AC_VERIFY] WARNING"* ]]; then
        echo "Unexpected WARNING: $output" >&2
        return 1
    fi
}

@test "verify_ac_consistency: SKIP when task has no parent_cmd" {
    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac verify no parent"
  task_type: impl
  acceptance_criteria:
  - id: AC1
    description: first
EOF

    run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]

    if [[ "$output" == *"[AC_VERIFY] WARNING"* ]]; then
        echo "Unexpected WARNING: $output" >&2
        return 1
    fi
}

# ─── Edge: string-format ACs in cmd source ───

@test "verify_ac_consistency: handles string-format ACs (AC1: desc) matching dict-format task ACs" {
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_504:
    acceptance_criteria:
    - 'AC1: string format first'
    - 'AC2: string format second'
    project: testproj
    purpose: test ac verify
EOF

    # _ac_task_id matches → overwrite skipped → verify checks
    # Task has dict-format ACs with matching IDs (AC1, AC2)
    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac verify string format"
  task_type: impl
  parent_cmd: cmd_504
  task_id: cmd_504_impl
  worker_id: sasuke
  status: assigned
  acceptance_criteria:
  - id: AC1
    description: string format first
  - id: AC2
    description: string format second
  ac_version: aabbccdd
  _ac_task_id: cmd_504_impl
  _ac_worker_id: sasuke
EOF

    run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]

    [[ "$output" == *"[AC_VERIFY] OK"* ]]
    if [[ "$output" == *"[AC_VERIFY] WARNING"* ]]; then
        echo "Unexpected WARNING: $output" >&2
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════
# ac_version tests (from test_deploy_task_ac_version.bats)
# ac_version injection + if_then lesson detail behavior
# ═══════════════════════════════════════════════════════════

@test "deploy_task injects ac_version and report ac_version_read on first deploy" {
    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_ac_version
    [ "$status" -eq 0 ]
    [ "$output" = "7d010443" ]

    run grep -E "^ac_version_read:[[:space:]]*7d010443$" "$TEST_PROJECT/queue/reports/sasuke_report.yaml"
    [ "$status" -eq 0 ]

    run read_task_field stop_for
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]
    [ "${lines[1]}" = "" ]

    run read_task_field never_stop_for
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]
    [[ "${lines[1]}" == *"CDPポート未応答"* ]]
    [[ "${lines[1]}" == *"自動対処機能"* ]]
    [[ "${lines[1]}" == *"自明な修正"* ]]
    [[ "${lines[1]}" == *"9p stall/hang疑い"* ]]

    run read_task_field parallel_ok
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]
    [ "${lines[1]}" = "AC1|AC2|AC3" ]

    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "AC1 > AC2 > AC3" ]

    run read_task_field ac_checkpoint
    [ "$status" -eq 0 ]
    [ "$output" = "各AC完了後に checkpoint: 次ACの前提条件確認 → scope drift検出 → progress更新" ]
}

@test "deploy_task pre-fills binary_checks from 3 ACs plus commit without outer quotes" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "binary_checks prefill test"
  task_type: impl
  parent_cmd: cmd_1731
  task_id: cmd_1731_impl
  project: infra
  acceptance_criteria:
    - id: AC1
      checks:
        - check: "first check"
    - id: AC2
      checks:
        - check: "'quoted check'"
    - id: AC3
      checks:
        - check: "third check"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run python3 - <<EOF
import yaml
from pathlib import Path

report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
bc = data["binary_checks"]

assert list(bc.keys()) == ["AC1", "AC2", "AC3", "commit"], bc.keys()
assert bc["AC1"][0]["check"] == "first check"
assert bc["AC2"][0]["check"] == "quoted check"
assert bc["AC3"][0]["check"] == "third check"
assert bc["commit"][0]["check"] == "git commitが完了したか(untracked/modified=0)"

item_count = sum(len(items) for items in bc.values())
assert item_count == 4, item_count
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "cmd_2528: deploy_task pre-fills idless ACs as AC1.. and avoids MISSING diagnostics" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "cmd_2528 template completeness"
  task_type: impl
  parent_cmd: cmd_2528
  task_id: cmd_2528_normal
  project: infra
  ac_version: 7d010443
  acceptance_criteria:
    - description: "deploy_task.sh generate_report_template()が生成するYAMLに9項目のデフォルト値が含まれる"
    - description: "gate_report_formatで9項目のMISSING検出が0になる"
    - description: "deploy_task関連テスト+gate_report_format関連テストがbats実行でPASS(SKIP=0)"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run python3 - <<EOF
import yaml
from pathlib import Path

data = yaml.safe_load(Path("$report_path").read_text(encoding="utf-8"))
for key in [
    "assumption_invalidation",
    "binary_checks",
    "ac_version_read",
    "purpose_validation",
    "files_modified",
    "lessons_useful",
    "worker_id",
    "parent_cmd",
]:
    assert key in data, key
assert isinstance(data["result"], dict) and data["result"].get("summary") == ""
assert list(data["binary_checks"].keys()) == ["AC1", "AC2", "AC3", "commit"], data["binary_checks"].keys()
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]

    run env GATE_NO_LOG=1 bash "$PROJECT_ROOT/scripts/gates/gate_report_format.sh" "$report_path"
    [ "$status" -eq 1 ]
    [[ "$output" != *"worker_id: MISSING"* ]]
    [[ "$output" != *"parent_cmd: MISSING"* ]]
    [[ "$output" != *"ac_version_read: MISSING"* ]]
    [[ "$output" != *"purpose_validation: MISSING"* ]]
    [[ "$output" != *"files_modified: MISSING"* ]]
    [[ "$output" != *"lessons_useful: MISSING"* ]]
    [[ "$output" != *"binary_checks: MISSING"* ]]
    [[ "$output" != *"assumption_invalidation: MISSING"* ]]
    [[ "$output" == *"result.summary: MISSING or empty"* ]]
}

@test "deploy_task rewrites generic full-test AC to affected_tests workflow in report template" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "affected tests template"
  task_type: impl
  parent_cmd: cmd_1942
  task_id: cmd_1942_impl
  project: infra
  acceptance_criteria:
    - id: AC1
      description: "全テストPASS(bats --jobs 4 tests/unit)"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run python3 - <<EOF
import yaml
from pathlib import Path

report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
check = data["binary_checks"]["AC1"][0]["check"]

assert "bash scripts/affected_tests.sh" in check, check
assert "bats --jobs 4 tests/unit" in check, check
assert "フォールバック" in check, check
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "deploy_task injects gate_fail_top3 warnings above matching report fields" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "gate warning injection test"
  task_type: impl
  parent_cmd: cmd_1734
  task_id: cmd_1734_impl
  project: infra
  acceptance_criteria:
    - id: AC1
      checks:
        - check: "warning comment injected"
  ninja_weak_points:
    gate_fail_top3:
      - pattern: verdict_invalid
        count: 5
      - pattern: bc_result_empty
        count: 3
      - pattern: lesson_candidate_no_reason_empty
        count: 2
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run grep -F '# ⚠ あなたの頻出FAIL: verdictは"PASS"/"FAIL"の二値のみ' "$report_path"
    [ "$status" -eq 0 ]
    run grep -F '# ⚠ あなたの頻出FAIL: binary_checksの各resultに"yes"/"no"を記入' "$report_path"
    [ "$status" -eq 0 ]
    run grep -F '# ⚠ あなたの頻出FAIL: lesson_candidate.found=false時はno_lesson_reasonに理由記入' "$report_path"
    [ "$status" -eq 0 ]

    run python3 - <<EOF
from pathlib import Path

lines = Path("$report_path").read_text(encoding="utf-8").splitlines()
verdict_idx = next(i for i, line in enumerate(lines) if line.startswith('verdict: "'))
binary_checks_idx = lines.index('binary_checks:')
no_lesson_idx = next(i for i, line in enumerate(lines) if line.startswith('  no_lesson_reason:'))
assert lines[verdict_idx - 1] == '# ⚠ あなたの頻出FAIL: verdictは"PASS"/"FAIL"の二値のみ'
assert lines[binary_checks_idx - 1] == '# ⚠ あなたの頻出FAIL: binary_checksの各resultに"yes"/"no"を記入'
assert lines[no_lesson_idx - 1] == '# ⚠ あなたの頻出FAIL: lesson_candidate.found=false時はno_lesson_reasonに理由記入'
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "deploy_task injects lessons_useful reason examples when related_lessons exist" {
    mkdir -p "$TEST_PROJECT/projects/testproj"
    cat > "$TEST_PROJECT/projects/testproj/lessons.yaml" <<'EOF'
lessons:
  - id: L246
    title: set -e return code lesson
    summary: summary
    detail: detail
    status: confirmed
    tags: [universal]
    helpful_count: 10
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "lessons_useful reason example injection"
  task_type: impl
  parent_cmd: cmd_reason_examples
  task_id: cmd_reason_examples_impl
  project: testproj
  acceptance_criteria:
    - id: AC1
      description: "report template is generated"
EOF

    run deploy_task_fast sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run grep -F 'L246のreturn 1罠と一致し、set -e呼出元確認の指針として有用' "$report_path"
    [ "$status" -eq 0 ]
    run grep -F '今回の変更では未使用。対象箇所と無関係' "$report_path"
    [ "$status" -eq 0 ]
}

@test "deploy_task leaves template unchanged when gate_fail_top3 is absent" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "no gate warning test"
  task_type: impl
  parent_cmd: cmd_1734
  task_id: cmd_1734_impl
  project: infra
  acceptance_criteria:
    - id: AC1
      checks:
        - check: "no warning comment"
  ninja_weak_points:
    warning: "⚠ report_field_set.sh必ず使用"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run grep -F '# ⚠ あなたの頻出FAIL:' "$report_path"
    [ "$status" -ne 0 ]
}

@test "cmd_2164: learned prefills annotate targeted placeholders and keep gate blocking on empty values" {
    cat > "$TEST_PROJECT/logs/gate_report_format_learning.yaml" <<'EOF'
threshold: 10
patterns:
  bc_result_empty:
    count: 12
    prefill_active: true
    prefill_field: binary_checks.result
  files_modified_missing:
    count: 14
    prefill_active: true
    prefill_field: files_modified
  lu_reason_empty:
    count: 11
    prefill_active: true
    prefill_field: lessons_useful.reason
  result_summary_empty:
    count: 13
    prefill_active: true
    prefill_field: result.summary
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "learned generic prefill injection test"
  task_type: impl
  parent_cmd: cmd_2164
  task_id: cmd_2164_impl
  project: infra
  acceptance_criteria:
    - id: AC1
      checks:
        - check: "学習済みtemplateが挿入される"
  related_lessons:
    - id: L246
      title: "dummy"
      summary: "dummy"
      detail: "dummy"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run grep -F '# AUTO-PREFILL: gate_report_format学習済み — reason空欄再発防止。具体理由を記入せよ' "$report_path"
    [ "$status" -eq 0 ]
    run grep -F '# AUTO-PREFILL: gate_report_format学習済み — result空欄再発防止。yes/noを記入せよ' "$report_path"
    [ "$status" -eq 0 ]
    run grep -F '# AUTO-PREFILL: gate_report_format学習済み — result.summary空欄再発防止。要約を記入せよ' "$report_path"
    [ "$status" -eq 0 ]
    run grep -F '# AUTO-PREFILL: gate_report_format学習済み — files_modified未記入再発防止。変更ファイル一覧を記入せよ' "$report_path"
    [ "$status" -eq 0 ]
    run grep -F 'FILL_THIS' "$report_path"
    [ "$status" -ne 0 ]

    run env GATE_NO_LOG=1 bash "$PROJECT_ROOT/scripts/gates/gate_report_format.sh" "$report_path"
    [ "$status" -eq 1 ]
    # cmd_2665: no_lesson_reason now has a default value, so this check no longer fires
    # gate_report_format.sh also removed this check in 44b191b8
    [[ "$output" != *"files_modified: MISSING"* ]]
    [[ "$output" == *"binary_checks.AC1[0].result: 空文字"* ]]
    [[ "$output" == *"result.summary: MISSING or empty"* ]]
    [[ "$output" != *"FILL_THIS"* ]]
}

# Duplicate ac_version/modifier/report-path tests are covered by test_deploy_task_ac_version.bats.
@test "deploy_task injects all related_lessons when below MAX_INJECT=10" {
    mkdir -p "$TEST_PROJECT/projects/testproj"
    cat > "$TEST_PROJECT/projects/testproj/lessons.yaml" <<'EOF'
lessons:
  - id: L910
    title: rollback safeguard
    summary: rollback branch before deploy cutover
    status: confirmed
    helpful_count: 10
  - id: L911
    title: database migration guard
    summary: database schema check before release
    status: confirmed
    helpful_count: 9
  - id: L912
    title: cache invalidation order
    summary: cache purge after config update
    status: confirmed
    helpful_count: 8
  - id: L913
    title: notification fallback route
    summary: notification fallback when primary webhook fails
    status: confirmed
    helpful_count: 7
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "deploy rollback database cache notification rollout"
  description: "validate rollback database cache notification lesson injection cap"
  task_type: impl
  project: testproj
  acceptance_criteria:
    - AC1
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
related = (data.get('task') or {}).get('related_lessons') or []
assert len(related) == 4, related
print(len(related))
"
    [ "$status" -eq 0 ]
    [ "$output" = "4" ]
}

@test "deploy_task tag fallback injects all tag-matched lessons below MAX_INJECT=10" {
    mkdir -p "$TEST_PROJECT/projects/testproj"
    cat > "$TEST_PROJECT/projects/testproj/lessons.yaml" <<'EOF'
lessons:
  - id: L920
    title: amber lantern
    summary: orbit maple quartz
    status: confirmed
    helpful_count: 4
    tags: [deploy]
  - id: L921
    title: cobalt harbor
    summary: velvet prism harbor
    status: confirmed
    helpful_count: 9
    tags: [deploy]
  - id: L922
    title: ember satellite
    summary: lattice canyon signal
    status: confirmed
    helpful_count: 7
    tags: [deploy]
  - id: L923
    title: fable orchard
    summary: copper meadow syntax
    status: confirmed
    helpful_count: 6
    tags: [deploy]
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "deploy rollout"
  description: "trigger tag fallback without keyword overlap"
  task_type: impl
  project: testproj
  acceptance_criteria:
    - AC1
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
related = (data.get('task') or {}).get('related_lessons') or []
ids = [entry.get('id') for entry in related]
assert len(related) == 4, related
assert ids == ['L921', 'L922', 'L923', 'L920'], ids
print('|'.join(ids))
"
    [ "$status" -eq 0 ]
    [ "$output" = "L921|L922|L923|L920" ]
}

@test "deploy_task injects cross-project lessons when command keywords match lesson title threshold" {
    mkdir -p "$TEST_PROJECT/projects/mainproj" "$TEST_PROJECT/projects/otherproj"
    cat > "$TEST_PROJECT/config/projects.yaml" <<'EOF'
projects:
  - id: mainproj
    name: "Main"
    status: active
  - id: otherproj
    name: "Other"
    status: active
current_project: mainproj
EOF

    cat > "$TEST_PROJECT/projects/mainproj/lessons.yaml" <<'EOF'
lessons:
  - id: L930
    title: local deploy checklist
    summary: local summary
    status: confirmed
    helpful_count: 3
EOF

    cat > "$TEST_PROJECT/projects/otherproj/lessons.yaml" <<'EOF'
lessons:
  - id: L931
    title: cache invalidation sequencing
    summary: cross-project match
    status: confirmed
    helpful_count: 8
    tags: [database]
  - id: L932
    title: unrelated observability lesson
    summary: should stay out
    status: confirmed
    helpful_count: 9
    tags: [ops]
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "cross-project injection"
  description: "validate other project lesson opt-in"
  command: "Run cache invalidation sequencing before deploy cutover."
  task_type: impl
  project: mainproj
  acceptance_criteria:
    - AC1
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
related = (data.get('task') or {}).get('related_lessons') or []
ids = [entry.get('id') for entry in related]
assert 'L931' in ids, ids
assert 'L932' not in ids, ids
print('|'.join(ids))
"
    [ "$status" -eq 0 ]
}

@test "deploy_task injects CDP lesson from purpose and command when target_path is outputs" {
    mkdir -p "$TEST_PROJECT/projects/infra"
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L274
    title: cdp reload benchmark auth wall
    summary: cdp reload計測は認証壁込みで扱う
    status: confirmed
    helpful_count: 7
  - id: L941
    title: unrelated lesson
    summary: should stay out
    status: confirmed
    helpful_count: 9
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "outputs only task"
  description: "target_pathだけではCDP文脈が出ない"
  purpose: "CDP再計測の教訓を正しく注入する"
  command: "Use auth wall aware benchmark routing for the reload run."
  target_path: outputs/benchmarks/cdp-reload.json
  task_type: impl
  project: infra
  acceptance_criteria:
    - AC1
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
related = (data.get('task') or {}).get('related_lessons') or []
ids = [entry.get('id') for entry in related]
assert 'L274' in ids, ids
assert 'L941' not in ids, ids
print('|'.join(ids))
"
    [ "$status" -eq 0 ]
}

# === GP-105: stale report reassignment detection ===

# Duplicate GP-105 and cmd_1493 tests are covered by test_deploy_task_ac_version.bats.
@test "resolve_cmd_to_task: broken _deploy_notice continuation line を除去して task YAML を再生する" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_601:
    acceptance_criteria:
    - 'AC1: recover broken task yaml'
    project: testproj
    target_path: scripts/lib/yaml_field_set.sh
    type: impl
    purpose: recover broken task yaml
    title: recover broken task yaml
    status: pending
EOF
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_601"
    echo "source: test" > "$TEST_PROJECT/queue/gates/cmd_601/report_merge.done"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  _deploy_notice: "STALE TASK INVALID. This YAML is the latest instruction for cmd_old (deployed 2026-04-22T21:09:20). Read from the beginning."
    (deployed 2026-04-22T20:00:00). Read from the beginning.
  status: done
  task_type: recon
  parent_cmd: cmd_old
  task_id: cmd_old_recon
EOF

    run deploy_task_resolve_only sasuke cmd_601
    [ "$status" -eq 0 ]

    run python3 - <<PY
import yaml
from pathlib import Path
data = yaml.safe_load(Path("$TEST_PROJECT/queue/tasks/sasuke.yaml").read_text())
task = data["task"]
assert task["parent_cmd"] == "cmd_601"
assert task["task_id"] == "cmd_601_impl"
assert task["task_type"] == "impl"
assert "cmd_601" in task["_deploy_notice"]
print("PARSE_OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"PARSE_OK"* ]]

    run grep -n "2026-04-22T20:00:00" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 1 ]
}

# Duplicate resolve/LK021 tests are covered by test_deploy_task_ac_version.bats.
@test "GP-194 AC1: ac_assigned field is preserved in task YAML after deploy" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac_assigned preservation test"
  task_type: impl
  parent_cmd: cmd_1909
  task_id: cmd_1909_exact
  project: infra
  ac_assigned: [AC1, AC2]
  acceptance_criteria:
  - id: AC1
    description: "AC1の確認"
  - id: AC2
    description: "AC2の確認"
  - id: AC3
    description: "AC3の確認"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    # ac_assigned フィールドがタスクYAMLに存在することを確認（inline/multi-line 両形式対応）
    run grep -q "ac_assigned" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
}

@test "GP-194 AC2: ac_assigned=[AC2] → binary_checks has only AC2 (not AC1, AC3)" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac_assigned filter test"
  task_type: impl
  parent_cmd: cmd_1909
  task_id: cmd_1909_exact
  project: infra
  ac_assigned: [AC2]
  acceptance_criteria:
  - id: AC1
    description: "AC1の確認"
  - id: AC2
    description: "AC2の確認"
  - id: AC3
    description: "AC3の確認"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run python3 - <<EOF
import yaml
from pathlib import Path

report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
bc = data["binary_checks"]

keys = list(bc.keys())
assert "AC2" in keys, f"AC2 missing: {keys}"
assert "AC1" not in keys, f"AC1 should be filtered out: {keys}"
assert "AC3" not in keys, f"AC3 should be filtered out: {keys}"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "GP-194 AC2: ac_assigned=[AC1, AC3] → binary_checks has AC1 and AC3 (not AC2)" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac_assigned multi filter test"
  task_type: impl
  parent_cmd: cmd_1909
  task_id: cmd_1909_exact
  project: infra
  ac_assigned: [AC1, AC3]
  acceptance_criteria:
  - id: AC1
    description: "AC1の確認"
  - id: AC2
    description: "AC2の確認"
  - id: AC3
    description: "AC3の確認"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run python3 - <<EOF
import yaml
from pathlib import Path

report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
bc = data["binary_checks"]

keys = list(bc.keys())
assert "AC1" in keys, f"AC1 missing: {keys}"
assert "AC3" in keys, f"AC3 missing: {keys}"
assert "AC2" not in keys, f"AC2 should be filtered out: {keys}"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "GP-194 AC2: ac_assigned unset → all ACs in binary_checks (backward compat)" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac_assigned absent backward compat test"
  task_type: impl
  parent_cmd: cmd_1909
  task_id: cmd_1909_exact
  project: infra
  acceptance_criteria:
  - id: AC1
    description: "AC1の確認"
  - id: AC2
    description: "AC2の確認"
  - id: AC3
    description: "AC3の確認"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run python3 - <<EOF
import yaml
from pathlib import Path

report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
bc = data["binary_checks"]

keys = list(bc.keys())
assert "AC1" in keys, f"AC1 missing: {keys}"
assert "AC2" in keys, f"AC2 missing: {keys}"
assert "AC3" in keys, f"AC3 missing: {keys}"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "cmd_2483: chunk task_id infers ac_assigned and filters binary_checks" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "chunk inferred ac_assigned test"
  task_type: impl
  parent_cmd: cmd_2483
  task_id: cmd_2483_ac3_chunk2
  project: infra
  acceptance_criteria:
  - id: AC1
    description: "AC1の確認"
  - id: AC2
    description: "AC2の確認"
  - id: AC3
    description: "AC3の確認"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run grep -Eq '^  ac_assigned:[[:space:]]*"?AC3"?$' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    run grep -Eq '^  assigned_acs:[[:space:]]*"?AC3"?$' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run python3 - <<EOF
import yaml
from pathlib import Path

data = yaml.safe_load(Path("$report_path").read_text(encoding="utf-8"))
bc = data["binary_checks"]
keys = list(bc.keys())
assert "AC3" in keys, keys
assert "AC1" not in keys, keys
assert "AC2" not in keys, keys
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "GP-194 AC2: ac_assigned=[AC1] with explicit checks → only AC1 checks in binary_checks" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac_assigned with explicit checks test"
  task_type: impl
  parent_cmd: cmd_1909
  task_id: cmd_1909_exact
  project: infra
  ac_assigned: [AC1]
  acceptance_criteria:
  - id: AC1
    checks:
      - check: "AC1専用の確認"
  - id: AC2
    checks:
      - check: "AC2専用の確認"
  - id: AC3
    checks:
      - check: "AC3専用の確認"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run python3 - <<EOF
import yaml
from pathlib import Path

report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
bc = data["binary_checks"]

keys = list(bc.keys())
assert "AC1" in keys, f"AC1 missing: {keys}"
assert "AC2" not in keys, f"AC2 should be filtered out: {keys}"
assert "AC3" not in keys, f"AC3 should be filtered out: {keys}"
assert bc["AC1"][0]["check"] == "AC1専用の確認", bc["AC1"]
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
