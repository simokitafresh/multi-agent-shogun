#!/usr/bin/env bats
# test_cmd_save_block_time_nazenaze.bats — AC1: BLOCK時間コスト計測, AC2: 同一check3回なぜなぜ強制

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    export QUALITY_LOG_SCRIPT="$PROJECT_ROOT/scripts/cmd_quality_log.sh"
    [ -f "$SAVE_SCRIPT" ] || return 1
    [ -f "$QUALITY_LOG_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
    export TEST_QUEUE="$TEST_TMPDIR/shogun_to_karo.yaml"
    export TEST_ARCHIVE_DIR="$TEST_TMPDIR/archive"
    export TEST_QUALITY_LOG="$TEST_TMPDIR/cmd_design_quality.yaml"
    export TEST_LOCK="$TEST_TMPDIR/shogun_to_karo.lock"
    export TEST_LAST_CMD="$TEST_TMPDIR/cmd_save_last_cmd.txt"
    export TEST_SHOGUN_LESSONS="$TEST_TMPDIR/lessons_shogun.yaml"
    export TEST_PREFLIGHT_AUTOLEARN="$TEST_TMPDIR/preflight_autolearn.txt"
    export TEST_LORD_CONVERSATION="$TEST_TMPDIR/lord_conversation.jsonl"
    export TEST_CMD_CHRONICLE="$TEST_TMPDIR/cmd-chronicle.md"
    export TEST_BULLETIN="$TEST_TMPDIR/bulletin_board.yaml"
    export TEST_MEMORY_DB="$TEST_TMPDIR/data/memory.db"
    export TEST_Q11_RESEARCH_DIR="$TEST_TMPDIR/docs/research"
    export TEST_INSIGHTS="$TEST_TMPDIR/insights.yaml"
    mkdir -p "$TEST_ARCHIVE_DIR" "$TEST_Q11_RESEARCH_DIR"
    printf '%s\n' '[]' > "$TEST_INSIGHTS"
    # Clean up any stale block start file
    rm -f "$TEST_TMPDIR/cmd_save_block_start_cmd_btn_test.ts"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
    rm -f "$TEST_TMPDIR/cmd_save_block_start_cmd_btn_test.ts"
}

write_cmd_yaml_block() {
    # Missing q11 → guaranteed BLOCK
    local extra="${1:-}"
    cat > "$TEST_QUEUE" <<YAML
commands:
  cmd_btn_test:
    id: cmd_btn_test
    title: "infra — block time nazenaze test"
    project: infra
    depends_on: none
    origin: "[[cmd_3243]] [[block_time_test]]"
    command: "テスト用cmd"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow"
      q5_verified_source: "code_reading + isolated_test"
      q6_not_hiding: "no"
      q7_definition_verified: "yes"
      q8_why_what: "WHY: テスト WHAT: テスト WHEN: テスト WHERE: テスト WHO: テスト HOW: テスト。複利: 正の複利"
      q10_knowledge_boundary: "test scope"
      q_ambiguity: "none"
${extra}
    assumptions:
      - claim: "テスト用"
        source: "test"
        trust: "verified"
YAML
}

write_cmd_yaml_pass() {
    cat > "$TEST_QUEUE" <<YAML
commands:
  cmd_btn_test:
    id: cmd_btn_test
    title: "infra — block time nazenaze test"
    project: infra
    depends_on: none
    origin: "[[cmd_3243]] [[block_time_test]]"
    command: "テスト用cmd"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow"
      q5_verified_source: "code_reading + isolated_test"
      q6_not_hiding: "no"
      q7_definition_verified: "yes"
      q8_why_what: "WHY: テスト WHAT: テスト WHEN: テスト WHERE: テスト WHO: テスト HOW: テスト。複利: 正の複利"
      q10_knowledge_boundary: "test scope"
      q11_not_already_done: "no — 既存で対処済みの施策ではない"
      q12_lord_30min_cost: "no"
      q_ambiguity: "none"
      diagnosis: "BLOCK理由: q11未記入 対策: q11追加"
      environment_change: "type=gate; file=scripts/cmd_save.sh; pattern=BLOCK_START_FILE"
    assumptions:
      - claim: "テスト用"
        source: "test"
        trust: "verified"
YAML
}

run_cmd_save() {
    run env \
        CMD_SAVE_QUEUE_FILE="$TEST_QUEUE" \
        CMD_SAVE_ARCHIVE_CMD_DIR="$TEST_ARCHIVE_DIR" \
        CMD_QUALITY_LOG_FILE="$TEST_QUALITY_LOG" \
        CMD_SAVE_LOCK_FILE="$TEST_LOCK" \
        CMD_SAVE_LAST_CMD_FILE="$TEST_LAST_CMD" \
        CMD_SAVE_SHOGUN_LESSONS_FILE="$TEST_SHOGUN_LESSONS" \
        CMD_SAVE_PREFLIGHT_AUTOLEARN_FILE="$TEST_PREFLIGHT_AUTOLEARN" \
        CMD_SAVE_LORD_CONVERSATION_FILE="$TEST_LORD_CONVERSATION" \
        CMD_SAVE_CMD_CHRONICLE_FILE="$TEST_CMD_CHRONICLE" \
        CMD_SAVE_BULLETIN_FILE="$TEST_BULLETIN" \
        CMD_SAVE_INSIGHTS_FILE="$TEST_INSIGHTS" \
        CMD_SAVE_SEMANTIC_SEARCH_SCRIPT="$TEST_TMPDIR/no_semantic_search.sh" \
        CMD_SAVE_BLOCK_DIR="$TEST_TMPDIR" \
        CMD_SAVE_Q11_RESEARCH_DIR="$TEST_Q11_RESEARCH_DIR" \
        CMD_SAVE_SYNC_QUALITY_LOG=1 \
        MEMORY_DB_LIVE_INSERT="$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
        SHOGUN_MEMORY_DB="$TEST_MEMORY_DB" \
        CMD_QUALITY_FAST_METADATA=1 \
        bash "$SAVE_SCRIPT" cmd_btn_test
}

@test "AC1: BLOCK時にblock_start_fileが作成される" {
    write_cmd_yaml_block ""

    run_cmd_save
    echo "$output" >&2
    [ "$status" -eq 1 ]

    # BLOCK start timestamp file should exist
    [ -f "$TEST_TMPDIR/cmd_save_block_start_cmd_btn_test.ts" ]
    # Content should be epoch seconds
    local ts
    ts=$(cat "$TEST_TMPDIR/cmd_save_block_start_cmd_btn_test.ts")
    [[ "$ts" =~ ^[0-9]+$ ]]
}

@test "AC1: PASS時にblock_duration_minutesがquality_logに記録される" {
    # First: BLOCK to create timestamp
    write_cmd_yaml_block ""
    run_cmd_save
    [ "$status" -eq 1 ]
    [ -f "$TEST_TMPDIR/cmd_save_block_start_cmd_btn_test.ts" ]

    # Manipulate timestamp to simulate 3 minutes ago
    local now_epoch
    now_epoch=$(date +%s)
    echo $(( now_epoch - 180 )) > "$TEST_TMPDIR/cmd_save_block_start_cmd_btn_test.ts"

    # Now PASS
    write_cmd_yaml_pass
    run_cmd_save
    echo "$output" >&2
    [ "$status" -eq 0 ]

    # block start file should be cleaned up
    [ ! -f "$TEST_TMPDIR/cmd_save_block_start_cmd_btn_test.ts" ]

    # Quality log should have PASS entry with block_duration_minutes
    run python3 - <<'PY'
import os
import yaml

with open(os.environ["TEST_QUALITY_LOG"], encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

entries = data.get("entries", [])
pass_entries = [
    e for e in entries
    if e.get("cmd_id") == "cmd_btn_test"
    and e.get("gate_result") == "PASS"
    and e.get("source") == "cmd_save"
]
assert len(pass_entries) >= 1, f"No PASS entries found: {entries}"
last_pass = pass_entries[-1]
duration = last_pass.get("block_duration_minutes", 0)
assert duration >= 2, f"Expected duration >= 2 minutes, got: {duration}. Entry: {last_pass}"
PY
    echo "$output" >&2
    [ "$status" -eq 0 ]
}

@test "AC1: BLOCKログにchecksフィールドが記録される" {
    write_cmd_yaml_block ""

    run_cmd_save
    echo "$output" >&2
    [ "$status" -eq 1 ]

    # Quality log should have BLOCK entry with checks field
    run python3 - <<'PY'
import os
import yaml

log_path = os.environ["TEST_QUALITY_LOG"]
if not os.path.exists(log_path):
    print(f"Quality log not found: {log_path}")
    raise SystemExit(1)

with open(log_path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

entries = data.get("entries", [])
block_entries = [
    e for e in entries
    if e.get("cmd_id") == "cmd_btn_test"
    and e.get("gate_result") == "BLOCK"
    and e.get("source") == "cmd_save"
]
assert len(block_entries) >= 1, f"No BLOCK entries found: {entries}"
last_block = block_entries[-1]
checks = last_block.get("checks", "")
assert checks, f"checks field is empty. Entry: {last_block}"
PY
    echo "$output" >&2
    [ "$status" -eq 0 ]
}

@test "AC2: 同一checkで3回BLOCKするとnazenaze_root_cause要求" {
    write_cmd_yaml_block ""

    # Pre-seed quality log with 2 prior BLOCKs from the same check
    cat > "$TEST_QUALITY_LOG" <<'YAML'
entries:
- cmd_id: "cmd_btn_test"
  ac_count: 0
  gate_result: "BLOCK"
  karo_rework: "no"
  gunshi_verdict: "unknown"
  ninja_blockers: 0
  project: "infra"
  supplementary_cmds: 0
  source: "cmd_save"
  timestamp: "2026-06-08T10:00:00Z"
  checks: "check_required_quality_gate_keys_block"
  notes: "必須項目 1件 未記入"
- cmd_id: "cmd_btn_test"
  ac_count: 0
  gate_result: "BLOCK"
  karo_rework: "no"
  gunshi_verdict: "unknown"
  ninja_blockers: 0
  project: "infra"
  supplementary_cmds: 0
  source: "cmd_save"
  timestamp: "2026-06-08T10:05:00Z"
  checks: "check_required_quality_gate_keys_block"
  notes: "必須項目 1件 未記入"
YAML

    run_cmd_save
    echo "$output" >&2
    [ "$status" -eq 1 ]

    # Should contain nazenaze requirement message
    [[ "$output" == *"nazenaze_root_cause"* ]]
    [[ "$output" == *"3回目BLOCK"* ]]
}

@test "AC2: nazenaze_root_cause記入済みなら追加BLOCKなし" {
    # Pre-seed quality log with 2 prior BLOCKs
    cat > "$TEST_QUALITY_LOG" <<'YAML'
entries:
- cmd_id: "cmd_btn_test"
  ac_count: 0
  gate_result: "BLOCK"
  karo_rework: "no"
  gunshi_verdict: "unknown"
  ninja_blockers: 0
  project: "infra"
  supplementary_cmds: 0
  source: "cmd_save"
  timestamp: "2026-06-08T10:00:00Z"
  checks: "cmd_save_main"
  notes: "必須項目 1件 未記入"
- cmd_id: "cmd_btn_test"
  ac_count: 0
  gate_result: "BLOCK"
  karo_rework: "no"
  gunshi_verdict: "unknown"
  ninja_blockers: 0
  project: "infra"
  supplementary_cmds: 0
  source: "cmd_save"
  timestamp: "2026-06-08T10:05:00Z"
  checks: "cmd_save_main"
  notes: "必須項目 1件 未記入"
YAML

    # Write cmd YAML with nazenaze_root_cause filled (but still missing q11)
    write_cmd_yaml_block '      nazenaze_root_cause: "なぜ1→なぜ2→根因: q11確認フロー不在→仕組み: preflight自動チェック"
'

    run_cmd_save
    echo "$output" >&2
    [ "$status" -eq 1 ]

    # Should NOT contain nazenaze requirement (it's already filled)
    [[ "$output" != *"nazenaze_root_cause にn"* ]] || {
        echo "FAIL: nazenaze_root_cause is filled but still required" >&2
        return 1
    }
}
