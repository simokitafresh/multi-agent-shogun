#!/usr/bin/env bats
# test_necessity: Duplicate/missing block IDs fail closed with byte-identical file (no partial writes); violation is BLOCK.
# test_yaml_field_set.bats
# Purpose: scripts/lib/yaml_field_set.sh の関数テスト
# Origin: cmd_cycle_002
# cmd_1565: tests/版(flock並行/indent保存/task_id追加)を統合
# 教訓L074: ((PASS++))禁止 → PASS=$((PASS+1))
# 教訓L283: テスト名に"skip"を含めない（hook誤検知防止）

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export YFS="$PROJECT_ROOT/scripts/lib/yaml_field_set.sh"
    [ -f "$YFS" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$BATS_TEST_TMPDIR"
}

make_nonexec_structural_writer_yfs() {
    local fixture_root="$TEST_TMPDIR/nonexec-structural-writer"
    mkdir -p "$fixture_root/scripts/lib"
    cp "$YFS" "$fixture_root/scripts/lib/yaml_field_set.sh"
    cat > "$fixture_root/scripts/report_field_set.sh" <<EOF
#!/usr/bin/env bash
exec bash "$PROJECT_ROOT/scripts/report_field_set.sh" "\$@"
EOF
    chmod 0644 "$fixture_root/scripts/report_field_set.sh"
    [ "$(stat -c '%a' "$fixture_root/scripts/report_field_set.sh")" = "644" ] || return 1
    printf '%s\n' "$fixture_root/scripts/lib/yaml_field_set.sh"
}

# --- 1. 既存フィールドの値更新 ---

@test "mapping block: 既存フィールド値の更新" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
task:
  status: pending
  ninja: hayate
EOF
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" task status done
    [ "$status" -eq 0 ]
    run grep "status: done" "$TEST_TMPDIR/test.yaml"
    [ "$status" -eq 0 ]
}

# test_necessity: Interpreter-invoked typed task writes must work when Git preserves report_field_set.sh as mode 100644; violation blocks every structured field.
@test "task test_necessity: JSON入力をscalar化せず構造listとしてatomic保存する" {
    local yaml="$TEST_TMPDIR/task_necessity.yaml"
    local fixture_yfs
    fixture_yfs="$(make_nonexec_structural_writer_yfs)"
    cat > "$yaml" <<'EOF'
task:
  status: in_progress
  test_necessity: []
EOF
    local payload='[{"path":"tests/test_contract.py","defense_target":"typed contract remains structured","overlap_evidence":"no equivalent contract exists","overlaps_existing":false,"fixture_self_reference":false,"deprecated_mechanism":false}]'

    run bash "$fixture_yfs" "$yaml" task test_necessity "$payload"
    [ "$status" -eq 0 ]
    run python3 - "$yaml" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
value = data["task"]["test_necessity"]
assert isinstance(value, list), type(value)
assert len(value) == 1
assert value[0]["path"] == "tests/test_contract.py"
assert value[0]["overlaps_existing"] is False
print("STRUCTURED_LIST_OK=1 ENTRIES=1")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"STRUCTURED_LIST_OK=1 ENTRIES=1"* ]]
}

@test "task test_necessity: scalar入力はbyte-identical fail closedする" {
    local yaml="$TEST_TMPDIR/task_necessity_scalar.yaml"
    cat > "$yaml" <<'EOF'
task:
  status: in_progress
  test_necessity: []
EOF
    cp "$yaml" "$yaml.before"

    run bash "$YFS" "$yaml" task test_necessity "not-structured"
    [ "$status" -eq 2 ]
    [[ "$output" == *"must be a YAML list or mapping"* ]]
    run cmp -s "$yaml.before" "$yaml"
    [ "$status" -eq 0 ]
}

# cmd_karo_hotfix_control_plane_contracts_ga321_20260723
# test_necessity: deploy_taskが公開するcommit_contractはreportと同じmapping型でなければreadonly免除判定が壊れる。
@test "task commit_contract: JSON mapping入力をscalar化せず構造mappingとして保存する" {
    local yaml="$TEST_TMPDIR/task_commit_contract.yaml"
    cat > "$yaml" <<'EOF'
task:
  status: assigned
  commit_contract: {}
EOF
    local payload='{"required":false,"reason":"allowed_no_code_task_type","task_type":"readonly","planned_paths":[]}'

    run bash "$YFS" "$yaml" task commit_contract "$payload"
    [ "$status" -eq 0 ]
    run python3 - "$yaml" <<'PY'
import sys, yaml
contract = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]["commit_contract"]
assert isinstance(contract, dict), type(contract)
assert contract == {
    "required": False,
    "reason": "allowed_no_code_task_type",
    "task_type": "readonly",
    "planned_paths": [],
}
PY
    [ "$status" -eq 0 ]
}

# test_necessity: 10分契約のsplit_decisionはmapping型でなければ
# deploy_task preflightが見た目上JSONのscalarを拒否し、再配備不能になる。
@test "split_decision: taskとcmd正本でJSON mapping入力を構造mappingとして保存する" {
    local yaml="$TEST_TMPDIR/task_split_decision.yaml"
    cat > "$yaml" <<'EOF'
task:
  status: assigned
  split_decision: {}
EOF
    local payload='{"boundary_ac_ids":["AC1","AC2"],"integration_tasks":0,"review_round_trips":1}'

    run bash "$YFS" "$yaml" task split_decision "$payload"
    [ "$status" -eq 0 ]
    run python3 - "$yaml" <<'PY'
import sys, yaml
value = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]["split_decision"]
assert isinstance(value, dict), type(value)
assert value == {
    "boundary_ac_ids": ["AC1", "AC2"],
    "integration_tasks": 0,
    "review_round_trips": 1,
}
PY
    [ "$status" -eq 0 ]

    local cmd_yaml="$TEST_TMPDIR/cmd_split_decision.yaml"
    cat > "$cmd_yaml" <<'EOF'
commands:
  cmd_test:
    status: delegated
    split_decision: {}
EOF
    run bash "$YFS" "$cmd_yaml" cmd_test split_decision "$payload"
    [ "$status" -eq 0 ]
    run python3 - "$cmd_yaml" <<'PY'
import sys, yaml
value = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["commands"]["cmd_test"]["split_decision"]
assert isinstance(value, dict), type(value)
assert value["boundary_ac_ids"] == ["AC1", "AC2"]
PY
    [ "$status" -eq 0 ]
}

@test "task planned_paths: flow-list入力をscalar化せず構造listとしてatomic保存する" {
    local yaml="$TEST_TMPDIR/task_planned_paths.yaml"
    local fixture_yfs
    fixture_yfs="$(make_nonexec_structural_writer_yfs)"
    cat > "$yaml" <<'EOF'
task:
  status: done
  planned_paths: old-path
EOF
    local payload='[backend/app/main.py, backend/tests/test_api.py]'

    run bash "$fixture_yfs" "$yaml" task planned_paths "$payload"
    [ "$status" -eq 0 ]
    run python3 - "$yaml" <<'PY'
import sys, yaml
value = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]["planned_paths"]
assert value == ["backend/app/main.py", "backend/tests/test_api.py"], value
print("PLANNED_PATHS_LIST_OK=1 ENTRIES=2")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"PLANNED_PATHS_LIST_OK=1 ENTRIES=2"* ]]
}

@test "task planned_paths: scalar入力はbyte-identical fail closedする" {
    local yaml="$TEST_TMPDIR/task_planned_paths_scalar.yaml"
    cat > "$yaml" <<'EOF'
task:
  status: done
  planned_paths: [backend/app/main.py]
EOF
    cp "$yaml" "$yaml.before"

    run bash "$YFS" "$yaml" task planned_paths "backend/app/main.py"
    [ "$status" -eq 2 ]
    [[ "$output" == *"task.planned_paths must be a YAML list"* ]]
    run cmp -s "$yaml.before" "$yaml"
    [ "$status" -eq 0 ]
}

# test_necessity: task scope SSOTのtarget_pathをflow-list入力してもscalar化せず、scope commitが正しい配列を読む不変量を守る。
@test "task target_path: flow-list入力を構造listとしてatomic保存する" {
    local yaml="$TEST_TMPDIR/task_target_path.yaml"
    cat > "$yaml" <<'YAML'
task:
  status: in_progress
  target_path: old-path
YAML
    local payload='["scripts/a.sh", "tests/unit/test_a.bats"]'
    run bash "$YFS" "$yaml" task target_path "$payload"
    [ "$status" -eq 0 ]
    run python3 - "$yaml" <<'PY'
import sys, yaml
value = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]["target_path"]
assert value == ["scripts/a.sh", "tests/unit/test_a.bats"], value
PY
    [ "$status" -eq 0 ]
}

# test_necessity: task publication must keep the three acceptance criteria as a
# YAML list so downstream AC iteration cannot silently operate on characters
# from a scalarized string.
@test "task acceptance_criteria: three-item input stays a structured list" {
    local yaml="$TEST_TMPDIR/task_acceptance_criteria.yaml"
    local payload='[{"id":"AC1","description":"first"},{"id":"AC2","description":"second"},{"id":"AC3","description":"third"}]'
    cat > "$yaml" <<'EOF'
task:
  status: assigned
  acceptance_criteria: []
EOF

    run bash "$YFS" "$yaml" task acceptance_criteria "$payload"
    [ "$status" -eq 0 ]
    run python3 - "$yaml" <<'PY'
import sys, yaml
value = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]["acceptance_criteria"]
assert isinstance(value, list), type(value)
assert len(value) == 3, value
assert [item["id"] for item in value] == ["AC1", "AC2", "AC3"], value
print("AC_LIST_OK=1 COUNT=3")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"AC_LIST_OK=1 COUNT=3"* ]]
}

# test_necessity: scalar and mapping values must not enter the list-only
# acceptance_criteria contract or partially rewrite the task YAML.
@test "task acceptance_criteria: non-list input is fail-closed and byte-identical" {
    local yaml="$TEST_TMPDIR/task_acceptance_criteria_scalar.yaml"
    cat > "$yaml" <<'EOF'
task:
  status: assigned
  acceptance_criteria:
  - id: AC1
    description: keep
EOF

    for payload in "not-a-list" '{"id":"AC1"}'; do
        cp "$yaml" "$yaml.before"
        run bash "$YFS" "$yaml" task acceptance_criteria "$payload"
        [ "$status" -eq 2 ]
        [[ "$output" == *"task.acceptance_criteria must be a YAML list"* ]]
        run cmp -s "$yaml.before" "$yaml"
        [ "$status" -eq 0 ]
    done
}

@test "list item id block: 既存フィールド値の更新" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
- id: AC1
  status: pending
  description: test
- id: AC2
  status: pending
EOF
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" AC1 status done
    [ "$status" -eq 0 ]
    # AC1のstatusだけ変わること
    run grep -A1 "id: AC1" "$TEST_TMPDIR/test.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"status: done"* ]]
    # AC2は変わらないこと
    run grep -A1 "id: AC2" "$TEST_TMPDIR/test.yaml"
    [[ "$output" == *"status: pending"* ]]
}

@test "list item id後置: 同一itemだけを更新しコメントと順序を保持" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
root: keep
items:
  # item comment
  - description: first
    status: pending
    id: AC1
  - id: AC2
    description: second
    status: pending
EOF
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" AC1 status done
    [ "$status" -eq 0 ]
    run python3 - "$TEST_TMPDIR/test.yaml" <<'PY'
import sys, yaml
text = open(sys.argv[1], encoding="utf-8").read()
data = yaml.safe_load(text)
assert data["root"] == "keep"
assert data["items"][0] == {"description": "first", "status": "done", "id": "AC1"}
assert data["items"][1]["status"] == "pending"
assert "# item comment" in text
assert text.index("description: first") < text.index("id: AC1")
PY
    [ "$status" -eq 0 ]
}

@test "list item id位置variation: ネストlistとmultilineを安全に処理" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
groups:
  - name: outer
    children:
      - description: child
        detail: |-
          old line one
          old line two
        id: CHILD1
      - id: CHILD2
        detail: untouched
EOF
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" CHILD1 detail "new line"
    [ "$status" -eq 0 ]
    run python3 - "$TEST_TMPDIR/test.yaml" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
children = data["groups"][0]["children"]
assert children[0]["detail"] == "new line"
assert children[0]["id"] == "CHILD1"
assert children[1]["detail"] == "untouched"
PY
    [ "$status" -eq 0 ]
}

@test "list item id異常系: 不存在と重複idはbyte不変でfail closed" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
items:
  - description: first
    id: DUP
  - id: DUP
    description: second
EOF
    cp "$TEST_TMPDIR/test.yaml" "$TEST_TMPDIR/before.yaml"
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" MISSING status done
    [ "$status" -ne 0 ]
    run cmp -s "$TEST_TMPDIR/before.yaml" "$TEST_TMPDIR/test.yaml"
    [ "$status" -eq 0 ]
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" DUP status done
    [ "$status" -ne 0 ]
    [[ "$output" == *"duplicate_list_id"* ]]
    run cmp -s "$TEST_TMPDIR/before.yaml" "$TEST_TMPDIR/test.yaml"
    [ "$status" -eq 0 ]
}

@test "root-level fallback: ブロックID不在時にルートフィールド更新" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
status: idle
ninja: kagemaru
EOF
    # block_id "root" は存在しない → root-level fallbackで "status" を更新
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" root status active
    # block_id "root" not found → fallback to root-level field "status"
    [ "$status" -eq 0 ]
    run grep "^status:" "$TEST_TMPDIR/test.yaml"
    [[ "$output" == *"active"* ]]
}

# --- 2. 新規フィールドの追加 ---

@test "mapping block: 存在しないフィールドの追加" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
task:
  status: pending
EOF
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" task ninja kagemaru
    [ "$status" -eq 0 ]
    run grep "ninja: kagemaru" "$TEST_TMPDIR/test.yaml"
    [ "$status" -eq 0 ]
}

@test "list item block: 存在しないフィールドの追加" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
- id: AC1
  status: pending
- id: AC2
  status: pending
EOF
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" AC1 verdict PASS
    [ "$status" -eq 0 ]
    run grep "verdict: PASS" "$TEST_TMPDIR/test.yaml"
    [ "$status" -eq 0 ]
}

@test "binary_checks list item: check項目へresultを追加してlist構造を維持" {
    cat > "$TEST_TMPDIR/report.yaml" <<'EOF'
binary_checks:
  AC1:
    - check: yaml_field_set list item insert
      detail: before
    - check: other check
      result: ""
EOF
    run bash "$YFS" "$TEST_TMPDIR/report.yaml" "yaml_field_set list item insert" result yes
    [ "$status" -eq 0 ]

    run python3 - <<PY
import yaml
from pathlib import Path
data = yaml.safe_load(Path("$TEST_TMPDIR/report.yaml").read_text())
items = data["binary_checks"]["AC1"]
assert isinstance(items, list)
assert items[0]["check"] == "yaml_field_set list item insert"
assert items[0]["result"] in ("yes", True)
assert items[0]["detail"] == "before"
assert items[1]["check"] == "other check"
assert items[1]["result"] == ""
print("PARSE_OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"PARSE_OK"* ]]
}

@test "binary_checks list item: 既存resultを同一check項目内で置換" {
    cat > "$TEST_TMPDIR/report.yaml" <<'EOF'
binary_checks:
  AC1:
    - check: replace target
      result: ""
    - check: untouched target
      result: ""
EOF
    run bash "$YFS" "$TEST_TMPDIR/report.yaml" "replace target" result yes
    [ "$status" -eq 0 ]

    run python3 - <<PY
import yaml
from pathlib import Path
data = yaml.safe_load(Path("$TEST_TMPDIR/report.yaml").read_text())
items = data["binary_checks"]["AC1"]
assert items[0] == {"check": "replace target", "result": True} or items[0] == {"check": "replace target", "result": "yes"}
assert items[1] == {"check": "untouched target", "result": ""}
print("PARSE_OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"PARSE_OK"* ]]
}

# --- 3. ネストされたフィールド(task.status等)の更新 ---

@test "深いネスト: task配下のstatusを更新" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
task:
  acceptance_criteria:
    AC1:
      status: pending
  status: idle
  ninja: hayate
EOF
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" task status in_progress
    [ "$status" -eq 0 ]
    # task直下のstatusが更新されること
    source "$YFS"
    actual=$(_yaml_field_get_in_block "$TEST_TMPDIR/test.yaml" task status)
    [ "$actual" = "in_progress" ]
}

# --- 4. 特殊文字を含む値の書込み ---

@test "コロンを含む値がクォートされる" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
task:
  timestamp: old
EOF
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" task timestamp "2026-03-25T17:00:00"
    [ "$status" -eq 0 ]
    # コロン含む値はクォートされて保存
    source "$YFS"
    actual=$(_yaml_field_get_in_block "$TEST_TMPDIR/test.yaml" task timestamp)
    [ "$actual" = "2026-03-25T17:00:00" ]
}

@test "空白を含む値の書込み" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
task:
  description: old
EOF
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" task description "hello world test"
    [ "$status" -eq 0 ]
    source "$YFS"
    actual=$(_yaml_field_get_in_block "$TEST_TMPDIR/test.yaml" task description)
    [ "$actual" = "hello world test" ]
}

# --- 5. ファイル不存在時のエラー処理 ---

@test "存在しないファイルでエラー終了" {
    run bash "$YFS" "$TEST_TMPDIR/nonexistent.yaml" task status done
    [ "$status" -ne 0 ]
    [[ "$output" == *"FATAL"* ]]
}

@test "引数不足でエラー終了" {
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" task status
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage"* ]]
}

# --- 6. 書込み前後でファイル構造が壊れないこと ---

@test "他ブロックの値が変更されない" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
task:
  status: pending
  ninja: hayate
config:
  debug: false
  verbose: true
EOF
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" task status done
    [ "$status" -eq 0 ]
    # config配下が壊れていないこと
    source "$YFS"
    debug=$(_yaml_field_get_in_block "$TEST_TMPDIR/test.yaml" config debug)
    [ "$debug" = "false" ]
    verbose=$(_yaml_field_get_in_block "$TEST_TMPDIR/test.yaml" config verbose)
    [ "$verbose" = "true" ]
}

@test "複数回の書込みで構造が維持される" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
task:
  status: pending
  ninja: hayate
  count: 0
EOF
    bash "$YFS" "$TEST_TMPDIR/test.yaml" task status done
    bash "$YFS" "$TEST_TMPDIR/test.yaml" task count 5
    bash "$YFS" "$TEST_TMPDIR/test.yaml" task ninja kagemaru

    source "$YFS"
    s=$(_yaml_field_get_in_block "$TEST_TMPDIR/test.yaml" task status)
    [ "$s" = "done" ]
    c=$(_yaml_field_get_in_block "$TEST_TMPDIR/test.yaml" task count)
    [ "$c" = "5" ]
    n=$(_yaml_field_get_in_block "$TEST_TMPDIR/test.yaml" task ninja)
    [ "$n" = "kagemaru" ]
}

@test "post-write verification: 書込み値が読み戻しで一致" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
task:
  status: pending
EOF
    # yaml_field_set内部でpost-write verificationが走る
    # 不一致ならFATALで終了する
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" task status "completed"
    [ "$status" -eq 0 ]
    [[ "$output" != *"FATAL"* ]]
}

@test "scalar replace: 継続行つき field を更新しても旧継続行を残さない" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
task:
  _deploy_notice: "STALE TASK INVALID. This YAML is the latest instruction for cmd_2235 (deployed 2026-04-22T20:27:51). Read from the beginning."
    (deployed 2026-04-22T19:44:45). Read from the beginning.
  status: idle
EOF
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" task _deploy_notice "STALE TASK INVALID. This YAML is the latest instruction for cmd_2236 (deployed 2026-04-22T21:09:20). Read from the beginning."
    [ "$status" -eq 0 ]
    run python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1], encoding="utf-8"))' "$TEST_TMPDIR/test.yaml"
    [ "$status" -eq 0 ]
    run grep -n "2026-04-22T19:44:45" "$TEST_TMPDIR/test.yaml"
    [ "$status" -ne 0 ]
}

@test "batch replace: 継続行つき field を更新してもYAML parse errorにならない" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
task:
  _deploy_notice: "STALE TASK INVALID. This YAML is the latest instruction for cmd_2235 (deployed 2026-04-22T20:27:51). Read from the beginning."
    (deployed 2026-04-22T19:44:45). Read from the beginning.
  status: idle
EOF
    run bash -lc '
        source "'"$YFS"'"
        yaml_field_set_batch "'"$TEST_TMPDIR/test.yaml"'" task \
          "_deploy_notice=STALE TASK INVALID. This YAML is the latest instruction for cmd_2236 (deployed 2026-04-22T21:09:20). Read from the beginning." \
          "status=assigned"
    '
    [ "$status" -eq 0 ]
    run python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1], encoding="utf-8"))' "$TEST_TMPDIR/test.yaml"
    [ "$status" -eq 0 ]
    run grep -n "2026-04-22T19:44:45" "$TEST_TMPDIR/test.yaml"
    [ "$status" -ne 0 ]
    run grep -n "^  status: assigned$" "$TEST_TMPDIR/test.yaml"
    [ "$status" -eq 0 ]
}

# --- 追加: block_id不在時のエラー ---

@test "block_idもroot fieldも不在でエラー" {
    cat > "$TEST_TMPDIR/test.yaml" <<'EOF'
task:
  status: pending
EOF
    run bash "$YFS" "$TEST_TMPDIR/test.yaml" nonexistent_block field value
    [ "$status" -ne 0 ]
    [[ "$output" == *"FATAL"* ]]
}

# --- 7. flock並行書込みテスト (tests/版から統合) ---

@test "flock serialization allows concurrent writes without corruption" {
    local yaml="$TEST_TMPDIR/concurrent.yaml"
    cat > "$yaml" <<'YAML'
commands:
  - id: cmd_200
    status: pending
YAML

    bash "$YFS" "$yaml" "cmd_200" "status" "in_progress" &
    local pid1=$!
    bash "$YFS" "$yaml" "cmd_200" "status" "completed" &
    local pid2=$!

    wait "$pid1"
    local rc1=$?
    wait "$pid2"
    local rc2=$?

    [ "$rc1" -eq 0 ]
    [ "$rc2" -eq 0 ]

    local count
    count=$(grep -c "^    status:" "$yaml")
    [ "$count" -eq 1 ]

    local final
    final=$(awk '/^    status:/ {print $2}' "$yaml")
    [[ "$final" == "in_progress" || "$final" == "completed" ]]
}

# --- 8. 4スペースリストスタイルのindent保存 (tests/版から統合) ---

@test "preserves indent level for 4-space list style" {
    local yaml="$TEST_TMPDIR/indent.yaml"
    cat > "$yaml" <<'YAML'
commands:
    - id: cmd_300
      status: pending
      project: infra
YAML

    run bash "$YFS" "$yaml" "cmd_300" "status" "done"
    [ "$status" -eq 0 ]

    run grep -n "^      status: done$" "$yaml"
    [ "$status" -eq 0 ]
}

# --- 9. task_idフィールド追加 (tests/版から統合, cmd_465回帰テスト) ---

@test "adds task_id field from subtask_id (cmd_465: STALL検知キー統一)" {
    local yaml="$TEST_TMPDIR/task_id.yaml"
    cat > "$yaml" <<'YAML'
task:
  subtask_id: subtask_465_impl
  parent_cmd: cmd_465
  status: pending
YAML

    run bash "$YFS" "$yaml" "task" "task_id" "subtask_465_impl"
    [ "$status" -eq 0 ]

    run grep -n "^  task_id: subtask_465_impl$" "$yaml"
    [ "$status" -eq 0 ]

    run grep -c "^  task_id:" "$yaml"
    [ "$output" = "1" ]
}

@test "yaml_field_set: 置換後に旧継続行を残さず parseable を維持" {
    local yaml="$TEST_TMPDIR/single_multiline_cleanup.yaml"
    cat > "$yaml" <<'YAML'
task:
  _deploy_notice: "STALE TASK INVALID. This YAML is the latest instruction for cmd_old (deployed 2026-04-22T21:09:20). Read from the beginning."
    (deployed 2026-04-22T20:00:00). Read from the beginning.
  status: assigned
YAML

    run bash "$YFS" "$yaml" task status in_progress
    [ "$status" -eq 0 ]

    run python3 - <<PY
import yaml
from pathlib import Path
data = yaml.safe_load(Path("$yaml").read_text())
assert data["task"]["status"] == "in_progress"
assert data["task"]["_deploy_notice"].startswith("STALE TASK INVALID.")
print("PARSE_OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"PARSE_OK"* ]]

    run grep -n "2026-04-22T20:00:00" "$yaml"
    [ "$status" -eq 1 ]
}

@test "yaml_field_set: indentless sequenceをscalarへ置換して旧list子行を残さない" {
    local yaml="$TEST_TMPDIR/indentless_sequence_cleanup.yaml"
    cat > "$yaml" <<'YAML'
task:
  assigned_lesson_ids:
  - L001
  - L002
  status: done
YAML

    run bash "$YFS" "$yaml" task assigned_lesson_ids null
    [ "$status" -eq 0 ]

    run python3 - "$yaml" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
assert task["assigned_lesson_ids"] is None, task
assert task["status"] == "done", task
PY
    [ "$status" -eq 0 ]
    run grep -c '^  - L00' "$yaml"
    [ "$output" = "0" ]
}

@test "yaml_field_set_batch: 置換後に旧継続行を残さず parseable を維持" {
    local yaml="$TEST_TMPDIR/batch_multiline_cleanup.yaml"
    cat > "$yaml" <<'YAML'
task:
  _deploy_notice: "STALE TASK INVALID. This YAML is the latest instruction for cmd_old (deployed 2026-04-22T21:09:20). Read from the beginning."
    (deployed 2026-04-22T20:00:00). Read from the beginning.
  status: assigned
YAML

    run bash -lc "source \"$YFS\" && yaml_field_set_batch \"$yaml\" task \"_deploy_notice=STALE TASK INVALID. This YAML is the latest instruction for cmd_new (deployed 2026-04-22T22:23:28). Read from the beginning.\" \"status=acknowledged\""
    [ "$status" -eq 0 ]

    run python3 - <<PY
import yaml
from pathlib import Path
data = yaml.safe_load(Path("$yaml").read_text())
assert data["task"]["status"] == "acknowledged"
assert data["task"]["_deploy_notice"].startswith("STALE TASK INVALID. This YAML is the latest instruction for cmd_new")
print("PARSE_OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"PARSE_OK"* ]]

    run grep -n "2026-04-22T20:00:00" "$yaml"
    [ "$status" -eq 1 ]
}

@test "yaml_field_set_batch: pipeを含む値を切り詰めずに保存する" {
    local yaml="$TEST_TMPDIR/batch_pipe_value.yaml"
    cat > "$yaml" <<'YAML'
task:
  purpose: old
  status: assigned
YAML

    run bash -lc "source \"$YFS\" && yaml_field_set_batch \"$yaml\" task \"purpose=cmd text with alpha | beta || gamma \\| delta\" \"status=acknowledged\""
    [ "$status" -eq 0 ]

    run python3 - <<PY
import yaml
from pathlib import Path
data = yaml.safe_load(Path("$yaml").read_text())
assert data["task"]["purpose"] == r"cmd text with alpha | beta || gamma \| delta"
assert data["task"]["status"] == "acknowledged"
print("PIPE_OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"PIPE_OK"* ]]
}

@test "yaml_field_set_batch: 単引用符を含むクォート値を検証で誤FAILしない" {
    local yaml="$TEST_TMPDIR/batch_single_quote_value.yaml"
    cat > "$yaml" <<'YAML'
task:
  purpose: old
YAML

    local value="target_re=r'自動化ターゲット\\s*[:：]\\s*(.+)'がMarkdown太字にマッチする"
    run bash -lc "source \"$YFS\" && yaml_field_set_batch \"$yaml\" task \"purpose=$value\""
    [ "$status" -eq 0 ]

    run python3 - <<PY
import yaml
from pathlib import Path
data = yaml.safe_load(Path("$yaml").read_text(encoding="utf-8"))
assert data["task"]["purpose"] == "target_re=r'自動化ターゲット\\\\s*[:：]\\\\s*(.+)'がMarkdown太字にマッチする", data
print("SINGLE_QUOTE_OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"SINGLE_QUOTE_OK"* ]]
}

@test "mapping block: ネスト末尾を持つblockへ新規field追加しても子要素を親field配下へ移動しない" {
    local yaml="$TEST_TMPDIR/nested_tail_insert.yaml"
    cat > "$yaml" <<'YAML'
commands:
  cmd_curr:
    id: cmd_curr
    status: draft
    quality_gate:
      q11_not_already_done: "rg -nF 'q11' scripts/cmd_publish.sh -> 0"
YAML

    run bash "$YFS" "$yaml" cmd_curr depends_on none
    [ "$status" -eq 0 ]

    run python3 - <<PY
import yaml
from pathlib import Path
data = yaml.safe_load(Path("$yaml").read_text())
cmd = data["commands"]["cmd_curr"]
assert cmd["depends_on"] == "none"
assert cmd["quality_gate"]["q11_not_already_done"].startswith("rg -nF")
print("NESTED_TAIL_OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"NESTED_TAIL_OK"* ]]
}

# ── cmd_id list item support (yaml_field_set.sh begin_target + is_boundary) ──

@test "cmd_id list: 対象エントリだけ更新し次エントリを汚染しない" {
    yaml="$BATS_TMPDIR/cmdid_boundary.yaml"
    cat > "$yaml" <<'EOF'
- cmd_id: cmd_alpha
  review_type: draft
  verdict: APPROVE
  gate_result: null
- cmd_id: cmd_beta
  review_type: report
  verdict: LGTM
  gate_result: CLEAR
EOF
    run bash "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$yaml" "cmd_alpha" gate_result "BLOCK"
    [ "$status" -eq 0 ]
    # cmd_alpha の gate_result が BLOCK に変わっている
    run python3 -c "
import yaml, pathlib
docs = list(yaml.safe_load_all(pathlib.Path('$yaml').read_text()))
data = docs[0]  # single doc list
alpha = [d for d in data if d.get('cmd_id') == 'cmd_alpha'][0] if isinstance(data, list) else None
if alpha is None:
    data_list = data
    alpha = data
beta = [d for d in (data if isinstance(data,list) else [data]) if d.get('cmd_id') == 'cmd_beta'][0]
print('alpha_gate=' + str(alpha.get('gate_result','')))
print('beta_gate=' + str(beta.get('gate_result','')))
assert alpha['gate_result'] == 'BLOCK', f'alpha expected BLOCK got {alpha[\"gate_result\"]}'
assert beta['gate_result'] == 'CLEAR', f'beta expected CLEAR got {beta[\"gate_result\"]}'
print('CMD_ID_BOUNDARY_OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CMD_ID_BOUNDARY_OK"* ]]
}

@test "cmd_id list: 1行だけのブロックに新field追加してもYAML構造が壊れない" {
    yaml="$BATS_TMPDIR/cmdid_single_line.yaml"
    cat > "$yaml" <<'EOF'
- cmd_id: cmd_solo
- cmd_id: cmd_next
  review_type: report
  verdict: LGTM
  gate_result: CLEAR
EOF
    run bash "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$yaml" "cmd_solo" gate_result "NEW_BLOCK"
    [ "$status" -eq 0 ]
    run python3 -c "
import yaml, pathlib
data = yaml.safe_load(pathlib.Path('$yaml').read_text())
solo = [d for d in data if d['cmd_id'] == 'cmd_solo'][0]
nxt = [d for d in data if d['cmd_id'] == 'cmd_next'][0]
assert solo['gate_result'] == 'NEW_BLOCK', f'solo got {solo[\"gate_result\"]}'
assert nxt['gate_result'] == 'CLEAR', f'next got {nxt[\"gate_result\"]}'
print('CMD_ID_SINGLE_LINE_OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CMD_ID_SINGLE_LINE_OK"* ]]
}

# ── cmd_karo_hotfix_queue_yaml_atomicity_202607110113 回帰テスト ──
# Origin: 2026-07-11 01:09 queue/tasks/kagemaru.yaml破損(queue YAML parse error)。
# 直接原因: (1) 公開が非atomicなcat>truncateで、flockを取らない読み手(gate等)が
#   truncate-write間の一瞬(空/不完全な内容)を観測しうる。
#   (2) list/idブロック向けの書込み関数(_yaml_field_set_apply)には改行を含む値の
#   ガードがなく、値に生の改行が混入すると裸テキストが行頭に漏れ不正YAMLを公開していた。
# 修正: 公開前にpython3 yaml.safe_loadで検証しfail-closed、公開は同一ディレクトリ
#   mktemp+mv(atomic rename)に統一。
#
# cmd_karo_hotfix_yaml_field_set_multiline_verify_202607122228 で挙動変更:
#   値に生の改行が混入するケースは「不正注入」ではなく「複数行値の正当な書込み」
#   として扱う。yaml_safe()がnewline/tab/CRをdouble-quote scalarへエスケープし
#   1物理行に収めるため、公開前検証(yaml.safe_load)を安全に通過しexit0で成功する。
#   旧テストが検証していた「fail-closedで旧ファイルを保つ」経路は
#   publish_atomic単体テスト(下記2件)で別途カバー済み。

@test "複数行値の書込み: 生の改行を含む値でも1物理行のquoted scalarへ安全にエスケープされ成功する" {
    local yaml="$TEST_TMPDIR/multiline_injection.yaml"
    cat > "$yaml" <<'EOF'
- id: AC1
  status: pending
  description: test
- id: AC2
  status: pending
EOF

    run bash "$YFS" "$yaml" AC1 status $'line1\nline2 malformed'
    [ "$status" -eq 0 ]
    [[ "$output" != *"FATAL"* ]]

    run python3 -c '
import sys
import yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
ac1 = [d for d in data if d["id"] == "AC1"][0]
ac2 = [d for d in data if d["id"] == "AC2"][0]
assert ac1["status"] == "line1\nline2 malformed", ac1["status"]
assert ac1["description"] == "test", ac1["description"]
assert ac2["status"] == "pending", ac2["status"]
print("MULTILINE_INJECTION_OK")
' "$yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MULTILINE_INJECTION_OK"* ]]

    # 値は1物理行に収まっている(裸テキストが行頭に漏れていないこと)
    run grep -c "^line2 malformed$" "$yaml"
    [ "$output" = "0" ]
}

@test "root block scalar更新: 旧本文を除去して複数行と単一scalarをexact round-tripする" {
    local yaml="$TEST_TMPDIR/root_block_scalar.yaml"
    cat > "$yaml" <<'EOF'
agent: karo
session_summary: |-
  old line one

  old line two
next_key: preserved
EOF
    local multiline=$'new line one\nnew line two'

    run bash "$YFS" "$yaml" root session_summary "$multiline"
    [ "$status" -eq 0 ]
    export EXPECT="$multiline"
    run python3 - "$yaml" <<'PY'
import os, sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert data["session_summary"] == os.environ["EXPECT"]
assert data["next_key"] == "preserved"
assert "old line" not in open(sys.argv[1], encoding="utf-8").read()
PY
    [ "$status" -eq 0 ]

    run bash "$YFS" "$yaml" root session_summary "single summary"
    [ "$status" -eq 0 ]
    run python3 - "$yaml" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert data["session_summary"] == "single summary"
assert data["next_key"] == "preserved"
PY
    [ "$status" -eq 0 ]
}

# ── cmd_karo_hotfix_yaml_field_set_multiline_verify_202607122228 回帰テスト ──
# Origin: 家老実測でLK-A13.detailへ複数行値を書込んだ際、値自体はYAML-validかつ
# 内容も反映されていたのに、post-write検証がawk単一物理行の生テキストを誤抽出し
# (先頭引用符だけ残る等)偽FATALした。書込側(yaml_safe)と検証側
# (_yaml_field_set_verify_parsed)を「yaml.safe_load後のscalar比較」という
# 同一データモデルへ統一して解消する。

@test "AC1専用corpus: 複数行+両クォート+コロン+日本語+Obsidianリンクを含む値がexact round-tripする" {
    local yaml="$TEST_TMPDIR/ac1_corpus.yaml"
    cat > "$yaml" <<'EOF'
task:
  acceptance_criteria:
  - id: LK-A13
    detail: pending
EOF
    local value=$'第1行: これは "テスト" と \'確認\' です\n第2行: [[some-obsidian-link]] を含む複数行値'

    run bash "$YFS" "$yaml" LK-A13 detail "$value"
    [ "$status" -eq 0 ]
    [[ "$output" != *"FATAL"* ]]

    export EXPECT="$value"
    run python3 -c '
import os
import sys

import yaml

expect = os.environ["EXPECT"]
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
ac = [d for d in data["task"]["acceptance_criteria"] if d["id"] == "LK-A13"][0]
assert ac["detail"] == expect, (ac["detail"], expect)
print("AC1_CORPUS_OK")
' "$yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AC1_CORPUS_OK"* ]]
}

@test "AC1専用corpus: 代表値バッテリーが誤FAILなくexact round-tripする(正当系)" {
    local yaml="$TEST_TMPDIR/ac1_battery.yaml"
    local labels=(single_line japanese colon both_quotes obsidian_link multiline tab crlf pipe bool_true bool_false numeric backslash)
    local values=(
        "simple value"
        "日本語のテスト値です"
        "key: value pair"
        'he said "hi" and it'"'"'s fine'
        "See [[some-link]] for details"
        "$(printf 'line1\nline2 continuation')"
        "$(printf 'col1\tcol2')"
        "$(printf 'line1\r\nline2')"
        "alpha | beta || gamma"
        "true"
        "false"
        "5"
        'C:\new_folder\end'
    )

    local i label value yaml_case
    for i in "${!labels[@]}"; do
        label="${labels[$i]}"
        value="${values[$i]}"
        yaml_case="$TEST_TMPDIR/ac1_battery_${label}.yaml"
        printf 'task:\n  detail: pending\n' > "$yaml_case"

        run bash "$YFS" "$yaml_case" task detail "$value"
        [ "$status" -eq 0 ]
        [[ "$output" != *"FATAL"* ]]

        export EXPECT="$value"
        run python3 -c '
import os
import sys

import yaml

expect = os.environ["EXPECT"]
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
actual = data["task"]["detail"]

YAML_TRUE = {"y", "Y", "yes", "Yes", "YES", "true", "True", "TRUE", "on", "On", "ON"}
YAML_FALSE = {"n", "N", "no", "No", "NO", "false", "False", "FALSE", "off", "Off", "OFF"}

if isinstance(actual, bool):
    ok = (expect in YAML_TRUE) if actual else (expect in YAML_FALSE)
elif isinstance(actual, int):
    ok = str(actual) == expect
else:
    ok = actual == expect
assert ok, (repr(actual), repr(expect))
print("BATTERY_OK")
' "$yaml_case"
        [ "$status" -eq 0 ]
        [[ "$output" == *"BATTERY_OK"* ]]
    done
}

@test "yaml_field_set_batch: 複数行値もbatch経由で1回のflockでexact round-tripする" {
    local yaml="$TEST_TMPDIR/batch_multiline.yaml"
    cat > "$yaml" <<'EOF'
task:
  status: pending
  detail: old
EOF
    local value=$'batch line1: colon付き\nbatch line2 continuation'

    run bash -lc "source \"$YFS\" && yaml_field_set_batch \"$yaml\" task \"detail=$value\" \"status=done\""
    [ "$status" -eq 0 ]
    [[ "$output" != *"FATAL"* ]]

    export EXPECT="$value"
    run python3 -c '
import os
import sys

import yaml

expect = os.environ["EXPECT"]
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert data["task"]["detail"] == expect, data["task"]["detail"]
assert data["task"]["status"] == "done"
print("BATCH_MULTILINE_OK")
' "$yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BATCH_MULTILINE_OK"* ]]
}

@test "AC2: _yaml_field_set_verify_parsedは実値不一致をfail-closedでexit非0にし、ファイルを書き換えない" {
    local yaml="$TEST_TMPDIR/verify_mismatch.yaml"
    cat > "$yaml" <<'EOF'
task:
  status: pending
EOF
    cp "$yaml" "$yaml.orig"
    source "$YFS"
    run _yaml_field_set_verify_parsed "$yaml" task status "completed" "0"
    [ "$status" -ne 0 ]
    [[ "$output" == *"mismatch"* ]]

    # 検証のみでファイル内容は変化しないこと(全体dumpしていない証跡)
    run diff "$yaml.orig" "$yaml"
    [ "$status" -eq 0 ]
}

@test "AC2: _yaml_field_set_verify_parsedはblock不在をexit非0にする" {
    local yaml="$TEST_TMPDIR/verify_noblock.yaml"
    cat > "$yaml" <<'EOF'
task:
  status: pending
EOF
    source "$YFS"
    run _yaml_field_set_verify_parsed "$yaml" nonexistent_block field "value" "0"
    [ "$status" -ne 0 ]
    [[ "$output" == *"block_not_found"* ]]
}

# cmd_karo_hotfix_queue_yaml_atomicity_202607110113 follow-up (家老GATE BLOCK 01:56):
# renameat2(RENAME_EXCHANGE)は/mnt/c(drvfs)でEINVAL(未対応。同一probeは/tmp native tmpfsでは成功)
# のため実装不可と確定。同一パスが消えないatomic交換は不可能なので、家老指示の代替案
# 「全reader共通入口での透明retry」をscripts/lib/yaml_safe_read.py(safe_load_retry)として実装。
# 以下2テストで(1)個別未対応readerには残余曝露が実在すること(修正前FAIL再現の裏付け)
# (2) 共通entry point採用readerは10連続ラウンドすべてbad=0であること、の両方を証明する。

# bats test_tags=long_race
@test "並行アクセス(生reader・リトライなし): flock非取得の素朴なopen()は稀にFileNotFoundErrorを観測しうる(残余曝露の実証)" {
    source "$YFS"
    # $BATS_TMPDIR(=/tmp)はtmpfsでwriteがμs級のため非atomic窓が狭すぎて再現しない(実測済み)。
    # /mnt/c(drvfs)配下でのみ再現する。本テストはbad=0を要求しない。むしろ「個別のreaderが
    # 各自でopen()するだけでは家老指摘のAC4(読取失敗0)を満たせない」ことの生き証拠であり、
    # 出現した場合でも種別がFileNotFoundErrorのみ(データ破損=YAMLErrorではない)ことだけを保証する。
    local race_dir="$PROJECT_ROOT/tmp/yfs_race_raw_$$"
    mkdir -p "$race_dir"
    local yaml="$race_dir/race_target.yaml"
    {
        echo "task:"
        echo "  status: pending"
        echo "  ninja: hayate"
        for i in $(seq 1 300); do
            echo "  note_${i}: \"padding value ${i} to widen the publish window\""
        done
    } > "$yaml"

    python3 -c "
import time, yaml, sys
deadline = time.time() + 3.0
enoent = 0
other_bad = 0
total = 0
while time.time() < deadline:
    total += 1
    try:
        with open('$yaml', encoding='utf-8') as f:
            yaml.safe_load(f)
    except FileNotFoundError:
        enoent += 1
    except Exception:
        other_bad += 1
with open('$race_dir/reader_result.txt', 'w') as out:
    out.write(f'{enoent} {other_bad} {total}\n')
" &
    local reader_pid=$!

    end=$((SECONDS + 3))
    local i=0
    while [ $SECONDS -lt $end ]; do
        yaml_field_set "$yaml" task status "in_progress_${i}" >/dev/null 2>&1 || true
        i=$((i + 1))
        sleep 0.05
    done
    wait "$reader_pid"

    local enoent other_bad total
    read -r enoent other_bad total < "$race_dir/reader_result.txt" || true
    echo "raw reader (no retry): enoent=${enoent} other_bad=${other_bad} total=${total} writer_iterations=${i}"
    rm -rf "$race_dir"
    [ "$total" -gt 0 ]
    # データ破損(YAMLError等)は0件であること。瞬間的なENOENTのみが許容される既知の残余事象。
    [ "$other_bad" -eq 0 ]
}

# bats test_tags=long_race
@test "並行アクセス(共通entry point・safe_load_retry): 10連続ラウンドすべてbad=0" {
    source "$YFS"
    # scripts/lib/yaml_safe_read.py の safe_load_retry() を「全reader共通入口」として
    # 採用した場合、drvfsの瞬間的ENOENTを吸収して10連続ラウンドすべてbad=0になることを証明する。
    local race_dir="$PROJECT_ROOT/tmp/yfs_race_safe_$$"
    mkdir -p "$race_dir"
    local yaml="$race_dir/race_target.yaml"
    local round total_reads=0

    for round in $(seq 1 10); do
        {
            echo "task:"
            echo "  status: pending"
            echo "  ninja: hayate"
            for i in $(seq 1 300); do
                echo "  note_${i}: \"padding value ${i} round ${round}\""
            done
        } > "$yaml"

        PYTHONPATH="$PROJECT_ROOT/scripts/lib" python3 -c "
import sys, time
sys.path.insert(0, '$PROJECT_ROOT/scripts/lib')
from yaml_safe_read import safe_load_retry
deadline = time.time() + 1.0
bad = 0
total = 0
while time.time() < deadline:
    total += 1
    try:
        safe_load_retry('$yaml')
    except Exception as e:
        bad += 1
        print(f'BAD round ${round}: {e}', file=sys.stderr)
with open('$race_dir/round_result.txt', 'w') as out:
    out.write(f'{bad} {total}\n')
" &
        local reader_pid=$!

        end=$((SECONDS + 1))
        local i=0
        while [ $SECONDS -lt $end ]; do
            yaml_field_set "$yaml" task status "in_progress_${round}_${i}" >/dev/null 2>&1 || true
            i=$((i + 1))
            sleep 0.05
        done
        wait "$reader_pid"

        local bad total
        read -r bad total < "$race_dir/round_result.txt" || true
        total_reads=$((total_reads + total))
        echo "round ${round}: bad=${bad} total=${total} writer_iterations=${i}"
        if [ "$bad" -ne 0 ]; then
            rm -rf "$race_dir"
            echo "FAIL at round ${round}: bad=${bad} (expected 0)"
            return 1
        fi
    done

    rm -rf "$race_dir"
    echo "all 10 rounds bad=0, total_reads=${total_reads}"
    [ "$total_reads" -gt 0 ]
}

@test "cmd_id list: 対象にfieldが無い時は対象直下に追加する" {
    yaml="$BATS_TMPDIR/cmdid_insert.yaml"
    cat > "$yaml" <<'EOF'
- cmd_id: cmd_first
  review_type: draft
  verdict: APPROVE
- cmd_id: cmd_second
  review_type: report
  verdict: LGTM
  gate_result: CLEAR
EOF
    run bash "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$yaml" "cmd_first" gate_result "NEW_CLEAR"
    [ "$status" -eq 0 ]
    run python3 -c "
import yaml, pathlib
data = yaml.safe_load(pathlib.Path('$yaml').read_text())
first = [d for d in data if d['cmd_id'] == 'cmd_first'][0]
second = [d for d in data if d['cmd_id'] == 'cmd_second'][0]
assert first['gate_result'] == 'NEW_CLEAR', f'first got {first[\"gate_result\"]}'
assert second['gate_result'] == 'CLEAR', f'second got {second[\"gate_result\"]}'
print('CMD_ID_INSERT_OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CMD_ID_INSERT_OK"* ]]
}

@test "map scalar: 別field更新時に折返しscalar継続行を保持する" {
    yaml="$BATS_TMPDIR/wrapped_scalar.yaml"
    printf '%s\n' \
        'task:' \
        "  purpose: 'first line" \
        "    second line'" \
        '  status: assigned' \
        '  variation_checks_required: false' > "$yaml"

    run bash "$YFS" "$yaml" task status acknowledged
    [ "$status" -eq 0 ]
    run python3 -c "
import yaml
data = yaml.safe_load(open('$yaml', encoding='utf-8'))
assert data['task']['status'] == 'acknowledged', data
assert data['task']['purpose'] == 'first line second line', data
assert data['task']['variation_checks_required'] is False, data
print('WRAPPED_SCALAR_OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WRAPPED_SCALAR_OK"* ]]
}

@test "batch: 別field一括更新時に折返しscalar継続行を保持する" {
    yaml="$BATS_TMPDIR/wrapped_scalar_batch.yaml"
    printf '%s\n' \
        'task:' \
        "  purpose: 'first line" \
        "    second line'" \
        '  status: assigned' \
        '  progress: pending' > "$yaml"

    run bash -c "source '$YFS'; yaml_field_set_batch '$yaml' task status=acknowledged progress=started"
    [ "$status" -eq 0 ]
    run python3 -c "
import yaml
data = yaml.safe_load(open('$yaml', encoding='utf-8'))
assert data['task']['status'] == 'acknowledged', data
assert data['task']['progress'] == 'started', data
assert data['task']['purpose'] == 'first line second line', data
print('WRAPPED_BATCH_OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WRAPPED_BATCH_OK"* ]]
}

# ── cmd_karo_hotfix_deploy_task_atomic_publish_202607111645 回帰テスト ──
# Origin: cmd_3847偵察でscripts/deploy_task.sh内11箇所がyaml_field_set.shを経由せず
# 非atomic cp+無検証で公開していたと判明(tmp_fileが/tmp、queue/tasksは/mnt/cで別
# filesystemのためmv不可)。共通口_yaml_field_set_publish_atomicを新設し11箇所を
# 同一dir mktemp+検証+atomic mvへ統一。以下は共通口自体の契約を保証する。

@test "publish_atomic: 不正YAML候補は旧targetをbyte-identicalに保ち一時ファイルも残さない" {
    local target="$TEST_TMPDIR/target.yaml"
    cat > "$target" <<'EOF'
task:
  status: assigned
  purpose: original
EOF
    cp "$target" "$target.orig"

    local candidate
    candidate="$(mktemp "${target}.XXXXXX")"
    printf 'task:\n  status: "broken\n' > "$candidate"

    run bash -c "source '$YFS' && _yaml_field_set_publish_atomic '$candidate' '$target'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"FATAL"* ]]

    run diff "$target.orig" "$target"
    [ "$status" -eq 0 ]

    [ ! -e "$candidate" ]
    run bash -c "compgen -G '${target}.*' | grep -v '\.orig$'"
    [ "$status" -ne 0 ]
}

@test "publish_atomic: 正当なYAML候補はatomic mvでtargetへ反映され候補ファイルは消える" {
    local target="$TEST_TMPDIR/target_ok.yaml"
    cat > "$target" <<'EOF'
task:
  status: assigned
EOF

    local candidate
    candidate="$(mktemp "${target}.XXXXXX")"
    cat > "$candidate" <<'EOF'
task:
  status: completed
EOF

    run bash -c "source '$YFS' && _yaml_field_set_publish_atomic '$candidate' '$target'"
    [ "$status" -eq 0 ]

    [ ! -e "$candidate" ]
    run python3 -c "
import yaml
data = yaml.safe_load(open('$target', encoding='utf-8'))
assert data['task']['status'] == 'completed', data
print('PUBLISH_OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PUBLISH_OK"* ]]
}

@test "deploy_task.sh: task YAML未検証cp公開が0件である(静的検査)" {
    run grep -nE 'cp[[:space:]]+"\$(tmp_file|YAML_FILE)"[[:space:]]+"\$(task_file|task_yaml)"' \
        "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "deploy_task.sh: 全injectorがpublish_atomic経由でtask_fileへ公開する(静的検査)" {
    run grep -c "_yaml_field_set_publish_atomic" "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]
    [ "$output" -ge 10 ]
}

# ── cmd_4162 (忍者利他報告blt_20260724_162804): ネストlist添字表記の明示エラー化 ──
# Origin: 才蔵がcmd_4156でplanned_paths[1]のようなlist添字表記をfield引数として渡した際、
# 一致するブロックが存在せずroot-level fallbackが働き、添字表記の文字列そのものが
# 新規のリテラルキーとして黙って書き込まれ手戻りが発生した(掲示板blt_20260724_162804)。
# yaml_field_setのawkエンジンはYAML構造を解釈しない行ベース置換であり、list要素単位の
# 更新は安全に実装できないため、添字表記はfail-closedで明示エラー化する。

@test "yaml_field_set: 添字指定(planned_paths[1])はFATALで即座に書込みを中止する" {
    local yaml="$TEST_TMPDIR/subscript_reject.yaml"
    cat > "$yaml" <<'EOF'
task:
  status: pending
  planned_paths:
  - path/a.sh
  - path/b.sh
EOF
    cp "$yaml" "$yaml.before"

    run bash "$YFS" "$yaml" task "planned_paths[1]" "path/changed.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"FATAL"* ]]
    [[ "$output" == *"nested list index notation is not supported"* ]]
}

@test "yaml_field_set: 添字表記が黙ってリテラルキー化せずファイルがbyte-identicalに保たれる" {
    local yaml="$TEST_TMPDIR/subscript_no_literal_key.yaml"
    cat > "$yaml" <<'EOF'
task:
  status: pending
  planned_paths:
  - path/a.sh
  - path/b.sh
EOF
    cp "$yaml" "$yaml.before"

    run bash "$YFS" "$yaml" task "planned_paths[1]" "path/changed.sh"
    [ "$status" -ne 0 ]

    # 添字表記の文字列がリテラルキーとして新規追加されていないこと
    run grep -F "planned_paths[1]:" "$yaml"
    [ "$status" -ne 0 ]

    # 元のlist構造・値も変わらず、ファイル全体がbyte-identicalであること
    run cmp -s "$yaml.before" "$yaml"
    [ "$status" -eq 0 ]
    run python3 -c "
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
assert data['task']['planned_paths'] == ['path/a.sh', 'path/b.sh'], data['task']['planned_paths']
print('PLANNED_PATHS_UNCHANGED_OK')
" "$yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PLANNED_PATHS_UNCHANGED_OK"* ]]
}

@test "yaml_field_set_batch: 添字指定を含むbatch呼出しは全体をFATALでfail-closedし部分書込みしない" {
    local yaml="$TEST_TMPDIR/subscript_batch_reject.yaml"
    cat > "$yaml" <<'EOF'
task:
  status: pending
  ninja: hayate
EOF
    cp "$yaml" "$yaml.before"

    run bash -lc "source \"$YFS\" && yaml_field_set_batch \"$yaml\" task \"status=done\" \"ninja[0]=bad\""
    [ "$status" -ne 0 ]
    [[ "$output" == *"FATAL"* ]]
    [[ "$output" == *"nested list index notation is not supported"* ]]

    # 添字表記でBLOCKされた際、先行フィールド(status=done)も部分書込みされないこと
    run cmp -s "$yaml.before" "$yaml"
    [ "$status" -eq 0 ]
}
# test_necessity: active task progress/status writes must renew progress_updated_at in the same atomic helper transaction.
@test "task active lifecycle write renews progress_updated_at" {
  local yaml="$TEST_TMPDIR/queue/tasks/lease.yaml"
  mkdir -p "$(dirname "$yaml")"
  printf '%s\n' 'task:' '  status: assigned' '  progress: old' > "$yaml"
  run bash "$YFS" "$yaml" task status acknowledged
  [ "$status" -eq 0 ]
  run python3 - "$yaml" <<'PY'
import datetime as dt, sys, yaml
t=yaml.safe_load(open(sys.argv[1]))['task']
s=dt.datetime.fromisoformat(t['progress_updated_at'].replace('Z','+00:00'))
assert t['status']=='acknowledged' and s.tzinfo is not None
PY
  [ "$status" -eq 0 ]
}

# test_necessity: AC fingerprints are fixed-width strings; a leading zero must
# never be resolved as a YAML 1.1 octal integer during task publication.
@test "yaml_field_set preserves leading-zero scalar as string" {
  local yaml="$TEST_TMPDIR/leading_zero.yaml"
  printf '%s\n' 'task:' '  ac_version: old' > "$yaml"
  run bash "$YFS" "$yaml" task ac_version 04575356
  [ "$status" -eq 0 ]
  run python3 - "$yaml" <<'PY'
import sys, yaml
value = yaml.safe_load(open(sys.argv[1]))['task']['ac_version']
assert value == '04575356', (type(value).__name__, value)
PY
  [ "$status" -eq 0 ]
}
