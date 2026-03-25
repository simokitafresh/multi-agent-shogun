#!/usr/bin/env bats
# test_deploy_task_engineering_preferences.bats - cmd_927 engineering_preferences injection

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_prefs"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "engineering preferences test"
  task_type: review
  project: dm-signal
  acceptance_criteria:
    - id: AC1
      description: "inject preferences"
EOF
}

teardown() {
    deploy_task_teardown
}

read_task_engineering_preferences() {
    python3 - <<'PY'
import os
import yaml

task_file = os.path.join(os.environ['TEST_PROJECT'], 'queue', 'tasks', 'sasuke.yaml')
with open(task_file, encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}

prefs = (data.get('task') or {}).get('engineering_preferences') or []
for pref in prefs:
    print(pref)
PY
}

@test "deploy_task injects engineering_preferences from YAML project file" {
    cat > "$TEST_PROJECT/projects/dm-signal.yaml" <<'EOF'
project:
  id: dm-signal
engineering_preferences:
  - "prefer parity over speed"
  - "prefer PostgreSQL over SQLite writes"
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_task_engineering_preferences
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "prefer parity over speed" ]
    [ "${lines[1]}" = "prefer PostgreSQL over SQLite writes" ]
}

@test "deploy_task injects engineering_preferences from mixed-format project file" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "engineering preferences test"
  task_type: review
  project: auto-ops
  acceptance_criteria:
    - id: AC1
      description: "inject preferences"
EOF

    cat > "$TEST_PROJECT/projects/auto-ops.yaml" <<'EOF'
repo: https://example.com/auto-ops
path: /tmp/auto-ops
language: python
created: 2026-03-08

engineering_preferences:
  - "prefer stdlib over new deps"
  - "prefer fail-close over warn-and-continue"

## Core Rules
- sample
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_task_engineering_preferences
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "prefer stdlib over new deps" ]
    [ "${lines[1]}" = "prefer fail-close over warn-and-continue" ]
}

@test "deploy_task preserves existing task engineering_preferences" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "engineering preferences test"
  task_type: review
  project: dm-signal
  engineering_preferences:
    - "manual override"
  acceptance_criteria:
    - id: AC1
      description: "preserve"
EOF

    cat > "$TEST_PROJECT/projects/dm-signal.yaml" <<'EOF'
project:
  id: dm-signal
engineering_preferences:
  - "prefer parity over speed"
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    # cmd_1321: FIELD_CLEAR→再inject設計により、既存値はクリアされプロジェクトデフォルトで再注入
    run read_task_engineering_preferences
    [ "$status" -eq 0 ]
    [ "$output" = "prefer parity over speed" ]
}
