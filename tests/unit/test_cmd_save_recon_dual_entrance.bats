#!/usr/bin/env bats

# test_necessity: cmd_save.sh Check 19.7 (check_recon_dual_contract) must, at
# the real save entrance, BLOCK a 2-track recon cmd without recon_dual, PASS a
# structured one, and record the legacy-prose case as a WARN reason. Karo REJECT
# blt_20260906_012140 (1): the helper's own unit tests do not prove the wiring.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  awk '
    /^check_recon_dual_contract\(\)/ { emit=1 }
    emit { print }
    emit && /^}$/ { exit }
  ' "$REPO_ROOT/scripts/cmd_save.sh" > "$BATS_TEST_TMPDIR/check.sh"
  [ -s "$BATS_TEST_TMPDIR/check.sh" ]
}

run_check() {
  local block="$1"
  run env CMD_RD_TEST_BLOCK="$block" bash -c '
    record_block_reason() { printf "BLOCKED:%s\n" "$1"; }
    record_warn_reason()  { printf "WARNED:%s|%s\n" "$1" "$2"; }
    cmd_block_has_field() { printf "%s\n" "$CMD_BLOCK_NC" | grep -qE "^    ${1}:"; }
    source "$1"
    PROJECT_DIR="$2"
    CMD_BLOCK_NC="$CMD_RD_TEST_BLOCK"
    check_recon_dual_contract
  ' _ "$BATS_TEST_TMPDIR/check.sh" "$REPO_ROOT"
}

DUAL_HEAD=$'  cmd_fixture:\n    title: "新四つ目 3 体の根因偵察(A1/A2 2 名並行)"\n    purpose: "readonly 偵察"\n    parallel_ok:\n    - AC1\n    - AC2\n    acceptance_criteria:\n      AC1: {description: "A1"}\n      AC2: {description: "A2"}'

@test "entrance: dual recon without recon_dual is recorded as BLOCK and returns 1" {
  run_check "$DUAL_HEAD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCKED:BLOCK:"*"recon_dual"* ]]
}

@test "entrance: structured recon_dual passes with PASS(recon_dual=structured)" {
  run_check "$DUAL_HEAD"$'\n    recon_dual:\n      mode: independent\n      cross_reference: forbidden\n      base: fixed_origin_main\n      shared_context_embargo: karo_release_required'
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS(recon_dual=structured)"* ]]
  [[ "$output" != *"BLOCKED:"* ]]
}

@test "entrance: legacy prose only records WARN reason recon_dual_legacy_prose and returns 0" {
  run_check "$DUAL_HEAD"$'\n    command: |\n      1. 独立2系統、相互参照禁止で偵察'
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNED:recon_dual_legacy_prose|check=check_recon_dual_contract"* ]]
}

@test "entrance: cmd without parallel_ok is not_required and never calls the validator" {
  run_check $'  cmd_fixture:\n    title: "偵察 1 名"\n    purpose: "recon"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS(recon_dual=not_required)"* ]]
}
