#!/usr/bin/env bats
# test_deploy_task_if_then.bats - cmd_575 if_then lesson detail injection

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
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/deploy_if_then.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"

    mkdir -p \
        "$TEST_PROJECT/lib" \
        "$TEST_PROJECT/scripts/lib" \
        "$TEST_PROJECT/queue/tasks" \
        "$TEST_PROJECT/queue/reports" \
        "$TEST_PROJECT/queue/inbox" \
        "$TEST_PROJECT/projects/testproj" \
        "$TEST_PROJECT/logs" \
        "$TEST_PROJECT/config"

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

    cat > "$TEST_PROJECT/projects/testproj/lessons.yaml" <<'EOF'
lessons:
  - id: L900
    title: if_then lesson
    summary: if_then summary
    detail: legacy detail should be ignored
    status: confirmed
    tags: [universal]
    helpful_count: 10
    if_then:
      if: trigger condition
      then: take action
      because: expected effect
  - id: L901
    title: legacy lesson
    summary: legacy summary
    detail: legacy detail text
    status: confirmed
    tags: [universal]
    helpful_count: 9
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "if_then injection"
  description: "validate if_then detail output"
  task_type: review
  project: testproj
  acceptance_criteria:
    - AC1
EOF
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

read_related_detail() {
    local lesson_id="$1"
    TASK_FILE_ENV="$TEST_PROJECT/queue/tasks/sasuke.yaml" LESSON_ID_ENV="$lesson_id" python3 -c "
import os, yaml
with open(os.environ['TASK_FILE_ENV'], encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
related = (data.get('task') or {}).get('related_lessons') or []
target = os.environ['LESSON_ID_ENV']
for entry in related:
    if str(entry.get('id', '')) == target:
        print(str(entry.get('detail', '')))
        break
"
}

@test "deploy_task formats if_then lesson detail as IF/THEN/BECAUSE" {
    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_related_detail L900
    [ "$status" -eq 0 ]
    [ "$output" = "IF: trigger condition → THEN: take action (BECAUSE: expected effect)" ]
}

@test "deploy_task keeps legacy detail fallback when if_then is absent" {
    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_related_detail L901
    [ "$status" -eq 0 ]
    [ "$output" = "legacy detail text" ]
}
