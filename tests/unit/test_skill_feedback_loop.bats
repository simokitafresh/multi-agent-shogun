#!/usr/bin/env bats
# test_skill_feedback_loop.bats — cmd_2459 skill execution feedback loop

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SKILL_LOG_SCRIPT="$PROJECT_ROOT/scripts/skill_execution_log.sh"
    export SKILL_FEEDBACK_SCRIPT="$PROJECT_ROOT/scripts/skill_gate_feedback.sh"
    [ -x "$SKILL_LOG_SCRIPT" ] || return 1
    [ -x "$SKILL_FEEDBACK_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/skill_feedback.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/logs" "$TEST_TMPDIR/skills/report-bundle"
    cat > "$TEST_TMPDIR/skills/report-bundle/SKILL.md" <<'EOF'
---
name: report-bundle
description: |
  TRIGGER: report, gate_report_format, 報告YAML
---

# report-bundle

既存本文。
EOF
    export TEST_SKILL_LOG="$TEST_TMPDIR/logs/skill_execution_log.yaml"
    export TEST_SKILLS_DIR="$TEST_TMPDIR/skills"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "skill_execution_log records skill, executor, result, and stumbling_points" {
    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        bash "$SKILL_LOG_SCRIPT" report-bundle saizo PASS "迷いなし" gate_report_format report.yaml "$TEST_TMPDIR/skills/report-bundle/SKILL.md"
    [ "$status" -eq 0 ]

    run python3 - <<EOF
import yaml
data = yaml.safe_load(open("$TEST_SKILL_LOG", encoding="utf-8"))
entry = data["executions"][0]
assert entry["skill"] == "report-bundle"
assert entry["executor"] == "saizo"
assert entry["result"] == "PASS"
assert entry["stumbling_points"] == "迷いなし"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "skill_execution_log summary lists FAIL counts descending with top stumbling point" {
    cat > "$TEST_SKILL_LOG" <<'EOF'
executions:
- ts: "2026-05-02T10:00:00+0900"
  skill: "dashboard-update"
  executor: "hayate"
  result: "FAIL"
  stumbling_points: "verdict missing"
- ts: "2026-05-02T10:01:00+0900"
  skill: "report-write"
  executor: "hanzo"
  result: "FAIL"
  stumbling_points: "field empty"
- ts: "2026-05-02T10:02:00+0900"
  skill: "dashboard-update"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "verdict missing"
- ts: "2026-05-02T10:03:00+0900"
  skill: "dashboard-update"
  executor: "kotaro"
  result: "PASS"
  stumbling_points: "none"
EOF

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" bash "$SKILL_LOG_SCRIPT" summary
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "skill | fail_count | last_fail | top_stumbling_point" ]]
    [[ "${lines[1]}" == "dashboard-update | 2 | 2026-05-02T10:02:00+0900 | verdict missing" ]]
    [[ "${lines[2]}" == "report-write | 1 | 2026-05-02T10:01:00+0900 | field empty" ]]
}

@test "gate FAIL identifies skill and appends 注意ポイント" {
    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_FEEDBACK_SKILLS_DIRS="$TEST_SKILLS_DIR" \
        bash "$SKILL_FEEDBACK_SCRIPT" \
            --gate gate_report_format \
            --result FAIL \
            --reason "binary_checks.result empty" \
            --executor saizo \
            --source queue/reports/saizo_report.yaml
    [ "$status" -eq 0 ]
    [[ "$output" == *"UPDATED:"* ]]

    run grep -n "## 注意ポイント\\|gate=gate_report_format\\|binary_checks.result empty" "$TEST_TMPDIR/skills/report-bundle/SKILL.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## 注意ポイント"* ]]
    [[ "$output" == *"gate=gate_report_format"* ]]
    [[ "$output" == *"binary_checks.result empty"* ]]

    run python3 - <<EOF
import yaml
data = yaml.safe_load(open("$TEST_SKILL_LOG", encoding="utf-8"))
entry = data["executions"][0]
assert entry["skill"] == "report-bundle"
assert entry["result"] == "FAIL"
assert entry["gate"] == "gate_report_format"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "gate FAIL duplicate does not append log or 注意ポイント twice" {
    for attempt in 1 2; do
        run env \
            SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
            SKILL_FEEDBACK_SKILLS_DIRS="$TEST_SKILLS_DIR" \
            bash "$SKILL_FEEDBACK_SCRIPT" \
                --gate gate_report_format \
                --result FAIL \
                --reason "binary_checks.result empty" \
                --executor saizo \
                --source queue/reports/saizo_report.yaml
        [ "$status" -eq 0 ]
    done
    [[ "$output" == *"DUPLICATE:"* ]]

    run python3 - <<EOF
import pathlib
import yaml

data = yaml.safe_load(open("$TEST_SKILL_LOG", encoding="utf-8"))
assert len(data["executions"]) == 1
skill_text = pathlib.Path("$TEST_TMPDIR/skills/report-bundle/SKILL.md").read_text(encoding="utf-8")
assert skill_text.count("gate=gate_report_format") == 1
assert skill_text.count("binary_checks.result empty") == 1
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
