#!/usr/bin/env bats
# test_deploy_task_ac_version.bats - ac_version injection + if_then lesson detail behavior

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_acv"
    # shellcheck disable=SC1090
    source "$TEST_PROJECT/scripts/lib/field_get.sh"

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
    FIELD_GET_NO_LOG=1 field_get "$TEST_PROJECT/queue/tasks/sasuke.yaml" "ac_version" "" 2>/dev/null
}

read_task_list_field() {
    local field_name="$1"
    if grep -q "^  ${field_name}: \\[\\][[:space:]]*$" "$TEST_PROJECT/queue/tasks/sasuke.yaml"; then
        printf '__empty__\n'
        return 0
    fi
    awk -v field="$field_name" '
{
    if (!capture) {
        if ($0 ~ "^  " field ":[[:space:]]*$") {
            capture = 1
            next
        }
        next
    }
    if ($0 ~ /^  [A-Za-z_][A-Za-z0-9_]*:/) {
        exit
    }
    if ($0 ~ /^[[:space:]]*-[[:space:]]+/) {
        line = $0
        sub(/^[[:space:]]*-[[:space:]]+/, "", line)
        vals[++n] = line
    }
}
END {
    if (!capture && n == 0) {
        print "__missing__"
        exit
    }
    if (n == 0) {
        print "__empty__"
        exit
    }
    out = vals[1]
    for (i = 2; i <= n; i++) out = out "|" vals[i]
    print out
}
' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
}

read_task_report_path() {
    FIELD_GET_NO_LOG=1 field_get "$TEST_PROJECT/queue/tasks/sasuke.yaml" "report_path" "" 2>/dev/null
}

read_task_field() {
    local field_name="$1"
    FIELD_GET_NO_LOG=1 field_get "$TEST_PROJECT/queue/tasks/sasuke.yaml" "$field_name" "__missing__" 2>/dev/null
}

@test "deploy_task injects ac_version and report ac_version_read on first deploy" {
    run deploy_task_fast sasuke
    [ "$status" -eq 0 ]

    run read_task_ac_version
    [ "$status" -eq 0 ]
    [ "$output" = "7d010443" ]

    run grep -E "^ac_version_read:[[:space:]]*7d010443$" "$TEST_PROJECT/queue/reports/sasuke_report.yaml"
    [ "$status" -eq 0 ]

    run read_task_list_field stop_for
    [ "$status" -eq 0 ]
    [ "$output" = "__empty__" ]

    run read_task_list_field never_stop_for
    [ "$status" -eq 0 ]
    [[ "$output" == *"CDPポート未応答"* ]]
    [[ "$output" == *"自動対処機能"* ]]
    [[ "$output" == *"自明な修正"* ]]

    run read_task_list_field parallel_ok
    [ "$status" -eq 0 ]
    [ "$output" = "AC1|AC2|AC3" ]

    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "AC1 > AC2 > AC3" ]

    run read_task_field ac_checkpoint
    [ "$status" -eq 0 ]
    [ "$output" = "各AC完了後に checkpoint: 次ACの前提条件確認 → scope drift検出 → progress更新" ]
}

@test "deploy_task recalculates ac_version when acceptance_criteria count changes" {
    run deploy_task_ac_only sasuke
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

    run deploy_task_ac_only sasuke
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

    run deploy_task_ac_only sasuke
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

    run deploy_task_ac_only sasuke
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

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    run inject_modifiers_only sasuke
    [ "$status" -eq 0 ]

    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "__missing__" ]

    run read_task_field ac_checkpoint
    [ "$status" -eq 0 ]
    [ "$output" = "__missing__" ]

    run read_task_list_field stop_for
    [ "$status" -eq 0 ]
    [ "$output" = "__empty__" ]
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

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    run inject_modifiers_only sasuke
    [ "$status" -eq 0 ]

    # cmd_1321: FIELD_CLEAR→再inject設計により、既存値はクリアされデフォルト再注入される
    run read_task_list_field stop_for
    [ "$status" -eq 0 ]
    [ "$output" = "__empty__" ]

    run read_task_list_field never_stop_for
    [ "$status" -eq 0 ]
    [[ "$output" == *"CDPポート未応答"* ]]

    # 3AC → parallel_ok/ac_priorityはデフォルト再生成
    run read_task_list_field parallel_ok
    [ "$status" -eq 0 ]
    [ "$output" = "AC1|AC2|AC3" ]

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

    run deploy_task_fast sasuke
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

    run grep -n "^lesson_candidate:$" "$TEST_PROJECT/queue/reports/sasuke_report_cmd_999.yaml"
    [ "$status" -eq 0 ]
    run grep -n "^  found: false$" "$TEST_PROJECT/queue/reports/sasuke_report_cmd_999.yaml"
    [ "$status" -eq 0 ]
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

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    run inject_modifiers_only sasuke
    [ "$status" -eq 0 ]

    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "FOO > BAR > BAZ" ]

    run read_task_list_field parallel_ok
    [ "$status" -eq 0 ]
    [ "$output" = "FOO|BAR|BAZ" ]
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

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    run inject_modifiers_only sasuke
    [ "$status" -eq 0 ]

    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "__missing__" ]

    run read_task_list_field parallel_ok
    [ "$status" -eq 0 ]
    [ "$output" = "X1|X2" ]
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

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    run inject_modifiers_only sasuke
    [ "$status" -eq 0 ]

    run read_task_list_field parallel_ok
    [ "$status" -eq 0 ]
    [ "$output" = "__empty__" ]

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

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    run inject_modifiers_only sasuke
    [ "$status" -eq 0 ]

    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "AC1 > AC2 > AC3" ]

    # parallel_ok should be preserved (non-empty)
    run read_task_list_field parallel_ok
    [ "$status" -eq 0 ]
    [ "$output" = "AC1|AC2|AC3" ]
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

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    run inject_modifiers_only sasuke
    [ "$status" -eq 0 ]

    run read_task_list_field parallel_ok
    [ "$status" -eq 0 ]
    [ "$output" = "AC1|AC2|AC3" ]

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

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    run inject_modifiers_only sasuke
    [ "$status" -eq 0 ]

    run read_task_list_field parallel_ok
    [ "$status" -eq 0 ]
    [ "$output" = "X1|X2" ]

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

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    run inject_modifiers_only sasuke
    [ "$status" -eq 0 ]

    run read_task_field ac_priority
    [ "$status" -eq 0 ]
    [ "$output" = "AC1 > AC2 > AC3" ]

    run read_task_list_field parallel_ok
    [ "$status" -eq 0 ]
    [ "$output" = "AC1|AC2|AC3" ]
}

@test "deploy_task rejects None ninja_name and removes ghost task artifacts" {
    cat > "$TEST_PROJECT/queue/tasks/None.yaml" <<'EOF'
task:
  title: ghost
EOF
    : > "$TEST_PROJECT/queue/tasks/None.yaml.lock"

    run deploy_task_ac_only None
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

    run deploy_task_fast sasuke
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
    # Scout gate bypass (this test is for report archival, not scout_gate)
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_stale_test"
    echo "source: test" > "$TEST_PROJECT/queue/gates/cmd_stale_test/report_merge.done"
    # Simulate stale template from another ninja (STALL reassignment)
    cat > "$TEST_PROJECT/queue/reports/hanzo_report_cmd_stale_test.yaml" <<'EOF'
worker_id: hanzo
parent_cmd: cmd_stale_test
verdict:
status: pending
EOF
    run deploy_task_fast sasuke
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
    # Scout gate bypass (this test is for report preservation, not scout_gate)
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_preserve_test"
    echo "source: test" > "$TEST_PROJECT/queue/gates/cmd_preserve_test/report_merge.done"
    # Simulate completed report from another ninja
    cat > "$TEST_PROJECT/queue/reports/hanzo_report_cmd_preserve_test.yaml" <<'EOF'
worker_id: hanzo
parent_cmd: cmd_preserve_test
verdict: PASS
status: done
EOF
    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]
    # Completed report should be preserved (not archived)
    [ -f "$TEST_PROJECT/queue/reports/hanzo_report_cmd_preserve_test.yaml" ]
}

# =============================================================================
# cmd_1493: redeploy AC overwrite tests
# =============================================================================

@test "cmd_1493: redeploy with different task_id overwrites ACs from cmd source" {
    # Setup: shogun_to_karo.yaml with cmd_200's correct ACs
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_200:
    acceptance_criteria:
    - 'AC1: New correct AC for cmd_200'
    - 'AC2: Second AC for cmd_200'
    project: testproj
    purpose: test
EOF
    # Scout gate bypass (this test is for AC overwrite, not scout_gate)
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_200"
    echo "source: test" > "$TEST_PROJECT/queue/gates/cmd_200/report_merge.done"

    # Setup: task YAML with STALE ACs from a previous cmd + tracking fields
    # ac_version must match what _compute_ac_hash produces from these ACs
    # Simple string list ACs have no description: field → awk extracts nothing → md5("")=d41d8cd9
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "redeploy test"
  task_type: impl
  parent_cmd: cmd_200
  task_id: cmd_200_impl
  worker_id: sasuke
  status: assigned
  acceptance_criteria:
  - 'AC1: Old stale AC from previous cmd'
  ac_version: d41d8cd9
  _ac_task_id: cmd_100_impl
  _ac_worker_id: hayate
EOF

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    # Verify: ACs overwritten with cmd_200's ACs
    run grep "New correct AC for cmd_200" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    run grep "Second AC for cmd_200" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    # Old AC should be gone
    run grep "Old stale AC" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 1 ]
}

@test "cmd_1493: redeploy with different worker_id overwrites ACs from cmd source" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_300:
    acceptance_criteria:
    - 'AC1: Correct AC for cmd_300'
    project: testproj
    purpose: test
EOF
    # Scout gate bypass
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_300"
    echo "source: test" > "$TEST_PROJECT/queue/gates/cmd_300/report_merge.done"

    # Same task_id but different worker_id (re-assigned to different ninja)
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "worker change test"
  task_type: impl
  parent_cmd: cmd_300
  task_id: cmd_300_impl
  worker_id: sasuke
  status: assigned
  acceptance_criteria:
  - 'AC1: Stale AC from when hayate had this task'
  ac_version: d41d8cd9
  _ac_task_id: cmd_300_impl
  _ac_worker_id: hayate
EOF

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    run grep "Correct AC for cmd_300" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    run grep "Stale AC from when hayate" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 1 ]
}

@test "cmd_1493: same task_id and worker_id does NOT trigger AC overwrite" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_400:
    acceptance_criteria:
    - 'AC1: cmd source AC'
    project: testproj
    purpose: test
EOF
    # Scout gate bypass
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_400"
    echo "source: test" > "$TEST_PROJECT/queue/gates/cmd_400/report_merge.done"

    # Same task_id and worker_id — no redeploy, ACs should stay
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "no redeploy test"
  task_type: impl
  parent_cmd: cmd_400
  task_id: cmd_400_impl
  worker_id: sasuke
  status: assigned
  acceptance_criteria:
  - 'AC1: Already correct local AC'
  ac_version: some_hash
  _ac_task_id: cmd_400_impl
  _ac_worker_id: sasuke
EOF

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    # ACs should remain unchanged (no overwrite)
    run grep "Already correct local AC" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
}

@test "cmd_1493: first deploy (no tracking fields) DOES trigger AC overwrite (bug fix)" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_500:
    acceptance_criteria:
    - 'AC1: cmd source AC'
    project: testproj
    purpose: test
EOF
    # Scout gate bypass
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_500"
    echo "source: test" > "$TEST_PROJECT/queue/gates/cmd_500/report_merge.done"

    # Fresh deploy — no _ac_task_id/_ac_worker_id yet
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "first deploy"
  task_type: impl
  parent_cmd: cmd_500
  task_id: cmd_500_impl
  worker_id: sasuke
  status: assigned
  acceptance_criteria:
  - 'AC1: Karo-written AC for first deploy'
EOF

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    # cmd_1493 bug fix: first deploy SHOULD overwrite ACs from cmd source
    # (旧バグ: _ac_task_idが空→スキップ→前cmdのACが残存)
    run grep "cmd source AC" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    run grep "Karo-written AC for first deploy" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 1 ]

    # Tracking fields should be set after first deploy
    run read_task_field _ac_task_id
    [ "$status" -eq 0 ]
    [ "$output" = "cmd_500_impl" ]

    run read_task_field _ac_worker_id
    [ "$status" -eq 0 ]
    [ "$output" = "sasuke" ]
}

@test "cmd_1493: tracking fields updated after every deploy" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "tracking test"
  task_type: review
  task_id: my_task_123
  worker_id: sasuke
  acceptance_criteria:
  - ac1: first
  - ac2: second
  - ac3: third
EOF

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    run read_task_field _ac_task_id
    [ "$status" -eq 0 ]
    [ "$output" = "my_task_123" ]

    run read_task_field _ac_worker_id
    [ "$status" -eq 0 ]
    [ "$output" = "sasuke" ]
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

    run deploy_task_fast sasuke
    [ "$status" -eq 0 ]

    run read_related_detail L901
    [ "$status" -eq 0 ]
    [ "$output" = "legacy detail text" ]
}

@test "resolve_cmd_to_task: cmd_id引数でtask YAMLのparent_cmd/task_id/projectが自動設定される" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_600:
    acceptance_criteria:
    - 'AC1: New task AC'
    - 'AC2: Second AC'
    project: testproj
    target_path: scripts/deploy_task.sh
    type: impl
    purpose: test resolve
    title: resolve test
    status: pending
EOF
    # Scout gate bypass
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_600"
    echo "source: test" > "$TEST_PROJECT/queue/gates/cmd_600/report_merge.done"

    # 旧cmdのtask YAMLが残っている状態
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "old task"
  task_type: recon
  parent_cmd: cmd_OLD
  task_id: cmd_OLD_recon
  worker_id: sasuke
  status: done
  acceptance_criteria:
  - 'AC1: Stale old AC'
  _ac_task_id: cmd_OLD_recon
  _ac_worker_id: sasuke
EOF

    # cmd_id引数付きで配備
    run deploy_task_resolve_only sasuke cmd_600
    [ "$status" -eq 0 ]

    # parent_cmd/task_id/projectが新cmdに更新されたか
    run read_task_field parent_cmd
    [ "$status" -eq 0 ]
    [ "$output" = "cmd_600" ]

    run read_task_field task_id
    [ "$status" -eq 0 ]
    [ "$output" = "cmd_600_impl" ]

    run read_task_field project
    [ "$status" -eq 0 ]
    [ "$output" = "testproj" ]

    run read_task_field task_type
    [ "$status" -eq 0 ]
    [ "$output" = "impl" ]

    run read_task_field target_path
    [ "$status" -eq 0 ]
    [ "$output" = "scripts/deploy_task.sh" ]

    # ACが新cmdのものに上書きされたか
    run grep "New task AC" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    run grep "Stale old AC" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 1 ]
}

@test "resolve_cmd_to_task: cmd_id未指定時は既存動作維持（後方互換）" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_700:
    acceptance_criteria:
    - 'AC1: cmd_700 AC'
    project: testproj
    purpose: test
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "existing task"
  parent_cmd: cmd_700
  task_id: cmd_700_impl
  worker_id: sasuke
  status: assigned
  acceptance_criteria:
  - 'AC1: Already set AC'
  _ac_task_id: cmd_700_impl
  _ac_worker_id: sasuke
EOF

    # cmd_id無し（レガシー呼び出し）
    run deploy_task_ac_only sasuke "配備メッセージ" task_assigned karo
    [ "$status" -eq 0 ]

    # parent_cmdは変更されない
    run read_task_field parent_cmd
    [ "$status" -eq 0 ]
    [ "$output" = "cmd_700" ]

    # ACも変更されない（同一task_id → overwriteトリガーなし）
    run grep "Already set AC" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
}

@test "resolve_cmd_to_task: 存在しないcmd_idでBLOCK" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_800:
    acceptance_criteria:
    - 'AC1: exists'
    project: testproj
    purpose: test
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "test"
  parent_cmd: cmd_800
  task_id: cmd_800_impl
  worker_id: sasuke
  status: done
EOF

    # 存在しないcmd_idで配備試行
    run deploy_task_resolve_only sasuke cmd_999
    [ "$status" -eq 1 ]
}

# =============================================================================
# LK021: nested ac: format support (cmd_1604+)
# =============================================================================

@test "LK021: nested ac format (ac: {AC1: {title,criteria}}) is converted and overwrites task ACs" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_1610:
    project: testproj
    purpose: test nested ac
    ac:
      AC1:
        title: "NewHigh+UWP実行"
        criteria:
          - "新規スクリプト作成"
          - "入力: 20体"
          - "K=3, CLUSTER_LOOKBACK=36m"
      AC2:
        title: "統合ヒートマップ"
        criteria:
          - "6x12ヒートマップ出力"
          - "最適ペア特定"
EOF
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_1610"
    echo "source: test" > "$TEST_PROJECT/queue/gates/cmd_1610/report_merge.done"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "old task"
  task_type: impl
  parent_cmd: cmd_1610
  task_id: cmd_1610_impl
  worker_id: sasuke
  status: assigned
  acceptance_criteria:
  - 'AC1: Stale old AC'
  _ac_task_id: cmd_OLD_impl
  _ac_worker_id: sasuke
EOF

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    # Nested ac: should be converted and injected
    run grep "NewHigh+UWP" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    run grep "統合ヒートマップ" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    # Old AC should be gone
    run grep "Stale old AC" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 1 ]
    # id: fields should exist for binary_checks extraction
    run grep "id: AC1" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    run grep "id: AC2" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    # check: fields should exist for binary_checks extraction
    run grep "check:" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
}

@test "LK021: nested ac format via resolve_cmd_to_task (cmd_id arg)" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_1611:
    project: testproj
    type: impl
    purpose: test nested resolve
    title: nested resolve test
    ac:
      AC1:
        title: "First task"
        criteria:
          - "Do something"
      AC2:
        title: "Second task"
        criteria:
          - "Do something else"
          - "Verify result"
EOF
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_1611"
    echo "source: test" > "$TEST_PROJECT/queue/gates/cmd_1611/report_merge.done"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "old"
  parent_cmd: cmd_OLD
  task_id: cmd_OLD_impl
  worker_id: sasuke
  status: done
  acceptance_criteria:
  - 'AC1: Old'
  _ac_task_id: cmd_OLD_impl
  _ac_worker_id: sasuke
EOF

    run deploy_task_resolve_only sasuke cmd_1611
    [ "$status" -eq 0 ]

    # parent_cmd updated
    run read_task_field parent_cmd
    [ "$status" -eq 0 ]
    [ "$output" = "cmd_1611" ]

    run read_task_field task_id
    [ "$status" -eq 0 ]
    [ "$output" = "cmd_1611_impl" ]

    # ACs from nested ac: format
    run grep "First task" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    run grep "Do something else" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    run grep "Old" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 1 ]
}

@test "LK021: nested ac format generates binary_checks in report template" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_1612:
    project: testproj
    purpose: test bc extraction
    ac:
      AC1:
        title: "Build feature"
        criteria:
          - "Create new file"
          - "Add tests"
      AC2:
        title: "Deploy feature"
        criteria:
          - "Run deploy script"
EOF
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_1612"
    echo "source: test" > "$TEST_PROJECT/queue/gates/cmd_1612/report_merge.done"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "bc test"
  task_type: impl
  parent_cmd: cmd_1612
  task_id: cmd_1612_impl
  worker_id: sasuke
  status: assigned
  acceptance_criteria:
  - 'AC1: Stale'
  _ac_task_id: cmd_OLD_impl
  _ac_worker_id: sasuke
EOF

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    run inject_report_only sasuke
    [ "$status" -eq 0 ]

    # Report template should have binary_checks extracted from nested ac: format
    local report_file="$TEST_PROJECT/queue/reports/sasuke_report_cmd_1612.yaml"
    [ -f "$report_file" ]
    # AC1 and AC2 sections should exist in binary_checks
    run grep "AC1:" "$report_file"
    [ "$status" -eq 0 ]
    run grep "AC2:" "$report_file"
    [ "$status" -eq 0 ]
    # Check items from criteria should be present
    run grep "Create new file" "$report_file"
    [ "$status" -eq 0 ]
    run grep "Run deploy script" "$report_file"
    [ "$status" -eq 0 ]
}

@test "LK021: flat dict ac format (acceptance_criteria: {AC1: string}) is converted" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_1620:
    project: testproj
    purpose: test flat dict ac
    acceptance_criteria:
      AC1: "APIエンドポイント作成"
      AC2: "FE表示実装"
      AC3: "フォールバック表示"
EOF
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_1620"
    echo "source: test" > "$TEST_PROJECT/queue/gates/cmd_1620/report_merge.done"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "old"
  task_type: impl
  parent_cmd: cmd_1620
  task_id: cmd_1620_impl
  worker_id: sasuke
  status: assigned
  acceptance_criteria:
  - 'AC1: Stale'
  _ac_task_id: cmd_OLD_impl
  _ac_worker_id: sasuke
EOF

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    # Flat dict should be converted with id: fields
    run grep "id: AC1" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    run grep "id: AC2" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    run grep "APIエンドポイント作成" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    run grep "Stale" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 1 ]
}

@test "LK021: archive fallback also handles nested ac format" {
    # Empty shogun_to_karo
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands: {}
EOF
    # Archive with nested ac format
    mkdir -p "$TEST_PROJECT/queue/archive/cmds"
    cat > "$TEST_PROJECT/queue/archive/cmds/cmd_1613_done_20260330.yaml" <<'EOF'
commands:
  cmd_1613:
    project: testproj
    purpose: test archive fallback
    ac:
      AC1:
        title: "Archive AC"
        criteria:
          - "Archived criterion"
EOF
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_1613"
    echo "source: test" > "$TEST_PROJECT/queue/gates/cmd_1613/report_merge.done"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "archive test"
  task_type: impl
  parent_cmd: cmd_1613
  task_id: cmd_1613_impl
  worker_id: sasuke
  status: assigned
  acceptance_criteria:
  - 'AC1: Stale'
  _ac_task_id: cmd_OLD_impl
  _ac_worker_id: sasuke
EOF

    run deploy_task_ac_only sasuke
    [ "$status" -eq 0 ]

    # ACs from archive should be converted and injected
    run grep "Archive AC" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    run grep "Archived criterion" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
}
