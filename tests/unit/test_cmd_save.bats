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

@test "quoted scalar continuation beginning hash survives comment stripping" {
  awk '
    /^cmd_save_strip_yaml_comment_lines\(\)/ { emit=1 }
    emit && /^load_cmd_block\(\)/ { exit }
    emit { print }
  ' "$REPO_ROOT/scripts/cmd_save.sh" > "$BATS_TEST_TMPDIR/comment_guard.sh"

  run bash -c '
    source "$1"
    cmd_save_strip_yaml_comment_lines <<'"'"'YAML'"'"'
purpose: "cmd_4141 fold
  #9 remains quoted data"
  # ordinary YAML comment
command: |
  # block scalar data
YAML
  ' _ "$BATS_TEST_TMPDIR/comment_guard.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"#9 remains quoted data"* ]]
  [[ "$output" == *"# block scalar data"* ]]
  [[ "$output" != *"ordinary YAML comment"* ]]
  run python3 -c 'import sys,yaml; data=yaml.safe_load(sys.stdin.read()); assert "#9" in data["purpose"]; assert "# block scalar data" in data["command"]' <<< "$output"
  [ "$status" -eq 0 ]
}

# test_necessity: three-layer INFO検索の同義空白正規化と並行cold missの
# query単位single-flightを守り、cmd保存間で重い検索が重複しない不変量を固定する。
@test "three-layer ruling search normalizes whitespace and coalesces concurrent cold misses" {
  awk '
    /^show_three_layer_memory_ruling_info\(\)/ { emit=1 }
    emit && /^# WSL2最適化: 非同期化/ { exit }
    emit { print }
  ' "$REPO_ROOT/scripts/cmd_save.sh" > "$BATS_TEST_TMPDIR/ruling.sh"
  cat > "$BATS_TEST_TMPDIR/search.sh" <<'SH'
#!/usr/bin/env bash
printf 'call\n' >> "$CALL_LOG"
sleep 0.2
printf 'matched:%s\n' "$1"
SH
  chmod +x "$BATS_TEST_TMPDIR/search.sh"

  run env CALL_LOG="$BATS_TEST_TMPDIR/calls" \
    CMD_SAVE_SEMANTIC_SEARCH_SCRIPT="$BATS_TEST_TMPDIR/search.sh" \
    SEM_CACHE="$BATS_TEST_TMPDIR/cache" \
    bash -c '
      source "$1"
      PROJECT_DIR="$2"
      _SEMANTIC_SESSION_CACHE_DIR="$SEM_CACHE"
      CMD_SAVE_SEMANTIC_CACHE_READY=0
      CMD_BLOCK_NC=$'"'"'title: alpha   beta\npurpose: gamma'"'"'
      show_three_layer_memory_ruling_info &
      CMD_BLOCK_NC=$'"'"'title: alpha beta\npurpose: gamma'"'"'
      show_three_layer_memory_ruling_info &
      wait
    ' _ "$BATS_TEST_TMPDIR/ruling.sh" "$REPO_ROOT"

  [ "$status" -eq 0 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/calls")" -eq 1 ]
  [[ "$output" == *"重複起動をスキップ"* ]]
}
