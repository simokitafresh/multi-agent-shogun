#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    export SRC_CONTEXT_FRESHNESS_SCRIPT="$PROJECT_ROOT/scripts/context_freshness_check.sh"
    export SRC_MODEL_ANALYSIS="$PROJECT_ROOT/scripts/model_analysis.sh"
    export SRC_FIELD_GET_SCRIPT="$PROJECT_ROOT/scripts/lib/field_get.sh"
    export SRC_YAML_FIELD_SET_SCRIPT="$PROJECT_ROOT/scripts/lib/yaml_field_set.sh"
    export SRC_NORMALIZE_REPORT_SCRIPT="$PROJECT_ROOT/scripts/lib/normalize_report.sh"

    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    [ -f "$SRC_CONTEXT_FRESHNESS_SCRIPT" ] || return 1
    [ -f "$SRC_MODEL_ANALYSIS" ] || return 1
    [ -f "$SRC_FIELD_GET_SCRIPT" ] || return 1
    [ -f "$SRC_YAML_FIELD_SET_SCRIPT" ] || return 1
    [ -f "$SRC_NORMALIZE_REPORT_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_metrics_models.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export TEST_CMD_ID="cmd_999"

    mkdir -p \
        "$TEST_PROJECT/scripts/lib" \
        "$TEST_PROJECT/scripts/gates" \
        "$TEST_PROJECT/queue/tasks" \
        "$TEST_PROJECT/queue/reports" \
        "$TEST_PROJECT/queue/gates/$TEST_CMD_ID" \
        "$TEST_PROJECT/queue/inbox" \
        "$TEST_PROJECT/config" \
        "$TEST_PROJECT/logs" \
        "$TEST_PROJECT/context" \
        "$TEST_PROJECT/tasks"

    cp "$SRC_GATE_SCRIPT" "$TEST_PROJECT/scripts/cmd_complete_gate.sh"
    cp "$SRC_CONTEXT_FRESHNESS_SCRIPT" "$TEST_PROJECT/scripts/context_freshness_check.sh"
    cp "$SRC_MODEL_ANALYSIS" "$TEST_PROJECT/scripts/model_analysis.sh"
    cp "$SRC_FIELD_GET_SCRIPT" "$TEST_PROJECT/scripts/lib/field_get.sh"
    cp "$SRC_YAML_FIELD_SET_SCRIPT" "$TEST_PROJECT/scripts/lib/yaml_field_set.sh"
    cp "$SRC_NORMALIZE_REPORT_SCRIPT" "$TEST_PROJECT/scripts/lib/normalize_report.sh"

    for stub in \
        auto_draft_lesson.sh \
        inbox_archive.sh \
        lesson_impact_analysis.sh \
        dashboard_update.sh \
        gist_sync.sh \
        ntfy_cmd.sh \
        ntfy.sh
    do
        cat > "$TEST_PROJECT/scripts/$stub" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "$TEST_PROJECT/scripts/$stub"
    done

    cat > "$TEST_PROJECT/scripts/gates/gate_yaml_status.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/gates/gate_dc_duplicate.sh" <<'EOF'
#!/usr/bin/env bash
echo "OK: no duplicates"
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/gates/gate_report_format.sh" <<'EOF'
#!/usr/bin/env bash
echo "PASS"
exit 0
EOF
    chmod +x \
        "$TEST_PROJECT/scripts/gates/gate_dc_duplicate.sh" \
        "$TEST_PROJECT/scripts/gates/gate_report_format.sh" \
        "$TEST_PROJECT/scripts/cmd_complete_gate.sh" \
        "$TEST_PROJECT/scripts/context_freshness_check.sh" \
        "$TEST_PROJECT/scripts/model_analysis.sh" \
        "$TEST_PROJECT/scripts/lib/field_get.sh" \
        "$TEST_PROJECT/scripts/lib/yaml_field_set.sh" \
        "$TEST_PROJECT/scripts/lib/normalize_report.sh" \
        "$TEST_PROJECT/scripts/gates/gate_yaml_status.sh"

    cat > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/archive.done" <<'EOF'
timestamp: 2026-03-06T00:00:00
source: test
EOF
    cat > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done" <<'EOF'
timestamp: 2026-03-06T00:00:00
source: test
EOF

    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: infra
    path: $TEST_PROJECT
EOF

    cat > "$TEST_PROJECT/config/settings.yaml" <<'EOF'
cli:
  default: codex
  agents:
    sasuke:
      type: codex
      model_name: gpt-5.4 high fast
    kagemaru:
      model_name: claude-opus-4-6
effort: ""
EOF

    cat > "$TEST_PROJECT/config/cli_profiles.yaml" <<'EOF'
profiles:
  codex:
    display_name: GPT-5.4
  claude:
    display_name: Opus
EOF

    cat > "$TEST_PROJECT/tasks/lessons.md" <<'EOF'
# Lessons
- **status**: confirmed
EOF

    cat > "$TEST_PROJECT/queue/inbox/karo.yaml" <<'EOF'
messages:
  - id: msg_test
    read: false
EOF
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

write_gate_cmd_fixture() {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  - id: $TEST_CMD_ID
    purpose: "gate metrics model label test"
    project: infra
    status: delegated
    delegated_at: "2026-03-06T14:00:00"
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  assigned_to: sasuke
  task_type: review
  bloom_level: routine
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 2
  related_lessons: []
EOF

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-06T14:00:00"
status: done
ac_version_read: 2
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
  no_lesson_reason: "テスト用フィクスチャ — 教訓該当なし"
skill_candidate:
  found: false
decision_candidate:
  found: false
  entries: []
binary_checks:
  AC1:
    - check: "gate metrics test"
      result: PASS
lessons_useful: []
EOF
}

@test "cmd_complete_gate writes encoded model labels without shifting TSV columns" {
    write_gate_cmd_fixture

    # Prevent live tmux pane lookup from overriding test settings.yaml model_name
    mkdir -p "$TEST_TMPDIR/bin"
    printf '#!/bin/sh\nexit 1\n' > "$TEST_TMPDIR/bin/tmux"
    chmod +x "$TEST_TMPDIR/bin/tmux"
    run env PATH="$TEST_TMPDIR/bin:$PATH" bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]

    result="$(python3 - <<'PY' "$TEST_PROJECT/logs/gate_metrics.log"
import sys
from pathlib import Path
line = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()[-1]
parts = line.split("\t")
print(f"{len(parts)}|{parts[5]}|{parts[6]}")
PY
)"
    [ "$result" = "9|gpt-5.4_high_fast|routine" ]
}

@test "model_analysis decodes encoded labels and avoids fragment model rows" {
    cat > "$TEST_PROJECT/logs/gate_metrics.log" <<'EOF'
2026-03-06T13:44:27	cmd_594	CLEAR	all_gates_passed	recon	Opus_4.6_high,Codex_5.4_high_fast	complex	none	recon title
2026-03-06T13:55:57	cmd_595	CLEAR	all_gates_passed	review	gpt-5.4_high_fast	routine	none	review title
EOF

    run bash "$TEST_PROJECT/scripts/model_analysis.sh" --summary
    [ "$status" -eq 0 ]
    [[ "$output" == *$'model_row=codex_5_4_high_fast\tCodex 5.4 high fast\t100.0'* ]]
    # gpt-5.4 and Codex 5.4 are same family (gpt_5_4) → merged into one row
    [[ "$output" != *$'model_row=gpt_5_4_high_fast\t'* ]]
    [[ "$output" == *$'model_row=opus_4_6_high\tOpus 4.6 high\t100.0'* ]]
    [[ "$output" != *$'\tCodex high\t'* ]]
    [[ "$output" != *$'\tgpt-5.4\t'* ]]
}
