#!/usr/bin/env bats
# test_deploy_task_stale_field_reset.bats - 再配備時のstale field清掃テスト
# Optimized: deploy_task.sh から resolve_cmd_to_task を抽出して source し、
# 共通の再配備結果を setup_file で一度だけ生成する。

extract_function() {
    local name="$1"
    local start end

    start=$(awk -v name="$name" '$0 ~ "^" name "\\(\\) \\{" { print NR; exit }' "$SRC_DEPLOY_SCRIPT")
    [ -n "$start" ] || return 1

    end=$(awk -v start="$start" '
        NR > start && /^[A-Za-z0-9_]+\(\) \{/ { print NR - 1; found = 1; exit }
        END { if (!found) print NR }
    ' "$SRC_DEPLOY_SCRIPT")
    sed -n "${start},${end}p" "$SRC_DEPLOY_SCRIPT"
}

write_shogun_to_karo_fixture() {
    local root="$1"
    cat > "$root/queue/shogun_to_karo.yaml" <<'EOF'
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
}

write_task_fixture() {
    local root="$1"
    cat > "$root/queue/tasks/tobisaru.yaml" <<'EOF'
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
  timestamp: '2026-03-29T10:00:00'
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
  type: impl
  report_template: '旧テンプレートデータ'
  AC1: '旧AC1: SF LOW偵察のAC1'
  AC2: '旧AC2: SF LOW偵察のAC2'
  AC3: '旧AC3: git commit'
  acceptance_criteria:
    AC1:
      description: '前cmdのAC1'
  _ac_task_id: cmd_8888_impl
  _ac_worker_id: tobisaru
status: in_progress
EOF
}

prepare_source_fixture() {
    local root="$1"
    mkdir -p "$root/queue/tasks" "$root/logs"
    write_shogun_to_karo_fixture "$root"
    write_task_fixture "$root"
}

resolve_fixture_task() {
    local root="$1"
    local cmd_id="$2"
    local ninja_name="$3"

    SCRIPT_DIR="$root"

    log() { :; }

    yaml_field_set() {
        bash "$REAL_PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$@"
    }

    eval "$(extract_function reset_stale_fields)"
    eval "$(extract_function resolve_cmd_to_task)"
    reset_stale_fields "$ninja_name"
    resolve_cmd_to_task "$cmd_id" "$ninja_name"
}

get_task_values() {
    local file="$1"
    shift
    python3 - "$file" "$@" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}
task = data.get("task", {})

for field in sys.argv[2:]:
    value = task.get(field)
    if value is None:
        rendered = "<missing>"
    elif isinstance(value, list):
        rendered = f"<list:{len(value)}>"
    elif isinstance(value, dict):
        rendered = f"<dict:{len(value)}>"
    elif isinstance(value, bool):
        rendered = str(value).lower()
    else:
        rendered = str(value)
    print(f"{field}={rendered}")
PY
}

assert_missing_fields() {
    local file="$1"
    shift
    local output field
    output="$(get_task_values "$file" "$@")"

    for field in "$@"; do
        [[ "$output" == *"${field}=<missing>"* ]]
    done
}

setup_file() {
    export REAL_PROJECT_ROOT
    REAL_PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_DEPLOY_SCRIPT="$REAL_PROJECT_ROOT/scripts/deploy_task.sh"

    [ -f "$SRC_DEPLOY_SCRIPT" ] || return 1
    [ -f "$REAL_PROJECT_ROOT/scripts/lib/yaml_field_set.sh" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    export SOURCE_FIXTURE_ROOT
    SOURCE_FIXTURE_ROOT="$(mktemp -d "$BATS_TMPDIR/stale_reset_source.XXXXXX")"
    export RESOLVED_FIXTURE_ROOT
    RESOLVED_FIXTURE_ROOT="$(mktemp -d "$BATS_TMPDIR/stale_reset_resolved.XXXXXX")"
    export NESTED_RESOLVED_FIXTURE_ROOT
    NESTED_RESOLVED_FIXTURE_ROOT="$(mktemp -d "$BATS_TMPDIR/stale_reset_nested.XXXXXX")"

    prepare_source_fixture "$SOURCE_FIXTURE_ROOT"
    cp -R "$SOURCE_FIXTURE_ROOT"/. "$RESOLVED_FIXTURE_ROOT"/
    resolve_fixture_task "$RESOLVED_FIXTURE_ROOT" "cmd_9999" "tobisaru"

    cp -R "$SOURCE_FIXTURE_ROOT"/. "$NESTED_RESOLVED_FIXTURE_ROOT"/
    python3 - "$NESTED_RESOLVED_FIXTURE_ROOT/queue/tasks/tobisaru.yaml" <<'PY'
import sys

task_file = sys.argv[1]
with open(task_file, encoding="utf-8") as f:
    raw = f.read()

insertion = """  task:
    _ac_task_id: cmd_old_impl
    status: completed
    type: impl
"""
raw = raw.replace("  task_id:", insertion + "  task_id:")

with open(task_file, "w", encoding="utf-8") as f:
    f.write(raw)
PY
    resolve_fixture_task "$NESTED_RESOLVED_FIXTURE_ROOT" "cmd_9999" "tobisaru"
}

teardown_file() {
    [ -d "$SOURCE_FIXTURE_ROOT" ] && rm -rf "$SOURCE_FIXTURE_ROOT"
    [ -d "$RESOLVED_FIXTURE_ROOT" ] && rm -rf "$RESOLVED_FIXTURE_ROOT"
    [ -d "$NESTED_RESOLVED_FIXTURE_ROOT" ] && rm -rf "$NESTED_RESOLVED_FIXTURE_ROOT"
}

@test "再配備でstale field群とネスト汚染を清掃し必要フィールドを保持する" {
    local file="$RESOLVED_FIXTURE_ROOT/queue/tasks/tobisaru.yaml"
    local nested_file="$NESTED_RESOLVED_FIXTURE_ROOT/queue/tasks/tobisaru.yaml"
    local output nested_after root_fields root_field_name

    output="$(get_task_values "$file" parent_cmd task_id task_type project status purpose _ac_task_id _ac_worker_id)"

    [[ "$output" == *"parent_cmd=cmd_9999"* ]]
    [[ "$output" == *"task_id=cmd_9999_impl"* ]]
    [[ "$output" == *"task_type=impl"* ]]
    [[ "$output" == *"project=infra"* ]]
    [[ "$output" == *"status=assigned"* ]]
    [[ "$output" == *"purpose=新しいpurpose"* ]]
    [[ "$output" == *$'_ac_task_id='* ]]
    [[ "$output" == *$'_ac_worker_id='* ]]

    assert_missing_fields \
        "$file" \
        target_path progress description deployed_at \
        constraints engineering_preferences context_files stop_for never_stop_for parallel_ok \
        AC1 AC2 AC3 acceptance_criteria scout_exempt ac_priority ac_checkpoint \
        command reports_to_read credential_warning context_update type report_template \
        worker_id timestamp

    nested_after=$(grep -c '^\s*task:' "$nested_file")
    [ "$nested_after" -eq 1 ]

    root_fields=$(grep -c '^[a-zA-Z_]' "$nested_file")
    [ "$root_fields" -eq 1 ]

    root_field_name=$(grep '^[a-zA-Z_]' "$nested_file" | head -1)
    [[ "$root_field_name" == task:* ]]
}

@test "--directモード: reset_stale_fieldsがstaleフィールドを清掃する(AC2)" {
    # --directモードではresolve_cmd_to_taskをスキップするが
    # reset_stale_fieldsがL3269直後の共通位置で呼ばれるためstaleフィールドは清掃される
    local direct_root
    direct_root="$(mktemp -d "$BATS_TMPDIR/stale_reset_direct.XXXXXX")"
    prepare_source_fixture "$direct_root"

    local file="$direct_root/queue/tasks/tobisaru.yaml"

    SCRIPT_DIR="$direct_root"
    log() { :; }
    eval "$(extract_function reset_stale_fields)"
    reset_stale_fields "tobisaru"

    assert_missing_fields \
        "$file" \
        target_path progress description deployed_at \
        constraints engineering_preferences context_files stop_for never_stop_for parallel_ok \
        AC1 AC2 AC3 acceptance_criteria scout_exempt ac_priority ac_checkpoint \
        command reports_to_read credential_warning context_update type report_template \
        worker_id timestamp

    rm -rf "$direct_root"
}
