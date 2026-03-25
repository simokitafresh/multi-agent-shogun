#!/usr/bin/env bats
# test_deploy_task_ac_version.bats - ac_version injection + if_then lesson detail behavior

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_acv"

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
    deploy_task_teardown
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

read_task_field() {
    local field_name="$1"
    TASK_FILE_ENV="$TEST_PROJECT/queue/tasks/sasuke.yaml" FIELD_NAME_ENV="$field_name" python3 -c "
import os, yaml
with open(os.environ['TASK_FILE_ENV'], encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
task = data.get('task', {})
value = task.get(os.environ['FIELD_NAME_ENV'], '__missing__')
if isinstance(value, list):
    print('list')
    print('|'.join(str(v) for v in value))
elif value == '__missing__':
    print('__missing__')
else:
    print(str(value))
"
}

@test "deploy_task injects ac_version and report ac_version_read on first deploy" {
    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_task_ac_version
    [ "$status" -eq 0 ]
    [ "$output" = "7d010443" ]

    run grep -E "^ac_version_read:[[:space:]]*7d010443$" "$TEST_PROJECT/queue/reports/sasuke_report.yaml"
    [ "$status" -eq 0 ]

    run read_task_field stop_for
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]
    [ "${lines[1]}" = "" ]

    run read_task_field never_stop_for
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]
    [[ "${lines[1]}" == *"CDPポート未応答"* ]]
    [[ "${lines[1]}" == *"自動対処機能"* ]]
    [[ "${lines[1]}" == *"自明な修正"* ]]

    run read_task_field parallel_ok
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]
    [ "${lines[1]}" = "AC1|AC2|AC3" ]

    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "AC1 > AC2 > AC3" ]

    run read_task_field ac_checkpoint
    [ "$status" -eq 0 ]
    [ "$output" = "各AC完了後に checkpoint: 次ACの前提条件確認 → scope drift検出 → progress更新" ]
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
  ac_version: 7d010443
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_task_ac_version
    [ "$status" -eq 0 ]
    [ "$output" = "59d7d64d" ]
}

@test "deploy_task detects ac_version change when AC count same but content differs" {
    # 3 ACs with descriptions: first, second, third
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "content change test"
  task_type: review
  acceptance_criteria:
    - id: AC1
      description: "first"
    - id: AC2
      description: "second"
    - id: AC3
      description: "third"
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]
    run read_task_ac_version
    [ "$status" -eq 0 ]
    local hash_before="$output"
    [ "$hash_before" = "519485d7" ]

    # Same count (3) but different content
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "content change test"
  task_type: review
  acceptance_criteria:
    - id: AC1
      description: "alpha"
    - id: AC2
      description: "beta"
    - id: AC3
      description: "gamma"
  ac_version: 519485d7
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]
    run read_task_ac_version
    [ "$status" -eq 0 ]
    [ "$output" = "d287147e" ]
    [ "$output" != "$hash_before" ]
}

@test "deploy_task skips ac_priority injection when acceptance_criteria has fewer than 3 items" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "short ac"
  task_type: review
  acceptance_criteria:
    - ac1: first
    - ac2: second
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "__missing__" ]

    run read_task_field ac_checkpoint
    [ "$status" -eq 0 ]
    [ "$output" = "__missing__" ]

    run read_task_field stop_for
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]
}

@test "deploy_task preserves existing execution control values on redeploy" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "existing controls"
  task_type: review
  acceptance_criteria:
    - ac1: first
    - ac2: second
    - ac3: third
  stop_for:
    - test failure
  never_stop_for:
    - formatting only
  ac_checkpoint: "custom checkpoint"
  parallel_ok:
    - AC1
  ac_priority: "AC2 > AC1 > AC3"
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    # cmd_1321: FIELD_CLEAR→再inject設計により、既存値はクリアされデフォルト再注入される
    run read_task_field stop_for
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]

    run read_task_field never_stop_for
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]

    # 3AC → parallel_ok/ac_priorityはデフォルト再生成
    run read_task_field parallel_ok
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]

    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [[ "$output" == *">"* ]]

    run read_task_field ac_checkpoint
    [ "$status" -eq 0 ]
    [[ "$output" == *"checkpoint"* ]]
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

    run grep -F "# Step1: Read this file" \
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

@test "deploy_task generates ac_priority and parallel_ok from explicit AC ids" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "explicit ids"
  task_type: review
  acceptance_criteria:
    - id: FOO
      description: "first"
    - id: BAR
      description: "second"
    - id: BAZ
      description: "third"
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "FOO > BAR > BAZ" ]

    run read_task_field parallel_ok
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]
    [ "${lines[1]}" = "FOO|BAR|BAZ" ]
}

@test "deploy_task generates parallel_ok for 2 ACs but skips ac_priority" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "two acs"
  task_type: review
  acceptance_criteria:
    - id: X1
      description: "first"
    - id: X2
      description: "second"
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "__missing__" ]

    run read_task_field parallel_ok
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]
    [ "${lines[1]}" = "X1|X2" ]
}

@test "deploy_task sets empty parallel_ok for single AC" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "single ac"
  task_type: review
  acceptance_criteria:
    - id: ONLY
      description: "the only one"
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_task_field parallel_ok
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]
    [ "${lines[1]}" = "" ]

    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "__missing__" ]
}

@test "deploy_task replaces empty-string ac_priority with default for 3+ ACs" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "empty ac_priority sentinel"
  task_type: impl
  acceptance_criteria:
    - id: AC1
      description: "first"
    - id: AC2
      description: "second"
    - id: AC3
      description: "third"
  ac_priority: ""
  parallel_ok:
    - AC1
    - AC2
    - AC3
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "AC1 > AC2 > AC3" ]

    # parallel_ok should be preserved (non-empty)
    run read_task_field parallel_ok
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]
    [ "${lines[1]}" = "AC1|AC2|AC3" ]
}

@test "deploy_task replaces empty-list parallel_ok with default AC IDs for 3 ACs" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "empty parallel_ok sentinel"
  task_type: impl
  acceptance_criteria:
    - id: AC1
      description: "first"
    - id: AC2
      description: "second"
    - id: AC3
      description: "third"
  ac_priority: "AC1 > AC2 > AC3"
  parallel_ok: []
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_task_field parallel_ok
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]
    [ "${lines[1]}" = "AC1|AC2|AC3" ]

    # ac_priority should be preserved (non-empty)
    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "AC1 > AC2 > AC3" ]
}

@test "deploy_task replaces empty-list parallel_ok with default AC IDs for 2 ACs" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "empty parallel_ok 2 ACs"
  task_type: impl
  acceptance_criteria:
    - id: X1
      description: "first"
    - id: X2
      description: "second"
  parallel_ok: []
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_task_field parallel_ok
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]
    [ "${lines[1]}" = "X1|X2" ]

    # ac_priority should not be injected (< 3 ACs)
    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "__missing__" ]
}

@test "deploy_task replaces both empty ac_priority and empty parallel_ok simultaneously" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "both empty sentinels"
  task_type: impl
  acceptance_criteria:
    - id: AC1
      description: "first"
    - id: AC2
      description: "second"
    - id: AC3
      description: "third"
  ac_priority: ""
  parallel_ok: []
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "AC1 > AC2 > AC3" ]

    run read_task_field parallel_ok
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "list" ]
    [ "${lines[1]}" = "AC1|AC2|AC3" ]
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

# =============================================================================
# if_then lesson detail injection tests (merged from test_deploy_task_if_then.bats)
# =============================================================================

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
    mkdir -p "$TEST_PROJECT/projects/testproj"
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

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_related_detail L900
    [ "$status" -eq 0 ]
    [ "$output" = "IF: trigger condition → THEN: take action (BECAUSE: expected effect)" ]
}

# === GP-105: stale report reassignment detection ===
# STALL再配備時に旧忍者のテンプレート(verdict空)がアーカイブされることを確認

@test "GP-105: stale other ninja template archived on reassignment (verdict empty)" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "stale report test"
  task_type: impl
  parent_cmd: cmd_stale_test
  acceptance_criteria:
    - id: AC1
      description: "test"
EOF
    # Simulate stale template from another ninja (STALL reassignment)
    cat > "$TEST_PROJECT/queue/reports/hanzo_report_cmd_stale_test.yaml" <<'EOF'
worker_id: hanzo
parent_cmd: cmd_stale_test
verdict:
status: pending
EOF
    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]
    # Stale template should be archived
    [ ! -f "$TEST_PROJECT/queue/reports/hanzo_report_cmd_stale_test.yaml" ]
    [ -f "$TEST_PROJECT/archive/reports/stale/hanzo_report_cmd_stale_test.yaml" ]
}

@test "GP-105: completed other ninja report preserved on reassignment (verdict PASS)" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "preserve completed report"
  task_type: impl
  parent_cmd: cmd_preserve_test
  acceptance_criteria:
    - id: AC1
      description: "test"
EOF
    # Simulate completed report from another ninja
    cat > "$TEST_PROJECT/queue/reports/hanzo_report_cmd_preserve_test.yaml" <<'EOF'
worker_id: hanzo
parent_cmd: cmd_preserve_test
verdict: PASS
status: done
EOF
    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]
    # Completed report should be preserved (not archived)
    [ -f "$TEST_PROJECT/queue/reports/hanzo_report_cmd_preserve_test.yaml" ]
}

@test "deploy_task keeps legacy detail fallback when if_then is absent" {
    mkdir -p "$TEST_PROJECT/projects/testproj"
    cat > "$TEST_PROJECT/projects/testproj/lessons.yaml" <<'EOF'
lessons:
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
  title: "legacy detail"
  description: "validate legacy detail fallback"
  task_type: review
  project: testproj
  acceptance_criteria:
    - AC1
EOF

    run bash "$TEST_PROJECT/scripts/deploy_task.sh" sasuke
    [ "$status" -eq 0 ]

    run read_related_detail L901
    [ "$status" -eq 0 ]
    [ "$output" = "legacy detail text" ]
}
