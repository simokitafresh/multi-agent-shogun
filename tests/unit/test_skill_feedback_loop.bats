#!/usr/bin/env bats
# test_necessity: skill品質ログは実行結果を重複なく記録し未解消FAILだけを改善入力へ反映する
# test_skill_feedback_loop.bats — cmd_2459 skill execution feedback loop
# Test-speed design: [[skill-feedback-loop-test-speed]]

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SKILL_LOG_SCRIPT="$PROJECT_ROOT/scripts/skill_execution_log.sh"
    export SKILL_FEEDBACK_SCRIPT="$PROJECT_ROOT/scripts/skill_gate_feedback.sh"
    export SKILL_AUTO_IMPROVE_SCRIPT="$PROJECT_ROOT/scripts/skill_auto_improve.sh"
    export SKILL_METRICS_SCRIPT="$PROJECT_ROOT/scripts/skill_metrics.sh"
    export DASHBOARD_UPDATE_SCRIPT="$PROJECT_ROOT/scripts/dashboard_update.sh"
    [ -x "$SKILL_LOG_SCRIPT" ] || return 1
    [ -x "$SKILL_FEEDBACK_SCRIPT" ] || return 1
    [ -x "$SKILL_AUTO_IMPROVE_SCRIPT" ] || return 1
    [ -x "$SKILL_METRICS_SCRIPT" ] || return 1
    [ -x "$DASHBOARD_UPDATE_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/skill_feedback.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/logs" "$TEST_TMPDIR/skills/report-bundle" "$TEST_TMPDIR/skills/report-write"
    cat > "$TEST_TMPDIR/skills/report-bundle/SKILL.md" <<'EOF'
---
name: report-bundle
description: |
  TRIGGER: report, gate_report_format, 報告YAML
quality_metric: "report gate pass rate"
---

# report-bundle

既存本文。
EOF
    cat > "$TEST_TMPDIR/skills/report-write/SKILL.md" <<'EOF'
---
name: report-write
description: |
  TRIGGER: 報告YAML作成, report_field_set, FILL_THIS修正
quality_metric: "report gate pass rate"
---

# report-write

既存本文。
EOF
    export TEST_SKILL_LOG="$TEST_TMPDIR/logs/skill_execution_log.yaml"
    export TEST_SKILLS_DIR="$TEST_TMPDIR/skills"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

install_dashboard_update_dependencies() {
    local test_repo="$1"
    mkdir -p "$test_repo/scripts/gates"
    cp "$PROJECT_ROOT/scripts/lib/review_approval.sh" "$test_repo/scripts/lib/review_approval.sh"
    cp "$PROJECT_ROOT/scripts/lib/report_commit_identity.py" "$test_repo/scripts/lib/report_commit_identity.py"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format.sh" "$test_repo/scripts/gates/gate_report_format.sh"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_combined.py" "$test_repo/scripts/gates/gate_report_format_combined.py"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_autofix_main.py" "$test_repo/scripts/gates/gate_report_autofix_main.py"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_main.py" "$test_repo/scripts/gates/gate_report_format_main.py"
}

complete_dashboard_report_fixture() {
    local report="$1"
    python3 - "$report" <<'PY'
import pathlib, sys, yaml
p = pathlib.Path(sys.argv[1])
d = yaml.safe_load(p.read_text()) or {}
d.update({
    "task_id": d["parent_cmd"], "task_type": "hotfix", "timestamp": "2026-07-12T00:00:00+09:00",
    "status": "completed", "ac_version_read": "fixture-v1",
    "purpose_validation": {"cmd_purpose": "dashboard fixture", "fit": True, "purpose_gap": ""},
    "files_modified": ["tests/unit/test_skill_feedback_loop.bats"],
    "lesson_candidate": {"found": False, "no_lesson_reason": "既存fixture依存の追随確認"},
    "lessons_useful": [{"id": "L659", "useful": True, "reason": "fixture依存追随の既知教訓"}],
    "operational_simulation": {
        "command": "bash scripts/dashboard_update.sh fixture --dry-run",
        "expected": "dashboard fixture path completes with the declared result",
        "actual": "fixture report supplies integration evidence for production gate validation",
        "result": "PASS",
    },
    "binary_checks": {"AC1": [{"check": "dashboard fixture report validates with production gate", "result": "yes"}]},
    "assumption_invalidation": {"found": False, "affected_cmds": [], "detail": ""},
    "verdict": "PASS",
})
p.write_text(yaml.safe_dump(d, sort_keys=False, allow_unicode=True))
PY
}

@test "skill_metrics calculates quality scores from SKILL.md quality_metric and execution log" {
    mkdir -p "$TEST_TMPDIR/skills/dashboard-update"
    cat > "$TEST_TMPDIR/skills/dashboard-update/SKILL.md" <<'EOF'
---
name: dashboard-update
description: dashboard updater
quality_metric: "dashboard update clear rate"
---

# dashboard-update
EOF

    cat > "$TEST_SKILL_LOG" <<'EOF'
executions:
- ts: "2026-05-02T10:00:00+0900"
  skill: "dashboard-update"
  executor: "hayate"
  result: "PASS"
  stumbling_points: "ok"
- ts: "2026-05-02T10:01:00+0900"
  skill: "dashboard-update"
  executor: "hanzo"
  result: "FAIL"
  stumbling_points: "format"
- ts: "2026-05-02T10:02:00+0900"
  skill: "report-bundle"
  executor: "saizo"
  result: "PASS"
  stumbling_points: "ok"
EOF

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_METRICS_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        bash "$SKILL_METRICS_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "skill | quality_score | pass | fail | total | last_result | quality_metric" ]]
    [[ "$output" == *"dashboard-update | 50.0% | 1 | 1 | 2 | FAIL | dashboard update clear rate"* ]]
    [[ "$output" == *"report-bundle | 100.0% | 1 | 0 | 1 | PASS | report gate pass rate"* ]]
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
assert entry["used"] == "true"
assert entry["stumbling_points"] == "迷いなし"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "skill_execution_log summary lists only latest unresolved FAIL with top stumbling point" {
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
    [[ "${lines[1]}" == "report-write | 1 | 2026-05-02T10:01:00+0900 | field empty" ]]
    [[ "$output" != *"dashboard-update |"* ]]
}

@test "skill_execution_log summary treats short cmd FAIL as resolved by full cmd PASS" {
    cat > "$TEST_SKILL_LOG" <<'EOF'
executions:
- ts: "2026-06-20T00:37:23+0900"
  skill: "dashboard-update"
  executor: "karo"
  result: "PASS"
  used: "true"
  stumbling_points: "dashboard_update.sh exit=0 cmd=cmd_karo_hotfix_ga093_prepush_test_select_mapping_20260620 dry_run=false"
  source: "cmd_karo_hotfix_ga093_prepush_test_select_mapping_20260620"
- ts: "2026-06-20T00:38:28+0900"
  skill: "dashboard-update"
  executor: "karo"
  result: "FAIL"
  used: "true"
  stumbling_points: "dashboard_update.sh exit=1 cmd=cmd_karo_hotfix_ga093 dry_run=false"
  source: "cmd_karo_hotfix_ga093"
EOF

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" bash "$SKILL_LOG_SCRIPT" summary
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "skill | fail_count | last_fail | top_stumbling_point" ]]
    [[ "${#lines[@]}" -eq 1 ]]
}

@test "skill_execution_log source-summary collapses retries and preserves exclusions" {
    cat > "$TEST_SKILL_LOG" <<'EOF'
executions:
- {ts: "01", skill: "report-write", result: "FAIL", source: "cmd_100"}
- {ts: "02", skill: "report-write", result: "PASS", source: "cmd_100"}
- {ts: "03", skill: "report-write", result: "PASS", source: "cmd_200"}
- {ts: "04", skill: "report-write", result: "FAIL", source: "cmd_200"}
- {ts: "05", skill: "report-write", result: "FAIL", source: "cmd_300"}
- {ts: "06", skill: "report-write", result: "PASS", source: "cmd_400"}
- {ts: "07", skill: "report-write", result: "FAIL", source: ""}
- {ts: "08", skill: "report-write", result: "PASS", source: ""}
- {ts: "09", skill: "report-write", result: "FAIL", used: false, source: "cmd_500"}
- {ts: "10", skill: "report-write", result: "FAIL", source: "cmd_test_fixture"}
- {ts: "11", skill: "report-write", result: "FAIL", source: "cmd_training_speed_fixture"}
EOF
    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" bash "$SKILL_LOG_SCRIPT" source-summary
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == $'skill\tfail_rate\tfail_count\ttotal\tsuccess_streak\tlast_result\tlast_ts' ]]
    [[ "${lines[1]}" == $'report-write\t38\t3\t8\t3\tPASS\t11' ]]
}

@test "skill_execution_log source-summary tolerates malformed legacy log" {
    cat > "$TEST_SKILL_LOG" <<'EOF'
executions:
- ts: "01"
  skill: "report-write"
  result: "FAIL"
  source: "cmd_100"
  stumbling_points: "legacy "quote"
- ts: "02"
  skill: "report-write"
  result: "PASS"
  source: "cmd_100"
EOF
    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" bash "$SKILL_LOG_SCRIPT" source-summary
    [ "$status" -eq 0 ]
    [[ "${lines[1]}" == $'report-write\t0\t0\t1\t1\tPASS\t02' ]]
}

@test "skill_execution_log source-summary applies the last-50 boundary before source collapse" {
    printf 'executions:\n' > "$TEST_SKILL_LOG"
    printf '%s\n' '- {ts: "00", skill: "report-write", result: "FAIL", source: "outside"}' >> "$TEST_SKILL_LOG"
    for i in $(seq 1 50); do
        printf -- '- {ts: "%02d", skill: "report-write", result: "PASS", source: "inside_%02d"}\n' "$i" "$i" >> "$TEST_SKILL_LOG"
    done
    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" bash "$SKILL_LOG_SCRIPT" source-summary
    [ "$status" -eq 0 ]
    [[ "${lines[1]}" == $'report-write\t0\t0\t50\t50\tPASS\t50' ]]
}

@test "skill log readers tolerate legacy unescaped traceback quotes" {
    cat > "$TEST_SKILL_LOG" <<'EOF'
executions:
- ts: "2026-06-11T21:47:20+0900"
  skill: "note-draft"
  executor: "shogun"
  result: "FAIL"
  used: "true"
  stumbling_points: "Python exit 1:   File "<stdin>", line 143, in login_if_needed
RuntimeError: reCAPTCHA challenge"
  gate: "none"
  source: "note_draft.sh"
  skill_path: "/tmp/skills/note-draft/SKILL.md"
- ts: "2026-06-11T21:50:13+0900"
  skill: "report-write"
  executor: "kagemaru"
  result: "FAIL"
  used: "true"
  stumbling_points: "Traceback (most recent call last):\n  File \"<stdin>\", line 1, in <module>\nValueError: \"quoted\""
  gate: "gate_report_format"
  source: "queue/reports/kagemaru_report_cmd_1.yaml"
  skill_path: "$TEST_TMPDIR/skills/report-write/SKILL.md"
EOF

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" bash "$SKILL_LOG_SCRIPT" summary
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "skill | fail_count | last_fail | top_stumbling_point" ]]
    [[ "$output" == *"note-draft | 1 | 2026-06-11T21:47:20+0900 | Python exit 1:   File \"<stdin>\", line 143, in login_if_needed"* ]]
    [[ "$output" == *"report-write | 1 | 2026-06-11T21:50:13+0900 | Traceback (most recent call last):"* ]]

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"report-write | 1 | 1 | 2026-06-11T21:50:13+0900 | gate_report_format | Traceback (most recent call last):"* ]]
}

@test "skill aggregation excludes used false FAIL entries" {
    mkdir -p "$TEST_TMPDIR/skills/report-write" "$TEST_TMPDIR/skills/dashboard-update"
    cat > "$TEST_TMPDIR/skills/report-write/SKILL.md" <<'EOF'
---
name: report-write
quality_metric: "report gate pass rate"
---
# report-write
EOF
    cat > "$TEST_TMPDIR/skills/dashboard-update/SKILL.md" <<'EOF'
---
name: dashboard-update
quality_metric: "dashboard update clear rate"
---
# dashboard-update
EOF
    cat > "$TEST_SKILL_LOG" <<'EOF'
executions:
- ts: "2026-05-02T10:00:00+0900"
  skill: "report-write"
  executor: "hayate"
  result: "FAIL"
  used: "false"
  stumbling_points: "inferred but unused"
  gate: "gate_report_format"
- ts: "2026-05-02T10:01:00+0900"
  skill: "report-write"
  executor: "hayate"
  result: "FAIL"
  used: "true"
  stumbling_points: "actual failure"
  gate: "gate_report_format"
- ts: "2026-05-02T10:02:00+0900"
  skill: "dashboard-update"
  executor: "hayate"
  result: "FAIL"
  used: "false"
  stumbling_points: "unused dashboard failure"
  gate: "gate_report_format"
EOF

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" bash "$SKILL_LOG_SCRIPT" summary
    [ "$status" -eq 0 ]
    [[ "$output" == *"report-write | 1 | 2026-05-02T10:01:00+0900 | actual failure"* ]]
    [[ "$output" != *"dashboard-update |"* ]]
    [[ "$output" != *"inferred but unused"* ]]

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_METRICS_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        bash "$SKILL_METRICS_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"report-write | 0.0% | 0 | 1 | 1 | FAIL | report gate pass rate"* ]]
    [[ "$output" == *"dashboard-update | N/A | 0 | 0 | 0 | N/A | dashboard update clear rate"* ]]

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        bash "$SKILL_AUTO_IMPROVE_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"report-write | 1 | 1 | 2026-05-02T10:01:00+0900 | gate_report_format | actual failure"* ]]
    [[ "$output" != *"dashboard-update |"* ]]
    [[ "$output" != *"unused dashboard failure"* ]]
}

@test "skill_execution_log skips entries whose source is under tests path" {
    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        bash "$SKILL_LOG_SCRIPT" report-write hayate FAIL "fixture failure" gate_report_format tests/unit/fixture_report.yaml "$TEST_TMPDIR/skills/report-bundle/SKILL.md"
    [ "$status" -eq 0 ]

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        bash "$SKILL_LOG_SCRIPT" report-write hayate FAIL "fixture failure" gate_report_format "$PROJECT_ROOT/tests/unit/fixture_report.yaml" "$TEST_TMPDIR/skills/report-bundle/SKILL.md"
    [ "$status" -eq 0 ]

    run python3 - <<EOF
import pathlib
import yaml

path = pathlib.Path("$TEST_SKILL_LOG")
if path.exists():
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    entries = data.get("executions") or []
else:
    entries = []
assert not [entry for entry in entries if "tests/" in str(entry.get("source", ""))]
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "gate FAIL identifies skill and appends 注意ポイント" {
    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        bash "$SKILL_LOG_SCRIPT" report-bundle saizo FAIL "binary_checks.result empty" gate_report_format queue/reports/saizo_report.yaml "$TEST_TMPDIR/skills/report-bundle/SKILL.md"
    [ "$status" -eq 0 ]

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

    run grep -n "## 注意ポイント\\|gate=gate_report_format\\|binary_checks.result empty" "$TEST_TMPDIR/skills/report-write/SKILL.md"
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
            --source queue/reports/saizo_report.yaml \
            --skill report-bundle
        [ "$status" -eq 0 ]
    done
    [[ "$output" == *"DUPLICATE:"* || "$output" == *"UNCHANGED:"* ]]

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

@test "gate_report_format failure is routed away from dashboard-update" {
    mkdir -p "$TEST_TMPDIR/skills/dashboard-update" "$TEST_TMPDIR/skills/report-write"
    cat > "$TEST_TMPDIR/skills/dashboard-update/SKILL.md" <<'EOF'
---
name: dashboard-update
description: |
  TRIGGER: /dashboard-update、cmd完了後のダッシュボード更新、GATE CLEAR後
---
# dashboard-update
EOF
    cat > "$TEST_TMPDIR/skills/report-write/SKILL.md" <<'EOF'
---
name: report-write
description: |
  TRIGGER: /report-write、報告YAML作成、報告記入
---
# report-write
EOF
    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        bash "$SKILL_LOG_SCRIPT" report-write hayate FAIL "dashboard-update text in reason but report-write owns it" gate_report_format queue/reports/hayate_report_cmd_2473.yaml "$TEST_TMPDIR/skills/report-write/SKILL.md"
    [ "$status" -eq 0 ]

    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_FEEDBACK_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        bash "$SKILL_FEEDBACK_SCRIPT" \
            --gate gate_report_format \
            --result FAIL \
            --reason "dashboard-update text in reason but report-write owns it" \
            --executor hayate \
            --source queue/reports/hayate_report_cmd_2473.yaml
    [ "$status" -eq 0 ]

    run python3 - <<EOF
import yaml
data = yaml.safe_load(open("$TEST_SKILL_LOG", encoding="utf-8"))
entry = data["executions"][-1]
assert entry["skill"] == "report-write"
assert entry["gate"] == "gate_report_format"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]

    run grep -n "dashboard-update text in reason but report-write owns it" "$TEST_TMPDIR/skills/report-write/SKILL.md"
    [ "$status" -eq 0 ]
    run grep -n "dashboard-update text in reason but report-write owns it" "$TEST_TMPDIR/skills/dashboard-update/SKILL.md"
    [ "$status" -ne 0 ]
}

@test "cmd_complete_gate routes workflow failures to cmd-complete and report content failures to report-write" {
    run python3 - <<'PY'
import os
from pathlib import Path

text = (Path(os.environ["PROJECT_ROOT"]) / "scripts/cmd_complete_gate.sh").read_text(encoding="utf-8")
feedback_marker = "# BLOCK理由から還流先スキルを特定"
feedback_start = text.index(feedback_marker)
start = text.index('case "$block_reason" in', feedback_start)
end = text.index('        esac', start)
case_block = text[start:end]
case_lines = case_block.splitlines()

workflow_idx = next(i for i, line in enumerate(case_lines) if "cmd-complete" in line)
report_idx = next(i for i, line in enumerate(case_lines) if "report-write" in line)
workflow_line = case_lines[workflow_idx - 1]
report_line = case_lines[report_idx - 1]

for pattern in ("missing_gate", "lesson_done_missing", "draft_lessons"):
    assert pattern in workflow_line, f"{pattern} must route to cmd-complete"
    assert pattern not in report_line, f"{pattern} must not route to report-write"

for pattern in ("lessons_useful", "lesson_candidate", "report_format", "report_yaml_missing"):
    assert pattern in report_line, f"{pattern} must route to report-write"

print("OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "skill_gate_feedback excludes karo_direct and training cmd-complete failures" {
    mkdir -p "$TEST_TMPDIR/skills/cmd-complete"
    cat > "$TEST_TMPDIR/skills/cmd-complete/SKILL.md" <<'EOF'
---
name: cmd-complete
---
# cmd-complete
EOF

    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_FEEDBACK_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        bash "$SKILL_FEEDBACK_SCRIPT" \
            --gate cmd_complete_gate \
            --result FAIL \
            --reason missing_gate \
            --executor karo \
            --source cmd_karo_direct_skill_metric_fix \
            --skill cmd-complete
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP: cmd-complete feedback excluded for cmd_karo_direct_skill_metric_fix"* ]]
    [ ! -f "$TEST_SKILL_LOG" ]
    ! grep -q "注意ポイント" "$TEST_TMPDIR/skills/cmd-complete/SKILL.md"

    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_FEEDBACK_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        bash "$SKILL_FEEDBACK_SCRIPT" \
            --gate cmd_complete_gate \
            --result FAIL \
            --reason missing_gate \
            --executor karo \
            --source cmd_training_001 \
            --skill cmd-complete
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP: cmd-complete feedback excluded for cmd_training_001"* ]]
    [ ! -f "$TEST_SKILL_LOG" ]
    ! grep -q "注意ポイント" "$TEST_TMPDIR/skills/cmd-complete/SKILL.md"
}

@test "skill_gate_feedback keeps normal cmd-complete failures" {
    mkdir -p "$TEST_TMPDIR/skills/cmd-complete"
    cat > "$TEST_TMPDIR/skills/cmd-complete/SKILL.md" <<'EOF'
---
name: cmd-complete
---
# cmd-complete
EOF

    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_FEEDBACK_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        bash "$SKILL_FEEDBACK_SCRIPT" \
            --gate cmd_complete_gate \
            --result FAIL \
            --reason missing_gate \
            --executor karo \
            --source cmd_2615 \
            --skill cmd-complete
    [ "$status" -eq 0 ]
    [[ "$output" == *"UPDATED: $TEST_TMPDIR/skills/cmd-complete/SKILL.md"* ]]

    run python3 - <<EOF
import yaml
data = yaml.safe_load(open("$TEST_SKILL_LOG", encoding="utf-8"))
entry = data["executions"][0]
assert entry["skill"] == "cmd-complete"
assert entry["result"] == "FAIL"
assert entry["gate"] == "cmd_complete_gate"
assert entry["source"] == "cmd_2615"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    grep -q "gate=cmd_complete_gate result=FAIL executor=karo reason=missing_gate" "$TEST_TMPDIR/skills/cmd-complete/SKILL.md"
}

@test "explicit report-write and ninja-commit routing still records requested skill" {
    mkdir -p "$TEST_TMPDIR/skills/report-write" "$TEST_TMPDIR/skills/ninja-commit"
    cat > "$TEST_TMPDIR/skills/report-write/SKILL.md" <<'EOF'
---
name: report-write
description: |
  TRIGGER: /report-write、報告YAML作成、報告記入
---
# report-write
EOF
    cat > "$TEST_TMPDIR/skills/ninja-commit/SKILL.md" <<'EOF'
---
name: ninja-commit
description: |
  TRIGGER: /ninja-commit、コミット、commit
---
# ninja-commit
EOF

    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_FEEDBACK_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        bash "$SKILL_FEEDBACK_SCRIPT" \
            --gate cmd_complete_gate \
            --result FAIL \
            --reason "commit missing" \
            --executor hayate \
            --source cmd_2473 \
            --skill ninja-commit
    [ "$status" -eq 0 ]

    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_FEEDBACK_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        bash "$SKILL_FEEDBACK_SCRIPT" \
            --gate gate_report_format \
            --result FAIL \
            --reason "lesson_candidate missing" \
            --executor hayate \
            --source queue/reports/hayate_report_cmd_2473.yaml \
            --skill report-write
    [ "$status" -eq 0 ]

    run python3 - <<EOF
import yaml
data = yaml.safe_load(open("$TEST_SKILL_LOG", encoding="utf-8"))
skills = [entry["skill"] for entry in data["executions"]]
assert "ninja-commit" in skills
assert "report-write" in skills
assert all(entry["used"] == "false" for entry in data["executions"])
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "dashboard_update.sh dry-run logs dashboard-update PASS with dashboard_update gate" {
    TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/scripts/lib" "$TEST_REPO/config" \
             "$TEST_REPO/queue/reports" "$TEST_REPO/queue/archive/reports" "$TEST_REPO/queue/gates/cmd_2473" "$TEST_REPO/skills/dashboard-update"
    cp "$DASHBOARD_UPDATE_SCRIPT" "$TEST_REPO/scripts/dashboard_update.sh"
    cp "$PROJECT_ROOT/scripts/review_bundle.py" "$TEST_REPO/scripts/review_bundle.py"
    cp "$SKILL_LOG_SCRIPT" "$TEST_REPO/scripts/skill_execution_log.sh"
    install_dashboard_update_dependencies "$TEST_REPO"
    chmod +x "$TEST_REPO/scripts/dashboard_update.sh" "$TEST_REPO/scripts/skill_execution_log.sh"
    cat > "$TEST_REPO/scripts/lib/agent_config.sh" <<'EOF'
#!/usr/bin/env bash
EOF
    cat > "$TEST_REPO/config/settings.yaml" <<'EOF'
cli:
  agents: {}
EOF
    cat > "$TEST_REPO/dashboard.md" <<'EOF'
# Dashboard
<!-- KARO_SECTION_START -->
old
EOF
    cat > "$TEST_REPO/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_2473:
    purpose: test purpose
EOF
    cat > "$TEST_REPO/queue/reports/hayate_report_cmd_2473.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_2473
status: completed
result:
  summary: dashboard update test
EOF
    complete_dashboard_report_fixture "$TEST_REPO/queue/reports/hayate_report_cmd_2473.yaml"
    python3 - "$TEST_REPO/queue/reports/hayate_report_cmd_2473.yaml" <<'PY'
import pathlib, sys, yaml
p = pathlib.Path(sys.argv[1])
d = yaml.safe_load(p.read_text()) or {}
d["task_type"] = "recon2"
d["commit_contract"] = {"required": False, "reason": "hook-state fixture has no production change"}
d["files_modified"] = [{"path": "queue/reports/hayate_report_cmd_2473.yaml", "change": "fixture evidence only"}]
d.setdefault("binary_checks", {})["commit"] = [{"check": "no-commit fixture contract", "result": "yes"}]
p.write_text(yaml.safe_dump(d, sort_keys=False, allow_unicode=True))
PY
    cat > "$TEST_REPO/queue/gates/cmd_2473/sg7_bundle.json" <<'EOF'
{"review":{"cmd_id":"cmd_2473","report_fingerprint":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","verdict":"APPROVE","cmd_spec_summary":{"acceptance_criteria_count":1,"scope":["fixture"],"project":"infra"},"dashboard_line":"- **cmd_2473**: 完了。bundle line is authoritative"}}
EOF
    # The reviewed bundle must remain authoritative even when a later task
    # makes legacy report revalidation fail.  This reproduces cmd_3932 where
    # the worker's next task had 14 checks while the archived report had 3.
    python3 - "$TEST_REPO/queue/reports/hayate_report_cmd_2473.yaml" <<'PY'
import pathlib, sys, yaml
p = pathlib.Path(sys.argv[1])
d = yaml.safe_load(p.read_text(encoding="utf-8"))
d["binary_checks"]["AC1"][0]["result"] = "no"
d["verdict"] = "FAIL"
p.write_text(yaml.safe_dump(d, sort_keys=False, allow_unicode=True), encoding="utf-8")
PY
    cat > "$TEST_REPO/skills/dashboard-update/SKILL.md" <<'EOF'
# dashboard-update
EOF

    run env SHOGUN_COMPLETION_GENERATION=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" bash "$TEST_REPO/scripts/dashboard_update.sh" cmd_2473 --bundle queue/gates/cmd_2473/sg7_bundle.json --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"bundle line is authoritative"* ]]
    [[ "$output" != *"test purpose"* ]]

    run python3 - <<EOF
import yaml
data = yaml.safe_load(open("$TEST_SKILL_LOG", encoding="utf-8"))
entry = data["executions"][-1]
assert entry["skill"] == "dashboard-update"
assert entry["result"] == "PASS"
assert entry["gate"] == "dashboard_update"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "dashboard_update.sh skips pre-completion invocation and logs used=false" {
    TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/scripts/lib" "$TEST_REPO/config" \
             "$TEST_REPO/queue/reports" "$TEST_REPO/queue/archive/reports" "$TEST_REPO/skills/dashboard-update"
    cp "$DASHBOARD_UPDATE_SCRIPT" "$TEST_REPO/scripts/dashboard_update.sh"
    cp "$SKILL_LOG_SCRIPT" "$TEST_REPO/scripts/skill_execution_log.sh"
    install_dashboard_update_dependencies "$TEST_REPO"
    chmod +x "$TEST_REPO/scripts/dashboard_update.sh" "$TEST_REPO/scripts/skill_execution_log.sh"
    cat > "$TEST_REPO/scripts/lib/agent_config.sh" <<'EOF'
#!/usr/bin/env bash
EOF
    cat > "$TEST_REPO/config/settings.yaml" <<'EOF'
cli:
  agents: {}
EOF
    cat > "$TEST_REPO/dashboard.md" <<'EOF'
# Dashboard
unchanged sentinel
EOF
    cat > "$TEST_REPO/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_5000:
    purpose: in progress fixture
EOF
    cat > "$TEST_REPO/queue/reports/kotaro_report_cmd_5000.yaml" <<'EOF'
worker_id: kotaro
parent_cmd: cmd_5000
status: pending
result:
  summary: FILL_THIS
EOF
    cat > "$TEST_REPO/skills/dashboard-update/SKILL.md" <<'EOF'
# dashboard-update
EOF

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" SKIP_AUTO_SECTION=1 \
        bash "$TEST_REPO/scripts/dashboard_update.sh" cmd_5000
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP: dashboard-update is post-completion only"* ]]
    run grep -F "unchanged sentinel" "$TEST_REPO/dashboard.md"
    [ "$status" -eq 0 ]

    run python3 - <<EOF
import yaml
data = yaml.safe_load(open("$TEST_SKILL_LOG", encoding="utf-8"))
entry = data["executions"][-1]
assert entry["skill"] == "dashboard-update"
assert entry["result"] == "SKIP"
assert entry["used"] == "false"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "dashboard_update.sh validates completed report and ignores stale pending sibling" {
    TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/scripts/lib" "$TEST_REPO/config" \
             "$TEST_REPO/queue/reports" "$TEST_REPO/queue/archive/reports" "$TEST_REPO/skills/dashboard-update"
    cp "$DASHBOARD_UPDATE_SCRIPT" "$TEST_REPO/scripts/dashboard_update.sh"
    cp "$SKILL_LOG_SCRIPT" "$TEST_REPO/scripts/skill_execution_log.sh"
    install_dashboard_update_dependencies "$TEST_REPO"
    chmod +x "$TEST_REPO/scripts/dashboard_update.sh" "$TEST_REPO/scripts/skill_execution_log.sh"
    cat > "$TEST_REPO/scripts/lib/agent_config.sh" <<'EOF'
#!/usr/bin/env bash
EOF
    cat > "$TEST_REPO/config/settings.yaml" <<'EOF'
cli:
  agents: {}
EOF
    cat > "$TEST_REPO/dashboard.md" <<'EOF'
# Dashboard
## 最新更新
EOF
    cat > "$TEST_REPO/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_5001:
    purpose: completed fixture
EOF
    cat > "$TEST_REPO/queue/reports/hanzo_report_cmd_5001.yaml" <<'EOF'
worker_id: hanzo
parent_cmd: cmd_5001
status: completed
result:
  summary: completed evidence wins
EOF
    complete_dashboard_report_fixture "$TEST_REPO/queue/reports/hanzo_report_cmd_5001.yaml"
    cat > "$TEST_REPO/queue/reports/tobisaru_report.yaml" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_5001
status: pending
result:
  summary: FILL_THIS
EOF
    cat > "$TEST_REPO/skills/dashboard-update/SKILL.md" <<'EOF'
# dashboard-update
EOF

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" SKILL_EXECUTION_LOG_DISABLE=1 SKIP_AUTO_SECTION=1 \
        bash "$TEST_REPO/scripts/dashboard_update.sh" cmd_5001 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"completed evidence wins"* ]]
    [[ "$output" != *"FILL_THIS placeholder remaining"* ]]
}

@test "dashboard_update.sh finds report by parent_cmd when filename lacks cmd_id" {
    TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/scripts/lib" "$TEST_REPO/config" \
             "$TEST_REPO/queue/reports" "$TEST_REPO/queue/archive/reports" "$TEST_REPO/skills/dashboard-update"
    cp "$DASHBOARD_UPDATE_SCRIPT" "$TEST_REPO/scripts/dashboard_update.sh"
    cp "$SKILL_LOG_SCRIPT" "$TEST_REPO/scripts/skill_execution_log.sh"
    install_dashboard_update_dependencies "$TEST_REPO"
    chmod +x "$TEST_REPO/scripts/dashboard_update.sh" "$TEST_REPO/scripts/skill_execution_log.sh"
    cat > "$TEST_REPO/scripts/lib/agent_config.sh" <<'EOF'
#!/usr/bin/env bash
EOF
    cat > "$TEST_REPO/config/settings.yaml" <<'EOF'
cli:
  agents: {}
EOF
    cat > "$TEST_REPO/dashboard.md" <<'EOF'
# Dashboard
## 最新更新
EOF
    cat > "$TEST_REPO/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_3000:
    purpose: fallback purpose
EOF
    cat > "$TEST_REPO/queue/archive/reports/hanzo_report_task_slug_20260503.yaml" <<'EOF'
worker_id: hanzo
parent_cmd: cmd_3000
status: completed
timestamp: '2026-05-03T03:33:34'
result:
  summary: fallback report found
EOF
    complete_dashboard_report_fixture "$TEST_REPO/queue/archive/reports/hanzo_report_task_slug_20260503.yaml"
    cat > "$TEST_REPO/skills/dashboard-update/SKILL.md" <<'EOF'
# dashboard-update
EOF

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" SKILL_EXECUTION_LOG_DISABLE=1 SKIP_AUTO_SECTION=1 bash "$TEST_REPO/scripts/dashboard_update.sh" cmd_3000 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN: - **cmd_3000**:"* ]]
    [[ "$output" == *"fallback purpose"* ]]
    [[ "$output" == *"fallback report found"* ]]
}

@test "dashboard_update.sh accepts training cmd ids containing hyphenated skill names" {
    TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/scripts/lib" "$TEST_REPO/config" \
             "$TEST_REPO/queue/reports" "$TEST_REPO/queue/archive/reports" "$TEST_REPO/skills/dashboard-update"
    cp "$DASHBOARD_UPDATE_SCRIPT" "$TEST_REPO/scripts/dashboard_update.sh"
    cp "$SKILL_LOG_SCRIPT" "$TEST_REPO/scripts/skill_execution_log.sh"
    install_dashboard_update_dependencies "$TEST_REPO"
    chmod +x "$TEST_REPO/scripts/dashboard_update.sh" "$TEST_REPO/scripts/skill_execution_log.sh"
    cat > "$TEST_REPO/scripts/lib/agent_config.sh" <<'EOF'
#!/usr/bin/env bash
EOF
    cat > "$TEST_REPO/config/settings.yaml" <<'EOF'
cli:
  agents: {}
EOF
    cat > "$TEST_REPO/dashboard.md" <<'EOF'
# Dashboard
## 最新更新
EOF
    cat > "$TEST_REPO/queue/shogun_to_karo.yaml" <<'EOF'
commands: {}
EOF
    cat > "$TEST_REPO/queue/reports/hanzo_report_cmd_training_L1_report-write_20260708020332.yaml" <<'EOF'
worker_id: hanzo
parent_cmd: cmd_training_L1_report-write_20260708020332
status: completed
timestamp: '2026-07-08T02:20:09'
result:
  summary: hyphenated skill training completed
EOF
    complete_dashboard_report_fixture "$TEST_REPO/queue/reports/hanzo_report_cmd_training_L1_report-write_20260708020332.yaml"
    cat > "$TEST_REPO/skills/dashboard-update/SKILL.md" <<'EOF'
# dashboard-update
EOF

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" SKILL_EXECUTION_LOG_DISABLE=1 SKIP_AUTO_SECTION=1 bash "$TEST_REPO/scripts/dashboard_update.sh" cmd_training_L1_report-write_20260708020332 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN: - **cmd_training_L1_report-write_20260708020332**:"* ]]
    [[ "$output" == *"hyphenated skill training completed"* ]]
}

@test "dashboard_update.sh resolves short hotfix cmd id to long parent_cmd report" {
    TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/scripts/lib" "$TEST_REPO/config" \
             "$TEST_REPO/queue/reports" "$TEST_REPO/queue/archive/reports" "$TEST_REPO/skills/dashboard-update"
    cp "$DASHBOARD_UPDATE_SCRIPT" "$TEST_REPO/scripts/dashboard_update.sh"
    cp "$SKILL_LOG_SCRIPT" "$TEST_REPO/scripts/skill_execution_log.sh"
    install_dashboard_update_dependencies "$TEST_REPO"
    chmod +x "$TEST_REPO/scripts/dashboard_update.sh" "$TEST_REPO/scripts/skill_execution_log.sh"
    cat > "$TEST_REPO/scripts/lib/agent_config.sh" <<'EOF'
#!/usr/bin/env bash
EOF
    cat > "$TEST_REPO/config/settings.yaml" <<'EOF'
cli:
  agents: {}
EOF
    cat > "$TEST_REPO/dashboard.md" <<'EOF'
# Dashboard
## 最新更新
EOF
    cat > "$TEST_REPO/queue/shogun_to_karo.yaml" <<'EOF'
commands: {}
EOF
    cat > "$TEST_REPO/queue/reports/saizo_report_cmd_karo_hotfix_ga190_generated_instructions_hook_20260707.yaml" <<'EOF'
worker_id: saizo
parent_cmd: cmd_karo_hotfix_ga190_generated_instructions_hook_20260707
status: completed
timestamp: '2026-07-07T14:00:28'
result:
  summary: generated instructions hook fixed
EOF
    complete_dashboard_report_fixture "$TEST_REPO/queue/reports/saizo_report_cmd_karo_hotfix_ga190_generated_instructions_hook_20260707.yaml"
    cat > "$TEST_REPO/skills/dashboard-update/SKILL.md" <<'EOF'
# dashboard-update
EOF

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" SKILL_EXECUTION_LOG_DISABLE=1 SKIP_AUTO_SECTION=1 bash "$TEST_REPO/scripts/dashboard_update.sh" cmd_karo_hotfix_ga190 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN: - **cmd_karo_hotfix_ga190**:"* ]]
    [[ "$output" == *"generated instructions hook fixed"* ]]
}

@test "dashboard_update.sh --dry-run without cmd_id exits success and logs PASS" {
    TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/scripts/lib" "$TEST_REPO/skills/dashboard-update"
    cp "$DASHBOARD_UPDATE_SCRIPT" "$TEST_REPO/scripts/dashboard_update.sh"
    cp "$SKILL_LOG_SCRIPT" "$TEST_REPO/scripts/skill_execution_log.sh"
    install_dashboard_update_dependencies "$TEST_REPO"
    chmod +x "$TEST_REPO/scripts/dashboard_update.sh" "$TEST_REPO/scripts/skill_execution_log.sh"
    cat > "$TEST_REPO/scripts/lib/agent_config.sh" <<'EOF'
#!/usr/bin/env bash
EOF
    cat > "$TEST_REPO/skills/dashboard-update/SKILL.md" <<'EOF'
# dashboard-update
EOF

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" bash "$TEST_REPO/scripts/dashboard_update.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN: cmd_id未指定"* ]]

    run python3 - <<EOF
import yaml
data = yaml.safe_load(open("$TEST_SKILL_LOG", encoding="utf-8"))
entry = data["executions"][-1]
assert entry["skill"] == "dashboard-update"
assert entry["result"] == "PASS"
assert entry["gate"] == "dashboard_update"
assert "cmd=<empty> dry_run=true" in entry["stumbling_points"]
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "dashboard_update.sh refreshes karo_snapshot before dashboard auto section" {
    run python3 - <<EOF
from pathlib import Path
text = Path("$DASHBOARD_UPDATE_SCRIPT").read_text()
assert "refresh_snapshot_before_auto_section()" in text
assert "NINJA_MONITOR_LIB_ONLY=1" in text
assert "refresh_karo_snapshot_fast_path" in text
auto_call = 'bash "\$SCRIPT_DIR/dashboard_auto_section.sh"'
refresh_call = 'refresh_snapshot_before_auto_section ||'
assert text.index(refresh_call) < text.index(auto_call)
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "dashboard_update.sh restores empty dashboard from template when 最新更新 is missing" {
    TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/scripts/lib" "$TEST_REPO/config" \
             "$TEST_REPO/queue/reports" "$TEST_REPO/queue/archive/reports" "$TEST_REPO/skills/dashboard-update"
    cp "$DASHBOARD_UPDATE_SCRIPT" "$TEST_REPO/scripts/dashboard_update.sh"
    cp "$SKILL_LOG_SCRIPT" "$TEST_REPO/scripts/skill_execution_log.sh"
    install_dashboard_update_dependencies "$TEST_REPO"
    chmod +x "$TEST_REPO/scripts/dashboard_update.sh" "$TEST_REPO/scripts/skill_execution_log.sh"
    cat > "$TEST_REPO/scripts/lib/agent_config.sh" <<'EOF'
#!/usr/bin/env bash
EOF
    cat > "$TEST_REPO/config/settings.yaml" <<'EOF'
cli:
  agents: {}
EOF
    cat > "$TEST_REPO/config/dashboard_template.md" <<'EOF'
# Dashboard
<!-- DASHBOARD_AUTO_START -->
<!-- DASHBOARD_AUTO_END -->
## 最新更新
EOF
    : > "$TEST_REPO/dashboard.md"
    cat > "$TEST_REPO/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_4000:
    purpose: recovered purpose
EOF
    cat > "$TEST_REPO/queue/reports/saizo_report_cmd_4000.yaml" <<'EOF'
worker_id: saizo
parent_cmd: cmd_4000
status: completed
result:
  summary: recovered report
EOF
    complete_dashboard_report_fixture "$TEST_REPO/queue/reports/saizo_report_cmd_4000.yaml"
    cat > "$TEST_REPO/skills/dashboard-update/SKILL.md" <<'EOF'
# dashboard-update
EOF

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" SKILL_EXECUTION_LOG_DISABLE=1 SKIP_AUTO_SECTION=1 bash "$TEST_REPO/scripts/dashboard_update.sh" cmd_4000
    [ "$status" -eq 0 ]
    [[ "$output" == *"UPDATED: cmd_4000 line appended"* ]]
    [[ "$output" == *"WARN: DATA_QUALITY dashboard.md missing ## 最新更新"* ]]
    grep -q '<!-- DASHBOARD_AUTO_START -->' "$TEST_REPO/dashboard.md"
    grep -q '^## 最新更新' "$TEST_REPO/dashboard.md"
    grep -q 'cmd_4000' "$TEST_REPO/dashboard.md"
}

@test "dashboard_update.sh restores partial template dashboard from template when 最新更新 is missing" {
    TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/scripts/lib" "$TEST_REPO/config" \
             "$TEST_REPO/queue/reports" "$TEST_REPO/queue/archive/reports" "$TEST_REPO/skills/dashboard-update"
    cp "$DASHBOARD_UPDATE_SCRIPT" "$TEST_REPO/scripts/dashboard_update.sh"
    cp "$SKILL_LOG_SCRIPT" "$TEST_REPO/scripts/skill_execution_log.sh"
    install_dashboard_update_dependencies "$TEST_REPO"
    chmod +x "$TEST_REPO/scripts/dashboard_update.sh" "$TEST_REPO/scripts/skill_execution_log.sh"
    cat > "$TEST_REPO/scripts/lib/agent_config.sh" <<'EOF'
#!/usr/bin/env bash
EOF
    cat > "$TEST_REPO/config/settings.yaml" <<'EOF'
cli:
  agents: {}
EOF
    cat > "$TEST_REPO/config/dashboard_template.md" <<'EOF'
<!-- Dashboard Template v3.0
  insert_target: 最新更新
-->
# 🏯 Dashboard [{PJ名}] — {YYYY-MM-DD HH:MM} 更新
<!-- DASHBOARD_AUTO_START -->
<!-- DASHBOARD_AUTO_END -->
## 最新更新
EOF
    cat > "$TEST_REPO/dashboard.md" <<'EOF'
<!-- Dashboard Template v3.0
  insert_target: 最新更新
-->
# 🏯 Dashboard [{PJ名}] — {YYYY-MM-DD HH:MM} 更新
EOF
    cat > "$TEST_REPO/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_4002:
    purpose: recovered partial purpose
EOF
    cat > "$TEST_REPO/queue/reports/saizo_report_cmd_4002.yaml" <<'EOF'
worker_id: saizo
parent_cmd: cmd_4002
status: completed
result:
  summary: recovered partial report
EOF
    complete_dashboard_report_fixture "$TEST_REPO/queue/reports/saizo_report_cmd_4002.yaml"
    cat > "$TEST_REPO/skills/dashboard-update/SKILL.md" <<'EOF'
# dashboard-update
EOF

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" SKILL_EXECUTION_LOG_DISABLE=1 SKIP_AUTO_SECTION=1 bash "$TEST_REPO/scripts/dashboard_update.sh" cmd_4002
    [ "$status" -eq 0 ]
    [[ "$output" == *"UPDATED: cmd_4002 line appended"* ]]
    [[ "$output" == *"restored partial template dashboard from template"* ]]
    grep -q '<!-- DASHBOARD_AUTO_START -->' "$TEST_REPO/dashboard.md"
    grep -q '^## 最新更新' "$TEST_REPO/dashboard.md"
    grep -q 'cmd_4002' "$TEST_REPO/dashboard.md"
    grep -q "^# 🏯 Dashboard \\[infra\\] — $(TZ=Asia/Tokyo date +%Y-%m-%d)" "$TEST_REPO/dashboard.md"
}

@test "dashboard_update.sh blocks non-empty dashboard without 最新更新" {
    TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/scripts/lib" "$TEST_REPO/config" \
             "$TEST_REPO/queue/reports" "$TEST_REPO/queue/archive/reports" "$TEST_REPO/skills/dashboard-update"
    cp "$DASHBOARD_UPDATE_SCRIPT" "$TEST_REPO/scripts/dashboard_update.sh"
    cp "$SKILL_LOG_SCRIPT" "$TEST_REPO/scripts/skill_execution_log.sh"
    install_dashboard_update_dependencies "$TEST_REPO"
    chmod +x "$TEST_REPO/scripts/dashboard_update.sh" "$TEST_REPO/scripts/skill_execution_log.sh"
    cat > "$TEST_REPO/scripts/lib/agent_config.sh" <<'EOF'
#!/usr/bin/env bash
EOF
    cat > "$TEST_REPO/config/settings.yaml" <<'EOF'
cli:
  agents: {}
EOF
    cat > "$TEST_REPO/config/dashboard_template.md" <<'EOF'
## 最新更新
EOF
    printf '# Broken dashboard\nNo latest section\n' > "$TEST_REPO/dashboard.md"
    cat > "$TEST_REPO/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_4001:
    purpose: blocked purpose
EOF
    cat > "$TEST_REPO/queue/reports/saizo_report_cmd_4001.yaml" <<'EOF'
worker_id: saizo
parent_cmd: cmd_4001
status: completed
result:
  summary: blocked report
EOF
    complete_dashboard_report_fixture "$TEST_REPO/queue/reports/saizo_report_cmd_4001.yaml"
    cat > "$TEST_REPO/skills/dashboard-update/SKILL.md" <<'EOF'
# dashboard-update
EOF

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" SKILL_EXECUTION_LOG_DISABLE=1 SKIP_AUTO_SECTION=1 bash "$TEST_REPO/scripts/dashboard_update.sh" cmd_4001
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: DATA_QUALITY '## 最新更新' section not found"* ]]
    ! grep -q 'cmd_4001' "$TEST_REPO/dashboard.md"
}

@test "dashboard_update.sh treats missing optional 要対応 as no-op and validates it when present" {
    TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/scripts/lib" "$TEST_REPO/config" \
             "$TEST_REPO/queue/reports" "$TEST_REPO/queue/archive/reports" "$TEST_REPO/skills/dashboard-update"
    cp "$DASHBOARD_UPDATE_SCRIPT" "$TEST_REPO/scripts/dashboard_update.sh"
    cp "$SKILL_LOG_SCRIPT" "$TEST_REPO/scripts/skill_execution_log.sh"
    install_dashboard_update_dependencies "$TEST_REPO"
    chmod +x "$TEST_REPO/scripts/dashboard_update.sh" "$TEST_REPO/scripts/skill_execution_log.sh"
    printf '#!/usr/bin/env bash\n' > "$TEST_REPO/scripts/lib/agent_config.sh"
    printf 'cli:\n  agents: {}\n' > "$TEST_REPO/config/settings.yaml"
    cat > "$TEST_REPO/config/dashboard_template.md" <<'EOF'
## 最新更新
## 要対応
EOF
    cat > "$TEST_REPO/dashboard.md" <<'EOF'
# Dashboard
## 最新更新
EOF
    printf 'decisions:\n  - id: PD-TEST\n    status: pending\n    summary: test\n' > "$TEST_REPO/queue/pending_decisions.yaml"
    printf 'commands: []\n' > "$TEST_REPO/queue/shogun_to_karo.yaml"
    cat > "$TEST_REPO/queue/reports/hayate_report_cmd_4010.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_4010
status: completed
result:
  summary: optional section fixture
EOF
    complete_dashboard_report_fixture "$TEST_REPO/queue/reports/hayate_report_cmd_4010.yaml"
    printf '# dashboard-update\n' > "$TEST_REPO/skills/dashboard-update/SKILL.md"

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" SKILL_EXECUTION_LOG_DISABLE=1 SKIP_AUTO_SECTION=1 \
        bash "$TEST_REPO/scripts/dashboard_update.sh" cmd_4010
    [ "$status" -eq 0 ]
    [[ "$output" == *"UPDATED: cmd_4010 line appended"* ]]
    [[ "$output" != *"要対応セクションが見つかりません"* ]]
    [[ "$output" != *"postcondition: 要対応セクション未発見"* ]]
    [[ "$output" != *"Missing section: ## 要対応"* ]]

    printf '\n## 要対応\n古い値\n' >> "$TEST_REPO/dashboard.md"
    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" SKILL_EXECUTION_LOG_DISABLE=1 SKIP_AUTO_SECTION=1 \
        bash "$TEST_REPO/scripts/dashboard_update.sh" cmd_4010
    [ "$status" -eq 0 ]
    [[ "$output" == *"UPDATED: 要対応セクション同期完了 (1件)"* ]]
    [[ "$output" == *"OK: PD⇔要対応一致 (1件)"* ]]

    printf 'decisions: [\n' > "$TEST_REPO/queue/pending_decisions.yaml"
    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" SKILL_EXECUTION_LOG_DISABLE=1 SKIP_AUTO_SECTION=1 \
        bash "$TEST_REPO/scripts/dashboard_update.sh" cmd_4010
    [ "$status" -eq 0 ]
    [[ "$output" == *"pending_decisions.yaml読み込み失敗"* ]]
}

@test "dashboard_update.sh keeps 要対応 postcondition when optional section exists" {
    run python3 - <<EOF
from pathlib import Path
text = Path("$DASHBOARD_UPDATE_SCRIPT").read_text()
assert "WARN: PD⇔要対応不一致" in text
assert "OK: PD⇔要対応一致" in text
assert "if expected != actual:" in text
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "skill_auto_improve outputs per-skill Top3 FAIL reasons" {
    mkdir -p "$TEST_TMPDIR/skills/report-write" "$TEST_TMPDIR/skills/cmd-complete"
    cat > "$TEST_SKILL_LOG" <<'EOF'
executions:
- ts: "2026-05-02T10:00:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "verdict missing"
  gate: "gate_report_format"
- ts: "2026-05-02T10:01:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "verdict missing"
  gate: "gate_report_format"
- ts: "2026-05-02T10:02:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "lessons_useful missing"
  gate: "cmd_complete_gate"
- ts: "2026-05-02T10:03:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "binary_checks empty"
  gate: "gate_report_format"
- ts: "2026-05-02T10:04:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "fourth reason omitted"
  gate: "gate_report_format"
- ts: "2026-05-02T10:05:00+0900"
  skill: "cmd-complete"
  executor: "karo"
  result: "FAIL"
  stumbling_points: "ac_version mismatch"
  gate: "cmd_complete_gate"
EOF

    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 3
    [ "$status" -eq 0 ]

    [[ "${lines[0]}" == "skill | rank | fail_count | last_fail | gate | top_fail_reason" ]]
    [[ "$output" == *"report-write | 1 | 2 | 2026-05-02T10:01:00+0900 | gate_report_format | verdict missing"* ]]
    [[ "$output" == *"report-write | 2 | 1"* ]]
    [[ "$output" == *"report-write | 3 | 1"* ]]
    [[ "$output" != *"report-write | 4"* ]]
    [[ "$output" == *"cmd-complete | 1 | 1 | 2026-05-02T10:05:00+0900 | cmd_complete_gate | ac_version mismatch"* ]]
}

@test "skill_auto_improve groups volatile cmd and ninja ids and refreshes last_fail" {
    mkdir -p "$TEST_TMPDIR/skills/dashboard-update" "$TEST_TMPDIR/skills/verdict-check"
    cat > "$TEST_TMPDIR/skills/dashboard-update/SKILL.md" <<'EOF'
---
name: dashboard-update
---

# dashboard-update

## 実行フロー
既存手順。
EOF
    cat > "$TEST_TMPDIR/skills/verdict-check/SKILL.md" <<'EOF'
---
name: verdict-check
---

# verdict-check

## 実行フロー
既存手順。
EOF
    STATE_JSON="$TEST_TMPDIR/skill_auto_improve_state.json"
    cat > "$TEST_SKILL_LOG" <<EOF
executions:
- ts: "2026-05-02T10:00:00+0900"
  skill: "dashboard-update"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "dashboard_update.sh exit=1 cmd=cmd_1001 dry_run=false"
  gate: "dashboard_update"
  skill_path: "$TEST_TMPDIR/skills/dashboard-update/SKILL.md"
- ts: "2026-05-02T10:02:00+0900"
  skill: "dashboard-update"
  executor: "hayate"
  result: "FAIL"
  stumbling_points: "dashboard_update.sh exit=1 cmd=cmd_1002 dry_run=false"
  gate: "dashboard_update"
  skill_path: "$TEST_TMPDIR/skills/dashboard-update/SKILL.md"
- ts: "2026-05-02T10:03:00+0900"
  skill: "verdict-check"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "saizo:binary_checks_fail"
  gate: "cmd_complete_gate"
  skill_path: "$TEST_TMPDIR/skills/verdict-check/SKILL.md"
- ts: "2026-05-02T10:04:00+0900"
  skill: "verdict-check"
  executor: "hayate"
  result: "FAIL"
  stumbling_points: "hayate:binary_checks_fail"
  gate: "cmd_complete_gate"
  skill_path: "$TEST_TMPDIR/skills/verdict-check/SKILL.md"
EOF

    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        SKILL_AUTO_IMPROVE_STATE_JSON="$STATE_JSON" \
        bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 3 --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"dashboard-update | 1 | 2 | 2026-05-02T10:02:00+0900 | dashboard_update | dashboard_update.sh exit=1 cmd=<cmd_id> dry_run=false"* ]]
    [[ "$output" == *"verdict-check | 1 | 2 | 2026-05-02T10:04:00+0900 | cmd_complete_gate | <ninja>:binary_checks_fail"* ]]
    [[ "$output" != *"cmd_1001"* ]]
    [[ "$output" != *"cmd_1002"* ]]

    cat > "$TEST_SKILL_LOG" <<EOF
executions:
- ts: "2026-05-02T10:00:00+0900"
  skill: "dashboard-update"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "dashboard_update.sh exit=1 cmd=cmd_1001 dry_run=false"
  gate: "dashboard_update"
  skill_path: "$TEST_TMPDIR/skills/dashboard-update/SKILL.md"
- ts: "2026-05-02T10:05:00+0900"
  skill: "dashboard-update"
  executor: "hayate"
  result: "FAIL"
  stumbling_points: "dashboard_update.sh exit=1 cmd=cmd_1003 dry_run=false"
  gate: "dashboard_update"
  skill_path: "$TEST_TMPDIR/skills/dashboard-update/SKILL.md"
EOF

    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        SKILL_AUTO_IMPROVE_STATE_JSON="$STATE_JSON" \
        bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 3 --apply
    [ "$status" -eq 0 ]

    run python3 - <<EOF
import json
from pathlib import Path
state = json.loads(Path("$STATE_JSON").read_text(encoding="utf-8"))
dashboard = [p for p in state["patterns"].values() if p["skill"] == "dashboard-update"]
assert len(dashboard) == 1
assert dashboard[0]["reason"] == "dashboard_update.sh exit=1 cmd=<cmd_id> dry_run=false"
assert dashboard[0]["last_fail"] == "2026-05-02T10:05:00+0900"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "skill_auto_improve applies Top FAIL reasons to SKILL.md procedure section without duplicates" {
    mkdir -p "$TEST_TMPDIR/skills/report-write"
    cat > "$TEST_TMPDIR/skills/report-write/SKILL.md" <<'EOF'
---
name: report-write
---

# report-write

## 報告YAML記入手順

### Step 1: path
既存手順。

## 注意ポイント

- 既存注意。
EOF
    cat > "$TEST_SKILL_LOG" <<EOF
executions:
- ts: "2026-05-02T10:00:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "verdict missing"
  gate: "gate_report_format"
  skill_path: "$TEST_TMPDIR/skills/report-write/SKILL.md"
- ts: "2026-05-02T10:01:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "verdict missing"
  gate: "gate_report_format"
  skill_path: "$TEST_TMPDIR/skills/report-write/SKILL.md"
EOF

    for attempt in 1 2; do
        run env \
            SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
            SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
            bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 3 --apply
        [ "$status" -eq 0 ]
    done

    run python3 - <<EOF
from pathlib import Path
text = Path("$TEST_TMPDIR/skills/report-write/SKILL.md").read_text(encoding="utf-8")
assert "## 報告YAML記入手順" in text
assert "### 自動防止ステップ" in text
assert "Top FAIL理由「verdict missing」" in text
assert "確認:" in text
assert "修正:" in text
assert "verdict が空/None/不正値でないこと" in text
assert "report_field_set.sh" in text
assert text.count("skill-auto-improve:") == 1
assert text.index("### 自動防止ステップ") < text.index("### Step 1: path")
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "skill_auto_improve escalates repeated UNCHANGED failures to code-fix bulletin" {
    mkdir -p "$TEST_TMPDIR/skills/report-write" "$TEST_TMPDIR/scripts"
    cat > "$TEST_TMPDIR/skills/report-write/SKILL.md" <<'EOF'
---
name: report-write
---

# report-write

## 報告YAML記入手順
既存手順。
EOF
    cat > "$TEST_TMPDIR/scripts/bulletin_write.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BULLETIN_CAPTURE"
EOF
    chmod +x "$TEST_TMPDIR/scripts/bulletin_write.sh"
    cat > "$TEST_SKILL_LOG" <<EOF
executions:
- ts: "2026-05-02T10:00:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "verdict missing"
  gate: "gate_report_format"
  skill_path: "$TEST_TMPDIR/skills/report-write/SKILL.md"
- ts: "2026-05-02T10:01:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "verdict missing"
  gate: "gate_report_format"
  skill_path: "$TEST_TMPDIR/skills/report-write/SKILL.md"
EOF

    BULLETIN_CAPTURE="$TEST_TMPDIR/bulletin_args.log"
    STATE_JSON="$TEST_TMPDIR/skill_auto_improve_state.json"

    for attempt in 1 2 3; do
        run env \
            SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
            SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
            SKILL_AUTO_IMPROVE_STATE_JSON="$STATE_JSON" \
            SKILL_AUTO_IMPROVE_FAIL_TTL_DAYS=99999 \
            SKILL_AUTO_IMPROVE_BULLETIN_SCRIPT="$TEST_TMPDIR/scripts/bulletin_write.sh" \
            SKILL_AUTO_IMPROVE_POSTED_BY="hayate" \
            BULLETIN_CAPTURE="$BULLETIN_CAPTURE" \
            bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 1 --apply --unchanged-threshold 2
        [ "$status" -eq 0 ]
    done

    run python3 - <<EOF
import json
from pathlib import Path
state = json.loads(Path("$STATE_JSON").read_text(encoding="utf-8"))
entry = next(iter(state["patterns"].values()))
assert entry["unchanged_streak"] == 2
assert entry["classification"] == "code_fix_required"
capture = Path("$BULLETIN_CAPTURE").read_text(encoding="utf-8")
assert "hayate skill_auto_improve escalation:" in capture
assert "コード修正cmd起票を要請" in capture
assert "unchanged_streak=2" in capture
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "skill_auto_improve clears code_fix_required after later PASS and preserves unresolved FAIL" {
    mkdir -p "$TEST_TMPDIR/skills/report-write" "$TEST_TMPDIR/skills/verdict-check"
    cat > "$TEST_TMPDIR/skills/report-write/SKILL.md" <<'EOF'
---
name: report-write
---

# report-write

## 報告YAML記入手順
既存手順。
EOF
    cat > "$TEST_TMPDIR/skills/verdict-check/SKILL.md" <<'EOF'
---
name: verdict-check
---

# verdict-check

## 実行フロー
既存手順。
EOF
    STATE_JSON="$TEST_TMPDIR/skill_auto_improve_state.json"
    cat > "$TEST_SKILL_LOG" <<EOF
executions:
- ts: "2026-05-02T10:00:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "verdict missing"
  gate: "gate_report_format"
  skill_path: "$TEST_TMPDIR/skills/report-write/SKILL.md"
- ts: "2026-05-02T10:05:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "PASS"
  stumbling_points: "gate_report_format PASS"
  gate: "gate_report_format"
  skill_path: "$TEST_TMPDIR/skills/report-write/SKILL.md"
- ts: "2026-05-02T10:10:00+0900"
  skill: "verdict-check"
  executor: "hayate"
  result: "PASS"
  stumbling_points: "cmd_complete_gate PASS"
  gate: "cmd_complete_gate"
  skill_path: "$TEST_TMPDIR/skills/verdict-check/SKILL.md"
- ts: "2026-05-02T10:15:00+0900"
  skill: "verdict-check"
  executor: "hayate"
  result: "FAIL"
  stumbling_points: "hayate:binary_checks_fail"
  gate: "cmd_complete_gate"
  skill_path: "$TEST_TMPDIR/skills/verdict-check/SKILL.md"
EOF
    cat > "$STATE_JSON" <<'EOF'
{
  "patterns": {
    "old_report": {
      "skill": "report-write",
      "gate": "gate_report_format",
      "reason": "verdict missing",
      "last_fail": "2026-05-02T10:00:00+0900",
      "classification": "code_fix_required",
      "classification_reason": "SKILL.md unchanged 3 consecutive runs"
    },
    "old_verdict": {
      "skill": "verdict-check",
      "gate": "cmd_complete_gate",
      "reason": "<ninja>:binary_checks_fail",
      "last_fail": "2026-05-02T10:15:00+0900",
      "classification": "code_fix_required",
      "classification_reason": "SKILL.md unchanged 3 consecutive runs"
    }
  }
}
EOF

    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        SKILL_AUTO_IMPROVE_STATE_JSON="$STATE_JSON" \
        SKILL_AUTO_IMPROVE_FAIL_TTL_DAYS=99999 \
        bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 3 --apply --unchanged-threshold 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLEARED_CODE_FIX: report-write gate=gate_report_format pass=2026-05-02T10:05:00+0900 last_fail=2026-05-02T10:00:00+0900"* ]]
    [[ "$output" == *"SKIPPED_CLASSIFICATION_AFTER_PASS: report-write"* ]]

    run python3 - <<EOF
import json
from pathlib import Path
state = json.loads(Path("$STATE_JSON").read_text(encoding="utf-8"))
report_entries = [p for p in state["patterns"].values() if p["skill"] == "report-write"]
verdict_entries = [p for p in state["patterns"].values() if p["skill"] == "verdict-check"]
assert report_entries
assert all(p.get("classification") != "code_fix_required" for p in report_entries)
assert any(p.get("code_fix_cleared_by") == "skill_auto_improve_pass_result" for p in report_entries)
assert any(p.get("classification") == "code_fix_required" for p in verdict_entries)
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "skill_auto_improve keeps same-timestamp PASS unresolved fail-closed" {
    mkdir -p "$TEST_TMPDIR/skills/report-write"
    printf '# report-write\n' > "$TEST_TMPDIR/skills/report-write/SKILL.md"
    STATE_JSON="$TEST_TMPDIR/skill_auto_improve_state.json"
    cat > "$TEST_SKILL_LOG" <<EOF
executions:
- ts: "2026-05-02T10:00:00+0900"
  skill: "report-write"
  result: "FAIL"
  stumbling_points: "verdict missing"
  gate: "gate_report_format"
- ts: "2026-05-02T10:00:00+09:00"
  skill: "report-write"
  result: "PASS"
  gate: "gate_report_format"
EOF
    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" SKILL_AUTO_IMPROVE_STATE_JSON="$STATE_JSON" bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 1 --apply --unchanged-threshold 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLASSIFIED: report-write"* ]]
    [[ "$output" != *"SKIPPED_CLASSIFICATION_AFTER_PASS"* ]]
}

@test "skill_auto_improve does not reclassify or escalate code_fix_cleared pattern" {
    mkdir -p "$TEST_TMPDIR/skills/report-write" "$TEST_TMPDIR/scripts"
    cat > "$TEST_TMPDIR/skills/report-write/SKILL.md" <<'EOF'
---
name: report-write
---

# report-write

## 報告YAML記入手順
既存手順。
EOF
    cat > "$TEST_TMPDIR/scripts/bulletin_write.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BULLETIN_CAPTURE"
EOF
    chmod +x "$TEST_TMPDIR/scripts/bulletin_write.sh"
    cat > "$TEST_SKILL_LOG" <<EOF
executions:
- ts: "2026-05-02T10:00:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "script exit code failure in report-write"
  gate: "gate_report_format"
  skill_path: "$TEST_TMPDIR/skills/report-write/SKILL.md"
EOF
    STATE_JSON="$TEST_TMPDIR/skill_auto_improve_state.json"
    BULLETIN_CAPTURE="$TEST_TMPDIR/bulletin_args.log"

    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        SKILL_AUTO_IMPROVE_STATE_JSON="$STATE_JSON" \
        SKILL_AUTO_IMPROVE_FAIL_TTL_DAYS=99999 \
        SKILL_AUTO_IMPROVE_BULLETIN_SCRIPT="$TEST_TMPDIR/scripts/bulletin_write.sh" \
        SKILL_AUTO_IMPROVE_POSTED_BY="hayate" \
        BULLETIN_CAPTURE="$BULLETIN_CAPTURE" \
        bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 1 --apply --unchanged-threshold 1
    [ "$status" -eq 0 ]

    run python3 - <<EOF
import json
from pathlib import Path
state = json.loads(Path("$STATE_JSON").read_text(encoding="utf-8"))
entry = next(iter(state["patterns"].values()))
entry["code_fix_cleared_by"] = "test_clear"
entry["code_fix_cleared_at"] = "2026-05-02T10:05:00+0900"
Path("$STATE_JSON").write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]

    before=0
    [ -f "$BULLETIN_CAPTURE" ] && before="$(wc -l < "$BULLETIN_CAPTURE")"
    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        SKILL_AUTO_IMPROVE_STATE_JSON="$STATE_JSON" \
        SKILL_AUTO_IMPROVE_BULLETIN_SCRIPT="$TEST_TMPDIR/scripts/bulletin_write.sh" \
        SKILL_AUTO_IMPROVE_POSTED_BY="hayate" \
        BULLETIN_CAPTURE="$BULLETIN_CAPTURE" \
        bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 1 --apply --unchanged-threshold 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIPPED_CLASSIFICATION_CODE_FIX_CLEARED: report-write rank=1 gate=gate_report_format"* ]]
    [[ "$output" != *"CLASSIFIED: report-write"* ]]
    [[ "$output" != *"ESCALATED_CODE_FIX: report-write"* ]]
    after=0
    [ -f "$BULLETIN_CAPTURE" ] && after="$(wc -l < "$BULLETIN_CAPTURE")"
    [ "$before" -eq "$after" ]

    run python3 - <<EOF
import json
from pathlib import Path
state = json.loads(Path("$STATE_JSON").read_text(encoding="utf-8"))
entry = next(iter(state["patterns"].values()))
assert entry.get("classification") is None, entry
assert entry.get("code_fix_cleared_by") == "test_clear", entry
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "skill_auto_improve syncs CLEAR counters and emits one task only for a later unresolved FAIL" {
    mkdir -p "$TEST_TMPDIR/skills/report-write" "$TEST_TMPDIR/scripts"
    printf '# report-write\n' > "$TEST_TMPDIR/skills/report-write/SKILL.md"
    cat > "$TEST_TMPDIR/scripts/training_task_generator.sh" <<'EOF'
#!/usr/bin/env bash
printf 'generated\n' >> "$TRAINING_CAPTURE"
EOF
    chmod +x "$TEST_TMPDIR/scripts/training_task_generator.sh"
    STATE_JSON="$TEST_TMPDIR/skill_auto_improve_state.json"
    TRAINING_CAPTURE="$TEST_TMPDIR/training.log"

    cat > "$TEST_SKILL_LOG" <<EOF
executions:
- ts: "2026-05-02T10:00:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "verdict missing"
  gate: "gate_report_format"
  skill_path: "$TEST_TMPDIR/skills/report-write/SKILL.md"
EOF
    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        SKILL_AUTO_IMPROVE_STATE_JSON="$STATE_JSON" \
        SKILL_AUTO_IMPROVE_TRAINING_GENERATOR="$TEST_TMPDIR/scripts/training_task_generator.sh" \
        SKILL_AUTO_IMPROVE_FAIL_TTL_DAYS=99999 \
        TRAINING_CAPTURE="$TRAINING_CAPTURE" \
        bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 1 --apply --unchanged-threshold 1
    [ "$status" -eq 0 ]
    [ ! -e "$TRAINING_CAPTURE" ]

    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        SKILL_AUTO_IMPROVE_STATE_JSON="$STATE_JSON" \
        SKILL_AUTO_IMPROVE_TRAINING_GENERATOR="$TEST_TMPDIR/scripts/training_task_generator.sh" \
        SKILL_AUTO_IMPROVE_FAIL_TTL_DAYS=99999 \
        TRAINING_CAPTURE="$TRAINING_CAPTURE" \
        bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 1 --apply --unchanged-threshold 1
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TRAINING_CAPTURE")" -eq 1 ]

    cat > "$TEST_SKILL_LOG" <<EOF
executions:
- ts: "2026-05-02T10:00:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "verdict missing"
  gate: "gate_report_format"
  skill_path: "$TEST_TMPDIR/skills/report-write/SKILL.md"
- ts: "2026-05-02T10:05:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "PASS"
  stumbling_points: "gate_report_format PASS"
  gate: "gate_report_format"
  skill_path: "$TEST_TMPDIR/skills/report-write/SKILL.md"
EOF
    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        SKILL_AUTO_IMPROVE_STATE_JSON="$STATE_JSON" \
        SKILL_AUTO_IMPROVE_TRAINING_GENERATOR="$TEST_TMPDIR/scripts/training_task_generator.sh" \
        SKILL_AUTO_IMPROVE_FAIL_TTL_DAYS=99999 \
        TRAINING_CAPTURE="$TRAINING_CAPTURE" \
        bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 1 --apply --unchanged-threshold 1
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TRAINING_CAPTURE")" -eq 1 ]

    cat >> "$TEST_SKILL_LOG" <<EOF
- ts: "2026-05-02T10:10:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "verdict missing"
  gate: "gate_report_format"
  skill_path: "$TEST_TMPDIR/skills/report-write/SKILL.md"
EOF
    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        SKILL_AUTO_IMPROVE_STATE_JSON="$STATE_JSON" \
        SKILL_AUTO_IMPROVE_TRAINING_GENERATOR="$TEST_TMPDIR/scripts/training_task_generator.sh" \
        SKILL_AUTO_IMPROVE_FAIL_TTL_DAYS=99999 \
        TRAINING_CAPTURE="$TRAINING_CAPTURE" \
        bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 1 --apply --unchanged-threshold 1
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TRAINING_CAPTURE")" -eq 2 ]

    python3 - "$STATE_JSON" <<'PY'
import json, sys
entry = next(iter(json.load(open(sys.argv[1], encoding="utf-8"))["patterns"].values()))
assert entry["unchanged_streak"] == 1, entry
assert entry["training_notified_streak"] == 1, entry
assert "code_fix_cleared_at" not in entry, entry
PY
}

@test "skill_auto_improve isolated inputs cannot use production side effects by default" {
    mkdir -p "$TEST_TMPDIR/skills/report-write"
    printf '# report-write\n' > "$TEST_TMPDIR/skills/report-write/SKILL.md"
    cat > "$TEST_SKILL_LOG" <<EOF
executions:
- ts: "2026-05-02T10:00:00+0900"
  skill: "report-write"
  result: "FAIL"
  stumbling_points: "verdict missing"
  gate: "gate_report_format"
EOF

    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        SKILL_AUTO_IMPROVE_STATE_JSON="$TEST_TMPDIR/state.json" \
        SKILL_AUTO_IMPROVE_FAIL_TTL_DAYS=99999 \
        bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 1 --apply --unchanged-threshold 1
    [ "$status" -eq 0 ]

    run env \
        SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_TMPDIR/skills" \
        SKILL_AUTO_IMPROVE_STATE_JSON="$TEST_TMPDIR/state.json" \
        SKILL_AUTO_IMPROVE_FAIL_TTL_DAYS=99999 \
        bash "$SKILL_AUTO_IMPROVE_SCRIPT" --top 1 --apply --unchanged-threshold 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"ESCALATION_SKIPPED_NO_BULLETIN"* ]]
    [[ "$output" == *"TRAINING_SKIPPED_NO_GENERATOR"* ]]
}

# review_bundle.py judges hook_failures by state, not by count.  The fixtures
# below carry the real evidence from kagemaru's B27 report (count 3, full re-run
# PASS) and hayate's divergent-detector report (count 1, identical FAIL set).
setup_hook_failure_repo() {
    TEST_REPO="$TEST_TMPDIR/hookrepo"
    rm -rf "$TEST_REPO"
    mkdir -p "$TEST_REPO/scripts/lib" "$TEST_REPO/queue/reports" "$TEST_REPO/queue/gates" "$TEST_REPO/queue/tasks"
    cp "$PROJECT_ROOT/scripts/review_bundle.py" "$TEST_REPO/scripts/review_bundle.py"
    cp "$PROJECT_ROOT/scripts/lib/review_approval.sh" "$TEST_REPO/scripts/lib/review_approval.sh"
    cp "$PROJECT_ROOT/scripts/lib/report_commit_identity.py" "$TEST_REPO/scripts/lib/report_commit_identity.py"
    cat > "$TEST_REPO/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_2473:
    purpose: hook failure state fixture
    project: infra
    target_path: scripts/review_bundle.py
    acceptance_criteria:
      - id: AC1
        description: hook failure state fixture
EOF
    cat > "$TEST_REPO/queue/reports/hayate_report_cmd_2473.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_2473
task_id: cmd_2473
report_id: rpt-hook-failure
status: completed
result:
  summary: hook failure state fixture
EOF
    complete_dashboard_report_fixture "$TEST_REPO/queue/reports/hayate_report_cmd_2473.yaml"
    python3 - "$TEST_REPO/queue/reports/hayate_report_cmd_2473.yaml" <<'PY'
import pathlib, sys, yaml
p = pathlib.Path(sys.argv[1])
d = yaml.safe_load(p.read_text()) or {}
d["task_type"] = "recon2"
d["commit_contract"] = {"required": False, "reason": "hook-state fixture has no production change"}
d["files_modified"] = [{"path": "queue/reports/hayate_report_cmd_2473.yaml", "change": "fixture evidence only"}]
d.setdefault("binary_checks", {})["commit"] = [{"check": "no-commit fixture contract", "result": "yes"}]
p.write_text(yaml.safe_dump(d, sort_keys=False, allow_unicode=True))
PY
    cat > "$TEST_REPO/queue/tasks/hayate.yaml" <<'EOF'
task:
  task_id: cmd_2473
  parent_cmd: cmd_2473
  ac_version: fixture-v1
  report_id: rpt-hook-failure
  report_filename: hayate_report_cmd_2473.yaml
EOF
    HOOK_REPORT="$TEST_REPO/queue/reports/hayate_report_cmd_2473.yaml"
}

run_hook_failure_generate() {
    local root="$TEST_REPO" logical="queue/reports/hayate_report_cmd_2473.yaml"
    run python3 "$root/scripts/review_bundle.py" --root "$root" generate \
        --cmd cmd_2473 --verdict APPROVE --report "$logical"
    local first_status="$status" first_output="$output"
    if [ "$first_status" -eq 2 ]; then
        status="$first_status"
        output="$first_output"
        return 0
    fi
    [ "$first_status" -eq 3 ] || {
        status="$first_status"
        output="$first_output"
        return 1
    }
    source "$root/scripts/lib/review_approval.sh"
    local key fingerprint approval_dir
    key=$(PROJECT_ROOT="$root" review_report_key "$logical") || return 1
    fingerprint=$(PROJECT_ROOT="$root" review_report_fingerprint "$root/$logical") || return 1
    approval_dir="$root/queue/gates/cmd_2473/review_approvals/reports/$key"
    mkdir -p "$approval_dir"
    printf "role: gunshi\nresult: LGTM\nfingerprint: %s\nreport: %s\n" \
        "$fingerprint" "$logical" > "$approval_dir/gunshi.yaml"
    run python3 "$root/scripts/review_bundle.py" --root "$root" generate \
        --cmd cmd_2473 --verdict APPROVE --report "$logical"
}

@test "review_bundle APPROVE passes hook failures carrying full four-step resolution evidence" {
    setup_hook_failure_repo
    cat >> "$HOOK_REPORT" <<'EOF'
hook_failures:
  count: 3
  details:
    cause: "GA-PRECOMMIT1 blocked on existing test28 in test_ninja_scope_commit.bats, outside this task diff and unmodified"
    independent_verification: "bats --filter of test28 passed 3/3 consecutively in isolation"
    bypass_record: "SHOGUN_PRECOMMIT_AFFECTED_BYPASS set with the reason; recorded in logs/precommit_affected_bypass.jsonl"
    post_verification: "after commit the bats re-run reported 66/66 PASS including test28"
    post_verification_result: all_pass
    post_verification_head: 8203a2a3e
EOF
    run_hook_failure_generate
    [ "$status" -eq 0 ]
    [[ "$output" == *"queue/gates/cmd_2473/sg7_bundle.json"* ]]
}

@test "review_bundle APPROVE accepts a no-new-failure post verification outcome" {
    setup_hook_failure_repo
    cat >> "$HOOK_REPORT" <<'EOF'
hook_failures:
  count: 1
  details:
    cause: "DrvFs chmod EPERM breaks the fixture git init; the guard aborts before the gate is reached"
    independent_verification: "a plain mktemp -d + git init reproduces the same EPERM without this change"
    bypass_record: "reason written to SHOGUN_PRECOMMIT_AFFECTED_BYPASS and recorded in logs/precommit_affected_bypass.jsonl"
    post_verification: "re-measured after commit: FAIL set identical, zero new FAIL"
    post_verification_result: no_new_failure
    post_verification_head: e104282cb
EOF
    run_hook_failure_generate
    [ "$status" -eq 0 ]
}

# hanzo's B28: (d) legitimately failed first (two new regressions after the merged
# commit 8203a2a3e), the cause was fixed by its owner (868d0213e), and the
# re-measurement on the new HEAD held.  Declaring the failure must block APPROVE
# while naming the way out; the corrected re-measurement must then pass.
@test "review_bundle APPROVE blocks a declared regression and clears after re-measurement" {
    setup_hook_failure_repo
    cat >> "$HOOK_REPORT" <<'EOF'
hook_failures:
  count: 2
  details:
    cause: "merged commit 8203a2a3e; pre-existing RED matched, but two new regressions appeared in test_report_commit_identity"
    independent_verification: "the three pre-existing RED tests reproduce without this change"
    bypass_record: "recorded in logs/precommit_affected_bypass.jsonl"
    post_verification: "measured after the merged commit: 2 new FAIL, so the bypass does not hold"
    post_verification_result: regression_detected
    post_verification_head: 8203a2a3e
EOF
    run_hook_failure_generate
    [ "$status" -eq 2 ]
    [[ "$output" == *"regression_detected"* ]]
    [[ "$output" == *"re-measure on the new HEAD"* ]]

    # after the owner fixed the cause, the re-measurement on the new HEAD holds
    setup_hook_failure_repo
    cat >> "$HOOK_REPORT" <<'EOF'
hook_failures:
  count: 2
  details:
    cause: "merged commit 8203a2a3e; the sidecar broke the cache boundary proxy, fixed by its owner in 868d0213e"
    independent_verification: "the pre-existing RED reproduces without this change"
    bypass_record: "recorded in logs/precommit_affected_bypass.jsonl"
    post_verification: "re-measured on the corrected HEAD: pre-existing RED 3 to 1, zero new FAIL"
    post_verification_result: no_new_failure
    post_verification_head: 868d0213e
EOF
    run_hook_failure_generate
    [ "$status" -eq 0 ]
}

@test "review_bundle APPROVE requires the HEAD the post verification was measured on" {
    setup_hook_failure_repo
    cat >> "$HOOK_REPORT" <<'EOF'
hook_failures:
  count: 1
  details:
    cause: "environment-only failure outside the diff"
    independent_verification: "reproduced without this change"
    bypass_record: "recorded in logs/precommit_affected_bypass.jsonl"
    post_verification: "re-measured after commit: FAIL set identical, zero new FAIL"
    post_verification_result: no_new_failure
EOF
    run_hook_failure_generate
    [ "$status" -eq 2 ]
    [[ "$output" == *"post_verification_head"* ]]

    setup_hook_failure_repo
    cat >> "$HOOK_REPORT" <<'EOF'
hook_failures:
  count: 1
  details:
    cause: "environment-only failure outside the diff"
    independent_verification: "reproduced without this change"
    bypass_record: "recorded in logs/precommit_affected_bypass.jsonl"
    post_verification: "re-measured after commit: FAIL set identical, zero new FAIL"
    post_verification_result: no_new_failure
    post_verification_head: "measured at 02:04"
EOF
    run_hook_failure_generate
    [ "$status" -eq 2 ]
    [[ "$output" == *"commit hash"* ]]
}

@test "review_bundle APPROVE stays blocked when hook failure resolution evidence is incomplete" {
    # legacy free-text details keep their unresolved meaning
    setup_hook_failure_repo
    cat >> "$HOOK_REPORT" <<'EOF'
hook_failures:
  count: 3
  details: "GA-PRECOMMIT1 blocked 3 times; bypassed"
EOF
    run_hook_failure_generate
    [ "$status" -eq 2 ]
    [[ "$output" == *"hook failures remain"* ]]

    # missing (d) post-commit verification is the escape hatch this must close
    setup_hook_failure_repo
    cat >> "$HOOK_REPORT" <<'EOF'
hook_failures:
  count: 3
  details:
    cause: "existing test outside the diff"
    independent_verification: "passed 3/3 in isolation"
    bypass_record: "recorded in logs/precommit_affected_bypass.jsonl"
    post_verification: ""
    post_verification_result: all_pass
EOF
    run_hook_failure_generate
    [ "$status" -eq 2 ]
    [[ "$output" == *"post_verification"* ]]

    # a declared but unclassifiable post-verification outcome is not evidence
    setup_hook_failure_repo
    cat >> "$HOOK_REPORT" <<'EOF'
hook_failures:
  count: 3
  details:
    cause: "existing test outside the diff"
    independent_verification: "passed 3/3 in isolation"
    bypass_record: "recorded in logs/precommit_affected_bypass.jsonl"
    post_verification: "looked fine"
    post_verification_result: confirmed
EOF
    run_hook_failure_generate
    [ "$status" -eq 2 ]
    [[ "$output" == *"post_verification_result"* ]]

    # count 0 keeps the historical fast path
    setup_hook_failure_repo
    cat >> "$HOOK_REPORT" <<'EOF'
hook_failures:
  count: 0
  details: ""
EOF
    run_hook_failure_generate
    [ "$status" -eq 0 ]
}
