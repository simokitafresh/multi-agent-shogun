#!/usr/bin/env bats
# test_yaml_safe_read.bats
# cmd_karo_hotfix_queue_yaml_atomicity_202607110113 follow-up
# Purpose: scripts/lib/yaml_safe_read.py の safe_load_retry() を単体で検証する。
# タイミング依存の統計テストはtest_yaml_field_set.batsの並行アクセステストが担う。
# 本ファイルは決定的な(flakyでない)ロジック検証に限定する。

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export LIB_DIR="$PROJECT_ROOT/scripts/lib"
    [ -f "$LIB_DIR/yaml_safe_read.py" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$PROJECT_ROOT/tmp/yaml_safe_read_test.XXXXXX")"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "有効なYAMLは即座にパース結果を返す" {
    printf 'task:\n  status: idle\n' > "$TEST_TMPDIR/valid.yaml"
    run python3 -c "
import sys
sys.path.insert(0, '$LIB_DIR')
from yaml_safe_read import safe_load_retry
data = safe_load_retry('$TEST_TMPDIR/valid.yaml')
assert data == {'task': {'status': 'idle'}}, data
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "恒久的に存在しないファイルはリトライを使い切りFileNotFoundErrorを送出する" {
    run python3 -c "
import sys, time
sys.path.insert(0, '$LIB_DIR')
from yaml_safe_read import safe_load_retry
start = time.time()
try:
    safe_load_retry('$TEST_TMPDIR/never_exists.yaml', retries=3, backoff=0.01)
    print('UNEXPECTED_SUCCESS')
except FileNotFoundError:
    elapsed = time.time() - start
    # retries=3・backoff=0.01なら最低0.03s(3回分)は待っているはず
    assert elapsed >= 0.03, f'elapsed={elapsed} too short for 3 retries'
    print('FNF_AS_EXPECTED')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FNF_AS_EXPECTED"* ]]
}

@test "不正なYAML内容はリトライせず即座にYAMLErrorを送出する(データ破損を握りつぶさない)" {
    printf 'task:\n  status: line1\nline2 malformed\n' > "$TEST_TMPDIR/broken.yaml"
    run python3 -c "
import sys, time
sys.path.insert(0, '$LIB_DIR')
import yaml
from yaml_safe_read import safe_load_retry
start = time.time()
try:
    safe_load_retry('$TEST_TMPDIR/broken.yaml', retries=5, backoff=0.5)
    print('UNEXPECTED_SUCCESS')
except yaml.YAMLError:
    elapsed = time.time() - start
    # YAMLErrorはリトライされないので即座に(backoffの0.5sを待たずに)返るはず
    assert elapsed < 0.4, f'elapsed={elapsed} suggests retry happened for YAMLError'
    print('YAMLERROR_NO_RETRY')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"YAMLERROR_NO_RETRY"* ]]
}

@test "リトライ待機中にファイルが出現すれば成功する(遅延出現の吸収)" {
    local target="$TEST_TMPDIR/delayed.yaml"
    (
        sleep 0.1
        printf 'task:\n  status: appeared_late\n' > "$target"
    ) &
    local writer_pid=$!

    run python3 -c "
import sys
sys.path.insert(0, '$LIB_DIR')
from yaml_safe_read import safe_load_retry
data = safe_load_retry('$target', retries=5, backoff=0.05)
assert data == {'task': {'status': 'appeared_late'}}, data
print('DELAYED_APPEAR_OK')
"
    wait "$writer_pid"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DELAYED_APPEAR_OK"* ]]
}
