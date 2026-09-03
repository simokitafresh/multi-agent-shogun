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

# test_necessity: q11 causal検索がrepoのgit管理集合だけを走査し、.git等の
# 再帰領域へ脱線しない不変量を固定する。
@test "q11 causal backlinks stay inside bounded git file set" {
  local q11_repo="$BATS_TEST_TMPDIR/q11repo"
  mkdir -p "$q11_repo"
  git -C "$q11_repo" init -q
  printf 'kept [[cmd_KEEP]]\n' > "$q11_repo/kept.md"
  git -C "$q11_repo" add kept.md
  git -C "$q11_repo" -c user.name=test -c user.email=test@example.invalid commit -qm init
  mkdir -p "$q11_repo/.git/private"
  printf 'hidden [[cmd_KEEP]]\n' > "$q11_repo/.git/private/hidden.txt"
  : > "$q11_repo/causal.sh"

  awk '
    /^show_q11_causal_backlinks\(\)/ { emit=1 }
    emit && /^extract_memory_db_search_tokens\(\)/ { exit }
    emit { print }
  ' "$REPO_ROOT/scripts/cmd_save.sh" > "$BATS_TEST_TMPDIR/q11_bounded.sh"
  run bash -c '
    source "$1"
    PROJECT_DIR="$2"
    SEMANTIC_CAUSAL_ROOT="$2"
    CMD_SAVE_CAUSAL_BACKLINKS_SCRIPT="$2/causal.sh"
    show_q11_causal_backlinks "[[cmd_KEEP]]"
  ' _ "$BATS_TEST_TMPDIR/q11_bounded.sh" "$q11_repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kept.md"* ]]
  [[ "$output" != *"hidden.txt"* ]]
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

# test_necessity: staleなprojects pathを参照せずorigin treeとplanned_pathsを
# 新規成果物の許容根拠にする不変量を固定する。
@test "AC new paths use origin tree parent or planned_paths" {
  awk '
    /^path_exists_for_cmd_source\(\)/ { emit=1 }
    emit && /^update_bulletin_actioned_by_for_cmd\(\)/ { exit }
    emit { print }
  ' "$REPO_ROOT/scripts/cmd_save.sh" > "$BATS_TEST_TMPDIR/path_guard.sh"
  awk '
    /^check_ac_file_paths\(\)/ { emit=1 }
    emit && /^check_ac_file_paths$/ { exit }
    emit { print }
  ' "$REPO_ROOT/scripts/cmd_save.sh" >> "$BATS_TEST_TMPDIR/path_guard.sh"
  mkdir -p "$WORK/future" "$BATS_TEST_TMPDIR/stale-repo"
  local origin_block=$'project: infra
acceptance_criteria:
  - description: scripts/new_origin.sh'

  run bash -c '
    source "$1"
    record_warn_reason() { printf "WARN:%s\n" "$1"; }
    PROJECT_DIR="$2"
    CMD_SAVE_PROJECT_WD_OVERRIDE="$3"
    CMD_BLOCK_PROJECT=infra
    CMD_BLOCK="$4"
    CMD_BLOCK_NC="$CMD_BLOCK"
    check_ac_file_paths
  ' _ "$BATS_TEST_TMPDIR/path_guard.sh" "$WORK" "$BATS_TEST_TMPDIR/stale-repo" "$origin_block"
  [ "$status" -eq 0 ]
  [[ "$output" == *"origin treeの親ディレクトリ"* ]]
  [[ "$output" != *"WARN:"* ]]

  local planned_block=$'project: infra
planned_paths:
  - future/new_planned.sh
acceptance_criteria:
  - description: future/new_planned.sh'
  run bash -c '
    source "$1"
    record_warn_reason() { printf "WARN:%s\n" "$1"; }
    PROJECT_DIR="$2"
    CMD_SAVE_PROJECT_WD_OVERRIDE="$3"
    CMD_BLOCK_PROJECT=infra
    CMD_BLOCK="$4"
    CMD_BLOCK_NC="$CMD_BLOCK"
    check_ac_file_paths
  ' _ "$BATS_TEST_TMPDIR/path_guard.sh" "$WORK" "$BATS_TEST_TMPDIR/stale-repo" "$planned_block"
  [ "$status" -eq 0 ]
  [[ "$output" == *"planned_paths"* ]]
  [[ "$output" != *"WARN:"* ]]
}

# test_necessity: LG020が測定値だけを要求し、HTTP/ISO/RFC/path/cmd識別子を
# 算出値として誤認しない不変量を固定する。
@test "LG020 excludes protocol dates paths and cmd identifiers" {
  awk '
    /^extract_lg020_numeric_claims\(\)/ { emit=1 }
    emit && /^count_acceptance_criteria_items\(\)/ { exit }
    emit { print }
  ' "$REPO_ROOT/scripts/cmd_save.sh" > "$BATS_TEST_TMPDIR/lg020.sh"
  run bash -c '
    source "$1"
    extract_lg020_numeric_claims
  ' _ "$BATS_TEST_TMPDIR/lg020.sh" <<'EOF'
HTTP status 404, RFC 9421, 2026-09-03T13:40:00Z, /2/tweets, cmd_4473
実測値 300件
EOF
  [ "$status" -eq 0 ]
  [ "$output" = "実測値 300件" ]
}

# test_necessity: measurement_sourceのURL/timestamp/log識別子を最初のcolonで
# 切断せず、production evidence判定へ完全な値を渡す不変量を固定する。
@test "PD-104 preserves measurement_source after the first colon" {
  awk '
    /^check_production_measurement_source\(\)/ { emit=1 }
    emit && /^check_rule_doc_sync_contract\(\)/ { exit }
    emit { print }
  ' "$REPO_ROOT/scripts/cmd_save.sh" > "$BATS_TEST_TMPDIR/pd104.sh"
  run bash -c '
    trim_inline_yaml_scalar() { printf "%s" "$1" | sed -E "s/^[[:space:]]+//; s/[[:space:]]+$//; s/^\\\"//; s/\\\"$//"; }
    record_block_reason() { printf "BLOCK:%s\n" "$1"; }
    source "$1"
    check_production_measurement_source "$2"
  ' _ "$BATS_TEST_TMPDIR/pd104.sh" $'本番ボトルネックを実測
measurement_source: "production log https://example.test/run:8443/evidence:abc timestamp 2026-09-03T13:40:00Z"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# test_necessity: production_proof/detectは検証フェーズとしてphase mixingから
# 除外し、同一cmd再保存の同一WARNを一度しか数えない不変量を固定する。
@test "phase mixing excludes production proof and dedupes same cmd warning" {
  awk '
    /^check_ac_phase_mixing\(\)/ { emit=1 }
    emit && /^check_ac_test_scope\(\)/ { exit }
    emit { print }
  ' "$REPO_ROOT/scripts/cmd_save.sh" > "$BATS_TEST_TMPDIR/phase.sh"
  run bash -c '
    extract_acceptance_criteria_block() { printf "%s\n" "$CMD_BLOCK_NC"; }
    WARN_COUNT=0
    record_warn_reason() { WARN_COUNT=$((WARN_COUNT + 1)); }
    source "$1"
    CMD_BLOCK_NC=$'"'"'acceptance_criteria:
  - description: implement gate; production_proof: detect and measure after deploy'"'"'
    check_ac_phase_mixing
    printf "warn=%s\n" "$WARN_COUNT"
  ' _ "$BATS_TEST_TMPDIR/phase.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"warn=0"* ]]
  [[ "$output" != *"WARN:"* ]]

  awk '
    /^build_warn_note\(\)/ { emit=1 }
    emit && /^warn_q5_pair_missing_session_state\(\)/ { exit }
    emit { print }
  ' "$REPO_ROOT/scripts/cmd_save.sh" > "$BATS_TEST_TMPDIR/warn.sh"
  run bash -c '
    WARN_REASONS=(); WARN_COUNT=0; declare -A WARN_KEYS_SEEN=(); CMD_ID=cmd_same
    count_same_warn_pattern() { (( WARN_COUNT > 0 )) && printf "%s" "$CMD_ID" || true; }
    source "$1"
    record_warn_reason ac_phase_mixing check=check_ac_phase_mixing
    record_warn_reason ac_phase_mixing check=check_ac_phase_mixing
    printf "warn=%s reasons=%s\n" "$WARN_COUNT" "${#WARN_REASONS[@]}"
  ' _ "$BATS_TEST_TMPDIR/warn.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "warn=1 reasons=1" ]
}
