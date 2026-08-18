#!/usr/bin/env bats
# test_necessity: terminal task archive publication is atomic and parseable.

@test "terminal task archive helper publishes an exact parseable snapshot" {
  root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/queue/tasks" "$root/queue/archive/tasks" "$root/logs"
  cat > "$root/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: done
  parent_cmd: cmd_old
YAML

  run env DEPLOY_TASK_LIB_ONLY=1 bash -c '
    source "$1/scripts/deploy_task.sh"
    SCRIPT_DIR="$2"
    LOG="$2/logs/deploy_task.log"
    deploy_task_archive_terminal_task "$2/queue/tasks/hayate.yaml" hayate cmd_old
  ' _ "$BATS_TEST_DIRNAME/../.." "$root"

  [ "$status" -eq 0 ]
  archive=$(find "$root/queue/archive/tasks" -name 'hayate_cmd_old_*.yaml')
  [ -f "$archive" ]
  cmp "$root/queue/tasks/hayate.yaml" "$archive"
  python3 -c 'import sys,yaml; assert yaml.safe_load(open(sys.argv[1]))["task"]["parent_cmd"] == "cmd_old"' "$archive"
}

# test_necessity: active task generations must remain protected from another command.
@test "active worker assignment remains blocked" {
  root="$BATS_TEST_TMPDIR/root-active"
  mkdir -p "$root/queue/tasks" "$root/logs"
  cat > "$root/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: in_progress
  parent_cmd: cmd_old
YAML

  run env DEPLOY_TASK_LIB_ONLY=1 bash -c '
    source "$1/scripts/deploy_task.sh"
    SCRIPT_DIR="$2"
    LOG="$2/logs/deploy_task.log"
    NINJA_NAME=hayate
    field_get() {
      python3 - "$1" "$2" "$3" <<"PY"
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1])) or {}
print((doc.get("task") or {}).get(sys.argv[2], sys.argv[3]))
PY
    }
    deploy_task_guard_worker_assignment "$2/queue/tasks/hayate.yaml" cmd_new
  ' _ "$BATS_TEST_DIRNAME/../.." "$root"

  [ "$status" -ne 0 ]
  [[ "$output" == *"already has active task"* ]]
  [ "$(find "$root" -path '*/queue/archive/tasks/*' -type f 2>/dev/null | wc -l)" -eq 0 ]
}
