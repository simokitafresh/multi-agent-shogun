#!/usr/bin/env bats
# test_necessity: Self-retro preserves durable telemetry while suppressing only known zero-signal insight delivery.

setup() {
  export TEST_TMP="$(mktemp -d)"
  export DEFENSE_OVERHEAD_LEDGER="$TEST_TMP/events.jsonl"
  source "$BATS_TEST_DIRNAME/../../scripts/lib/defense_overhead_writer.sh"
}

teardown() {
  self_retro_drain
  rm -rf "$TEST_TMP"
}

@test "writes required schema and rejects invalid or duplicate events" {
  run defense_overhead_write deploy_task deploy_total 17 PASS evt-1
  [ "$status" -eq 0 ]
  run defense_overhead_write 'bad source' deploy_total 17 PASS evt-2
  [ "$status" -eq 2 ]
  run defense_overhead_write deploy_task deploy_total 17 PASS evt-1
  [ "$status" -eq 4 ]
  python3 - "$DEFENSE_OVERHEAD_LEDGER" <<'PY'
import json, sys
rows=[json.loads(x) for x in open(sys.argv[1])]
assert len(rows)==1
assert set(rows[0])=={'timestamp','source','check_id','wall_ms','verdict','event_id'}
PY
}

@test "twenty concurrent events are complete unique parseable and classify exactly" {
  for i in $(seq 1 20); do
    defense_overhead_write test check "$i" "$([ $((i%2)) -eq 0 ] && echo PASS || echo FAIL)" "evt-$i" &
  done
  wait
  python3 - "$DEFENSE_OVERHEAD_LEDGER" <<'PY'
import json, sys
rows=[json.loads(x) for x in open(sys.argv[1])]
assert len(rows)==20 and len({r['event_id'] for r in rows})==20
assert sum(r['verdict']=='PASS' for r in rows)==10
assert sum(r['verdict']=='FAIL' for r in rows)==10
PY
}

@test "disabled and unwritable async writer preserve caller contract" {
  DEFENSE_OVERHEAD_ENABLED=0
  run bash -c 'source scripts/lib/defense_overhead_writer.sh; defense_overhead_write_async x y 1 PASS e; printf preserved'
  [ "$status" -eq 0 ] && [ "$output" = preserved ]
  DEFENSE_OVERHEAD_ENABLED=1 DEFENSE_OVERHEAD_LEDGER=/proc/forbidden/events.jsonl
  run bash -c 'source scripts/lib/defense_overhead_writer.sh; defense_overhead_write_async x y 1 FAIL e; printf preserved'
  [ "$status" -eq 0 ] && [ "$output" = preserved ]
}

@test "batch async writer emits complete unique events through one caller" {
  defense_overhead_write_batch_async test one 1 PASS batch-1 test two 2 BLOCK batch-2
  for _ in $(seq 1 100); do
    [ -f "$DEFENSE_OVERHEAD_LEDGER" ] && [ "$(wc -l < "$DEFENSE_OVERHEAD_LEDGER")" -eq 2 ] && break
    sleep 0.02
  done
  python3 - "$DEFENSE_OVERHEAD_LEDGER" <<'PY'
import json, sys
rows=[json.loads(x) for x in open(sys.argv[1])]
assert len(rows)==2 and {r['event_id'] for r in rows}=={'batch-1','batch-2'}
assert {r['verdict'] for r in rows}=={'PASS','BLOCK'}
PY
}

@test "production callers source and invoke the common async writer" {
  run grep -c 'defense_overhead_write_async' scripts/deploy_task.sh
  [ "$status" -eq 0 ] && [ "$output" -ge 1 ]
  run grep -c 'defense_overhead_write_async' scripts/gates/gate_gunshi_report_precheck.sh
  [ "$status" -eq 0 ] && [ "$output" -ge 1 ]
  run grep -c 'defense_overhead_write_batch_async' scripts/hooks/git-pre-commit.sh
  [ "$status" -eq 0 ] && [ "$output" -ge 1 ]
}

@test "deep self-retro is idempotent, backward compatible, and falls back without blocking" {
  export SELF_RETRO_LEDGER="$TEST_TMP/self-retro.jsonl"
  run self_retro_write ninja_report cmd_unit 12 '{"write":7,"delivery":5}' report_completion cause candidate criterion '[[a]] -> [[b]] -> [[c]]'
  [ "$status" -eq 0 ]
  run self_retro_write ninja_report cmd_unit 12 '{"write":7,"delivery":5}' report_completion cause candidate criterion '[[a]] -> [[b]] -> [[c]]'
  [ "$status" -eq 4 ]
  python3 - "$SELF_RETRO_LEDGER" <<'PY'
import json,sys
r=[json.loads(x) for x in open(sys.argv[1])]
assert len(r)==1 and r[0]['phase_ms']=={'write':7,'delivery':5}
assert all(r[0][k] for k in ('cause_structure','improvement_candidate','binary_criterion','origin'))
PY
  [ ! -e "$DEFENSE_OVERHEAD_LEDGER" ]
  SELF_RETRO_LEDGER=/proc/forbidden/events.jsonl
  run self_retro_write_async ninja_report cmd_fallback 9 '{"write":9}' delivery_missing cause candidate criterion '[[a]] -> [[b]] -> [[c]]'
  [ "$status" -eq 0 ]
}

@test "deep self-retro owner drains delayed async writers before teardown" {
  export SELF_RETRO_LEDGER="$TEST_TMP/self-retro.jsonl"
  self_retro_write() {
    sleep 0.05
    printf '{"done":true}\n' >"$SELF_RETRO_LEDGER"
  }
  self_retro_write_async ninja_report cmd_delayed 1 '{"write":1}' delayed cause candidate criterion '[[a]] -> [[b]] -> [[c]]'
  [ ! -e "$SELF_RETRO_LEDGER" ]
  self_retro_drain
  [ "$(cat "$SELF_RETRO_LEDGER")" = '{"done":true}' ]
  [ "${#SELF_RETRO_ASYNC_PIDS[@]}" -eq 0 ]
}

@test "all four terminal endpoints invoke detached deep self-retro" {
  run grep -c 'self_retro_write_async ninja_report' scripts/retro_write.sh; [ "$status" -eq 0 ] && [ "$output" -eq 1 ]
  run grep -c 'self_retro_write_async karo_cmd_complete' scripts/cmd_complete.sh; [ "$status" -eq 0 ] && [ "$output" -eq 1 ]
  run grep -c 'gunshi_review_bundle' scripts/review_bundle.py; [ "$status" -eq 0 ] && [ "$output" -ge 1 ]
  run grep -c 'self_retro_write_async shogun_gate_clear' scripts/cmd_complete_gate.sh; [ "$status" -eq 0 ] && [ "$output" -eq 1 ]
}

@test "dominant cause promotes a verified fix_known candidate" {
  export SELF_RETRO_LEDGER="$TEST_TMP/self-retro.jsonl"
  export DEFENSE_OVERHEAD_REPO_ROOT="$TEST_TMP/root"
  mkdir -p "$DEFENSE_OVERHEAD_REPO_ROOT/scripts"
  printf '#!/bin/bash\nprintf "%%s|%%s|%%s\\n" "$INSIGHT_FIX_KNOWN" "$INSIGHT_TARGET_FILE" "$INSIGHT_VERIFY_COMMAND" >>"%s"\n' "$TEST_TMP/insight.calls" >"$DEFENSE_OVERHEAD_REPO_ROOT/scripts/insight_write.sh"
  chmod +x "$DEFENSE_OVERHEAD_REPO_ROOT/scripts/insight_write.sh"
  SELF_RETRO_FIX_KNOWN_THRESHOLD=2 self_retro_write ninja_report cmd_one 1 '{"write":1}' repeated cause candidate criterion '[[a]] -> [[b]] -> [[c]]'
  SELF_RETRO_FIX_KNOWN_THRESHOLD=2 self_retro_write ninja_report cmd_two 1 '{"write":1}' repeated cause candidate criterion '[[a]] -> [[b]] -> [[c]]'
  SELF_RETRO_FIX_KNOWN_THRESHOLD=2 self_retro_write ninja_report cmd_three 1 '{"write":1}' singleton cause candidate criterion '[[a]] -> [[b]] -> [[c]]'
  run grep -c '^true|' "$TEST_TMP/insight.calls"
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]
  run python3 - "$SELF_RETRO_LEDGER" <<'PY'
import json,sys
r=[json.loads(x) for x in open(sys.argv[1])]
assert len(r)==3
assert sum(x['cause_class']=='repeated' for x in r)==2
assert sum(x['cause_class']=='singleton' for x in r)==1
PY
  [ "$status" -eq 0 ]
}

@test "known zero-signal template is recorded but not delivered while measured signal is delivered" {
  export SELF_RETRO_LEDGER="$TEST_TMP/self-retro.jsonl"
  export DEFENSE_OVERHEAD_REPO_ROOT="$TEST_TMP/root"
  mkdir -p "$DEFENSE_OVERHEAD_REPO_ROOT/scripts"
  printf '#!/bin/bash\nprintf "%%s\\n" "$1" >>"%s"\n' "$TEST_TMP/insight.calls" >"$DEFENSE_OVERHEAD_REPO_ROOT/scripts/insight_write.sh"
  chmod +x "$DEFENSE_OVERHEAD_REPO_ROOT/scripts/insight_write.sh"

  SELF_RETRO_FIX_KNOWN_THRESHOLD=2 self_retro_write ninja_report cmd_zero_one 0 '{"write":0}' repeated cause template criterion '[[a]] -> [[b]] -> [[c]]'
  SELF_RETRO_FIX_KNOWN_THRESHOLD=2 self_retro_write ninja_report cmd_zero_two 0 '{"write":0}' repeated cause template criterion '[[a]] -> [[b]] -> [[c]]'
  [ ! -e "$TEST_TMP/insight.calls" ]

  SELF_RETRO_FIX_KNOWN_THRESHOLD=2 self_retro_write ninja_report cmd_signal_one 8 '{"write":8}' measured cause template criterion '[[a]] -> [[b]] -> [[c]]'
  SELF_RETRO_FIX_KNOWN_THRESHOLD=2 self_retro_write ninja_report cmd_signal_two 9 '{"write":9}' measured cause template criterion '[[a]] -> [[b]] -> [[c]]'
  run grep -c 'self-retro dominant cause=measured' "$TEST_TMP/insight.calls"
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  run python3 - "$SELF_RETRO_LEDGER" <<'PY'
import json,sys
rows=[json.loads(x) for x in open(sys.argv[1])]
assert len(rows) == 4
assert sum(r['wall_ms'] == 0 for r in rows) == 2
assert sum(r['wall_ms'] > 0 for r in rows) == 2
PY
  [ "$status" -eq 0 ]
}
