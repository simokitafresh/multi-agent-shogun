#!/usr/bin/env bats
# test_deploy_task_double_deploy_guard.bats - 同一cmd別忍者二重配備防止ガード
# cmd_cycle_001: deploy_task.shに追加した二重配備ガードのテスト

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/double_deploy.XXXXXX")"

    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/logs"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# ─── Helper: 二重配備ガードロジック(deploy_task.shから抽出) ───
run_double_deploy_guard() {
    local SCRIPT_DIR="$TEST_TMPDIR"
    local NINJA_NAME="$1"
    local _TASK_YAML="$SCRIPT_DIR/queue/tasks/${NINJA_NAME}.yaml"
    local log_file="$SCRIPT_DIR/logs/double_deploy_test.log"

    log() { echo "$*" >> "$log_file"; }

    # field_get簡易版（grep/sed）
    local DEPLOY_PARENT_CMD
    DEPLOY_PARENT_CMD=$(grep -m1 '^\s*parent_cmd:' "$_TASK_YAML" 2>/dev/null | sed "s/.*parent_cmd:[[:space:]]*//" | sed "s/['\"]//g" | sed 's/[[:space:]]*$//')

    if [ -n "$DEPLOY_PARENT_CMD" ]; then
        for _dd_task in "$SCRIPT_DIR/queue/tasks/"*.yaml; do
            [ -f "$_dd_task" ] || continue
            _dd_ninja=$(basename "$_dd_task" .yaml)
            [ "$_dd_ninja" = "$NINJA_NAME" ] && continue
            _dd_pcmd=$(grep -m1 '^\s*parent_cmd:' "$_dd_task" 2>/dev/null | sed "s/.*parent_cmd:[[:space:]]*//" | sed "s/['\"]//g" | sed 's/[[:space:]]*$//')
            [ "$_dd_pcmd" != "$DEPLOY_PARENT_CMD" ] && continue
            _dd_status=$(grep -m1 '^\s*status:' "$_dd_task" 2>/dev/null | sed "s/.*status:[[:space:]]*//" | sed "s/['\"]//g" | sed 's/[[:space:]]*$//')
            case "$_dd_status" in
                assigned|acknowledged|in_progress)
                    log "BLOCK: ${DEPLOY_PARENT_CMD} is already assigned to ${_dd_ninja} (status: ${_dd_status})"
                    echo "BLOCK: ${DEPLOY_PARENT_CMD} is already assigned to ${_dd_ninja} (status: ${_dd_status})" >&2
                    echo "Clear the existing task first: bash scripts/lib/yaml_field_set.sh queue/tasks/${_dd_ninja}.yaml task status idle" >&2
                    return 1
                    ;;
            esac
        done
    fi
    return 0
}

# ─── テスト1: 同一cmd別忍者にassigned→BLOCK ───
@test "double_deploy_guard: same cmd assigned to another ninja → BLOCK" {
    # hayateにcmd_100をassigned
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: assigned
EOF

    # sasukeにcmd_100を配備しようとする → BLOCK
    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"hayate"* ]]
    [[ "$output" == *"assigned"* ]]
    [[ "$output" == *"yaml_field_set"* ]]
}

# ─── テスト2: 同一cmd別忍者にin_progress→BLOCK ───
@test "double_deploy_guard: same cmd in_progress on another ninja → BLOCK" {
    cat > "$TEST_TMPDIR/queue/tasks/hanzo.yaml" <<'EOF'
task:
  parent_cmd: cmd_200
  status: in_progress
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_200
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"hanzo"* ]]
    [[ "$output" == *"in_progress"* ]]
}

# ─── テスト3: 同一cmd別忍者idle→PASS（再配備可能） ───
@test "double_deploy_guard: same cmd idle on another ninja → PASS" {
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: idle
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 0 ]
}

# ─── テスト4: 同一cmd同一忍者（上書き）→PASS ───
@test "double_deploy_guard: same cmd same ninja (self-overwrite) → PASS" {
    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: assigned
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 0 ]
}

# ─── テスト5: 異なるcmd→PASS ───
@test "double_deploy_guard: different cmd on another ninja → PASS" {
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_200
  status: assigned
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 0 ]
}

# ─── テスト6: 同一cmd別忍者にacknowledged→BLOCK ───
@test "double_deploy_guard: same cmd acknowledged on another ninja → BLOCK" {
    cat > "$TEST_TMPDIR/queue/tasks/kagemaru.yaml" <<'EOF'
task:
  parent_cmd: cmd_300
  status: acknowledged
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_300
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"kagemaru"* ]]
}

# ─── テスト7: 同一cmd別忍者completed→PASS ───
@test "double_deploy_guard: same cmd completed on another ninja → PASS" {
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: completed
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 0 ]
}

# ─── テスト8: BLOCK時に解消コマンドが表示される ───
@test "double_deploy_guard: BLOCK message includes clear command" {
    cat > "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" <<'EOF'
task:
  parent_cmd: cmd_400
  status: in_progress
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_400
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 1 ]
    [[ "$output" == *"Clear the existing task first"* ]]
    [[ "$output" == *"tobisaru"* ]]
    [[ "$output" == *"status idle"* ]]
}
