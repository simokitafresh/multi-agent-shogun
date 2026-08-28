#!/usr/bin/env bats

# test_necessity: PD-104/107/110/114/135の実装境界が、
# 本番計測source・入力分類・revert順序・意味registry・memory/loop計測へ
# 接続され、直接経路や更新不要例を誤検出しない不変量を固定する。

setup() {
  ROOT="$BATS_TEST_DIRNAME/../.."
  ROOT="$(cd "$ROOT" && pwd)"
}

@test "PD-104 production measurement source blocks missing/local evidence" {
  guard="$BATS_TEST_TMPDIR/measurement.sh"
  awk '/^check_production_measurement_source\(\)/,/^}/' "$ROOT/scripts/cmd_save.sh" > "$guard"

  run bash -c '
    source "$1"
    record_block_reason() { printf "BLOCK_REASON=%s\n" "$1"; }
    check_production_measurement_source "$2"
  ' _ "$guard" $'purpose: production bottleneck claim
acceptance_criteria: measure production'
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCK(PD-104)"* ]]

  run bash -c '
    source "$1"
    record_block_reason() { printf "BLOCK_REASON=%s\n" "$1"; }
    check_production_measurement_source "$2"
  ' _ "$guard" $'purpose: production bottleneck claim
measurement_source: local'
  [ "$status" -eq 0 ]
  [[ "$output" == *"local-only"* ]]

  run bash -c '
    source "$1"
    record_block_reason() { printf "BLOCK_REASON=%s\n" "$1"; }
    check_production_measurement_source "$2"
  ' _ "$guard" $'purpose: production bottleneck claim
measurement_source: Render production receipt run-123'
  [ "$status" -eq 0 ]
  [[ "$output" != *"BLOCK(PD-104)"* ]]
}

@test "PD-107 terminal producer labels task notifications without changing Lord input" {
  fixture="$BATS_TEST_TMPDIR/log-input"
  mkdir -p "$fixture/scripts" "$fixture/lib" "$fixture/queue"
  cp "$ROOT/scripts/log_terminal_input.sh" "$fixture/scripts/"
  cp "$ROOT/lib/lord_conversation.sh" "$fixture/lib/"
  cat > "$fixture/tmux" <<'SH'
#!/usr/bin/env bash
printf 'kotaro\n'
SH
  chmod +x "$fixture/tmux"
  export PATH="$fixture:$PATH"
  export TMUX_PANE=kotaro
  export LORD_CONVERSATION_DB="$fixture/missing.db"

  run bash -c 'printf %s "$1" | bash "$2/scripts/log_terminal_input.sh"' _ \
    '{"prompt":"<task-notification>build finished</task>","source_event_id":"evt-task"}' "$fixture"
  [ "$status" -eq 0 ]
  run python3 - "$fixture/queue/lord_conversation.jsonl" <<'PY'
import json, sys
row = json.loads(open(sys.argv[1], encoding='utf-8').readline())
assert row['source'] == 'task-notification', row
assert row['agent'] == 'system', row
print('TASK_NOTIFICATION_CLASSIFIED')
PY
  [ "$status" -eq 0 ]
  [ "$output" = "TASK_NOTIFICATION_CLASSIFIED" ]

  rm -f "$fixture/queue/lord_conversation.jsonl" "$fixture/queue/lord_conversation_consumed.tsv"
  run bash -c 'printf %s "$1" | bash "$2/scripts/log_terminal_input.sh"' _ \
    '{"prompt":"殿の実入力","source_event_id":"evt-lord"}' "$fixture"
  [ "$status" -eq 0 ]
  run python3 - "$fixture/queue/lord_conversation.jsonl" <<'PY'
import json, sys
row = json.loads(open(sys.argv[1], encoding='utf-8').readline())
assert row['source'] == 'terminal', row
assert row['agent'] == 'lord', row
print('LORD_INPUT_PRESERVED')
PY
  [ "$status" -eq 0 ]
  [ "$output" = "LORD_INPUT_PRESERVED" ]
}

@test "PD-110 direct revert is blocked and wrapper records post-revert measurement" {
  run bash "$ROOT/scripts/gates/gate_revert_contract.sh" check "git revert abcdef1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"direct git revert is not allowed"* ]]

  payload='{"tool_name":"Bash","tool_input":{"command":"git revert abcdef1"}}'
  run bash -c 'printf %s "$1" | bash "$2/scripts/hooks/block_destructive.sh"' _ "$payload" "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PD-110"* ]]

  run bash "$ROOT/scripts/gates/gate_revert_contract.sh" check "git status --short"
  [ "$status" -eq 0 ]

  repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo/scripts/gates"
  cp "$ROOT/scripts/revert_with_receipt.sh" "$repo/scripts/"
  cp "$ROOT/scripts/gates/gate_revert_contract.sh" "$repo/scripts/gates/"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name Fixture
  printf old > "$repo/value"
  git -C "$repo" add value && git -C "$repo" commit -qm baseline
  target="$(git -C "$repo" rev-parse HEAD)"
  printf new > "$repo/value"
  git -C "$repo" add value && git -C "$repo" commit -qm change
  target="$(git -C "$repo" rev-parse HEAD)"

  run env REVERT_MEASURE_COMMAND='printf measured > measurement.txt' \
    bash "$repo/scripts/revert_with_receipt.sh" "$target" "contract test" "$repo"
  [ "$status" -eq 0 ]
  grep -q measured "$repo/measurement.txt"
  grep -q "measurement_rc.*0" "$repo/logs/revert_receipts.jsonl"
}

@test "PD-114 resolves semantic/context mapping and allows unrelated no-update changes" {
  run bash "$ROOT/scripts/gates/gate_rule_doc_sync.sh" scripts/cmd_save.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"MAP source=scripts/cmd_save.sh"* ]]
  [[ "$output" == *"contexts=context/infrastructure.md"* ]]

  run bash "$ROOT/scripts/gates/gate_rule_doc_sync.sh" scripts/unrelated-helper.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"update not required"* ]]
}

@test "PD-135 consumes memory loop detector observations and calculates FP rate" {
  fixture="$BATS_TEST_TMPDIR/fp"
  mkdir -p "$fixture/logs"
  cat > "$fixture/logs/loop_ledger.yaml" <<'YAML'
snapshots:
  - generated_at: "2026-08-28T20:00:00+09:00"
    memory:
      detector_observations:
        - detector: memory-source
          outcome: false_positive
          reason: fixture-fp
        - detector: memory-source
          outcome: true_positive
          reason: fixture-tp
YAML
  run env DETECTOR_FP_ROOT="$fixture" \
    DETECTOR_FP_GATE_FIRE_LOG="$fixture/logs/none.yaml" \
    DETECTOR_FP_CMD_QUALITY_LOG="$fixture/logs/none.yaml" \
    DETECTOR_FP_GATE_ALERTS_LOG="$fixture/logs/none.yaml" \
    DETECTOR_FP_LOOP_LEDGER_LOG="$fixture/logs/loop_ledger.yaml" \
    DETECTOR_FP_OUT="$fixture/logs/fp.yaml" \
    bash "$ROOT/scripts/detector_fp_rate.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"loop_ledger:memory:memory-source: fp_rate=50.0% fp=1/2"* ]]
  grep -q 'loop_ledger:memory:memory-source' "$fixture/logs/fp.yaml"
}
