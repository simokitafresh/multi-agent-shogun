#!/usr/bin/env bats

setup() {
  ROOT="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$ROOT/scripts/gates" "$ROOT/scripts" "$ROOT/skills/demo" "$ROOT/logs"
  cp "$BATS_TEST_DIRNAME/../../scripts/gates/gate_skill_script_refs.sh" "$ROOT/scripts/gates/"
  printf '#!/bin/sh\n' > "$ROOT/scripts/demo.sh"
  printf -- '---\nname: demo\n---\n`bash scripts/demo.sh`\n' > "$ROOT/skills/demo/SKILL.md"
  touch -d '2026-01-01' "$ROOT/skills/demo/SKILL.md"
  touch -d '2026-01-02' "$ROOT/scripts/demo.sh"
}

@test "changed script requires review then verified hash clears alert" {
  run env SKILL_REF_DISABLE_CACHE=1 SKILL_REF_DIRS=skills SKILL_REF_HASH_STATE="$ROOT/logs/state.json" bash "$ROOT/scripts/gates/gate_skill_script_refs.sh" "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"REVIEW_REQUIRED"* ]]

  run env SKILL_REF_DISABLE_CACHE=1 SKILL_REF_DIRS=skills SKILL_REF_HASH_STATE="$ROOT/logs/state.json" SKILL_REF_RECORD_VERIFIED=1 bash "$ROOT/scripts/gates/gate_skill_script_refs.sh" "$ROOT"
  [ "$status" -eq 0 ]

  printf 'echo changed-contract\n' >> "$ROOT/scripts/demo.sh"
  run env SKILL_REF_DISABLE_CACHE=1 SKILL_REF_DIRS=skills SKILL_REF_HASH_STATE="$ROOT/logs/state.json" bash "$ROOT/scripts/gates/gate_skill_script_refs.sh" "$ROOT"
  [ "$status" -eq 2 ]
}

@test "mtime-only and internal-only changes do not invalidate verified contract" {
  run env SKILL_REF_DISABLE_CACHE=1 SKILL_REF_DIRS=skills SKILL_REF_HASH_STATE="$ROOT/logs/state.json" SKILL_REF_RECORD_VERIFIED=1 bash "$ROOT/scripts/gates/gate_skill_script_refs.sh" "$ROOT"
  [ "$status" -eq 0 ]
  touch -d '2026-01-03' "$ROOT/scripts/demo.sh"
  run env SKILL_REF_DISABLE_CACHE=1 SKILL_REF_DIRS=skills SKILL_REF_HASH_STATE="$ROOT/logs/state.json" bash "$ROOT/scripts/gates/gate_skill_script_refs.sh" "$ROOT"
  [ "$status" -eq 0 ]
  printf 'internal_value=true\n' >> "$ROOT/scripts/demo.sh"
  run env SKILL_REF_DISABLE_CACHE=1 SKILL_REF_DIRS=skills SKILL_REF_HASH_STATE="$ROOT/logs/state.json" bash "$ROOT/scripts/gates/gate_skill_script_refs.sh" "$ROOT"
  [ "$status" -eq 0 ]
}

@test "CLI exit and side-effect contract changes require one deduplicated action" {
  run env SKILL_REF_DISABLE_CACHE=1 SKILL_REF_DIRS=skills SKILL_REF_HASH_STATE="$ROOT/logs/state.json" SKILL_REF_RECORD_VERIFIED=1 bash "$ROOT/scripts/gates/gate_skill_script_refs.sh" "$ROOT"
  [ "$status" -eq 0 ]
  printf 'echo changed-contract\nexit 7\ntouch "$1"\n' >> "$ROOT/scripts/demo.sh"
  run env SKILL_REF_DISABLE_CACHE=1 SKILL_REF_DIRS=skills SKILL_REF_HASH_STATE="$ROOT/logs/state.json" bash "$ROOT/scripts/gates/gate_skill_script_refs.sh" "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"required=1, deduped=0"* ]]
  run env SKILL_REF_DISABLE_CACHE=1 SKILL_REF_DIRS=skills SKILL_REF_HASH_STATE="$ROOT/logs/state.json" bash "$ROOT/scripts/gates/gate_skill_script_refs.sh" "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"required=0, deduped=1"* ]]
}

@test "corrupt contract hash state is a BLOCK" {
  printf '{broken' > "$ROOT/logs/state.json"
  run env SKILL_REF_DISABLE_CACHE=1 SKILL_REF_DIRS=skills SKILL_REF_HASH_STATE="$ROOT/logs/state.json" bash "$ROOT/scripts/gates/gate_skill_script_refs.sh" "$ROOT"
  [ "$status" -eq 3 ]
  [[ "$output" == *"state is corrupt"* ]]
}

@test "concurrent verified writers preserve valid atomic hash state" {
  env SKILL_REF_DISABLE_CACHE=1 SKILL_REF_DIRS=skills SKILL_REF_HASH_STATE="$ROOT/logs/state.json" SKILL_REF_RECORD_VERIFIED=1 bash "$ROOT/scripts/gates/gate_skill_script_refs.sh" "$ROOT" >/dev/null &
  p1=$!
  env SKILL_REF_DISABLE_CACHE=1 SKILL_REF_DIRS=skills SKILL_REF_HASH_STATE="$ROOT/logs/state.json" SKILL_REF_RECORD_VERIFIED=1 bash "$ROOT/scripts/gates/gate_skill_script_refs.sh" "$ROOT" >/dev/null &
  p2=$!
  wait "$p1"
  wait "$p2"
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert len(d["references"]) == 1' "$ROOT/logs/state.json"
  [ "$status" -eq 0 ]
}

@test "missing script is a BLOCK" {
  rm "$ROOT/scripts/demo.sh"
  run env SKILL_REF_DISABLE_CACHE=1 SKILL_REF_DIRS=skills SKILL_REF_HASH_STATE="$ROOT/logs/state.json" bash "$ROOT/scripts/gates/gate_skill_script_refs.sh" "$ROOT"
  [ "$status" -eq 3 ]
  [[ "$output" == *"BLOCK"* ]]
}

@test "recent high fail bucket queues one deduplicated action" {
  cp "$BATS_TEST_DIRNAME/../../scripts/skill_auto_improve.sh" "$ROOT/scripts/"
  cat > "$ROOT/logs/executions.yaml" <<'YAML'
executions:
- {ts: '2026-07-17T01:00:00+09:00', skill: demo, result: PASS}
- {ts: '2026-07-17T01:01:00+09:00', skill: demo, result: FAIL, gate: demo_gate, stumbling_points: broken contract}
- {ts: '2026-07-17T01:02:00+09:00', skill: demo, result: PASS}
YAML
  run env SHOGUN_REPO_ROOT="$ROOT" SKILL_EXECUTION_LOG_FILE="$ROOT/logs/executions.yaml" SKILL_AUTO_IMPROVE_SKILLS_DIRS="$ROOT/skills" SKILL_AUTO_IMPROVE_STATE_JSON="$ROOT/logs/improve.json" SKILL_AUTO_IMPROVE_ACTION_QUEUE="$ROOT/logs/actions.json" SKILL_AUTO_IMPROVE_FAIL_RATE_THRESHOLD=10 bash "$ROOT/scripts/skill_auto_improve.sh" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACTION_QUEUED"* ]]
  run env SHOGUN_REPO_ROOT="$ROOT" SKILL_EXECUTION_LOG_FILE="$ROOT/logs/executions.yaml" SKILL_AUTO_IMPROVE_SKILLS_DIRS="$ROOT/skills" SKILL_AUTO_IMPROVE_STATE_JSON="$ROOT/logs/improve.json" SKILL_AUTO_IMPROVE_ACTION_QUEUE="$ROOT/logs/actions.json" SKILL_AUTO_IMPROVE_FAIL_RATE_THRESHOLD=10 bash "$ROOT/scripts/skill_auto_improve.sh" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACTION_DEDUPED"* ]]
  run python3 -c 'import json,sys; assert len(json.load(open(sys.argv[1]))["actions"]) == 1' "$ROOT/logs/actions.json"
  [ "$status" -eq 0 ]
}
