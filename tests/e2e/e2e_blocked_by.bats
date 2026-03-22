#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export E2E_SETUP="$PROJECT_ROOT/tests/e2e/helpers/setup.bash"
    export E2E_ASSERT="$PROJECT_ROOT/tests/e2e/helpers/assertions.bash"
    export E2E_TMUX="$PROJECT_ROOT/tests/e2e/helpers/tmux_helpers.bash"
    export MOCK_CLI="$PROJECT_ROOT/tests/e2e/mock_cli.sh"
}

setup() {
    source "$E2E_SETUP"
    source "$E2E_ASSERT"
    source "$E2E_TMUX"
    export E2E_MOCK_CLI_PATH="$MOCK_CLI"
    export E2E_MOCK_DELAY=1
    setup_e2e_session 3
}

teardown() {
    source "$E2E_SETUP"
    teardown_e2e_session
}

@test "blocked_by flow: blocked task waits until status becomes assigned" {
    local task_file="$E2E_QUEUE/queue/tasks/kirimaru.yaml"
    cat > "$task_file" <<'YAML'
task:
  assigned_to: kirimaru
  parent_cmd: cmd_e2e_blocked
  subtask_id: subtask_e2e_blocked
  report_filename: kirimaru_report_cmd_e2e_blocked.yaml
  blocked_by:
    - subtask_dependency
  status: blocked
YAML

    run bash "$E2E_QUEUE/scripts/inbox_write.sh" "kirimaru" "blocked" "task_assigned" "karo"
    [ "$status" -eq 0 ]
    send_to_pane "$(pane_target 2)" "inbox1"
    sleep 3

    assert_yaml_field "$task_file" "task.status" "blocked"
    [ ! -f "$E2E_QUEUE/queue/reports/kirimaru_report_cmd_e2e_blocked.yaml" ]

    python3 - <<PY
import tempfile
import yaml
import os
task_file = "$task_file"
with open(task_file, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
data["task"]["status"] = "assigned"
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix=".tmp")
try:
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as fh:
        yaml.dump(data, fh, default_flow_style=False, allow_unicode=True, indent=2)
    os.replace(tmp_path, task_file)
finally:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
PY

    run bash "$E2E_QUEUE/scripts/inbox_write.sh" "kirimaru" "unblocked" "task_assigned" "karo"
    [ "$status" -eq 0 ]
    send_to_pane "$(pane_target 2)" "inbox1"

    wait_for_yaml_value "$task_file" "task.status" "done" 30
    wait_for_file "$E2E_QUEUE/queue/reports/kirimaru_report_cmd_e2e_blocked.yaml" 15
}
