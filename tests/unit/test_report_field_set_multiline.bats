#!/usr/bin/env bats
# test_report_field_set_multiline.bats
# Purpose: 直接引数でマルチライン値を渡した場合にYAML構造が保持されることを検証
# Origin: cmd_fix_report_field_set_multiline

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPT="$PROJECT_ROOT/scripts/report_field_set.sh"
    [ -f "$SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/rfs_ml.XXXXXX")"
    export TEST_REPORT="$TEST_TMPDIR/report.yaml"
    cat > "$TEST_REPORT" <<'EOF'
worker_id: kagemaru
parent_cmd: cmd_test
ac_version_read: abc12345
result:
  summary: ""
  details: ""
EOF
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "マルチライン直接引数: result.summaryにYAML構造が保持される" {
    local multiline_val=$'修正完了\n- report_field_set.sh L62にマルチライン検出追加\n- テスト作成'
    run bash "$SCRIPT" "$TEST_REPORT" result.summary "$multiline_val"
    [ "$status" -eq 0 ]

    # YAML構造が壊れていないことを確認（python3でパース可能）
    run python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
assert isinstance(data, dict), 'top-level must be dict'
assert 'result' in data, 'result key must exist'
s = data['result']['summary']
assert '修正完了' in str(s), f'summary missing content: {s}'
print('YAML structure OK')
" "$TEST_REPORT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"YAML structure OK"* ]]
}

@test "マルチライン直接引数: result.detailsに複数行テキストが保持される" {
    local multiline_val=$'行1: 概要\n行2: 詳細\n行3: 補足'
    run bash "$SCRIPT" "$TEST_REPORT" result.details "$multiline_val"
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
details = str(data['result']['details'])
assert '行1' in details, f'line1 missing: {details}'
assert '行2' in details, f'line2 missing: {details}'
assert '行3' in details, f'line3 missing: {details}'
print('Multiline content preserved')
" "$TEST_REPORT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Multiline content preserved"* ]]
}

@test "stdin経路のマルチライン: 既存動作に影響なし" {
    run bash -c "printf '修正内容\\n- 項目1\\n- 項目2' | bash '$SCRIPT' '$TEST_REPORT' result.summary -"
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
s = str(data['result']['summary'])
assert '修正内容' in s, f'stdin multiline failed: {s}'
print('stdin path OK')
" "$TEST_REPORT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"stdin path OK"* ]]
}

@test "シングルライン直接引数: awk経路で正常動作" {
    run bash "$SCRIPT" "$TEST_REPORT" result.summary "単一行の値"
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
s = str(data['result']['summary'])
assert '単一行の値' in s, f'single line failed: {s}'
print('Single line OK')
" "$TEST_REPORT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Single line OK"* ]]
}
