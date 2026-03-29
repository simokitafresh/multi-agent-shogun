#!/usr/bin/env bats
# test_deploy_task_stale_field_reset.bats - 再配備時のstale field清掃テスト
# なぜなぜ3層: (1)resolve_cmd_to_taskリセット漏れ (2)yaml_field_setリスト非対応
# (3)inject_task_modifiers.py存在チェック不整合 → Python一括クリアで根治

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/stale_reset.XXXXXX")"

    export SCRIPT_DIR="$TEST_TMPDIR"
    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/logs" "$TEST_TMPDIR/scripts/lib"

    # yaml_field_set.sh実体をコピー
    cp "$PWD/scripts/lib/yaml_field_set.sh" "$TEST_TMPDIR/scripts/lib/yaml_field_set.sh" 2>/dev/null || \
    cp "$(cd "$(dirname "$BATS_TEST_FILENAME")/../../scripts/lib/yaml_field_set.sh" && pwd)" \
        "$TEST_TMPDIR/scripts/lib/yaml_field_set.sh"

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

    # task YAML（前cmd: cmd_8888の残留フィールドあり — スカラー+リスト両方）
    cat > "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" <<'EOF'
task:
  parent_cmd: cmd_8888
  task_id: cmd_8888_impl
  task_type: impl
  project: dm-signal
  status: completed
  purpose: '前cmdの古いpurpose'
  target_path: /mnt/c/Python_app/DM-signal/backend/old_file.py
  constraints:
  - 'DM-signal制約1'
  - 'DM-signal制約2'
  progress: 'AC1-3全完了。PASS'
  description: '前cmdの説明'
  deployed_at: '2026-03-29T10:00:00'
  worker_id: tobisaru
  engineering_preferences:
  - 'prefer old approach'
  - 'prefer another old approach'
  context_files:
  - 'context/dm-signal.md'
  - 'context/dm-signal-core.md'
  stop_for:
  - 'old stop condition 1'
  - 'old stop condition 2'
  never_stop_for:
  - 'old never stop 1'
  ac_priority: 'AC1 > AC2 > AC3'
  ac_checkpoint: '旧チェックポイント'
  parallel_ok:
  - AC1
  - AC2
  - AC3
  scout_exempt: true
  command: 'gate_fire_log書込み箇所にgate名フィールドを追加せよ'
  reports_to_read:
  - 'queue/reports/old_report.yaml'
  credential_warning: '⚠ 認証が必要なタスク'
  context_update: '前cmdのcontext更新情報'
  AC1: '旧AC1: SF LOW偵察のAC1'
  AC2: '旧AC2: SF LOW偵察のAC2'
  AC3: '旧AC3: git commit'
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

    # Python一括stale fieldクリア（deploy_task.shと同一ロジック）
    python3 - "$task_file" <<'STALE_FIELD_RESET_PY'
import os, sys, tempfile, re

task_file = sys.argv[1]
STALE_FIELDS = [
    'purpose', 'target_path', 'constraints', 'progress', 'description', 'deployed_at',
    'engineering_preferences', 'context_files', 'stop_for', 'never_stop_for',
    'ac_priority', 'ac_checkpoint', 'parallel_ok',
    'AC1', 'AC2', 'AC3', 'scout_exempt',
    'command', 'reports_to_read', 'credential_warning', 'context_update',
]

with open(task_file, 'r', encoding='utf-8') as f:
    raw = f.read()

for field in STALE_FIELDS:
    pat = re.compile(
        r'^  ' + re.escape(field) + r':.*?(?=\n  [a-zA-Z_]|\Z)',
        re.MULTILINE | re.DOTALL,
    )
    raw = pat.sub('', raw)

raw = re.sub(r'\n{3,}', '\n\n', raw)

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(raw)
    os.replace(tmp_path, task_file)
except Exception:
    try: os.unlink(tmp_path)
    except OSError: pass
    raise
STALE_FIELD_RESET_PY

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
import yaml
with open('$file') as f:
    d = yaml.safe_load(f) or {}
t = d.get('task', {})
v = t.get('$field')
if v is None:
    print('')
elif isinstance(v, list):
    print('LIST:' + str(len(v)))
elif isinstance(v, bool):
    print(str(v).lower())
else:
    print(str(v))
"
}

# ─── スカラーフィールドのテスト ───

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

# ─── リスト型フィールドのテスト（yaml_field_setでは不可能→Python一括クリアで解決） ───

@test "再配備でconstraints(リスト)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "constraints")
    [ -z "$result" ]
}

@test "再配備でengineering_preferences(リスト)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "engineering_preferences")
    [ -z "$result" ]
}

@test "再配備でcontext_files(リスト)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "context_files")
    [ -z "$result" ]
}

@test "再配備でstop_for(リスト)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "stop_for")
    [ -z "$result" ]
}

@test "再配備でnever_stop_for(リスト)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "never_stop_for")
    [ -z "$result" ]
}

@test "再配備でparallel_ok(リスト)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "parallel_ok")
    [ -z "$result" ]
}

# ─── 忍者書込み+per-cmdフラグのテスト ───

@test "再配備でAC1(忍者書込み)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "AC1")
    [ -z "$result" ]
}

@test "再配備でAC2(忍者書込み)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "AC2")
    [ -z "$result" ]
}

@test "再配備でAC3(忍者書込み)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "AC3")
    [ -z "$result" ]
}

@test "再配備でscout_exempt(per-cmd)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "scout_exempt")
    [ -z "$result" ]
}

@test "再配備でac_priority(スカラー)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "ac_priority")
    [ -z "$result" ]
}

@test "再配備でac_checkpoint(スカラー)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "ac_checkpoint")
    [ -z "$result" ]
}

# ─── 第4層: 旧版由来の残留フィールドのテスト ───

@test "再配備でcommand(旧版残留)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "command")
    [ -z "$result" ]
}

@test "再配備でreports_to_read(リスト)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "reports_to_read")
    [ -z "$result" ]
}

@test "再配備でcredential_warning(スカラー)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "credential_warning")
    [ -z "$result" ]
}

@test "再配備でcontext_update(スカラー)がクリアされる" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "context_update")
    [ -z "$result" ]
}

# ─── 保持されるべきフィールドのテスト ───

@test "再配備でworker_idが保持される" {
    run_resolve_cmd_to_task cmd_9999 tobisaru
    result=$(get_field "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" "worker_id")
    [ "$result" = "tobisaru" ]
}
