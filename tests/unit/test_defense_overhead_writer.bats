#!/usr/bin/env bats

setup() {
  export TEST_TMP="$(mktemp -d)"
  export DEFENSE_OVERHEAD_LEDGER="$TEST_TMP/events.jsonl"
  source "$BATS_TEST_DIRNAME/../../scripts/lib/defense_overhead_writer.sh"
}

teardown() { rm -rf "$TEST_TMP"; }

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

@test "production callers source and invoke the common async writer" {
  run grep -c 'defense_overhead_write_async' scripts/deploy_task.sh
  [ "$status" -eq 0 ] && [ "$output" -ge 1 ]
  run grep -c 'defense_overhead_write_async' scripts/gates/gate_gunshi_report_precheck.sh
  [ "$status" -eq 0 ] && [ "$output" -ge 1 ]
}
