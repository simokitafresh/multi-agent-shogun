#!/usr/bin/env bats

# test_necessity: 実行batsは単一でも複数でもBLOCKし、run_tests file modeへ一本化する
# 永続契約。これが消えると無制御実行とrunner偽許可が
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
  [[ "$output" == *"BLOCK(heavy-job-admission)"* ]]
  [[ "$output" == *"bash scripts/run_tests.sh file"* ]]
}

assert_allowed() {
  run_guard "$1"
  [ "$status" -eq 0 ]
  [[ "$output" != *"BLOCK:"* ]]
}

@test "単一batsも複数batsもenv timeout bash-c wrapper込みでBLOCK" {
  assert_blocked "bats tests/unit/test_pre_bash_test_fullrun_guard.bats"
  assert_blocked "env BATS_TEST_TIMEOUT=5 bats tests/unit/test_pre_bash_test_fullrun_guard.bats"
  assert_blocked "timeout 30 bats tests/unit/test_pre_bash_test_fullrun_guard.bats"
  assert_blocked "timeout --kill-after 2 30 env FOO=bar bats tests/unit/test_pre_bash_test_fullrun_guard.bats"
  assert_blocked "bash -c 'bats tests/unit/test_pre_bash_test_fullrun_guard.bats'"
  assert_blocked "env FOO=bar bash -c 'timeout 30 bats tests/unit/test_pre_bash_test_fullrun_guard.bats'"
  assert_blocked "bats tests/unit/test_pre_bash_test_fullrun_guard.bats tests/unit/test_heavy_job_admission.bats"
  assert_blocked "env BATS_TEST_TIMEOUT=5 bats tests/unit/test_pre_bash_test_fullrun_guard.bats tests/unit/test_heavy_job_admission.bats"
  assert_blocked "timeout 30 bats tests/unit/test_pre_bash_test_fullrun_guard.bats tests/unit/test_heavy_job_admission.bats"
  assert_blocked "timeout --kill-after 2 30 env FOO=bar bats tests/unit/test_pre_bash_test_fullrun_guard.bats tests/unit/test_heavy_job_admission.bats"
  assert_blocked "bash -c 'bats tests/unit/test_pre_bash_test_fullrun_guard.bats tests/unit/test_heavy_job_admission.bats'"
  assert_blocked "env FOO=bar bash -c 'timeout 30 bats tests/unit/test_pre_bash_test_fullrun_guard.bats tests/unit/test_heavy_job_admission.bats'"
}

@test "run_tests.sh file経由は許可し非bats文字列の偽陽性を出さない" {
  assert_allowed "bash scripts/run_tests.sh file tests/unit/test_pre_bash_test_fullrun_guard.bats"
  assert_allowed "env BATS_TEST_TIMEOUT=5 bash scripts/run_tests.sh file tests/unit/test_pre_bash_test_fullrun_guard.bats"
  assert_allowed "printf '%s\\n' 'bats tests/unit/test_pre_bash_test_fullrun_guard.bats'"
  assert_allowed "rg -n 'bats' scripts/hooks/pre-bash-test-fullrun-guard.sh"
}

@test "JSON escaped commandも実コマンド位置を判定する" {
  assert_blocked "bash -c \"env FOO='a b' bats tests/unit/test_pre_bash_test_fullrun_guard.bats\""
  assert_blocked "bash -c \"env FOO='a b' bats tests/unit/test_pre_bash_test_fullrun_guard.bats tests/unit/test_heavy_job_admission.bats\""
  assert_allowed "echo \"正規代替: bash scripts/run_tests.sh file tests/unit/test_pre_bash_test_fullrun_guard.bats\""
}

# test_necessity: text that shlex cannot parse (a python heredoc with triple quotes)
# is not a bats execution; the guard must strip heredoc bodies before judging and
# must only fall back to BLOCK when a bats invocation is textually present.
# regression_justification: 2026-09-05 a python heredoc patch + run_tests.sh in one
# command was blocked three times (ValueError -> unconditional block) and pushed the
# operator into splitting '.bats' across a variable to hide it.
@test "heredoc内の三重引用符は解析不能でも bats 実行ではないので通る" {
  assert_allowed "python3 - <<'PY'
p='tests/unit/test_x.bats'; s='''a'''
PY
bash scripts/run_tests.sh file tests/unit/test_x.bats"
  assert_blocked "python3 - <<'PY'
s='''a'''
PY
bats tests/unit/test_x.bats"
  assert_allowed "python3 - <<'PY'
s='''a'''
PY
timeout 10 bats -c tests/unit/test_x.bats"
}
