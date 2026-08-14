#!/usr/bin/env bats

# test_necessity: 直接bats実行をwrapper込みでBLOCKし、run_tests.sh経由だけを許可する
# 永続契約。これが消えるとenv/timeout/bash-c経由の無制御実行とrunner偽許可が
# 実行前に検出されなくなる。

HOOK="$BATS_TEST_DIRNAME/../../scripts/hooks/pre-bash-test-fullrun-guard.sh"

run_guard() {
  local command="$1"
  local payload
  payload="$(python3 - "$command" <<'PY'
import json
import sys

print(json.dumps({"tool_input": {"command": sys.argv[1]}}))
PY
)"
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK"
}

assert_blocked() {
  run_guard "$1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK: batsの直接実行は禁止"* ]]
  [[ "$output" == *"bash scripts/run_tests.sh file"* ]]
}

assert_allowed() {
  run_guard "$1"
  [ "$status" -eq 0 ]
  [[ "$output" != *"BLOCK:"* ]]
}

@test "直接batsはenv timeout bash-c wrapperを含めてfail-closed BLOCK" {
  assert_blocked "bats tests/unit/test_pre_bash_test_fullrun_guard.bats"
  assert_blocked "env BATS_TEST_TIMEOUT=5 bats tests/unit/test_pre_bash_test_fullrun_guard.bats"
  assert_blocked "timeout 30 bats tests/unit/test_pre_bash_test_fullrun_guard.bats"
  assert_blocked "timeout --kill-after 2 30 env FOO=bar bats tests/unit/test_pre_bash_test_fullrun_guard.bats"
  assert_blocked "bash -c 'bats tests/unit/test_pre_bash_test_fullrun_guard.bats'"
  assert_blocked "env FOO=bar bash -c 'timeout 30 bats tests/unit/test_pre_bash_test_fullrun_guard.bats'"
}

@test "run_tests.sh file経由は許可し非bats文字列の偽陽性を出さない" {
  assert_allowed "bash scripts/run_tests.sh file tests/unit/test_pre_bash_test_fullrun_guard.bats"
  assert_allowed "env BATS_TEST_TIMEOUT=5 bash scripts/run_tests.sh file tests/unit/test_pre_bash_test_fullrun_guard.bats"
  assert_allowed "printf '%s\\n' 'bats tests/unit/test_pre_bash_test_fullrun_guard.bats'"
  assert_allowed "rg -n 'bats' scripts/hooks/pre-bash-test-fullrun-guard.sh"
}

@test "JSON escaped commandも実コマンド位置を判定する" {
  assert_blocked "bash -c \"env FOO='a b' bats tests/unit/test_pre_bash_test_fullrun_guard.bats\""
  assert_allowed "echo \"正規代替: bash scripts/run_tests.sh file tests/unit/test_pre_bash_test_fullrun_guard.bats\""
}
