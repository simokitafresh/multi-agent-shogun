#!/usr/bin/env bats
# test_deploy_task_engineering_preferences.bats - cmd_927 engineering_preferences injection

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/deploy_task.sh"
    export SRC_CLI_LOOKUP_SCRIPT="$PROJECT_ROOT/scripts/lib/cli_lookup.sh"
    export SRC_FIELD_GET_SCRIPT="$PROJECT_ROOT/scripts/lib/field_get.sh"
    export SRC_YAML_FIELD_SET_SCRIPT="$PROJECT_ROOT/scripts/lib/yaml_field_set.sh"
    export SRC_AGENT_STATE_LIB="$PROJECT_ROOT/lib/agent_state.sh"
    export SRC_CTX_UTILS_SCRIPT="$PROJECT_ROOT/scripts/lib/ctx_utils.sh"
    export SRC_PANE_LOOKUP_SCRIPT="$PROJECT_ROOT/scripts/lib/pane_lookup.sh"
    export SRC_AGENT_CONFIG_SCRIPT="$PROJECT_ROOT/scripts/lib/agent_config.sh"
    export SRC_INJECT_TASK_MODIFIERS="$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"

    [ -f "$SRC_DEPLOY_SCRIPT" ] || return 1
    [ -f "$SRC_CLI_LOOKUP_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET_SCRIPT" ] || return 1
    [ -f "$SRC_YAML_FIELD_SET_SCRIPT" ] || return 1
    [ -f "$SRC_AGENT_STATE_LIB" ] || return 1
    [ -f "$SRC_CTX_UTILS_SCRIPT" ] || return 1
    [ -f "$SRC_PANE_LOOKUP_SCRIPT" ] || return 1
    [ -f "$SRC_AGENT_CONFIG_SCRIPT" ] || return 1
    [ -f "$SRC_INJECT_TASK_MODIFIERS" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/deploy_prefs.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"

    mkdir -p \
        "$TEST_PROJECT/lib" \
        "$TEST_PROJECT/scripts/lib" \
        "$TEST_PROJECT/queue/tasks" \
        "$TEST_PROJECT/queue/reports" \
        "$TEST_PROJECT/queue/inbox" \
        "$TEST_PROJECT/logs" \
        "$TEST_PROJECT/config" \
        "$TEST_PROJECT/projects"

    cp "$SRC_DEPLOY_SCRIPT" "$TEST_PROJECT/scripts/deploy_task.sh"
    cp "$SRC_CLI_LOOKUP_SCRIPT" "$TEST_PROJECT/scripts/lib/cli_lookup.sh"
    cp "$SRC_FIELD_GET_SCRIPT" "$TEST_PROJECT/scripts/lib/field_get.sh"
    cp "$SRC_YAML_FIELD_SET_SCRIPT" "$TEST_PROJECT/scripts/lib/yaml_field_set.sh"
    cp "$SRC_AGENT_STATE_LIB" "$TEST_PROJECT/lib/agent_state.sh"
    cp "$SRC_CTX_UTILS_SCRIPT" "$TEST_PROJECT/scripts/lib/ctx_utils.sh"
    cp "$SRC_PANE_LOOKUP_SCRIPT" "$TEST_PROJECT/scripts/lib/pane_lookup.sh"
    cp "$SRC_AGENT_CONFIG_SCRIPT" "$TEST_PROJECT/scripts/lib/agent_config.sh"
    cp "$SRC_INJECT_TASK_MODIFIERS" "$TEST_PROJECT/scripts/lib/inject_task_modifiers.py"

    cat > "$TEST_PROJECT/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/ntfy_cmd.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/lesson_check.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

    chmod +x \
        "$TEST_PROJECT/scripts/deploy_task.sh" \
        "$TEST_PROJECT/scripts/lib/cli_lookup.sh" \
        "$TEST_PROJECT/scripts/lib/field_get.sh" \
        "$TEST_PROJECT/scripts/lib/yaml_field_set.sh" \
        "$TEST_PROJECT/lib/agent_state.sh" \
        "$TEST_PROJECT/scripts/lib/ctx_utils.sh" \
        "$TEST_PROJECT/scripts/lib/pane_lookup.sh" \
        "$TEST_PROJECT/scripts/lib/agent_config.sh" \
        "$TEST_PROJECT/scripts/inbox_write.sh" \
        "$TEST_PROJECT/scripts/ntfy_cmd.sh" \
        "$TEST_PROJECT/scripts/lesson_check.sh"

    cat > "$TEST_PROJECT/config/settings.yaml" <<'EOF'
cli:
  default: codex
  agents:
    sasuke:
      type: codex
      role: ninja
      japanese_name: 佐助
EOF

    cat > "$TEST_PROJECT/config/cli_profiles.yaml" <<'EOF'
profiles:
  codex:
    ctx_pattern: ""
    ctx_mode: used
    busy_patterns: []
    idle_pattern: ""
EOF

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
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
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
