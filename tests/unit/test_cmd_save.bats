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

# test_necessity: q11 semantic検索結果に含まれる関連IDが因果tree再走査の
# 入力へ増幅されず、cmd本文に明示されたIDだけを診断する不変量を固定する。
@test "q11 causal backlinks receive explicit query but not semantic result ids" {
  awk '
    /^show_q11_semantic_search_matches\(\)/ { emit=1 }
    emit && /^show_q11_causal_backlinks\(\)/ { exit }
    emit { print }
  ' "$REPO_ROOT/scripts/cmd_save.sh" > "$BATS_TEST_TMPDIR/q11.sh"
  cat > "$BATS_TEST_TMPDIR/semantic.sh" <<'SH'
#!/usr/bin/env bash
printf 'related [[cmd_RESULT_ONLY]]\n'
SH
  chmod +x "$BATS_TEST_TMPDIR/semantic.sh"

  run env CMD_SAVE_SEMANTIC_SEARCH_SCRIPT="$BATS_TEST_TMPDIR/semantic.sh" \
    CACHE_ROOT="$BATS_TEST_TMPDIR" \
    bash -c '
      source "$1"
      PROJECT_DIR="$2"
      extract_q11_semantic_query() { printf "explicit [[cmd_INPUT_ONLY]]\n"; }
      cmd_save_metadata_cache_replay() { return 1; }
      cmd_save_metadata_cache_file() { printf "%s/cache\n" "$CACHE_ROOT"; }
      cmd_save_metadata_cache_store() { :; }
      show_q11_causal_backlinks() { printf "causal-arg:%s\n" "$1"; }
      show_q11_semantic_search_matches "ignored"
    ' _ "$BATS_TEST_TMPDIR/q11.sh" "$REPO_ROOT" "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"causal-arg:explicit [[cmd_INPUT_ONLY]]"* ]]
  [[ "$output" != *"causal-arg:"*"cmd_RESULT_ONLY"* ]]
}

# test_necessity: fixed snapshot targets must be WARN-only, while an explicit
# but incomplete self-measurement contract must BLOCK before cmd publication.
@test "T25 fixed baseline warns and explicit measurement omissions block" {
  awk '
    /^check_dynamic_measurement_contract\(\)/ { emit=1 }
    emit && /^check_q6_not_hiding_warn\(\)/ { exit }
    emit { print }
  ' "$REPO_ROOT/scripts/cmd_save.sh" > "$BATS_TEST_TMPDIR/dynamic_contract.sh"

  local fixed_text=$'acceptance_criteria:\n  - description: 正本300秒・件数厳密一致・±20%'
  run bash -c '
    source "$1"
    WARN_COUNT=0; BLOCK_COUNT=0
    record_warn_reason() { WARN_COUNT=$((WARN_COUNT + 1)); }
    record_block_reason() { BLOCK_COUNT=$((BLOCK_COUNT + 1)); }
    check_dynamic_measurement_contract "$2"
    printf "warn=%s block=%s\n" "$WARN_COUNT" "$BLOCK_COUNT"
  ' _ "$BATS_TEST_TMPDIR/dynamic_contract.sh" "$fixed_text"
  [ "$status" -eq 0 ]
  [ "$output" = "WARNING(T25): 固定基準値だけのACは停止条件にしない。before/after/measurement_commandを同一環境で自己計測し、差異は報告して継続せよ
warn=1 block=0" ]

  local incomplete=$'measurement_environment: same\nbefore: 1\nacceptance_criteria:\n  - description: 正本300秒・件数厳密一致・±20%'
  run bash -c '
    source "$1"
    WARN_COUNT=0; BLOCK_COUNT=0
    record_warn_reason() { WARN_COUNT=$((WARN_COUNT + 1)); }
    record_block_reason() { BLOCK_COUNT=$((BLOCK_COUNT + 1)); }
    check_dynamic_measurement_contract "$2"
    printf "warn=%s block=%s\n" "$WARN_COUNT" "$BLOCK_COUNT"
  ' _ "$BATS_TEST_TMPDIR/dynamic_contract.sh" "$incomplete"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCK(T25): 自己計測欄が欠落しています: after, measurement_command。before/after/measurement_commandを埋めよ"* ]]
  [[ "$output" == *"warn=0 block=1"* ]]

  local complete=$'measurement_environment: same\nbefore: 1\nafter: 2\nmeasurement_command: measure\nacceptance_criteria:\n  - description: 正本300秒・件数厳密一致・±20%'
  run bash -c '
    source "$1"
    WARN_COUNT=0; BLOCK_COUNT=0
    record_warn_reason() { WARN_COUNT=$((WARN_COUNT + 1)); }
    record_block_reason() { BLOCK_COUNT=$((BLOCK_COUNT + 1)); }
    check_dynamic_measurement_contract "$2"
    printf "warn=%s block=%s\n" "$WARN_COUNT" "$BLOCK_COUNT"
  ' _ "$BATS_TEST_TMPDIR/dynamic_contract.sh" "$complete"
  [ "$status" -eq 0 ]
  [ "$output" = "warn=0 block=0" ]

  local neutral=$'acceptance_criteria:\n  - description: 同一環境の自己計測を実行する'
  run bash -c '
    source "$1"
    WARN_COUNT=0; BLOCK_COUNT=0
    record_warn_reason() { WARN_COUNT=$((WARN_COUNT + 1)); }
    record_block_reason() { BLOCK_COUNT=$((BLOCK_COUNT + 1)); }
    check_dynamic_measurement_contract "$2"
    printf "warn=%s block=%s\n" "$WARN_COUNT" "$BLOCK_COUNT"
  ' _ "$BATS_TEST_TMPDIR/dynamic_contract.sh" "$neutral"
  [ "$status" -eq 0 ]
  [ "$output" = "warn=0 block=0" ]
}
