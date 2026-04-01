#!/usr/bin/env bats
# test_deploy_task_ac_verify.bats - verify_ac_consistency: AC count/ID mismatch WARNING (cmd_1668)
# Optimized: deploy_task.sh全体実行→関数直接呼び出し（13.9s→<1.4s目標）

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/deploy_task.sh"
    export SRC_FIELD_GET_SCRIPT="$PROJECT_ROOT/scripts/lib/field_get.sh"
    [ -f "$SRC_DEPLOY_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/ac_verify.XXXXXX")"
    export SCRIPT_DIR="$TEST_TMPDIR"
    export LOG="/dev/null"

    mkdir -p \
        "$TEST_TMPDIR/queue/tasks" \
        "$TEST_TMPDIR/queue/archive/cmds"

    # field_getをsource
    source "$SRC_FIELD_GET_SCRIPT"

    # logスタブ（stderrに出力）
    log() { echo "[DEPLOY] $1" >&2; }
    export -f log

    # verify_ac_consistency関数を抽出してsource
    eval "$(sed -n '/^verify_ac_consistency()/,/^}/p' "$SRC_DEPLOY_SCRIPT")"
}

teardown() {
    [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# ─── AC1: WARNING on count mismatch ───
# To trigger WARNING, _ac_task_id and _ac_worker_id must match current deploy
# (so AC overwrite is skipped) but ACs are mismatched vs cmd source.

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
