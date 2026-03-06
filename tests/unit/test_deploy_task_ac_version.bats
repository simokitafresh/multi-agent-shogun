#!/usr/bin/env bats
# test_deploy_task_ac_version.bats - cmd_530 ac_version injection behavior

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/deploy_task.sh"
    export SRC_CLI_LOOKUP_SCRIPT="$PROJECT_ROOT/scripts/lib/cli_lookup.sh"
    export SRC_FIELD_GET_SCRIPT="$PROJECT_ROOT/scripts/lib/field_get.sh"
    export SRC_YAML_FIELD_SET_SCRIPT="$PROJECT_ROOT/scripts/lib/yaml_field_set.sh"
    export SRC_AGENT_STATE_LIB="$PROJECT_ROOT/lib/agent_state.sh"

    [ -f "$SRC_DEPLOY_SCRIPT" ] || return 1
    [ -f "$SRC_CLI_LOOKUP_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET_SCRIPT" ] || return 1
    [ -f "$SRC_YAML_FIELD_SET_SCRIPT" ] || return 1
    [ -f "$SRC_AGENT_STATE_LIB" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/deploy_acv.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"

    mkdir -p \
        "$TEST_PROJECT/lib" \
        "$TEST_PROJECT/scripts/lib" \
        "$TEST_PROJECT/queue/tasks" \
        "$TEST_PROJECT/queue/reports" \
        "$TEST_PROJECT/queue/inbox" \
        "$TEST_PROJECT/logs" \
        "$TEST_PROJECT/config"

    cp "$SRC_DEPLOY_SCRIPT" "$TEST_PROJECT/scripts/deploy_task.sh"
    cp "$SRC_CLI_LOOKUP_SCRIPT" "$TEST_PROJECT/scripts/lib/cli_lookup.sh"
    cp "$SRC_FIELD_GET_SCRIPT" "$TEST_PROJECT/scripts/lib/field_get.sh"
    cp "$SRC_YAML_FIELD_SET_SCRIPT" "$TEST_PROJECT/scripts/lib/yaml_field_set.sh"
    cp "$SRC_AGENT_STATE_LIB" "$TEST_PROJECT/lib/agent_state.sh"

    # Non-blocking stubs.
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
        "$TEST_PROJECT/scripts/inbox_write.sh" \
        "$TEST_PROJECT/scripts/ntfy_cmd.sh" \
        "$TEST_PROJECT/scripts/lesson_check.sh"

    # Minimal config for cli_lookup defaults.
    cat > "$TEST_PROJECT/config/settings.yaml" <<'EOF'
cli:
  default: codex
  agents:
    sasuke:
      type: codex
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
  title: "ac_version test"
  task_type: review
  acceptance_criteria:
    - ac1: first
    - ac2: second
    - ac3: third
EOF
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

read_task_ac_version() {
    python3 -c "
import yaml
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
print(data.get('task', {}).get('ac_version', ''))
"
}

read_task_report_path() {
    python3 -c "
import yaml
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
print(data.get('task', {}).get('report_path', ''))
"
}

@test "deploy_task injects ac_version and report ac_version_read on first deploy" {
    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_task_ac_version
    [ "$status" -eq 0 ]
    [ "$output" = "3" ]

    run grep -E "^ac_version_read:[[:space:]]*3$" "$TEST_PROJECT/queue/reports/sasuke_report.yaml"
    [ "$status" -eq 0 ]
}

@test "deploy_task recalculates ac_version when acceptance_criteria count changes" {
    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "ac_version test"
  task_type: review
  acceptance_criteria:
    - ac1: first
    - ac2: second
    - ac3: third
    - ac4: fourth
    - ac5: fifth
  ac_version: 3
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_task_ac_version
    [ "$status" -eq 0 ]
    [ "$output" = "5" ]
}

@test "deploy_task injects report_path and report template guidance on cmd-named reports" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "report path test"
  task_type: review
  parent_cmd: cmd_999
  acceptance_criteria:
    - ac1: first
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    [ "$output" = "queue/reports/sasuke_report_cmd_999.yaml" ]

    run grep -F "# Step1: Read this file → Step2: Edit tool で各フィールドを埋めよ → Write禁止" \
        "$TEST_PROJECT/queue/reports/sasuke_report_cmd_999.yaml"
    [ "$status" -eq 0 ]

    run grep -F "  # found: true/false を書け。リスト形式[] 禁止" \
        "$TEST_PROJECT/queue/reports/sasuke_report_cmd_999.yaml"
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('$TEST_PROJECT/queue/reports/sasuke_report_cmd_999.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
print(type(data.get('lesson_candidate')).__name__)
print(str((data.get('lesson_candidate') or {}).get('found', '')))
"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "dict" ]
    [ "${lines[1]}" = "False" ]
}

@test "deploy_task rejects None ninja_name and removes ghost task artifacts" {
    cat > "$TEST_PROJECT/queue/tasks/None.yaml" <<'EOF'
task:
  title: ghost
EOF
    : > "$TEST_PROJECT/queue/tasks/None.yaml.lock"

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" None
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot be empty/None"* ]]
    [ ! -e "$TEST_PROJECT/queue/tasks/None.yaml" ]
    [ ! -e "$TEST_PROJECT/queue/tasks/None.yaml.lock" ]
}
