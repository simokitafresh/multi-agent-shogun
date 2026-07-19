#!/usr/bin/env bats
# test_necessity: 三検索経路の実traversalだけを受理し、形式origin・不存在link・重複を拒否して0hopをexactly-once ready候補化する契約。

@test "three routes persist and validate traversal without loss duplicate FP or FN" {
  t="$BATS_TEST_TMPDIR"; printf 'snapshots: []\n' > "$t/loop.yml"; printf 'detectors: []\n' > "$t/fp.yml"; printf 'insights: []\n' > "$t/ins.yml"
  s="$BATS_TEST_DIRNAME/../../scripts/throughput_scan.sh"
  THROUGHPUT_SCAN_TRAVERSAL_LEDGER="$t/traversal.yml" bash "$s" --record-traversal preflight e1 A B f1 C '[[A]] -> [[B]] -> [[C]]' A,B,C
  THROUGHPUT_SCAN_TRAVERSAL_LEDGER="$t/traversal.yml" bash "$s" --record-traversal semantic_search e2 D E f2 F '[[D]] -> [[E]] -> [[F]]' D,E,F
  THROUGHPUT_SCAN_TRAVERSAL_LEDGER="$t/traversal.yml" bash "$s" --record-traversal causal_backlinks e3 G H f3 I '[[G]] -> [[H]] -> [[I]]' G,H,I
  THROUGHPUT_SCAN_TRAVERSAL_LEDGER="$t/traversal.yml" bash "$s" --record-traversal causal_backlinks e3 G H dup I '[[G]] -> [[H]] -> [[I]]' G,H,I
  run env THROUGHPUT_SCAN_TRAVERSAL_LEDGER="$t/traversal.yml" bash "$s" --record-traversal preflight bad X Y formal Z '[[one]] -> [[two]] -> [[three]]' X
  [ "$status" -ne 0 ]
  run bash "$BATS_TEST_DIRNAME/../../scripts/throughput_scan.sh" --dry-run --loop-ledger "$t/loop.yml" --fp-ledger "$t/fp.yml" --insights "$t/ins.yml" --gate-metrics "$t/gate.log" --traversal-ledger "$t/traversal.yml"
  [ "$status" -eq 0 ]; [[ "$output" == *"accepted=3 rejected=0 duplicate=0 traversal=3/3 discovery=3/3 action=3/3"* ]]; [[ "$output" == *"THROUGHPUT_SCAN_NONE"* ]]
}

@test "valid zero hop becomes one priority ready candidate" {
  t="$BATS_TEST_TMPDIR/z"; mkdir -p "$t"; printf 'snapshots: []\n' > "$t/loop"; printf 'detectors: []\n' > "$t/fp"; printf 'insights: []\n' > "$t/ins"
  printf "events:\n- {event_id: z1, route: preflight, landing_node: A, adjacent_node: B, finding: f, connected_action: C, hop_count: 0, origin: '[[A]] -> [[B]] -> [[C]]', existing_links: [A, B, C]}\n" > "$t/tr"
  run bash "$BATS_TEST_DIRNAME/../../scripts/throughput_scan.sh" --dry-run --loop-ledger "$t/loop" --fp-ledger "$t/fp" --insights "$t/ins" --gate-metrics "$t/g" --traversal-ledger "$t/tr"
  [ "$status" -eq 0 ]; [[ "$output" == *"candidates=1 queued=1 duplicates=0"* ]]
}
