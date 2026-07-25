#!/usr/bin/env bats
# test_necessity: dotted pathとlist追記は「書けないのに成功(RC=0)を返しトップレベルにリテラルキーを作る」形で壊れうる。本testはyaml_field_set/yaml_field_set_batchが(1)ネストへ実際に書く(2)listへ追記する(3)書けないpathで非ゼロ終了する、という不変量を守る。
# Purpose: cmd_karo_impl_yaml_field_set_list_nested_20260725 の実失敗4件の再現regression
# Origin: [[cmd_karo_impl_yaml_field_set_list_nested_20260725]] -> [[L1299 完全一致キー前提]] -> [[忍者が契約を自力で満たせずBLOCK]]

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export YFS="$PROJECT_ROOT/scripts/lib/yaml_field_set.sh"
    [ -f "$YFS" ] || return 1
}

setup() {
    export TEST_TMPDIR="$BATS_TEST_TMPDIR"
    cat > "$TEST_TMPDIR/task.yaml" <<'EOF'
task:
  status: assigned
  commit_contract:
    required: true
    planned_paths: scripts/lib/yaml_field_set.sh
  ci_fix_clean_repro_evidence:
    e2_harness_command: ''
    note: keep
  tail: end
EOF
}

yget() {
    python3 -c '
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
for key in sys.argv[2].split("."):
    data = data[key]
print(repr(data))
' "$TEST_TMPDIR/task.yaml" "$1"
}

# --- (a) 小太郎事例: planned_paths が scalar の状態から要素追加 ---

@test "append: scalar field はlist化され既存値を先頭に保持して追記される" {
    run bash "$YFS" --append "$TEST_TMPDIR/task.yaml" task commit_contract.planned_paths tests/unit/test_x.bats
    [ "$status" -eq 0 ]
    run yget commit_contract.planned_paths
    [ "$output" = "['scripts/lib/yaml_field_set.sh', 'tests/unit/test_x.bats']" ]
}

# --- (b) 半蔵事例: ネスト2階層への書込み ---

@test "nested set: dotted path がネスト先へ書かれトップレベルにリテラルキーを作らない" {
    run bash "$YFS" "$TEST_TMPDIR/task.yaml" task ci_fix_clean_repro_evidence.e2_harness_command 'bash scripts/run_tests.sh unit'
    [ "$status" -eq 0 ]
    run yget ci_fix_clean_repro_evidence.e2_harness_command
    [ "$output" = "'bash scripts/run_tests.sh unit'" ]
    # 兄弟fieldと後続blockが保存されていること
    run yget ci_fix_clean_repro_evidence.note
    [ "$output" = "'keep'" ]
    run yget tail
    [ "$output" = "'end'" ]
    # リテラルキーが作られていないこと(旧実装の壊れ方)
    run grep -c 'ci_fix_clean_repro_evidence\.e2_harness_command' "$TEST_TMPDIR/task.yaml"
    [ "$output" = "0" ]
}

@test "nested set: batchレーンでもdotted pathがネスト先へ書かれる" {
    run bash -c "source '$YFS' && yaml_field_set_batch '$TEST_TMPDIR/task.yaml' task 'status=in_progress' 'ci_fix_clean_repro_evidence.e2_harness_command=bash x.sh'"
    [ "$status" -eq 0 ]
    run yget ci_fix_clean_repro_evidence.e2_harness_command
    [ "$output" = "'bash x.sh'" ]
    run yget status
    [ "$output" = "'in_progress'" ]
    run grep -c 'ci_fix_clean_repro_evidence\.e2_harness_command' "$TEST_TMPDIR/task.yaml"
    [ "$output" = "0" ]
}

# --- (c) ネスト内のlistへの追記 ---

@test "append: 既存listへ追記され重複要素は増えない" {
    bash "$YFS" --append "$TEST_TMPDIR/task.yaml" task commit_contract.planned_paths tests/unit/test_x.bats
    run bash "$YFS" --append "$TEST_TMPDIR/task.yaml" task commit_contract.planned_paths tests/unit/test_y.bats
    [ "$status" -eq 0 ]
    run yget commit_contract.planned_paths
    [ "$output" = "['scripts/lib/yaml_field_set.sh', 'tests/unit/test_x.bats', 'tests/unit/test_y.bats']" ]
    # 同一要素の再追記は冪等
    run bash "$YFS" --append "$TEST_TMPDIR/task.yaml" task commit_contract.planned_paths tests/unit/test_y.bats
    [ "$status" -eq 0 ]
    run yget commit_contract.planned_paths
    [ "$output" = "['scripts/lib/yaml_field_set.sh', 'tests/unit/test_x.bats', 'tests/unit/test_y.bats']" ]
}

@test "append: 存在しないleaf keyは新規listとして親の中に作られる" {
    run bash "$YFS" --append "$TEST_TMPDIR/task.yaml" task commit_contract.extra_paths docs/a.md
    [ "$status" -eq 0 ]
    run yget commit_contract.extra_paths
    [ "$output" = "['docs/a.md']" ]
    run yget commit_contract.required
    [ "$output" = "True" ]
}

# --- (d) 書けないpathは非ゼロで明示的に失敗する ---

@test "書けないpathは非ゼロで失敗しファイルを変更しない" {
    local before after
    before="$(md5sum < "$TEST_TMPDIR/task.yaml")"
    run bash "$YFS" "$TEST_TMPDIR/task.yaml" task no_such.parent.key value
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
    after="$(md5sum < "$TEST_TMPDIR/task.yaml")"
    [ "$before" = "$after" ]
}

@test "scalar fieldを中間segmentに指定した場合も非ゼロで失敗する" {
    local before after
    before="$(md5sum < "$TEST_TMPDIR/task.yaml")"
    run bash "$YFS" "$TEST_TMPDIR/task.yaml" task status.sub value
    [ "$status" -ne 0 ]
    [[ "$output" == *"scalar"* ]]
    after="$(md5sum < "$TEST_TMPDIR/task.yaml")"
    [ "$before" = "$after" ]
}

@test "存在しないblock_idへのdotted pathは非ゼロで失敗する" {
    run bash "$YFS" "$TEST_TMPDIR/task.yaml" no_such_block a.b value
    [ "$status" -ne 0 ]
    run grep -c '^a\.b:' "$TEST_TMPDIR/task.yaml"
    [ "$output" = "0" ]
}
