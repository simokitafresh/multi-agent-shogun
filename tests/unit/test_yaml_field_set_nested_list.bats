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

ygetf() {
    local file="$1" path="$2"
    python3 -c '
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
for key in sys.argv[2].split("."):
    data = data[key]
print(repr(data))
' "$file" "$path"
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

# --- (e) cmd_karo_hotfix_yaml_duplicate_field_repair: 同一block同indentの重複field定義
# --- は先頭だけ更新→末尾の旧定義が生き残り、yaml.safe_loadが重複keyを最後勝ちで
# --- 解決するため書込み直後の候補が期待値と食い違いFATAL(candidate verification
# --- mismatch)で失敗し、元ファイルも修復不能に固まっていた(cmd_4476 live同型)。
# --- AC1(再現条件)とAC2(1件への正規化)を1つの回帰testで検証する。
# Origin: [[cmd_4476]] -> [[stale .bak誤配備でrelated_lessons重複field発生]] -> [[cmd_karo_hotfix_yaml_duplicate_field_repair]]

# test_necessity: 同一block同indentで重複定義されたfieldにsetterを実行すると、修正前は候補検証mismatchでexit非0となり書込みが失敗し続け元ファイルが永久に固まる。修正後は1件へ正規化されexit 0で成功する不変量を守る。
@test "AC1/AC2: related_lessons二重定義(先頭[]・末尾[L097,L019])へ[]設定でcandidate mismatchなく1件へ正規化される" {
    cat > "$TEST_TMPDIR/dup.yaml" <<'EOF'
task:
  status: assigned
  related_lessons: []
  filler: keep
  related_lessons: [L097, L019]
  tail: end
EOF
    run grep -c '^  related_lessons:' "$TEST_TMPDIR/dup.yaml"
    [ "$output" = "2" ]

    run bash "$YFS" "$TEST_TMPDIR/dup.yaml" task related_lessons '[]'
    [ "$status" -eq 0 ]

    run grep -c '^  related_lessons:' "$TEST_TMPDIR/dup.yaml"
    [ "$output" = "1" ]
    run grep -c 'related_lessons:.*\[\]' "$TEST_TMPDIR/dup.yaml"
    [ "$output" = "1" ]
    run ygetf "$TEST_TMPDIR/dup.yaml" filler
    [ "$output" = "'keep'" ]
    run ygetf "$TEST_TMPDIR/dup.yaml" status
    [ "$output" = "'assigned'" ]
    run ygetf "$TEST_TMPDIR/dup.yaml" tail
    [ "$output" = "'end'" ]
}

# test_necessity: map_scalarレーン(bracket始まりでないscalar値)で同名field重複を2回目以降まとめて除去し常に1件だけ残す不変量を守る。
@test "AC2: scalar fieldの重複定義もmap_scalarレーンで1件へ正規化される" {
    cat > "$TEST_TMPDIR/dup_scalar.yaml" <<'EOF'
task:
  status: assigned
  status: assigned
  commit_contract:
    required: true
  tail: end
EOF
    run grep -c '^  status:' "$TEST_TMPDIR/dup_scalar.yaml"
    [ "$output" = "2" ]

    run bash "$YFS" "$TEST_TMPDIR/dup_scalar.yaml" task status done
    [ "$status" -eq 0 ]

    run grep -c '^  status:' "$TEST_TMPDIR/dup_scalar.yaml"
    [ "$output" = "1" ]
    run ygetf "$TEST_TMPDIR/dup_scalar.yaml" status
    [ "$output" = "'done'" ]
    run ygetf "$TEST_TMPDIR/dup_scalar.yaml" commit_contract.required
    [ "$output" = "True" ]
    run ygetf "$TEST_TMPDIR/dup_scalar.yaml" tail
    [ "$output" = "'end'" ]
}

# test_necessity: 重複の先頭occurrenceがnested mapping(複数子行)であっても、正規化時に子行ごと正しく消費し1件だけ残す不変量を守る。
@test "AC2: 重複定義の先頭がnested mapping(子行あり)でも子行ごと除去して1件へ正規化される" {
    cat > "$TEST_TMPDIR/dup_mapping.yaml" <<'EOF'
task:
  status: assigned
  extra:
    a: 1
    b: 2
  extra: keep
  tail: end
EOF
    run grep -c '^  extra:' "$TEST_TMPDIR/dup_mapping.yaml"
    [ "$output" = "2" ]

    run bash "$YFS" "$TEST_TMPDIR/dup_mapping.yaml" task extra keep2
    [ "$status" -eq 0 ]

    run grep -c '^  extra:' "$TEST_TMPDIR/dup_mapping.yaml"
    [ "$output" = "1" ]
    run ygetf "$TEST_TMPDIR/dup_mapping.yaml" extra
    [ "$output" = "'keep2'" ]
    run grep -c '    a: 1' "$TEST_TMPDIR/dup_mapping.yaml"
    [ "$output" = "0" ]
    run grep -c '    b: 2' "$TEST_TMPDIR/dup_mapping.yaml"
    [ "$output" = "0" ]
    run ygetf "$TEST_TMPDIR/dup_mapping.yaml" tail
    [ "$output" = "'end'" ]
}

# test_necessity: 重複正規化ロジックが対象field以外の隣接field/nested listへ誤って波及しない不変量を守る。
@test "AC2(対照): 重複していない隣接fieldとnested listは正規化の影響を受けない" {
    cat > "$TEST_TMPDIR/dup_contrast.yaml" <<'EOF'
task:
  status: assigned
  related_lessons: []
  siblings:
    - one
    - two
  related_lessons: [L097, L019]
  tail: end
EOF
    run bash "$YFS" "$TEST_TMPDIR/dup_contrast.yaml" task related_lessons '[]'
    [ "$status" -eq 0 ]

    run grep -c '^  related_lessons:' "$TEST_TMPDIR/dup_contrast.yaml"
    [ "$output" = "1" ]
    run ygetf "$TEST_TMPDIR/dup_contrast.yaml" siblings
    [ "$output" = "['one', 'two']" ]
    run ygetf "$TEST_TMPDIR/dup_contrast.yaml" status
    [ "$output" = "'assigned'" ]
    run ygetf "$TEST_TMPDIR/dup_contrast.yaml" tail
    [ "$output" = "'end'" ]
}

ygetroot() {
    local file="$1" key="$2"
    python3 -c '
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
print(repr(data[sys.argv[2]]))
' "$file" "$key"
}

# test_necessity: root fallbackレーン(block_id=root)でも同名field重複を2回目以降まとめて除去し常に1件だけ残す不変量を守る。
@test "AC2: block_id=rootの重複定義もapply_rootレーンで1件へ正規化される" {
    cat > "$TEST_TMPDIR/dup_root.yaml" <<'EOF'
status: idle
ninja: kagemaru
status: idle
tail: end
EOF
    run grep -c '^status:' "$TEST_TMPDIR/dup_root.yaml"
    [ "$output" = "2" ]

    run bash "$YFS" "$TEST_TMPDIR/dup_root.yaml" root status active
    [ "$status" -eq 0 ]

    run grep -c '^status:' "$TEST_TMPDIR/dup_root.yaml"
    [ "$output" = "1" ]
    run ygetroot "$TEST_TMPDIR/dup_root.yaml" status
    [ "$output" = "'active'" ]
    run ygetroot "$TEST_TMPDIR/dup_root.yaml" ninja
    [ "$output" = "'kagemaru'" ]
    run ygetroot "$TEST_TMPDIR/dup_root.yaml" tail
    [ "$output" = "'end'" ]
}
