#!/usr/bin/env bats

# test_necessity: cmd_saveの明示参照だけを正本突合し、曖昧tokenをBLOCKしない不変量を守るcontract test。

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORK="$BATS_TEST_TMPDIR/project"
  mkdir -p "$WORK/scripts" "$WORK/data"
  touch "$WORK/scripts/existing.sh"
  python3 - "$WORK/data/app.sqlite" <<'PY'
import sqlite3
import sys
with sqlite3.connect(sys.argv[1]) as conn:
    conn.execute("CREATE TABLE existing_table(id INTEGER)")
PY

  awk '
    /^check_explicit_reference_existence\(\)/ { emit=1 }
    emit && /^check_explicit_reference_existence$/ { exit }
    emit { print }
  ' "$REPO_ROOT/scripts/cmd_save.sh" > "$BATS_TEST_TMPDIR/guard.sh"
}

run_guard() {
  local block="$1"
  run env CMD_REFERENCE_TEST_BLOCK="$block" CMD_REFERENCE_PROJECT_WD_OVERRIDE="$WORK" \
    bash -c '
      record_block_reason() { printf "%s\n" "$1"; }
      abort_if_block_immediate() { return 1; }
      source "$1"
      PROJECT_DIR="$2"
      CMD_BLOCK_NC="$CMD_REFERENCE_TEST_BLOCK"
      CMD_BLOCK_PROJECT=infra
      check_explicit_reference_existence
    ' _ "$BATS_TEST_TMPDIR/guard.sh" "$REPO_ROOT"
}

record_block_reason() {
  printf '%s\n' "$1"
}

abort_if_block_immediate() {
  return 1
}

@test "existing and missing explicit file paths are distinguished" {
  run_guard $'target_path: scripts/existing.sh\nacceptance_criteria:\n  - description: scripts/missing.sh'
  [ "$status" -eq 1 ]
  [[ "$output" == *"参照先が非実在: scripts/missing.sh。falsifyしてから起票せよ"* ]]
  [[ "$output" != *"existing.sh。falsify"* ]]
}

@test "explicit sqlite table reference checks sqlite_master read-only" {
  run_guard $'target_path: scripts/existing.sh\nassumptions:\n  - db_path: data/app.sqlite\n    table: existing_table'
  [ "$status" -eq 0 ]

  run_guard $'target_path: scripts/existing.sh\nassumptions:\n  - db_path: data/app.sqlite\n    table: missing_table'
  [ "$status" -eq 1 ]
  [[ "$output" == *"参照先が非実在: missing_table。falsifyしてから起票せよ"* ]]
}

@test "ambiguous negative corpus has zero false positives" {
  run_guard $'target_path: scripts/existing.sh\nacceptance_criteria:\n  - description: https://example.com/a.py\n  - description: 自然文 scripts/missing.sh を説明する\n  - description: scripts/*.sh\n  - description: scripts/<name>.sh\n  - description: cat scripts/missing.sh | wc -l\n  - description: users table'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
