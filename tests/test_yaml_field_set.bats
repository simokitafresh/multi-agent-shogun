#!/usr/bin/env bats
# test_yaml_field_set.bats - Unit tests for scripts/lib/yaml_field_set.sh

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export YAML_FIELD_SET_SCRIPT="$PROJECT_ROOT/scripts/lib/yaml_field_set.sh"

    [ -f "$YAML_FIELD_SET_SCRIPT" ] || return 1
    command -v awk >/dev/null 2>&1 || return 1
    command -v flock >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/yaml_field_set.XXXXXX")"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "replaces existing field in id block" {
    local yaml="$TEST_TMPDIR/cmd.yaml"
    cat > "$yaml" <<'YAML'
commands:
  - id: cmd_100
    status: pending
    project: infra
YAML

    run bash "$YAML_FIELD_SET_SCRIPT" "$yaml" "cmd_100" "status" "completed"
    [ "$status" -eq 0 ]

    run rg -n "^    status: completed$" "$yaml"
    [ "$status" -eq 0 ]
}

@test "adds missing field in id block" {
    local yaml="$TEST_TMPDIR/cmd_add.yaml"
    cat > "$yaml" <<'YAML'
commands:
  - id: cmd_101
    status: pending
YAML

    run bash "$YAML_FIELD_SET_SCRIPT" "$yaml" "cmd_101" "priority" "high"
    [ "$status" -eq 0 ]

    run rg -n "^    priority: high$" "$yaml"
    [ "$status" -eq 0 ]
}

@test "returns FATAL when block_id is missing" {
    local yaml="$TEST_TMPDIR/not_found.yaml"
    cat > "$yaml" <<'YAML'
commands:
  - id: cmd_102
    status: pending
YAML

    run bash "$YAML_FIELD_SET_SCRIPT" "$yaml" "cmd_999" "status" "completed"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FATAL"* ]]
    [[ "$output" == *"block_id not found"* ]]
}

@test "flock serialization allows concurrent writes without corruption" {
    local yaml="$TEST_TMPDIR/concurrent.yaml"
    cat > "$yaml" <<'YAML'
commands:
  - id: cmd_200
    status: pending
YAML

    bash "$YAML_FIELD_SET_SCRIPT" "$yaml" "cmd_200" "status" "in_progress" &
    local pid1=$!
    bash "$YAML_FIELD_SET_SCRIPT" "$yaml" "cmd_200" "status" "completed" &
    local pid2=$!

    wait "$pid1"
    local rc1=$?
    wait "$pid2"
    local rc2=$?

    [ "$rc1" -eq 0 ]
    [ "$rc2" -eq 0 ]

    local count
    count=$(rg -c "^    status:" "$yaml")
    [ "$count" -eq 1 ]

    local final
    final=$(awk '/^    status:/ {print $2}' "$yaml")
    [[ "$final" == "in_progress" || "$final" == "completed" ]]
}

@test "preserves indent level for 4-space list style" {
    local yaml="$TEST_TMPDIR/indent.yaml"
    cat > "$yaml" <<'YAML'
commands:
    - id: cmd_300
      status: pending
      project: infra
YAML

    run bash "$YAML_FIELD_SET_SCRIPT" "$yaml" "cmd_300" "status" "done"
    [ "$status" -eq 0 ]

    run rg -n "^      status: done$" "$yaml"
    [ "$status" -eq 0 ]
}

@test "supports top-level mapping block updates (task:)" {
    local yaml="$TEST_TMPDIR/task.yaml"
    cat > "$yaml" <<'YAML'
task:
  status: assigned
  assigned_to: kirimaru
YAML

    run bash "$YAML_FIELD_SET_SCRIPT" "$yaml" "task" "status" "done"
    [ "$status" -eq 0 ]

    run rg -n "^  status: done$" "$yaml"
    [ "$status" -eq 0 ]
}
