#!/usr/bin/env bats
# test_cmd_complete_gate_context_freshness_block.bats
# GA-238/239/241/242: check_context_freshness_own_commit() のBLOCK/WARN/PASS契約を検証する。
# 既存の「Context freshness nudge」(非同期・出力破棄、CLEARを止めない)を置き換える
# 新しい同期・相関ベースのpre-CLEARブロックゲート。

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1

    export CFB_HELPERS="$BATS_FILE_TMPDIR/cmd_complete_gate_context_freshness_block_helpers.bash"
    # Brace-balance extraction: robust regardless of whether another function
    # definition follows immediately (unlike a "next function start" scan,
    # which over-captures when the function is followed by plain script code).
    extract_function_braces() {
        local name="$1"
        awk -v name="$name" '
            BEGIN { active = 0; depth = 0 }
            !active && $0 ~ "^" name "\\(\\) \\{" { active = 1; depth = 0 }
            active {
                print
                n = gsub(/\{/, "{"); depth += n
                n = gsub(/\}/, "}"); depth -= n
                if (depth <= 0) { exit }
            }
        ' "$SRC_GATE_SCRIPT"
    }
    extract_function_braces check_context_freshness_own_commit > "$CFB_HELPERS"
    [ -s "$CFB_HELPERS" ]
}

setup() {
    source "$CFB_HELPERS"
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cfb.XXXXXX")"
    export SCRIPT_DIR="$TEST_TMPDIR"
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports"
}

teardown() {
    [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

_write_task() {
    local ninja="$1"
    local project="$2"
    cat > "$TEST_TMPDIR/queue/tasks/${ninja}.yaml" <<EOF
task:
  task_id: cmd_test_normal
  project: ${project}
EOF
}

_write_mock_check_script() {
    # $1 = script body (heredoc content printed by --cmd-commit-list)
    cat > "$TEST_TMPDIR/scripts/context_freshness_check.sh" <<SH
#!/usr/bin/env bash
$1
SH
    chmod +x "$TEST_TMPDIR/scripts/context_freshness_check.sh"
}

_write_report_paths() {
    local ninja="$1"
    shift
    local report_rel="queue/reports/${ninja}_report.yaml"
    printf '\n  report_path: %s\n' "$report_rel" >> "$TEST_TMPDIR/queue/tasks/${ninja}.yaml"
    {
        echo "files_modified:"
        local path
        for path in "$@"; do
            printf -- '- path: %s\n  change: test fixture\n' "$path"
        done
    } > "$TEST_TMPDIR/$report_rel"
}

@test "own commit present in unreflected backlog -> BLOCK (return 1)" {
    _write_task hayate dm-signal
    MATCHING_TASK_FILES=("$TEST_TMPDIR/queue/tasks/hayate.yaml")
    _write_mock_check_script '
cat <<OUT
context/dm-signal-core.md	0568b016	cmd_3873: add immutable recalculation input bundle
context/dm-signal-ops.md	0568b016	cmd_3873: add immutable recalculation input bundle
OUT
'
    run check_context_freshness_own_commit "cmd_3873"
    [ "$status" -eq 1 ]
    [[ "$output" == *"context/dm-signal-core.md"* ]]
    [[ "$output" == *"context/dm-signal-ops.md"* ]]
}

@test "approved report with test-only files skips context reflux BLOCK" {
    _write_task hanzo dm-signal
    _write_report_paths hanzo backend/tests/test_p4_bundle_uvicorn_cmd_3880.py
    MATCHING_TASK_FILES=("$TEST_TMPDIR/queue/tasks/hanzo.yaml")
    _write_mock_check_script '
cat <<OUT
context/dm-signal-core.md\t5ae3e208\tcmd_test_only: fix uvicorn test cwd
context/dm-signal-ops.md\t5ae3e208\tcmd_test_only: fix uvicorn test cwd
OUT
'
    run check_context_freshness_own_commit "cmd_test_only"
    [ "$status" -eq 0 ]
    [[ "$output" == *"approved files_modified are test-only"* ]]
}

@test "approved report containing source path still blocks context reflux" {
    _write_task tobisaru dm-signal
    _write_report_paths tobisaru tests/test_loader.py scripts/analysis/loader.py
    MATCHING_TASK_FILES=("$TEST_TMPDIR/queue/tasks/tobisaru.yaml")
    _write_mock_check_script '
echo -e "context/dm-signal-core.md\t1611ef2e\tcmd_source_change: restore loader"
'
    run check_context_freshness_own_commit "cmd_source_change"
    [ "$status" -eq 1 ]
    [[ "$output" == *"context/dm-signal-core.md"* ]]
}

@test "unrelated cmd whose own commit is NOT in the backlog -> PASS (return 0), zero false block" {
    _write_task hayate dm-signal
    MATCHING_TASK_FILES=("$TEST_TMPDIR/queue/tasks/hayate.yaml")
    _write_mock_check_script '
cat <<OUT
context/dm-signal-core.md	0568b016	cmd_3873: add immutable recalculation input bundle
OUT
'
    run check_context_freshness_own_commit "cmd_3999_totally_unrelated"
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK"* ]]
}

@test "no ALERT backlog at all -> PASS (return 0)" {
    _write_task hayate dm-signal
    MATCHING_TASK_FILES=("$TEST_TMPDIR/queue/tasks/hayate.yaml")
    _write_mock_check_script 'true'
    run check_context_freshness_own_commit "cmd_3873"
    [ "$status" -eq 0 ]
}

@test "GA-242: project without pathspec definitions naturally produces empty output -> PASS (no hardcoded project whitelist)" {
    _write_task hayate clinic-expense-tracker
    MATCHING_TASK_FILES=("$TEST_TMPDIR/queue/tasks/hayate.yaml")
    # Mirrors real context_freshness_check.sh --cmd-commit-list: a project with
    # no context_file/context_files pathspec definitions in config/projects.yaml
    # yields zero lines (iter_context_files finds no match), not an error.
    _write_mock_check_script '
if [ "$CFC_PROJECT_OVERRIDE" = "dm-signal" ] || [ "$CFC_PROJECT_OVERRIDE" = "infra" ] || [ "$CFC_PROJECT_OVERRIDE" = "database" ]; then
  echo -e "context/dm-signal-core.md\tdeadbeef\tcmd_3873: should never be seen for this project"
fi
'
    run check_context_freshness_own_commit "cmd_3873"
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK"* ]]
}

@test "GA-242: database project (split外, no infra/dm-signal hardcode) is checked and blocks like any other project" {
    _write_task hayate database
    MATCHING_TASK_FILES=("$TEST_TMPDIR/queue/tasks/hayate.yaml")
    _write_mock_check_script '
if [ "$CFC_PROJECT_OVERRIDE" = "database" ]; then
  echo -e "context/database.md\tabc1234\tcmd_3873: should be seen for database project"
fi
'
    run check_context_freshness_own_commit "cmd_3873"
    [ "$status" -eq 1 ]
    [[ "$output" == *"context/database.md"* ]]
}

@test "context_freshness_check.sh timeout/failure does NOT block completion (fail-open on infra flakiness, not on unreflected content)" {
    _write_task hayate dm-signal
    MATCHING_TASK_FILES=("$TEST_TMPDIR/queue/tasks/hayate.yaml")
    _write_mock_check_script 'exit 1'
    run check_context_freshness_own_commit "cmd_3873"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN]"* ]]
    [[ "$output" == *"timeout/error"* ]]
}

@test "CHECK_FAILED line for an unrelated file is surfaced as WARN but does not block when own commit is not among failures" {
    _write_task hayate dm-signal
    MATCHING_TASK_FILES=("$TEST_TMPDIR/queue/tasks/hayate.yaml")
    _write_mock_check_script '
cat <<OUT
CHECK_FAILED	context/dm-signal-frontend.md
OUT
'
    run check_context_freshness_own_commit "cmd_3873"
    [ "$status" -eq 0 ]
    [[ "$output" == *"context freshness check未確定"* ]]
    [[ "$output" == *"context/dm-signal-frontend.md"* ]]
}

@test "MISSING_SOURCE_COMMIT for a registered context fails closed and blocks completion" {
    _write_task hayate infra
    MATCHING_TASK_FILES=("$TEST_TMPDIR/queue/tasks/hayate.yaml")
    _write_mock_check_script '
echo -e "MISSING_SOURCE_COMMIT\tcontext/codd.md"
'
    run check_context_freshness_own_commit "cmd_3873"
    [ "$status" -eq 1 ]
    [[ "$output" == *"source_commit marker missing"* ]]
    [[ "$output" == *"context/codd.md"* ]]
}

@test "substring collision guard: cmd_id must be an exact subject prefix, not a partial match" {
    _write_task hayate dm-signal
    MATCHING_TASK_FILES=("$TEST_TMPDIR/queue/tasks/hayate.yaml")
    _write_mock_check_script '
cat <<OUT
context/dm-signal-core.md	abc1234	cmd_38730_unrelated_longer_id: not the same cmd
OUT
'
    run check_context_freshness_own_commit "cmd_3873"
    [ "$status" -eq 0 ]
}

@test "multiple distinct projects across MATCHING_TASK_FILES are all checked; a hit in either blocks" {
    _write_task hayate dm-signal
    cat > "$TEST_TMPDIR/queue/tasks/kotaro.yaml" <<EOF
task:
  task_id: cmd_test_normal2
  project: infra
EOF
    MATCHING_TASK_FILES=("$TEST_TMPDIR/queue/tasks/hayate.yaml" "$TEST_TMPDIR/queue/tasks/kotaro.yaml")
    _write_mock_check_script '
if [ "$CFC_PROJECT_OVERRIDE" = "infra" ]; then
  echo -e "context/codd.md\tabc1234\tcmd_3873: infra side change"
fi
'
    run check_context_freshness_own_commit "cmd_3873"
    [ "$status" -eq 1 ]
    [[ "$output" == *"context/codd.md"* ]]
}

@test "no MATCHING_TASK_FILES (benchmark fast-path style) -> PASS without invoking the check script" {
    MATCHING_TASK_FILES=()
    # No mock script written at all -- if the function tried to invoke it, this would error.
    run check_context_freshness_own_commit "cmd_bench_only"
    [ "$status" -eq 0 ]
}
