#!/usr/bin/env bats
# test_skill_feedback_loop.bats — cmd_2459 skill execution feedback loop

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
    mkdir -p "$TEST_TMPDIR/logs" "$TEST_TMPDIR/skills/report-bundle"
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
    export TEST_SKILL_LOG="$TEST_TMPDIR/logs/skill_execution_log.yaml"
    export TEST_SKILLS_DIR="$TEST_TMPDIR/skills"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
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
    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" \
        bash "$SKILL_LOG_SCRIPT" report-bundle saizo FAIL "binary_checks.result empty" gate_report_format queue/reports/saizo_report.yaml "$TEST_TMPDIR/skills/report-bundle/SKILL.md"
    [ "$status" -eq 0 ]

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
    [[ "$output" == *"UNCHANGED:"* ]]

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
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "dashboard_update.sh dry-run logs dashboard-update PASS with dashboard_update gate" {
    TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/scripts/lib" "$TEST_REPO/config" \
             "$TEST_REPO/queue/reports" "$TEST_REPO/queue/archive/reports" "$TEST_REPO/skills/dashboard-update"
    cp "$DASHBOARD_UPDATE_SCRIPT" "$TEST_REPO/scripts/dashboard_update.sh"
    cp "$SKILL_LOG_SCRIPT" "$TEST_REPO/scripts/skill_execution_log.sh"
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
    cat > "$TEST_REPO/skills/dashboard-update/SKILL.md" <<'EOF'
# dashboard-update
EOF

    run env SKILL_EXECUTION_LOG_FILE="$TEST_SKILL_LOG" bash "$TEST_REPO/scripts/dashboard_update.sh" cmd_2473 --dry-run
    [ "$status" -eq 0 ]

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
