#!/usr/bin/env bats
# test_deploy_task_stale_field_reset.bats - 再配備時のstale field清掃テスト
# 真因: resolve_cmd_to_taskが前cmdの残留フィールドをクリアしない(cmd_1519-1522実被害)

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/stale_reset.XXXXXX")"

    export SCRIPT_DIR="$TEST_TMPDIR"
    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/logs" "$TEST_TMPDIR/scripts/lib"

    # yaml_field_set.sh実体をコピー
    cp "$(cd "$(dirname "$BATS_TEST_FILENAME")/../../scripts/lib/yaml_field_set.sh" && pwd)" \
        "$TEST_TMPDIR/scripts/lib/yaml_field_set.sh" 2>/dev/null || \
    cp "$PWD/scripts/lib/yaml_field_set.sh" "$TEST_TMPDIR/scripts/lib/yaml_field_set.sh"

    # shogun_to_karo.yaml（新cmd: cmd_9999）
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_9999:
    id: cmd_9999
    title: 'テスト用新cmd'
    project: infra
    type: impl
    purpose: '新しいpurpose'
    acceptance_criteria:
    - 'AC1: テスト'
    timestamp: '2026-03-30T02:00:00+09:00'
    status: pending
EOF

    # task YAML（前cmd: cmd_8888の残留フィールドあり）
    cat > "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" <<'EOF'
task:
  parent_cmd: cmd_8888
  task_id: cmd_8888_impl
  task_type: impl
  project: dm-signal
  status: completed
  purpose: '前cmdの古いpurpose'
  target_path: /mnt/c/Python_app/DM-signal/backend/old_file.py
  constraints: 'DM-signal制約'
  progress: 'AC1-3全完了。PASS'
  description: '前cmdの説明'
  deployed_at: '2026-03-29T10:00:00'
  worker_id: tobisaru
  acceptance_criteria:
    AC1:
      description: '前cmdのAC1'
  _ac_task_id: cmd_8888_impl
  _ac_worker_id: tobisaru
EOF
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# ─── Helper: resolve_cmd_to_taskロジック抽出 ───
run_resolve_cmd_to_task() {
    local cmd_id="$1"
    local ninja_name="$2"
    local task_file="$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml"
    local stk="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    local log_file="$SCRIPT_DIR/logs/test.log"

    log() { echo "$*" >> "$log_file"; }

    # yaml_field_set
    yaml_field_set() {
        bash "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh" "$@"
    }

    # Python resolve
    local _resolve_output
    _resolve_output=$(python3 - "$stk" "$cmd_id" <<'RESOLVE_PY'
import sys
import yaml

stk_path = sys.argv[1]
cmd_id = sys.argv[2]
with open(stk_path, encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
cmd = (data.get('commands') or {}).get(cmd_id)
if not cmd:
    print(f"ERROR: {cmd_id} not found", file=sys.stderr)
    sys.exit(1)
print(f"project={cmd.get('project', '')}")
print(f"task_type={cmd.get('type', 'impl')}")
print(f"title={cmd.get('title', '')}")
print(f"purpose={cmd.get('purpose', '')}")
RESOLVE_PY
    ) || return 1

    local project task_type title purpose
    project=$(echo "$_resolve_output" | grep '^project=' | cut -d= -f2-)
    task_type=$(echo "$_resolve_output" | grep '^task_type=' | cut -d= -f2-)
    title=$(echo "$_resolve_output" | grep '^title=' | cut -d= -f2-)
    purpose=$(echo "$_resolve_output" | grep '^purpose=' | cut -d= -f2-)
    [ -z "$task_type" ] && task_type="impl"

    local task_id="${cmd_id}_${task_type}"

    # ─── 前cmd残留フィールド清掃 ───
    yaml_field_set "$task_file" "task" "purpose" ""
    yaml_field_set "$task_file" "task" "target_path" ""
    yaml_field_set "$task_file" "task" "constraints" ""
    yaml_field_set "$task_file" "task" "progress" ""
    yaml_field_set "$task_file" "task" "description" ""
    yaml_field_set "$task_file" "task" "deployed_at" ""

    # 中核フィールド設定
    yaml_field_set "$task_file" "task" "parent_cmd" "$cmd_id"
    yaml_field_set "$task_file" "task" "task_id" "$task_id"
    yaml_field_set "$task_file" "task" "task_type" "$task_type"
    [ -n "$project" ] && yaml_field_set "$task_file" "task" "project" "$project"
    yaml_field_set "$task_file" "task" "status" "assigned"
    [ -n "$purpose" ] && yaml_field_set "$task_file" "task" "purpose" "$purpose"
    yaml_field_set "$task_file" "task" "_ac_task_id" ""
    yaml_field_set "$task_file" "task" "_ac_worker_id" ""
}

# ─── field値取得ヘルパー ───
get_field() {
    local file="$1" field="$2"
    python3 -c "
import yaml, sys
with open('$file') as f:
    d = yaml.safe_load(f) or {}
t = d.get('task', {})
print(t.get('$field', '') or '')
"
}

# ─── テスト ───

@test "再配備でparent_cmdが新cmdに更新される" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "parent_cmd")
    [ "$result" = "cmd_9999" ]
}

@test "再配備でpurposeが新cmdのpurposeに更新される" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "purpose")
    [ "$result" = "新しいpurpose" ]
}

@test "再配備でtarget_pathがクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "target_path")
    [ -z "$result" ]
}

@test "再配備でconstraintsがクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "constraints")
    [ -z "$result" ]
}

@test "再配備でprogressがクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "progress")
    [ -z "$result" ]
}

@test "再配備でdescriptionがクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "description")
    [ -z "$result" ]
}

@test "再配備でdeployed_atがクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "deployed_at")
    [ -z "$result" ]
}

@test "再配備でprojectが新cmdのprojectに更新される" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "project")
    [ "$result" = "infra" ]
}
