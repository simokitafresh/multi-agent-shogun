#!/usr/bin/env bats
# test_necessity: Active-task write reservations, readonly exclusions, and explicit-handoff checkpoint barriers remain one deploy-lock contract.

setup() {
  ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$ROOT/scripts" "$ROOT/queue/tasks" "$ROOT/logs"
  SOURCE_ROOT="$BATS_TEST_DIRNAME/../.."
  sed -n '/^deploy_task_guard_target_path_collision()/,/^}/p' \
    "$SOURCE_ROOT/scripts/deploy_task.sh" > "$ROOT/guard.sh"
}

run_guard() {
  run bash -c 'export SCRIPT_DIR="$1" PYTHONPATH="$4"; source "$1/guard.sh"; deploy_task_guard_target_path_collision "$2" "$3"' _ "$ROOT" "$1" "$2" "$SOURCE_ROOT"
}

write_task() {
  local worker="$1" status="$2" body="$3"
  printf 'task:\n  status: %s\n  parent_cmd: cmd_%s\n%s\n' "$status" "$worker" "$body" > "$ROOT/queue/tasks/$worker.yaml"
}

@test "command-derived active peer collision blocks and disjoint fixture passes" {
  write_task hayate in_progress '  command: "bash scripts/shared.sh"'
  write_task saizo assigned '  target_path: [scripts/shared.sh]'
  run_guard "$ROOT/queue/tasks/saizo.yaml" saizo
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCK: reserved path collision with hayate"* ]]

  write_task saizo assigned '  target_path: [scripts/disjoint.sh]'
  run_guard "$ROOT/queue/tasks/saizo.yaml" saizo
  [ "$status" -eq 0 ]
}

@test "readonly overlap is excluded without false block and records zero false positives" {
  write_task hayate in_progress '  target_path: [scripts/shared.sh]'
  write_task saizo assigned $'  command: "scripts/shared.sh を確認"\n  readonly_ref:\n  - path: scripts/shared.sh\n    reason: reference only'
  run_guard "$ROOT/queue/tasks/saizo.yaml" saizo
  [ "$status" -eq 0 ]
  grep -q '"decision": "PASS".*"false_positive": 0' "$ROOT/logs/target_overlap_gate_fire.jsonl"
}

@test "explicit handoff creates final checkpoint barrier until peer terminal" {
  write_task hayate in_progress '  target_path: [scripts/shared.sh]'
  write_task saizo assigned $'  target_path: [scripts/shared.sh]\n  overlap_handoff_from: [hayate]'
  run_guard "$ROOT/queue/tasks/saizo.yaml" saizo
  [ "$status" -eq 0 ]
  python3 - "$ROOT/queue/tasks/saizo.yaml" <<'PY'
import sys, yaml
t = yaml.safe_load(open(sys.argv[1]))['task']
b = t['final_checkpoint_barrier'][0]
assert b['peer'] == 'hayate'
assert b['release_statuses'] == ['done', 'failed', 'idle']
PY

  write_task hayate done '  target_path: [scripts/shared.sh]'
  write_task saizo assigned '  target_path: [scripts/shared.sh]'
  run_guard "$ROOT/queue/tasks/saizo.yaml" saizo
  [ "$status" -eq 0 ]
}
