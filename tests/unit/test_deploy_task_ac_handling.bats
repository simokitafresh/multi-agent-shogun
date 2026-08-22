#!/usr/bin/env bats
# test_necessity: 配備task/reportのAC集合は親cmdの最新AC集合と一致する
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

    mkdir -p "$TEST_PROJECT/logs"
    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
EOF

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

    export LOG="/dev/null"

    # log stub
    log() { echo "[DEPLOY] $1" >&2; }
    export -f log
}

teardown() {
    deploy_task_teardown
}

# cmd_round7_lane2_deploy_task_ac_20260730 AC2: 旧`eval "$(sed -n ...
# verify_ac_consistency... "$SRC_DEPLOY_SCRIPT")"`は全49testのsetup()で毎回
# $SRC_DEPLOY_SCRIPT(/mnt/c実体、12,816行)をsedしWSL2 9p I/O待ちで1回210-260ms課税
# していたが、verify_ac_consistency()はdeploy_task_scaffold内のsource "$TEST_PROJECT/
# scripts/deploy_task.sh"で既に通常関数として定義済みであり、抽出は死んだ二重定義
# だった(敵対検証: 8test全てから抽出行を除去してもFAIL0・SKIP0で49/49 PASSを実測)。

# ─── Helper functions for ac_version tests ───

# test_necessity: DOC lane判定はAC本文ではなく所有pathだけを根拠にする不変量を守る。
# これを失うとコードtaskの説明文に含まれるcontext語が忍者配備を誤BLOCKする。
@test "cmd_karo_hotfix_doc_lane_guard_delete: code-owned task passes despite context wording" {
    local task_path="$TEST_PROJECT/queue/tasks/doc_lane_guard_code_owned.yaml"
    cat > "$task_path" <<'EOF'
task:
  target_path: scripts/deploy_task.sh
  planned_paths:
    - scripts/deploy_task.sh
    - tests/unit/test_deploy_task_ac_handling.bats
  acceptance_criteria:
    - id: AC1
      description: "context boundary updateを完了する"
EOF

    run deploy_task_guard_doc_update_ac "$task_path"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "cmd_karo_hotfix_doc_lane_guard_delete: documentation-owned path is BLOCKed" {
    local task_path="$TEST_PROJECT/queue/tasks/doc_lane_guard_owned.yaml"
    cat > "$task_path" <<'EOF'
task:
  target_path: scripts/deploy_task.sh
  planned_paths:
    - scripts/deploy_task.sh
    - context/infrastructure.md
  acceptance_criteria:
    - id: AC1
      description: "通常の実装を完了する"
EOF

    run deploy_task_guard_doc_update_ac "$task_path"
    [ "$status" -eq 2 ]
    [[ "$output" == *"DOC_LANE_ROUTING"* ]]
    [[ "$output" == *"shogun doc lane"* ]]
}

# test_necessity: 通常の実装pathはAC本文の語彙に関係なく通す不変量を守る。
# これを失うと実装taskの自然言語説明がDOC laneへ誤分類される。
@test "cmd_karo_hotfix_doc_lane_guard_delete: normal implementation path passes" {
    local task_path="$TEST_PROJECT/queue/tasks/doc_lane_guard_normal.yaml"
    cat > "$task_path" <<'EOF'
task:
  target_path: scripts/deploy_task.sh
  planned_paths:
    - scripts/deploy_task.sh
    - tests/unit/test_deploy_task_ac_handling.bats
  acceptance_criteria:
    - id: AC1
      description: "completion regression testsを全量実行する"
EOF

    run deploy_task_guard_doc_update_ac "$task_path"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# test_necessity: ACに「push禁止」「pushはしない」「do not push」のような否定形しかない task には
# push_allowed:true を自動付与しない不変量。これを失うと、push禁止cmdが配備時に push可へ反転し、
# cmd_complete_gate の pre-GATE autopush が殿のdeploy凍結裁定を破って本番deployまで進む
# (2026-08-18 01:24/02:07/02:55 cmd_4349/4351/4352 実測)。肯定形の push 要求だけが付与対象。
@test "cmd_4352: inject_push_allowed ignores negated push mentions" {
    local task_path="$TEST_PROJECT/queue/tasks/push_allowed_negation.yaml"
    cat > "$task_path" <<'EOF'
task:
  task_id: cmd_fixture_push_neg
  acceptance_criteria:
    - id: AC1
      description: "選択実行でFAIL0を確認しcommitする(pushはしない)。push禁止。do not push to origin"
EOF
    run inject_push_allowed "$task_path"
    [ "$status" -eq 0 ]
    ! grep -q '^[[:space:]]*push_allowed:' "$task_path"

    cat > "$task_path" <<'EOF'
task:
  task_id: cmd_fixture_push_pos
  acceptance_criteria:
    - id: AC1
      description: "commit後にorigin/mainへpushしCI GREENを確認する"
EOF
    run inject_push_allowed "$task_path"
    [ "$status" -eq 0 ]
    grep -q '^[[:space:]]*push_allowed: *true' "$task_path"
}

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

    SCRIPT_DIR="$TEST_TMPDIR" run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
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

    SCRIPT_DIR="$TEST_TMPDIR" run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
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

    SCRIPT_DIR="$TEST_TMPDIR" run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
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

    SCRIPT_DIR="$TEST_TMPDIR" run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
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

    SCRIPT_DIR="$TEST_TMPDIR" run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
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

    SCRIPT_DIR="$TEST_TMPDIR" run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
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

    SCRIPT_DIR="$TEST_TMPDIR" run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
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

    SCRIPT_DIR="$TEST_TMPDIR" run verify_ac_consistency "$TEST_TMPDIR/queue/tasks/sasuke.yaml"
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

# test_necessity: the AC fingerprint must include inline descriptions and
# folded continuation text; otherwise materially revised ACs share one hash.
@test "ac hash changes when folded description content changes" {
    cat > "$(task_file)" <<'YAML'
task:
  acceptance_criteria:
  - id: AC1
    description: first physical line
      folded contract version one
  - id: AC2
    description: second contract
YAML
    first=$(_compute_ac_hash "$(task_file)")

    sed -i 's/folded contract version one/folded contract version two/' "$(task_file)"
    second=$(_compute_ac_hash "$(task_file)")

    [ -n "$first" ]
    [ -n "$second" ]
    [ "$first" != "$second" ]
}

@test "deploy_task injects ac_version and report ac_version_read on first deploy [template_only]" {
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
    [ "${lines[1]-}" = "" ]

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
assert isinstance(data["result"], dict)
assert data["result"].get("summary") == "cmd_2528 template completeness — 実施・検証結果を本報告へ記録"
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
    [[ "$output" != *"result.summary: FILL_THIS placeholder remaining"* ]]
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
    when: lessons_useful reason example injection
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

@test "assigned_lesson_ids replace auto related lessons in report feedback template" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "exact lesson reflux"
  task_type: research
  parent_cmd: cmd_exact_lesson_reflux
  task_id: cmd_exact_lesson_reflux_research
  project: infra
  assigned_lesson_ids:
  - L101
  - L202
  related_lessons:
  - id: L625
    summary: auto-injected context lesson
  - id: L311
    summary: auto-injected workaround lesson
  acceptance_criteria:
  - id: AC1
    description: "report exact assigned lessons"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run python3 - "$report_path" <<'PY'
import sys, yaml

report = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
ids = [item["id"] for item in report["lessons_useful"]]
assert ids == ["L101", "L202"], ids
PY
    [ "$status" -eq 0 ]
}

@test "reset_stale_fields removes assigned_lesson_ids before a different command" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_old_reflux
  task_id: cmd_old_reflux_exact
  assigned_lesson_ids:
    - L101
    - L202
  acceptance_criteria:
    - id: AC1
      description: old
EOF

    DIRECT_MODE=false
    CMD_ID=cmd_new_normal
    run reset_stale_fields sasuke
    [ "$status" -eq 0 ]

    run python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import sys, yaml
task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {})["task"]
assert "assigned_lesson_ids" not in task, task
PY
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
    # cmd_reflux_insight_202607091206: gate_report_format.shは実際にはjson.dumpで
    # このファイルを書く(拡張子は.yamlだがキーはダブルクォート付きJSON)。
    # フィクスチャも本番出力形式(JSON)に合わせ、フォーマット不一致の再発を検出させる。
    cat > "$TEST_PROJECT/logs/gate_report_format_learning.yaml" <<'EOF'
{
  "threshold": 10,
  "patterns": {
    "bc_result_empty": {
      "count": 12,
      "prefill_active": true,
      "prefill_field": "binary_checks.result"
    },
    "files_modified_missing": {
      "count": 14,
      "prefill_active": true,
      "prefill_field": "files_modified"
    },
    "lu_reason_empty": {
      "count": 11,
      "prefill_active": true,
      "prefill_field": "lessons_useful.reason"
    },
    "result_summary_empty": {
      "count": 13,
      "prefill_active": true,
      "prefill_field": "result.summary"
    }
  }
}
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
    run grep -F 'summary: "learned generic prefill injection test — 実施・検証結果を本報告へ記録"' "$report_path"
    [ "$status" -eq 0 ]

    run env GATE_NO_LOG=1 bash "$PROJECT_ROOT/scripts/gates/gate_report_format.sh" "$report_path"
    [ "$status" -eq 1 ]
    # cmd_2665: no_lesson_reason now has a default value, so this check no longer fires
    # gate_report_format.sh also removed this check in 44b191b8
    [[ "$output" != *"files_modified: MISSING"* ]]
    [[ "$output" == *"binary_checks.AC1[0].result: 空文字"* ]]
    [[ "$output" != *"result.summary: FILL_THIS placeholder remaining"* ]]
}

# Duplicate ac_version/modifier/report-path tests are covered by test_deploy_task_ac_version.bats.
@test "deploy_task injects at most MAX_INJECT=3 related_lessons when candidates exceed cap" {
    mkdir -p "$TEST_PROJECT/projects/testproj"
    cat > "$TEST_PROJECT/projects/testproj/lessons.yaml" <<'EOF'
lessons:
  - id: L910
    tags: [deploy]
    target_files: [scripts/deploy.sh]
    title: rollback safeguard
    summary: rollback branch before deploy cutover
    when: deploy cutover
    how: rollback safeguard
    status: confirmed
    helpful_count: 10
  - id: L911
    tags: [deploy]
    target_files: [scripts/deploy.sh]
    title: database migration guard
    summary: database schema check before release
    when: database migration
    how: schema check
    status: confirmed
    helpful_count: 9
  - id: L912
    tags: [deploy]
    target_files: [scripts/deploy.sh]
    title: cache invalidation order
    summary: cache purge after config update
    when: config update
    how: cache purge order
    status: confirmed
    helpful_count: 8
  - id: L913
    tags: [deploy]
    target_files: [scripts/deploy.sh]
    title: notification fallback route
    summary: notification fallback when primary webhook fails
    when: webhook failure
    how: fallback route
    status: confirmed
    helpful_count: 7
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "deploy rollback database cache notification rollout"
  description: "validate rollback database cache notification lesson injection cap"
  task_type: impl
  project: testproj
  target_path: "scripts/deploy.sh"
  acceptance_criteria:
    - AC1
EOF

    MIN_KEYWORD_SCORE_IMPL=2 run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
related = (data.get('task') or {}).get('related_lessons') or []
assert len(related) == 3, related
print(len(related))
"
    [ "$status" -eq 0 ]
    [ "$output" = "3" ]
}

@test "deploy_task injects workaround TOP3 lessons into related_lessons" {
    mkdir -p "$TEST_PROJECT/projects/infra"
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L278
    title: commit and report are inseparable
    summary: commit後即座にreport作成が必要
    status: confirmed
  - id: L342
    title: git add force for whitelisted scripts
    summary: ホワイトリスト方式では新規scriptsもgit add -fが必要
    status: confirmed
  - id: L311
    title: workaround report yaml format pattern
    summary: report_yaml_format WAはreport_field_set使用で防ぐ
    status: confirmed
  - id: L295
    title: yaml dump data loss
    summary: yaml.dumpで運用YAMLを上書きするとデータ消失する
    status: confirmed
EOF
    cat > "$TEST_PROJECT/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_1
  ninja: sasuke
  workaround: true
  category: commit_missing
- cmd_id: cmd_2
  ninja: sasuke
  workaround: true
  category: report_yaml_format
- cmd_id: cmd_3
  ninja: sasuke
  workaround: true
  category: yaml_dump
- cmd_id: cmd_4
  ninja: hanzo
  workaround: true
  category: commit_missing
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "deploy workaround lesson injection"
  description: "WA頻発パターンを事前注入する"
  task_type: impl
  project: infra
  target_path: "scripts/deploy_task.sh"
  acceptance_criteria:
    - id: AC1
      checks:
        - check: "related lessons include WA lessons"
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1]))["task"]
related = task.get("related_lessons") or []
ids = [item.get("id") for item in related]
print(",".join(ids))
for item in related:
    if item.get("id") in {"L278", "L311", "L295"}:
        print(f"{item.get('id')}:{item.get('wa_category')}:{item.get('wa_count')}")
print(task.get("description", ""))
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"L278"* ]]
    [[ "$output" == *"L311:report_yaml_format:1"* ]]
    [[ "$output" == *"L295:yaml_dump:1"* ]]
    [[ "$output" == *"【注入教訓】"* ]]
}

@test "deploy_task auto-inserts commit_missing lessons from workaround history" {
    mkdir -p "$TEST_PROJECT/projects/infra"
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L278
    title: commit and report are inseparable
    summary: commit後即座にreport作成が必要
    status: confirmed
  - id: L342
    title: git add force for whitelisted scripts
    summary: ホワイトリスト方式では新規scriptsもgit add -fが必要
    status: confirmed
EOF
    cat > "$TEST_PROJECT/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_a
  ninja: sasuke
  workaround: true
  category: commit_missing
- cmd_id: cmd_b
  ninja: sasuke
  workaround: true
  category: commit_missing
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "commit missing prevention"
  description: "commit漏れ予防"
  task_type: impl
  project: infra
  target_path: "scripts/new_tool.sh"
  acceptance_criteria:
    - id: AC1
      checks:
        - check: "commit_missing lessons injected"
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1]))["task"]
related = task.get("related_lessons") or []
for item in related:
    print(f"{item.get('id')}:{item.get('wa_category')}:{item.get('wa_count')}")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"L278:commit_missing:2"* ]]
    [[ "$output" == *"L342:commit_missing:2"* ]]
}

@test "deploy_task does not duplicate existing related_lessons when adding WA lessons" {
    mkdir -p "$TEST_PROJECT/projects/infra"
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L278
    title: commit and report are inseparable
    summary: commit後即座にreport作成が必要
    status: confirmed
  - id: L342
    title: git add force for whitelisted scripts
    summary: ホワイトリスト方式では新規scriptsもgit add -fが必要
    status: confirmed
EOF
    cat > "$TEST_PROJECT/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_a
  ninja: sasuke
  workaround: true
  category: commit_missing
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "dedupe workaround lessons"
  description: "既存related_lessonsを保持"
  task_type: impl
  project: infra
  target_path: "scripts/new_tool.sh"
  related_lessons:
    - id: L278
      summary: already present
  acceptance_criteria:
    - id: AC1
      checks:
        - check: "dedupe"
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import sys, yaml
ids = [item.get("id") for item in (yaml.safe_load(open(sys.argv[1]))["task"].get("related_lessons") or [])]
print(ids.count("L278"))
print(",".join(ids))
PY
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "1" ]
    [[ "$output" == *"L342"* ]]
}

@test "deploy_task does not mark MIN_SAMPLES-below lessons as withheld" {
    mkdir -p "$TEST_PROJECT/projects/testproj"
    cat > "$TEST_PROJECT/projects/testproj/lessons.yaml" <<'EOF'
lessons:
  - id: L001
    tags: [deploy]
    title: deploy alpha orbit maple quartz
    summary: deploy alpha orbit maple quartz
    when: deploy alpha
    how: orbit maple quartz
    status: confirmed
    helpful_count: 20
  - id: L002
    tags: [deploy]
    title: deploy beta cobalt harbor prism
    summary: deploy beta cobalt harbor prism
    when: deploy beta
    how: cobalt harbor prism
    status: confirmed
    helpful_count: 19
  - id: L003
    tags: [deploy]
    title: deploy gamma ember satellite lattice
    summary: deploy gamma ember satellite lattice
    when: deploy gamma
    how: ember satellite lattice
    status: confirmed
    helpful_count: 18
  - id: L004
    tags: [deploy]
    title: deploy delta fable orchard copper
    summary: deploy delta fable orchard copper
    when: deploy delta
    how: fable orchard copper
    status: confirmed
    helpful_count: 17
  - id: L005
    tags: [deploy]
    title: deploy epsilon granite meadow syntax
    summary: deploy epsilon granite meadow syntax
    when: deploy epsilon
    how: granite meadow syntax
    status: confirmed
    helpful_count: 16
  - id: L006
    tags: [deploy]
    title: deploy zeta horizon velvet engine
    summary: deploy zeta horizon velvet engine
    when: deploy zeta
    how: horizon velvet engine
    status: confirmed
    helpful_count: 15
  - id: L007
    tags: [deploy]
    title: deploy eta ivory lagoon vector
    summary: deploy eta ivory lagoon vector
    when: deploy eta
    how: ivory lagoon vector
    status: confirmed
    helpful_count: 14
  - id: L008
    tags: [deploy]
    title: deploy theta jade canyon signal
    summary: deploy theta jade canyon signal
    when: deploy theta
    how: jade canyon signal
    status: confirmed
    helpful_count: 13
  - id: L009
    tags: [deploy]
    title: deploy iota kernel citadel packet
    summary: deploy iota kernel citadel packet
    when: deploy iota
    how: kernel citadel packet
    status: confirmed
    helpful_count: 12
  - id: L010
    tags: [deploy]
    title: deploy kappa lunar bridge token
    summary: deploy kappa lunar bridge token
    when: deploy kappa
    how: lunar bridge token
    status: confirmed
    helpful_count: 11
  - id: L_LOW
    tags: [deploy]
    title: deploy low sample nova metric
    summary: deploy low sample nova metric
    when: deploy low sample
    how: nova metric
    status: confirmed
    helpful_count: 1
  - id: L_BAD
    tags: [deploy]
    title: deploy mature bad omega parser
    summary: deploy mature bad omega parser
    when: deploy mature
    how: bad omega parser
    status: confirmed
    helpful_count: 0
EOF

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-05-12T00:00:00	cmd_a	sasuke	L_LOW	feedback	NOT_USEFUL	no	testproj	impl	None
2026-05-12T00:00:00	cmd_b	sasuke	L_LOW	feedback	NOT_USEFUL	no	testproj	impl	None
2026-05-12T00:00:00	cmd_a	sasuke	L_BAD	feedback	USEFUL	yes	testproj	impl	None
2026-05-12T00:00:00	cmd_b	sasuke	L_BAD	feedback	NOT_USEFUL	no	testproj	impl	None
2026-05-12T00:00:00	cmd_c	sasuke	L_BAD	feedback	NOT_USEFUL	no	testproj	impl	None
2026-05-12T00:00:00	cmd_d	sasuke	L_BAD	feedback	NOT_USEFUL	no	testproj	impl	None
2026-05-12T00:00:00	cmd_e	sasuke	L_BAD	feedback	NOT_USEFUL	no	testproj	impl	None
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "deploy rollout"
  description: "deploy injection cap"
  task_id: cmd_min_samples_exact
  assigned_to: sasuke
  task_type: impl
  project: testproj
  target_path: "scripts/deploy.sh"
  acceptance_criteria:
    - AC1
EOF

    MIN_KEYWORD_SCORE_IMPL=2 USEFUL_RATE_MIN_SAMPLES=3 run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run awk -F'\t' '$5=="withheld"{print $4}' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L_BAD"* ]]
    [[ "$output" != *"L_LOW"* ]]
}

@test "deploy_task writes score column for injected lesson impact rows" {
    mkdir -p "$TEST_PROJECT/projects/testproj"
    cat > "$TEST_PROJECT/projects/testproj/lessons.yaml" <<'EOF'
lessons:
  - id: L_SCORE
    tags: [deploy]
    title: deploy score metric tracer
    summary: deploy score metric tracer
    when: deploy score metric
    status: confirmed
    helpful_count: 1
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "deploy score metric"
  description: "deploy score metric"
  task_id: cmd_score_column
  assigned_to: sasuke
  task_type: impl
  project: testproj
  acceptance_criteria:
    - AC1
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run awk -F'\t' 'NR==1{for (i=1; i<=NF; i++) if ($i=="score") print i}' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]

    score_idx="$output"
    run awk -F'\t' -v score_idx="$score_idx" '$5=="injected" && $4=="L_SCORE"{print $score_idx}' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
    [ "$output" -gt 0 ]
}

@test "deploy_task excludes mature low-effectiveness feedback lessons from related_lessons" {
    mkdir -p "$TEST_PROJECT/projects/testproj"
    cat > "$TEST_PROJECT/projects/testproj/lessons.yaml" <<'EOF'
lessons:
  - id: L_GOOD
    title: deploy filter good lesson
    summary: deploy filter good lesson
    when: deploy filter
    how: good lesson
    status: confirmed
    helpful_count: 1
    tags: [deploy]
  - id: L_BAD
    title: deploy filter bad lesson
    summary: deploy filter bad lesson
    when: deploy filter
    how: bad lesson
    status: confirmed
    helpful_count: 100
    tags: [deploy]
EOF

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-05-12T00:00:00	cmd_a	sasuke	L_GOOD	feedback	USEFUL	yes	testproj	impl	None
2026-05-12T00:00:00	cmd_b	sasuke	L_GOOD	feedback	USEFUL	yes	testproj	impl	None
2026-05-12T00:00:00	cmd_c	sasuke	L_GOOD	feedback	USEFUL	yes	testproj	impl	None
2026-05-12T00:00:00	cmd_d	sasuke	L_GOOD	feedback	NOT_USEFUL	no	testproj	impl	None
2026-05-12T00:00:00	cmd_e	sasuke	L_GOOD	feedback	NOT_USEFUL	no	testproj	impl	None
2026-05-12T00:00:00	cmd_a	sasuke	L_BAD	feedback	USEFUL	yes	testproj	impl	None
2026-05-12T00:00:00	cmd_b	sasuke	L_BAD	feedback	NOT_USEFUL	no	testproj	impl	None
2026-05-12T00:00:00	cmd_c	sasuke	L_BAD	feedback	NOT_USEFUL	no	testproj	impl	None
2026-05-12T00:00:00	cmd_d	sasuke	L_BAD	feedback	NOT_USEFUL	no	testproj	impl	None
2026-05-12T00:00:00	cmd_e	sasuke	L_BAD	feedback	NOT_USEFUL	no	testproj	impl	None
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "deploy filter"
  description: "deploy filter effectiveness"
  task_id: cmd_effectiveness_filter
  assigned_to: sasuke
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
ids = [entry.get('id') for entry in (data.get('task') or {}).get('related_lessons') or []]
assert 'L_GOOD' in ids, ids
assert 'L_BAD' not in ids, ids
print(','.join(ids))
"
    [ "$status" -eq 0 ]

    run awk -F'\t' '$5=="withheld"{print $4}' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L_BAD"* ]]
}

@test "deploy_task cross-project opt-in requires at least one project-specific matched keyword" {
    mkdir -p "$TEST_PROJECT/projects/infra" "$TEST_PROJECT/projects/dm-signal"
    cat > "$TEST_PROJECT/config/projects.yaml" <<'EOF'
projects:
  - id: infra
    type: platform
  - id: dm-signal
    type: product
EOF
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_PROJECT/projects/dm-signal/lessons.yaml" <<'EOF'
lessons:
  - id: L_DM_GENERIC
    title: deploy filter score rate feedback
    summary: deploy filter score rate feedback
    status: confirmed
    helpful_count: 100
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "infra generic cross project"
  command: "deploy filter score rate feedback"
  task_id: cmd_cross_generic
  assigned_to: sasuke
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
ids = [entry.get('id') for entry in (data.get('task') or {}).get('related_lessons') or []]
assert 'L_DM_GENERIC' not in ids, ids
print(','.join(ids))
"
    [ "$status" -eq 0 ]
}

@test "deploy_task project filter blocks lessons from a non-platform project even with specific keyword match" {
    mkdir -p "$TEST_PROJECT/projects/infra" "$TEST_PROJECT/projects/dm-signal"
    # symlink→実体書換え防止: configをローカルコピーに差替え
    if [ -L "$TEST_PROJECT/config" ]; then
        local _real_config; _real_config="$(readlink -f "$TEST_PROJECT/config")"
        rm "$TEST_PROJECT/config"
        cp -r "$_real_config" "$TEST_PROJECT/config"
    fi
    cat > "$TEST_PROJECT/config/projects.yaml" <<'EOF'
projects:
  - id: infra
    type: platform
  - id: dm-signal
    type: product
EOF
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_PROJECT/projects/dm-signal/lessons.yaml" <<'EOF'
lessons:
  - id: L_DM_SPECIFIC
    title: shinshijin parity masking deploy
    summary: shinshijin parity masking deploy
    status: confirmed
    helpful_count: 1
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "infra specific cross project"
  command: "shinshijin parity masking deploy"
  task_id: cmd_cross_specific
  assigned_to: sasuke
  task_type: impl
  project: infra
  acceptance_criteria:
    - AC1
EOF

    run deploy_task_lessons_only sasuke
    echo "CI-DEBUG test649 deploy_task_lessons_only status=$status output=$output" >&2
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
ids = [entry.get('id') for entry in (data.get('task') or {}).get('related_lessons') or []]
assert 'L_DM_SPECIFIC' not in ids, ids
print(','.join(ids))
"
    echo "CI-DEBUG test649 python3 status=$status output=$output" >&2
    [ "$status" -eq 0 ]
}

@test "deploy_task project filter leaves non-platform project lessons untouched and excluded" {
    mkdir -p "$TEST_PROJECT/projects/infra" "$TEST_PROJECT/projects/dm-signal"
    # symlink→実体書換え防止: configをローカルコピーに差替え
    if [ -L "$TEST_PROJECT/config" ]; then
        local _real_config; _real_config="$(readlink -f "$TEST_PROJECT/config")"
        rm "$TEST_PROJECT/config"
        cp -r "$_real_config" "$TEST_PROJECT/config"
    fi
    cat > "$TEST_PROJECT/config/projects.yaml" <<'EOF'
projects:
  - id: infra
    type: platform
  - id: dm-signal
    type: product
EOF
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_PROJECT/projects/dm-signal/lessons.yaml" <<'EOF'
lessons:
  - id: L_DM_BAD
    title: shinshijin parity masking deploy
    summary: shinshijin parity masking deploy
    status: confirmed
    helpful_count: 100
  - id: L_DM_GOOD
    title: shinshijin parity masking fallback
    summary: shinshijin parity masking fallback
    status: confirmed
    helpful_count: 1
EOF
    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-05-12T00:00:00	cmd_a	sasuke	L_DM_BAD	feedback	NOT_USEFUL	no	infra	impl	None
2026-05-12T00:00:00	cmd_b	sasuke	L_DM_BAD	feedback	NOT_USEFUL	no	infra	impl	None
2026-05-12T00:00:00	cmd_c	sasuke	L_DM_GOOD	feedback	USEFUL	yes	infra	impl	None
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "infra zero useful cross project"
  command: "shinshijin parity masking deploy fallback"
  task_id: cmd_cross_deprecated
  assigned_to: sasuke
  task_type: impl
  project: infra
  acceptance_criteria:
    - AC1
EOF

    ZERO_USEFUL_DEPRECATE_MIN_SAMPLES=1 run deploy_task_lessons_only sasuke
    echo "CI-DEBUG test650 deploy_task_lessons_only status=$status output=$output" >&2
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml', encoding='utf-8') as f:
    task = (yaml.safe_load(f) or {}).get('task') or {}
ids = [entry.get('id') for entry in task.get('related_lessons') or []]
assert 'L_DM_BAD' not in ids, ids
assert 'L_DM_GOOD' not in ids, ids
with open('$TEST_PROJECT/projects/dm-signal/lessons.yaml', encoding='utf-8') as f:
    lessons = (yaml.safe_load(f) or {}).get('lessons') or []
bad = next(item for item in lessons if item.get('id') == 'L_DM_BAD')
assert bad.get('deprecated') is not True, bad
print(','.join(ids))
"
    [ "$status" -eq 0 ]
}

@test "deploy_task does not auto-deprecate zero-useful lessons by default" {
    mkdir -p "$TEST_PROJECT/projects/infra"
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L_ZERO
    title: deploy guard zero useful
    summary: deploy guard zero useful
    status: confirmed
    tags: [deploy]
    helpful_count: 100
EOF
    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-06-11T00:00:00	cmd_a	sasuke	L_ZERO	feedback	NOT_USEFUL	no	infra	impl	None
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "deploy guard"
  command: "deploy guard zero useful"
  task_id: cmd_no_auto_deprecate
  assigned_to: sasuke
  task_type: impl
  project: infra
  target_path: scripts/deploy_task.sh
  acceptance_criteria:
    - AC1
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('$TEST_PROJECT/projects/infra/lessons.yaml', encoding='utf-8') as f:
    lessons = (yaml.safe_load(f) or {}).get('lessons') or []
item = next(x for x in lessons if x.get('id') == 'L_ZERO')
assert item.get('deprecated') is not True, item
print('not_deprecated')
"
    [ "$status" -eq 0 ]
    [ "$output" = "not_deprecated" ]
}

@test "deploy_task injects platform project lessons into non-platform tasks" {
    mkdir -p "$TEST_PROJECT/projects/infra" "$TEST_PROJECT/projects/dm-signal"
    if [ -L "$TEST_PROJECT/config" ]; then
        local _real_config; _real_config="$(readlink -f "$TEST_PROJECT/config")"
        rm "$TEST_PROJECT/config"
        cp -r "$_real_config" "$TEST_PROJECT/config"
    fi
    cat > "$TEST_PROJECT/config/projects.yaml" <<'EOF'
projects:
  - id: infra
    type: platform
  - id: dm-signal
    type: product
EOF
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L_INFRA_PLATFORM
    tags: [deploy]
    title: deploy platform guard
    summary: deploy platform guard
    when: deploy platform guard
    status: confirmed
    helpful_count: 10
EOF
    cat > "$TEST_PROJECT/projects/dm-signal/lessons.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "dm signal platform deploy"
  command: "deploy platform guard"
  task_id: cmd_platform_lessons
  assigned_to: sasuke
  task_type: impl
  project: dm-signal
  acceptance_criteria:
    - AC1
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml', encoding='utf-8') as f:
    task = (yaml.safe_load(f) or {}).get('task') or {}
ids = [entry.get('id') for entry in task.get('related_lessons') or []]
assert 'L_INFRA_PLATFORM' in ids, ids
print(','.join(ids))
"
    [ "$status" -eq 0 ]
}

@test "deploy_task tag fallback injects at most MAX_INJECT=3 target-matched lessons" {
    mkdir -p "$TEST_PROJECT/projects/testproj"
    cat > "$TEST_PROJECT/projects/testproj/lessons.yaml" <<'EOF'
lessons:
  - id: L920
    title: amber lantern
    summary: orbit maple quartz
    status: confirmed
    helpful_count: 4
    tags: [deploy]
    target_files: [scripts/deploy.sh]
  - id: L921
    title: cobalt harbor
    summary: velvet prism harbor
    status: confirmed
    helpful_count: 9
    tags: [deploy]
    target_files: [scripts/deploy.sh]
  - id: L922
    title: ember satellite
    summary: lattice canyon signal
    status: confirmed
    helpful_count: 7
    tags: [deploy]
    target_files: [scripts/deploy.sh]
  - id: L923
    title: fable orchard
    summary: copper meadow syntax
    status: confirmed
    helpful_count: 6
    tags: [deploy]
    target_files: [scripts/deploy.sh]
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "deploy rollout"
  description: "trigger target-matched fallback without keyword overlap"
  task_type: impl
  project: testproj
  target_path: "scripts/deploy.sh"
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
assert len(related) == 3, related
assert ids == ['L921', 'L922', 'L923'], ids
print('|'.join(ids))
"
    [ "$status" -eq 0 ]
    [ "$output" = "L921|L922|L923" ]
}

@test "deploy_task excludes target_files mismatch even when task tags overlap" {
    mkdir -p "$TEST_PROJECT/projects/testproj"
    cat > "$TEST_PROJECT/projects/testproj/lessons.yaml" <<'EOF'
lessons:
  - id: L_MATCH
    title: insight write lock discipline
    summary: insight_write target match
    status: confirmed
    helpful_count: 20
    tags: [yaml, lesson, security]
    target_files: [scripts/insight_write.sh]
  - id: L_MISMATCH
    title: sync lessons count caveat
    summary: sync_lessons target mismatch
    status: confirmed
    helpful_count: 20
    tags: [yaml, lesson, security]
    target_files: [sync_lessons.sh]
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "insight write fix"
  description: "target_files mismatch must not leak through tag overlap"
  task_type: impl
  project: testproj
  target_path: "scripts/insight_write.sh"
  tags: [yaml]
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
assert 'L_MATCH' in ids, ids
assert 'L_MISMATCH' not in ids, ids
print('|'.join(ids))
"
    [ "$status" -eq 0 ]
}

@test "deploy_task does not inject non-platform cross-project lessons when command keywords match" {
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
assert 'L931' not in ids, ids
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
    tags: [cdp]
    when: CDP auth wall benchmark routing
    title: cdp reload benchmark auth wall
    summary: cdp reload計測は認証壁込みで扱う
    status: confirmed
    helpful_count: 7
  - id: L941
    tags: [unrelated]
    when: unrelated scenario only
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
    estimated_minutes: 10
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

@test "cmd_4127: assigned_acs=[AC2] → binary_checks has only AC2 (not AC1, AC3)" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac_assigned filter test"
  task_type: impl
  parent_cmd: cmd_1909
  task_id: cmd_1909_exact
  project: infra
  assigned_acs: [AC2]
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

@test "cmd_karo_hotfix_chunk_marker_boundary AC1: incident task_id gate_ac3_hunk_provenance does not falsely infer AC3" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "hunk provenance gate task (false positive repro)"
  task_type: hotfix
  parent_cmd: cmd_karo_hotfix_gate_ac3_hunk_provenance_202607121205
  task_id: cmd_karo_hotfix_gate_ac3_hunk_provenance_202607121205_normal
  project: infra
  acceptance_criteria:
  - id: AC1
    description: "AC1の確認"
  - id: AC2
    description: "AC2の確認"
  - id: AC3
    description: "AC3の確認"
  - id: AC4
    description: "AC4の確認"
  - id: AC5
    description: "AC5の確認"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run grep -Eq '^  ac_assigned:' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 1 ]
    run grep -Eq '^  assigned_acs:' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 1 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run python3 - <<EOF
import yaml
from pathlib import Path

data = yaml.safe_load(Path("$report_path").read_text(encoding="utf-8"))
bc = data["binary_checks"]
keys = list(bc.keys())
for ac in ["AC1", "AC2", "AC3", "AC4", "AC5"]:
    assert ac in keys, f"{ac} missing: {keys}"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "cmd_karo_hotfix_chunk_marker_boundary AC2: ordinary description word phase_ac2_fix does not infer ac_assigned" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ordinary description word test (phase_ac2_fix)"
  task_type: hotfix
  parent_cmd: cmd_9001
  task_id: cmd_9001_phase_ac2_fix
  project: infra
  acceptance_criteria:
  - id: AC1
    description: "AC1の確認"
  - id: AC2
    description: "AC2の確認"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run grep -Eq '^  ac_assigned:' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 1 ]
}

@test "cmd_karo_hotfix_chunk_marker_boundary AC2: ordinary description word docs_ac4_note does not infer ac_assigned" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ordinary description word test (docs_ac4_note)"
  task_type: hotfix
  parent_cmd: cmd_9002
  task_id: cmd_9002_docs_ac4_note
  project: infra
  acceptance_criteria:
  - id: AC1
    description: "AC1の確認"
  - id: AC4
    description: "AC4の確認"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run grep -Eq '^  ac_assigned:' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 1 ]
}

@test "cmd_karo_hotfix_chunk_marker_boundary AC2: explicit ac_assigned field wins over chunk-looking task_id" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "explicit field priority test"
  task_type: hotfix
  parent_cmd: cmd_9005
  task_id: cmd_9005_ac1_chunk1
  project: infra
  ac_assigned: AC2
  acceptance_criteria:
  - id: AC1
    description: "AC1の確認"
  - id: AC2
    description: "AC2の確認"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run grep -Eq '^  ac_assigned:[[:space:]]*"?AC2"?$' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
}

@test "cmd_karo_hotfix_chunk_marker_boundary AC3: multi-digit AC + uppercase CHUNK marker infers correctly" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "multi-digit AC uppercase chunk test"
  task_type: impl
  parent_cmd: cmd_9010
  task_id: cmd_9010_AC12_CHUNK3
  project: infra
  acceptance_criteria:
  - id: AC12
    description: "AC12の確認"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run grep -Eq '^  ac_assigned:[[:space:]]*"?AC12"?$' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
}

@test "cmd_karo_hotfix_chunk_marker_boundary AC3: trailing chunk marker without digit at end of task_id infers correctly" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "trailing chunk marker without digit test"
  task_type: impl
  parent_cmd: cmd_9011
  task_id: cmd_9011_ac1_chunk
  project: infra
  acceptance_criteria:
  - id: AC1
    description: "AC1の確認"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run grep -Eq '^  ac_assigned:[[:space:]]*"?AC1"?$' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
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

@test "cmd_2790 AC1: inject_ac_assigned_from_stk reads ac_assigned from STK scalar and sets in task YAML" {
    # STKにac_assigned: AC1を定義
    mkdir -p "$TEST_PROJECT/queue"
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_stk_ac_test:
    title: "ac_assigned STK inject test"
    project: infra
    scope_mode: exact
    ac_assigned: AC1
    acceptance_criteria:
      - description: "AC1の確認"
      - description: "AC2の確認"
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "STK ac_assigned injection test"
  task_type: impl
  parent_cmd: cmd_stk_ac_test
  task_id: cmd_stk_ac_test_exact
  project: infra
  acceptance_criteria:
  - id: AC1
    description: "AC1の確認"
  - id: AC2
    description: "AC2の確認"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    # task YAMLにac_assignedが追加されている(AC1)
    run grep -Eq '^  ac_assigned:[[:space:]]*"?AC1"?$' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    # binary_checksにAC1のみ存在し、AC2は除外されている(AC2)
    run python3 - <<EOF
import yaml
from pathlib import Path

report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
bc = data["binary_checks"]

keys = list(bc.keys())
assert "AC1" in keys, f"AC1 missing: {keys}"
assert "AC2" not in keys, f"AC2 should be filtered out: {keys}"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "cmd_2790 AC1: inject_ac_assigned_from_stk reads inline list [AC1, AC2] from STK" {
    mkdir -p "$TEST_PROJECT/queue"
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_stk_list_test:
    title: "ac_assigned list inject test"
    project: infra
    scope_mode: exact
    ac_assigned: [AC1, AC2]
    acceptance_criteria:
      - description: "AC1の確認"
      - description: "AC2の確認"
      - description: "AC3の確認"
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "STK ac_assigned list test"
  task_type: impl
  parent_cmd: cmd_stk_list_test
  task_id: cmd_stk_list_test_exact
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

    # task YAMLにac_assigned: [AC1, AC2]が追加されている
    run grep -q "ac_assigned" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    # binary_checksにAC1/AC2のみ、AC3は除外
    run python3 - <<EOF
import yaml
from pathlib import Path

report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
bc = data["binary_checks"]

keys = list(bc.keys())
assert "AC1" in keys, f"AC1 missing: {keys}"
assert "AC2" in keys, f"AC2 missing: {keys}"
assert "AC3" not in keys, f"AC3 should be filtered out: {keys}"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
