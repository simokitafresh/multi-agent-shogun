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

  printf '# changed\n' >> "$ROOT/scripts/demo.sh"
  run env SKILL_REF_DISABLE_CACHE=1 SKILL_REF_DIRS=skills SKILL_REF_HASH_STATE="$ROOT/logs/state.json" bash "$ROOT/scripts/gates/gate_skill_script_refs.sh" "$ROOT"
  [ "$status" -eq 2 ]
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
