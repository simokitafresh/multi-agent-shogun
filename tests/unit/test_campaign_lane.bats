#!/usr/bin/env bats

setup() {
  TMPROOT="$(mktemp -d)"
  CTRL="$BATS_TEST_DIRNAME/../../skills/campaign-lane/scripts/campaign_lane.py"
}

teardown() { rm -r "$TMPROOT"; }

catalog() {
  cat > "$TMPROOT/catalog.yaml" <<'YAML'
objective: minimize
min_rounds: 2
max_rounds: 3
budget: 6
candidates:
  - {id: a, cost: 1, capability: test, independent: true}
  - {id: b, cost: 1, capability: test, independent: true}
  - {id: c, cost: 1, capability: test, independent: true}
workers:
  - {id: w1, idle: true, capabilities: [test]}
  - {id: w2, idle: true, capabilities: [test]}
  - {id: w3, idle: true, capabilities: [test]}
YAML
  : > "$TMPROOT/m.jsonl"
}

@test "validate and dynamic shard-work handoff" {
  catalog
  run python3 "$CTRL" validate "$TMPROOT/catalog.yaml" "$TMPROOT/m.jsonl"
  [ "$status" -eq 0 ]
  run python3 "$CTRL" select "$TMPROOT/catalog.yaml" "$TMPROOT/m.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"n": 3'* && "$output" == *'"skill": "shard-work"'* ]]
}

@test "duplicate target and in-flight target are blocked" {
  catalog
  echo '{"target":"a","round":1,"status":"in_flight"}' > "$TMPROOT/m.jsonl"
  run python3 "$CTRL" record "$TMPROOT/catalog.yaml" "$TMPROOT/m.jsonl" --result '{"target":"a","round":1,"status":"success","value":9,"cost":1}'
  [ "$status" -eq 2 ]
  [[ "$output" == *'duplicate or in-flight target'* ]]
}

@test "stale and malformed measurements fail closed" {
  catalog
  echo '{"target":"a","status":"success","value":10}' > "$TMPROOT/m.jsonl"
  run python3 "$CTRL" validate "$TMPROOT/catalog.yaml" "$TMPROOT/m.jsonl"
  [ "$status" -eq 2 ]
}

@test "quality fail is excluded and regression never replaces global best" {
  catalog
  printf '%s\n' '{"target":"a","round":1,"status":"success","quality":"pass","value":10,"cost":1,"improved":true}' '{"target":"b","round":1,"status":"quality_fail","quality":"fail","value":5,"cost":1,"improved":false}' '{"target":"c","round":2,"status":"success","quality":"pass","value":15,"cost":1,"improved":false}' > "$TMPROOT/m.jsonl"
  python3 "$CTRL" record "$TMPROOT/catalog.yaml" "$TMPROOT/m.jsonl" --result '{"target":"d","round":2,"status":"success","value":12,"cost":1}' > "$TMPROOT/out"
  grep -q '"improved": false' "$TMPROOT/out"
  run python3 "$CTRL" status "$TMPROOT/catalog.yaml" "$TMPROOT/m.jsonl"
  [[ "$output" == *'"best_so_far": 10'* ]]
}

@test "round best is objective-best quality pass independent of input order" {
  catalog
  printf '%s\n' '{"target":"b","round":1,"status":"success","quality":"pass","value":4.285,"cost":1,"improved":true}' '{"target":"a","round":1,"status":"success","quality":"pass","value":5.196,"cost":1,"improved":true}' > "$TMPROOT/m.jsonl"
  run python3 "$CTRL" status "$TMPROOT/catalog.yaml" "$TMPROOT/m.jsonl"
  [[ "$output" == *'"best_so_far": 4.285'* ]]
  tac "$TMPROOT/m.jsonl" > "$TMPROOT/reversed" && mv "$TMPROOT/reversed" "$TMPROOT/m.jsonl"
  run python3 "$CTRL" status "$TMPROOT/catalog.yaml" "$TMPROOT/m.jsonl"
  [[ "$output" == *'"best_so_far": 4.285'* ]]
}

@test "target reached terminates" {
  catalog
  sed -i 's/objective: minimize/objective: target\ntarget: 10/' "$TMPROOT/catalog.yaml"
  echo '{"target":"a","round":1,"status":"success","quality":"pass","value":10,"cost":1,"improved":true}' > "$TMPROOT/m.jsonl"
  run python3 "$CTRL" select "$TMPROOT/catalog.yaml" "$TMPROOT/m.jsonl"
  [[ "$output" == *'TARGET_REACHED'* ]]
}

@test "budget and max round terminate" {
  catalog
  echo '{"target":"a","round":2,"status":"failed","cost":6}' > "$TMPROOT/m.jsonl"
  run python3 "$CTRL" select "$TMPROOT/catalog.yaml" "$TMPROOT/m.jsonl"
  [[ "$output" == *'BUDGET_EXHAUSTED'* ]]
  echo '{"target":"a","round":3,"status":"failed","cost":0}' > "$TMPROOT/m.jsonl"
  run python3 "$CTRL" select "$TMPROOT/catalog.yaml" "$TMPROOT/m.jsonl"
  [[ "$output" == *'MAX_ROUNDS'* ]]
}

@test "one worker, subjective, sealed, and dependent candidates block" {
  catalog
  sed -i '/w2/,+0d; /w3/,+0d' "$TMPROOT/catalog.yaml"
  run python3 "$CTRL" select "$TMPROOT/catalog.yaml" "$TMPROOT/m.jsonl"
  [ "$status" -eq 2 ]
  catalog
  printf '\nevaluation: subjective\n' >> "$TMPROOT/catalog.yaml"
  run python3 "$CTRL" select "$TMPROOT/catalog.yaml" "$TMPROOT/m.jsonl"
  [ "$status" -eq 2 ]
  catalog
  printf '\nenvironment: production\nsealed: true\n' >> "$TMPROOT/catalog.yaml"
  run python3 "$CTRL" select "$TMPROOT/catalog.yaml" "$TMPROOT/m.jsonl"
  [ "$status" -eq 2 ]
  catalog
  sed -i '0,/independent: true/s//independent: false/' "$TMPROOT/catalog.yaml"
  run python3 "$CTRL" validate "$TMPROOT/catalog.yaml" "$TMPROOT/m.jsonl"
  [ "$status" -eq 2 ]
}
