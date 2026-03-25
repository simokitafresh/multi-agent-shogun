#!/usr/bin/env bats
# test_yaml_field_set.bats
# Purpose: scripts/lib/yaml_field_set.sh の関数テスト
# Origin: cmd_cycle_002
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
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/yfs.XXXXXX")"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
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
