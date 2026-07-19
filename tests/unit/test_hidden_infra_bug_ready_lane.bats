#!/usr/bin/env bats

# test_necessity: 4ログ由来の未処理異常が優先度付きready eventへexactly-once昇格する不変量
setup() {
  ROOT=$(mktemp -d "$BATS_TEST_DIRNAME/.hidden-infra.XXXXXX")
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/throughput_growth_loop.sh"
  printf '%s\n' '{"operation":"cmd_save","wall_ms":1800,"role":"shogun","frequency":2}' >"$ROOT/defense.jsonl"
  printf '%s\n' '{"root_cause":"retry-loop","retry_count":2,"role":"karo","count":3}' >"$ROOT/retro.jsonl"
  printf '%s\n' '{"reason":"delivery-lost","status":"failed","actor":"karo","count":2}' >"$ROOT/bulletin.jsonl"
  printf '%s\n' '{"gate":"warning-detector","false_positive":true,"role":"shogun","frequency":1}' >"$ROOT/gate.jsonl"
}
teardown() { rm -r "$ROOT"; }

@test "four sources become one prioritized ready event exactly once" {
  run bash "$SCRIPT" --promote-hidden-infra --defense-overhead "$ROOT/defense.jsonl" --retro-events "$ROOT/retro.jsonl" --bulletin-notify-failures "$ROOT/bulletin.jsonl" --gate-fire-log "$ROOT/gate.jsonl" --ready-ledger "$ROOT/ready.jsonl" --output "$ROOT/event.json"
  [ "$status" -eq 0 ]
  run python3 - "$ROOT/event.json" "$ROOT/ready.jsonl" <<'PY'
import json,sys
e=json.load(open(sys.argv[1])); ledger=[json.loads(x) for x in open(sys.argv[2])]
assert e["state"]=="READY" and len(e["candidates"])==4
assert len({c["source"] for c in e["candidates"]})==4
assert len({c["root_cause_signature"] for c in e["candidates"]})==4
assert [c["priority"] for c in e["candidates"]]==sorted([c["priority"] for c in e["candidates"]],reverse=True)
assert len(ledger)==4 and len({x["root_cause_signature"] for x in ledger})==4
PY
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" --promote-hidden-infra --defense-overhead "$ROOT/defense.jsonl" --retro-events "$ROOT/retro.jsonl" --bulletin-notify-failures "$ROOT/bulletin.jsonl" --gate-fire-log "$ROOT/gate.jsonl" --ready-ledger "$ROOT/ready.jsonl" --output "$ROOT/event2.json"
  [ "$status" -eq 4 ]
  [[ "$output" == *"BLOCK hidden_infra_no_unprocessed_candidate"* ]]
  [ ! -e "$ROOT/event2.json" ]
  [ "$(wc -l <"$ROOT/ready.jsonl")" -eq 4 ]
}
