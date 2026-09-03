#!/usr/bin/env bats
# test_cmd_complete_gate_subsystems.bats
# Consolidated from:
#   test_cmd_complete_gate_review_quality (5 tests)
#   test_cmd_complete_gate_gs_bench (5 tests)
#   test_cmd_complete_gate_stk_status (3 tests)
# Total: 13 tests

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    export SRC_FIELD_GET="$PROJECT_ROOT/scripts/lib/field_get.sh"
    export SRC_YAML_FIELD_SET="$PROJECT_ROOT/scripts/lib/yaml_field_set.sh"
    export SRC_LOCK_PATH="$PROJECT_ROOT/scripts/lib/lock_path.sh"

    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET" ] || return 1
    [ -f "$SRC_YAML_FIELD_SET" ] || return 1
    [ -f "$SRC_LOCK_PATH" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    export SUBSYSTEM_HELPERS="$BATS_FILE_TMPDIR/cmd_complete_gate_subsystems_helpers.bash"
    awk '
        BEGIN {
            split("append_line_locked record_block_reason resolve_gate_rg level_heading detect_task_role cmd_task_matches evaluate_review_report_status find_overlapping_workers run_review_quality_check run_todo_fixme_residual_check run_skill_script_refs_check run_report_memory_semantic_scan classify_missing_report_status check_gs_bench_gate_warn update_status build_karo_ctx_metric", names)
            for (i in names) wanted[names[i]] = 1
        }
        /^[A-Za-z0-9_]+\(\) \{/ {
            name = $0
            sub(/\(\) \{.*/, "", name)
            emit = wanted[name]
        }
        emit { print }
    ' "$SRC_GATE_SCRIPT" "$PROJECT_ROOT/scripts/lib/append_line_locked.sh" > "$SUBSYSTEM_HELPERS"
    # cmd_karo_hotfix_t3s40_post_source_v6: append_line_locked moved (not
    # duplicated) to scripts/lib/append_line_locked.sh (sourced back into
    # $SRC_GATE_SCRIPT); the awk extraction above now also scans that file.
}

setup() {
    source "$SRC_FIELD_GET"
    source "$SRC_YAML_FIELD_SET"
    source "$SRC_LOCK_PATH"
    source "$SUBSYSTEM_HELPERS"
}

teardown() {
    if [ -d "${TEST_TMPDIR:-}" ]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

@test "completion metrics records Karo CTX separately from matching ninja CTX" {
    agent_pane_target() {
        [ "$1" = "karo" ] && printf '%s\n' "shogun:agents.1"
    }
    tmux() {
        printf '%s\n' "46%"
    }

    run build_karo_ctx_metric
    [ "$status" -eq 0 ]
    [ "$output" = "karo_ctx_pct=46" ]
}

@test "completion metrics marks unavailable Karo CTX unknown" {
    agent_pane_target() {
        return 1
    }
    tmux() {
        return 1
    }

    run build_karo_ctx_metric
    [ "$status" -eq 0 ]
    [ "$output" = "karo_ctx_pct=unknown" ]
}

# ═══════════════════════════════════════════════════════
@test "completion metrics append Karo CTX on every post-clear outcome" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
assert source.count('GATE_KARO_CTX_METRIC=$(build_karo_ctx_metric)') == 1
assert source.count('"$GATE_KARO_CTX_METRIC" "$GATE_FIRST_MODEL_METRIC"') == 3
PY
    [ "$status" -eq 0 ]
}

# Section 1: Review Quality (from test_cmd_complete_gate_review_quality.bats)
# ═══════════════════════════════════════════════════════

_setup_review_quality() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/review_quality.XXXXXX")"
    export SCRIPT_DIR="$TEST_TMPDIR"
    export TASKS_DIR="$TEST_TMPDIR/queue/tasks"
    export CMD_ID="cmd_999"
    export BLOCK_REASONS=()
    export ALL_CLEAR=true

    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports" "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/lib"

    resolve_report_file() {
        local ninja="$1"
        echo "$SCRIPT_DIR/queue/reports/${ninja}_report_${CMD_ID}.yaml"
    }
}

_write_task() {
    local ninja="$1"
    local task_type="$2"
    cat > "$TASKS_DIR/${ninja}.yaml" <<EOF
task:
  parent_cmd: $CMD_ID
  task_type: $task_type
  task_id: subtask_test_${task_type}
EOF
}

_write_impl_report() {
    local ninja="$1"
    local worker_id="$2"
    cat > "$TEST_TMPDIR/queue/reports/${ninja}_report_${CMD_ID}.yaml" <<EOF
worker_id: $worker_id
task_id: subtask_test_impl
parent_cmd: $CMD_ID
timestamp: "2026-03-06T00:00:00"
status: done
EOF
}

_write_review_report() {
    local ninja="$1"
    local worker_id="$2"
    local verdict_block="$3"
    local self_gate_block="$4"
    cat > "$TEST_TMPDIR/queue/reports/${ninja}_report_${CMD_ID}.yaml" <<EOF
worker_id: $worker_id
task_id: subtask_test_review
parent_cmd: $CMD_ID
timestamp: "2026-03-06T00:00:00"
status: done
${verdict_block}
${self_gate_block}
EOF
}

_write_recon_report() {
    local ninja="$1"
    cat > "$TEST_TMPDIR/queue/reports/${ninja}_report_${CMD_ID}.yaml" <<EOF
worker_id: $ninja
task_id: subtask_test_recon
parent_cmd: $CMD_ID
timestamp: "2026-03-06T00:00:00"
status: done
EOF
}

_run_review_quality_with_state() {
    run_review_quality_check
    echo "ALL_CLEAR=$ALL_CLEAR"
    echo "BLOCK_REASONS=${BLOCK_REASONS[*]}"
}

_run_todo_check_with_state() {
    run_todo_fixme_residual_check "$CMD_ID"
    echo "ALL_CLEAR=$ALL_CLEAR"
    echo "BLOCK_REASONS=${BLOCK_REASONS[*]}"
}

@test "review report without verdict blocks" {
    _setup_review_quality
    _write_task "sasuke" "implement"
    _write_task "hayate" "review"
    _write_impl_report "sasuke" "sasuke"
    _write_review_report "hayate" "hayate" "" "self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS"

    run _run_review_quality_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"[CRITICAL] hayate: NG ← verdict欠落または不正値"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
}

@test "review report with incomplete self_gate_check blocks" {
    _setup_review_quality
    _write_task "sasuke" "implement"
    _write_task "hayate" "review"
    _write_impl_report "sasuke" "sasuke"
    _write_review_report "hayate" "hayate" "verdict: PASS" "self_gate_check:
  lesson_ref: PASS
  lesson_candidate: FAIL
  status_valid: PASS
  purpose_fit: PASS"

    run _run_review_quality_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"[CRITICAL] hayate: NG ← self_gate_check 4項目が不足またはPASS以外"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
}

@test "same worker as implementer and reviewer blocks" {
    _setup_review_quality
    _write_task "sasuke" "implement"
    _write_task "hayate" "review"
    _write_impl_report "sasuke" "sasuke"
    _write_review_report "hayate" "sasuke" "verdict: PASS" "self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS"

    run _run_review_quality_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"[CRITICAL] NG ← reviewer and implementer overlap: sasuke"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
}

@test "cmd without review report skips new review checks" {
    _setup_review_quality
    _write_task "sasuke" "recon"
    _write_recon_report "sasuke"

    run _run_review_quality_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP (no review reports for this cmd)"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

_setup_skill_script_refs_check() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/skill_refs_cmd_gate.XXXXXX")"
    export SCRIPT_DIR="$TEST_TMPDIR"
    export LOG_DIR="$TEST_TMPDIR/logs"
    export CMD_ID="cmd_2889_test"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/logs"

    cat > "$TEST_TMPDIR/scripts/gates/gate_skill_script_refs.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
=== SKILL.md script reference check ===
走査: 1 SKILL.md / script参照 1件 / 参照あり 1件 / roots=skills
=== 要更新スキル一覧 (script newer than SKILL.md) ===
  WARN: skills/demo/SKILL.md <- scripts/demo.sh (newer: scripts/demo.sh)
--- 総合判定: WARN ---
OUT
exit 2
EOF
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_skill_script_refs.sh"

    cat > "$TEST_TMPDIR/scripts/insight_write.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$TEST_INSIGHT_LOG"
EOF
    chmod +x "$TEST_TMPDIR/scripts/insight_write.sh"
    export TEST_INSIGHT_LOG="$TEST_TMPDIR/insights.log"
}

@test "run_skill_script_refs_check queues insight when scripts changed and SKILL.md is stale" {
    _setup_skill_script_refs_check
    export CMD_CHANGED_FILES=$'scripts/demo.sh\nREADME.md'

    run run_skill_script_refs_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKILL.md script refs need follow-up"* ]]
    [[ "$output" == *"insight: queued SKILL.md follow-up candidate"* ]]
    grep -q "SKILL.md追従cmd候補: cmd_2889_test" "$TEST_INSIGHT_LOG"
    grep -q "cmd_complete_gate:skill_script_refs:cmd_2889_test" "$TEST_INSIGHT_LOG"
}

@test "run_skill_script_refs_check does not queue insight when no scripts changed" {
    _setup_skill_script_refs_check
    export CMD_CHANGED_FILES=$'docs/research/demo.md\nskills/demo/SKILL.md'

    run run_skill_script_refs_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"insight: SKIP (no scripts/* changes in cmd)"* ]]
    [ ! -f "$TEST_INSIGHT_LOG" ]
}

@test "run_skill_script_refs_check skips cmd insight when gate follow-up covers review" {
    _setup_skill_script_refs_check
    cat > "$TEST_TMPDIR/scripts/gates/gate_skill_script_refs.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
=== SKILL.md script reference check ===
走査: 1 SKILL.md / script参照 1件 / 参照あり 1件 / roots=skills
=== 要更新スキル一覧 (script newer than SKILL.md) ===
  WARN: skills/demo/SKILL.md <- scripts/demo.sh (newer: scripts/demo.sh)
FOLLOWUP_QUEUED: pairs=1 route=insight->reflux
FOLLOWUP_COVERS_REVIEW_REQUIRED: yes
--- 総合判定: WARN ---
OUT
exit 2
EOF
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_skill_script_refs.sh"
    export CMD_CHANGED_FILES=$'scripts/demo.sh\nREADME.md'

    run run_skill_script_refs_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"aggregate follow-up already covers review"* ]]
    [ ! -f "$TEST_INSIGHT_LOG" ]
}

@test "run_report_memory_semantic_scan queues NO_MATCH aliases from lesson_candidate" {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/report_memory_semantic.XXXXXX")"
    export SCRIPT_DIR="$TEST_TMPDIR"
    export CMD_ID="cmd_2964"
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports"
    export MATCHING_TASK_FILES=("$TEST_TMPDIR/queue/tasks/hayate.yaml")
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_2964
EOF
    cat > "$TEST_TMPDIR/queue/reports/hayate_report_cmd_2964.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_2964
lesson_candidate:
  found: true
  title: "短期記憶を長期記憶へ移行するPhase"
  detail: "semantic_searchでNO_MATCHをaliases候補として蓄積する"
EOF
    cat > "$TEST_TMPDIR/scripts/semantic_search.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_TMPDIR/semantic_calls.log"
exit 1
EOF
    cat > "$TEST_TMPDIR/scripts/insight_write.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$TEST_TMPDIR/insight_calls.log"
EOF
    chmod +x "$TEST_TMPDIR/scripts/semantic_search.sh" "$TEST_TMPDIR/scripts/insight_write.sh"
    resolve_report_file() {
        local ninja="$1"
        echo "$SCRIPT_DIR/queue/reports/${ninja}_report_${CMD_ID}.yaml"
    }

    run run_report_memory_semantic_scan

    [ "$status" -eq 0 ]
    [[ "$output" == *"checked=1 matched=0 no_match_queued=1 failed=0"* ]]
    grep -q "短期記憶を長期記憶へ移行するPhase" "$TEST_TMPDIR/semantic_calls.log"
    grep -q "cmd_complete NO_MATCH aliases候補: cmd_2964 hayate lesson_candidate" "$TEST_TMPDIR/insight_calls.log"
    grep -q "cmd_complete_gate:memory_phase" "$TEST_TMPDIR/insight_calls.log"
}

@test "TODO in non-test files blocks gate" {
    _setup_review_quality
    mkdir -p "$TEST_TMPDIR/scripts"
    cat > "$TEST_TMPDIR/scripts/sample.sh" <<EOF
#!/usr/bin/env bash
# TODO cmd_999
exit 0
EOF

    run _run_todo_check_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"[CRITICAL] NG ← 1件のTODO/FIXMEが残存:"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
}

@test "TODO check falls back to grep and blocks when rg is unavailable on PATH (AC3 rg fallback)" {
    _setup_review_quality
    mkdir -p "$TEST_TMPDIR/scripts"
    cat > "$TEST_TMPDIR/scripts/sample.sh" <<EOF
#!/usr/bin/env bash
# TODO cmd_999
exit 0
EOF
    local fake_home
    fake_home="$(mktemp -d "$BATS_TMPDIR/fake_home.XXXXXX")"

    # PATHからrgを含むディレクトリを排除し、$HOME/.local/bin/rgフォールバックも
    # fake_home(空)へ差し替えて無効化する。resolve_gate_rgが必ずgrepへ委譲する経路を検証。
    PATH="/usr/bin:/bin" HOME="$fake_home" run _run_todo_check_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"[CRITICAL] NG ← 1件のTODO/FIXMEが残存:"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
}

@test "TODO check falls back to grep and clears when rg is unavailable and no residual exists (AC3 rg fallback)" {
    _setup_review_quality
    mkdir -p "$TEST_TMPDIR/scripts"
    cat > "$TEST_TMPDIR/scripts/sample.sh" <<EOF
#!/usr/bin/env bash
echo "no residual markers here"
exit 0
EOF
    local fake_home
    fake_home="$(mktemp -d "$BATS_TMPDIR/fake_home.XXXXXX")"

    PATH="/usr/bin:/bin" HOME="$fake_home" run _run_todo_check_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"TODO check: OK (0 remaining)"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "skill script refs check runs after clear and keeps stale refs non-blocking" {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/skill_refs_clear.XXXXXX")"
    export SCRIPT_DIR="$TEST_TMPDIR"
    export LOG_DIR="$TEST_TMPDIR/logs"
    export CMD_ID="cmd_999"
    export SKILL_SCRIPT_REFS_GATE_PATH="$TEST_TMPDIR/gate_skill_script_refs.sh"
    mkdir -p "$LOG_DIR"
    cat > "$SKILL_SCRIPT_REFS_GATE_PATH" <<'EOF'
#!/usr/bin/env bash
echo "=== SKILL.md script reference check ==="
echo "走査: 1 SKILL.md / script参照 1件 / 参照あり 1件 / roots=skills"
echo "=== 要更新スキル一覧 (script newer than SKILL.md) ==="
echo "  WARN: skills/demo/SKILL.md <- scripts/demo.sh (newer: scripts/demo.sh)"
echo "--- 総合判定: WARN ---"
exit 2
EOF
    chmod +x "$SKILL_SCRIPT_REFS_GATE_PATH"

    run run_skill_script_refs_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKILL.md script refs (GATE CLEAR):"* ]]
    [[ "$output" == *"要更新スキル一覧"* ]]
    [[ "$output" == *"non-blocking after CLEAR"* ]]
    grep -q 'skill_script_refs' "$LOG_DIR/gate_fire_log.yaml"
}

# ═══════════════════════════════════════════════════════
# Section 2: GS Bench Gate (from test_cmd_complete_gate_gs_bench.bats)
# ═══════════════════════════════════════════════════════

_setup_gs_bench() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gs_bench.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export TEST_CMD_ID="cmd_999"
    export SCRIPT_DIR="$TEST_PROJECT"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"

    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/queue/reports" "$TEST_PROJECT/config"

    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: infra
    path: $TEST_PROJECT
  - id: dm-signal
    path: $TEST_PROJECT
EOF

    level_heading() { echo "=== $2 ==="; }
    is_cmd_task() { grep -q "parent_cmd: ${TEST_CMD_ID}" "$1" 2>/dev/null; }
    resolve_report_file() {
        local ninja="$1"
        echo "$SCRIPT_DIR/queue/reports/${ninja}_report_${TEST_CMD_ID}.yaml"
    }
}

_write_gs_task() {
    local ninja="${1:-sasuke}"
    cat > "$TASKS_DIR/${ninja}.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: impl
EOF
}

_write_report_with_run077() {
    local ninja="${1:-sasuke}"
    local py_file="${2:-run_077_nukimi.py}"
    cat > "$TEST_PROJECT/queue/reports/${ninja}_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: $ninja
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
status: completed
verdict: PASS
files_modified:
  - scripts/analysis/grid_search/${py_file}
EOF
}

_write_report_without_run077() {
    local ninja="${1:-sasuke}"
    cat > "$TEST_PROJECT/queue/reports/${ninja}_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: $ninja
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
status: completed
verdict: PASS
files_modified:
  - scripts/lib/field_get.sh
EOF
}

@test "AC2: files_modifiedにrun_077_nukimi.pyが含まれる場合WARNを出力する" {
    _setup_gs_bench
    _write_gs_task "sasuke"
    _write_report_with_run077 "sasuke" "run_077_nukimi.py"

    run check_gs_bench_gate_warn
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "\[WARN\]"
    echo "$output" | grep -q "nukimi"
}

@test "WARN出力に/gs-bench-gate after --ninjutsu nukimiが含まれる" {
    _setup_gs_bench
    _write_gs_task "sasuke"
    _write_report_with_run077 "sasuke" "run_077_nukimi.py"

    run check_gs_bench_gate_warn
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "/gs-bench-gate after --ninjutsu nukimi"
}

@test "files_modifiedにrun_077_*.pyが含まれない場合はSKIP" {
    _setup_gs_bench
    _write_gs_task "sasuke"
    _write_report_without_run077 "sasuke"

    run check_gs_bench_gate_warn
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "SKIP"
}

@test "gs_gate_after JSONが存在する場合はWARN非発火" {
    _setup_gs_bench
    _write_gs_task "sasuke"
    _write_report_with_run077 "sasuke" "run_077_nukimi.py"

    mkdir -p "$TEST_PROJECT/outputs/analysis"
    echo '{"ninjutsu":"nukimi"}' > "$TEST_PROJECT/outputs/analysis/gs_gate_after_nukimi.json"

    run check_gs_bench_gate_warn
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "\[WARN\]"
    echo "$output" | grep -q "OK"
}

@test "タスクファイルが存在しない場合はSKIP" {
    _setup_gs_bench
    run check_gs_bench_gate_warn
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "SKIP"
}

# ═══════════════════════════════════════════════════════
# Section 3: STK Status (from test_cmd_complete_gate_stk_status.bats)
# ═══════════════════════════════════════════════════════

_setup_stk_status() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/stk_status.XXXXXX")"
    export SCRIPT_DIR="$TEST_TMPDIR"
    export YAML_FILE="$TEST_TMPDIR/queue/shogun_to_karo.yaml"

    mkdir -p "$TEST_TMPDIR/queue" "$TEST_TMPDIR/scripts/lib"

}

@test "GATE CLEAR sets STK status to done (mapping format)" {
    _setup_stk_status
    cat > "$YAML_FILE" <<EOF
commands:
  cmd_999:
    purpose: "STK status update test"
    project: infra
    status: delegated
    timestamp: "2026-03-04T21:25:00+09:00"
EOF

    run update_status "cmd_999"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS UPDATED"* ]]
    run grep "status: done" "$YAML_FILE"
    [ "$status" -eq 0 ]
}

@test "GATE CLEAR sets STK status to done (list format)" {
    _setup_stk_status
    cat > "$YAML_FILE" <<EOF
commands:
  - id: cmd_999
    purpose: "STK status update test"
    project: infra
    status: delegated
    delegated_at: "2026-03-04T21:25:00"
EOF

    run update_status "cmd_999"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS UPDATED"* ]]
    run grep "status: done" "$YAML_FILE"
    [ "$status" -eq 0 ]
}

@test "GATE CLEAR skips update when STK status already done" {
    _setup_stk_status
    cat > "$YAML_FILE" <<EOF
commands:
  cmd_999:
    purpose: "STK status already done test"
    project: infra
    status: done
    timestamp: "2026-03-04T21:25:00+09:00"
EOF

    run update_status "cmd_999"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS ALREADY COMPLETED"* ]]
}

@test "update_status returns non-blocking status-not-found for karo-direct cmd absent from shogun_to_karo.yaml (AC2)" {
    _setup_stk_status
    # karo-direct cmds are never written to shogun_to_karo.yaml, so the cmd_id
    # is simply absent. update_status must surface this as a specified,
    # non-crashing rc=1 result (caller treats it as non-blocking) rather than
    # raising an exception that would abort cmd_complete_gate.sh under `set -e`.
    printf 'commands: {}\n' > "$YAML_FILE"

    run update_status "cmd_999"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: status not found for cmd_999"* ]]
}

# ═══════════════════════════════════════════════════════
# Section 4: AC Version (from test_cmd_complete_gate_ac_version.bats)
# ═══════════════════════════════════════════════════════

_setup_ac_version() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/acv_test.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports"
    source "$SRC_FIELD_GET"
    check_ac_version() {
        local task_file="$1" report_file="$2" ninja_name="$3"
        local _acv_task _acv_read
        _acv_task=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "ac_version" "")
        _acv_read=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "ac_version_read" "")
        case "${_acv_task,,}" in ""|null|none|"~") _acv_task="" ;; esac
        case "${_acv_read,,}" in ""|null|none|"~") _acv_read="" ;; esac
        if [ -z "$_acv_task" ]; then echo "  [INFO] ${ninja_name}: task.ac_version未設定のため照合SKIP"
        elif [[ "$_acv_task" =~ ^[0-9]+$ ]]; then echo "  [INFO] ${ninja_name}: 旧形式(数値)ac_version=${_acv_task}のため照合SKIP（後方互換）"
        elif [ -z "$_acv_read" ]; then echo "  [INFO] ${ninja_name}: ac_version_read未記載（task=${_acv_task}）。後方互換として非BLOCK"
        elif [ "$_acv_task" = "$_acv_read" ]; then echo "  ${ninja_name}: OK (ac_version task=${_acv_task}, report=${_acv_read})"
        else echo "  [CRITICAL] ${ninja_name}: NG ← ac_version不一致 (task=${_acv_task}, report=${_acv_read})"; return 1; fi
    }
}
_write_acv_task() { cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: cmd_999
  ac_version: $1
EOF
}
_write_acv_report() { cat > "$TEST_TMPDIR/queue/reports/sasuke_report.yaml" <<EOF
worker_id: sasuke
parent_cmd: cmd_999
status: done
${1:+ac_version_read: $1}
verdict: PASS
EOF
}

@test "ac_version legacy numeric: gate skips" {
    _setup_ac_version; _write_acv_task "7"; _write_acv_report "7"
    run check_ac_version "$TEST_TMPDIR/queue/tasks/sasuke.yaml" "$TEST_TMPDIR/queue/reports/sasuke_report.yaml" "sasuke"
    [ "$status" -eq 0 ]; [[ "$output" == *"旧形式(数値)"* ]]
}
@test "ac_version hash match: gate passes" {
    _setup_ac_version; _write_acv_task "a3f2b1c9"; _write_acv_report "a3f2b1c9"
    run check_ac_version "$TEST_TMPDIR/queue/tasks/sasuke.yaml" "$TEST_TMPDIR/queue/reports/sasuke_report.yaml" "sasuke"
    [ "$status" -eq 0 ]; [[ "$output" == *"OK (ac_version task=a3f2b1c9"* ]]
}
@test "ac_version hash mismatch: gate blocks" {
    _setup_ac_version; _write_acv_task "d287147e"; _write_acv_report "519485d7"
    run check_ac_version "$TEST_TMPDIR/queue/tasks/sasuke.yaml" "$TEST_TMPDIR/queue/reports/sasuke_report.yaml" "sasuke"
    [ "$status" -eq 1 ]; [[ "$output" == *"[CRITICAL] sasuke: NG ← ac_version不一致"* ]]
}
@test "ac_version missing report: warn only" {
    _setup_ac_version; _write_acv_task "a3f2b1c9"; _write_acv_report ""
    run check_ac_version "$TEST_TMPDIR/queue/tasks/sasuke.yaml" "$TEST_TMPDIR/queue/reports/sasuke_report.yaml" "sasuke"
    [ "$status" -eq 0 ]; [[ "$output" == *"ac_version_read未記載"* ]]
}

_setup_missing_report_status() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/missing_report_status.XXXXXX")"
}

@test "missing report waits only for active task states" {
    _setup_missing_report_status
    for state in assigned acknowledged in_progress; do
        run classify_missing_report_status "$state"
        [ "$status" -eq 0 ]
        [ "$output" = "wait" ]
    done
}

@test "missing report skips idle and terminal inactive task states" {
    _setup_missing_report_status
    for state in idle failed canceled cancelled superseded skipped; do
        run classify_missing_report_status "$state"
        [ "$status" -eq 0 ]
        [ "$output" = "skip" ]
    done
}

@test "missing report fails fast for done and unknown states" {
    _setup_missing_report_status
    for state in done complete unexpected ""; do
        run classify_missing_report_status "$state"
        [ "$status" -eq 0 ]
        [ "$output" = "missing" ]
    done
}
