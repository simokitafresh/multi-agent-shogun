#!/usr/bin/env bats
# test_cmd_complete_gate_ac_version.bats - cmd_530 ac_version gate behavior

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    export SRC_CONTEXT_FRESHNESS_SCRIPT="$PROJECT_ROOT/scripts/context_freshness_check.sh"
    export SRC_FIELD_GET_SCRIPT="$PROJECT_ROOT/scripts/lib/field_get.sh"
    export SRC_YAML_FIELD_SET_SCRIPT="$PROJECT_ROOT/scripts/lib/yaml_field_set.sh"

    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    [ -f "$SRC_CONTEXT_FRESHNESS_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET_SCRIPT" ] || return 1
    [ -f "$SRC_YAML_FIELD_SET_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_gate_acv.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export TEST_CMD_ID="cmd_999"

    mkdir -p \
        "$TEST_PROJECT/scripts/lib" \
        "$TEST_PROJECT/scripts/gates" \
        "$TEST_PROJECT/queue/tasks" \
        "$TEST_PROJECT/queue/reports" \
        "$TEST_PROJECT/queue/gates/$TEST_CMD_ID" \
        "$TEST_PROJECT/config" \
        "$TEST_PROJECT/logs"

    cp "$SRC_GATE_SCRIPT" "$TEST_PROJECT/scripts/cmd_complete_gate.sh"
    cp "$SRC_CONTEXT_FRESHNESS_SCRIPT" "$TEST_PROJECT/scripts/context_freshness_check.sh"
    cp "$SRC_FIELD_GET_SCRIPT" "$TEST_PROJECT/scripts/lib/field_get.sh"
    cp "$SRC_YAML_FIELD_SET_SCRIPT" "$TEST_PROJECT/scripts/lib/yaml_field_set.sh"

    # Non-blocking script stubs required by cmd_complete_gate.sh
    cat > "$TEST_PROJECT/scripts/auto_draft_lesson.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/inbox_archive.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/lesson_impact_analysis.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/dashboard_update.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/gist_sync.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/ntfy_cmd.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/ntfy.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/gates/gate_yaml_status.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/gates/gate_dc_duplicate.sh" <<'EOF'
#!/usr/bin/env bash
echo "OK"
exit 0
EOF

    chmod +x \
        "$TEST_PROJECT/scripts/cmd_complete_gate.sh" \
        "$TEST_PROJECT/scripts/context_freshness_check.sh" \
        "$TEST_PROJECT/scripts/lib/field_get.sh" \
        "$TEST_PROJECT/scripts/lib/yaml_field_set.sh" \
        "$TEST_PROJECT/scripts/auto_draft_lesson.sh" \
        "$TEST_PROJECT/scripts/inbox_archive.sh" \
        "$TEST_PROJECT/scripts/lesson_impact_analysis.sh" \
        "$TEST_PROJECT/scripts/dashboard_update.sh" \
        "$TEST_PROJECT/scripts/gist_sync.sh" \
        "$TEST_PROJECT/scripts/ntfy_cmd.sh" \
        "$TEST_PROJECT/scripts/ntfy.sh" \
        "$TEST_PROJECT/scripts/gates/gate_yaml_status.sh" \
        "$TEST_PROJECT/scripts/gates/gate_dc_duplicate.sh"

    # Required gate flags to bypass preflight side effects.
    cat > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/archive.done" <<'EOF'
timestamp: 2026-03-04T00:00:00
source: test
EOF
    cat > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done" <<'EOF'
timestamp: 2026-03-04T00:00:00
source: lesson_check
EOF

    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: infra
    path: $TEST_PROJECT
EOF

    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  - id: $TEST_CMD_ID
    purpose: "ac_version gate test"
    project: infra
    status: in_progress
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: review
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 7
  related_lessons: []
EOF
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

write_report() {
    local ac_version_line="$1"
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-04T00:00:00"
status: done
${ac_version_line}
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
EOF
}

@test "ac_version legacy numeric: gate skips (backward compatible)" {
    # task has numeric ac_version=7 (old format) → legacy_skip
    write_report "ac_version_read: 7"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AC version check:"* ]]
    [[ "$output" == *"旧形式(数値)ac_version=7のため照合SKIP（後方互換）"* ]]
}

@test "ac_version hash match: gate passes" {
    # Set hash-based ac_version in task
    python3 -c "
import yaml
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml') as f:
    data = yaml.safe_load(f)
data['task']['ac_version'] = 'a3f2b1c9'
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
"
    write_report "ac_version_read: a3f2b1c9"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AC version check:"* ]]
    [[ "$output" == *"sasuke: OK (ac_version task=a3f2b1c9, report=a3f2b1c9)"* ]]
}

@test "ac_version hash mismatch: gate blocks (content change detection)" {
    # Task has hash A but report has hash B (same AC count, different content)
    python3 -c "
import yaml
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml') as f:
    data = yaml.safe_load(f)
data['task']['ac_version'] = 'd287147e'
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
"
    write_report "ac_version_read: 519485d7"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 1 ]
    [[ "$output" == *"AC version check:"* ]]
    [[ "$output" == *"[CRITICAL] sasuke: NG ← ac_version不一致 (task=d287147e, report=519485d7)"* ]]
}

@test "ac_version hash with missing report: warn only (backward compatible)" {
    python3 -c "
import yaml
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml') as f:
    data = yaml.safe_load(f)
data['task']['ac_version'] = 'a3f2b1c9'
with open('$TEST_PROJECT/queue/tasks/sasuke.yaml', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
"
    write_report ""

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AC version check:"* ]]
    [[ "$output" == *"[INFO] sasuke: ac_version_read未記載（task=a3f2b1c9）。後方互換として非BLOCK"* ]]
}
