#!/usr/bin/env bats
# Consolidated small workflow/static tests (cmd_3633).

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
    true
}

make_test_tmpdir() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/small_workflow.XXXXXX")"
}

@test "cmd-complete skill points to the real cmd_complete_gate path" {
    local skill_file="$PROJECT_ROOT/skills/cmd-complete/SKILL.md"
    grep -q 'bash scripts/cmd_complete_gate.sh <cmd_id>' "$skill_file"
    ! grep -q 'scripts/gates/cmd_complete_gate.sh' "$skill_file"
}

@test "cmd-complete skill handles already archived commands via status gate evidence" {
    local skill_file="$PROJECT_ROOT/skills/cmd-complete/SKILL.md"
    grep -q 'bash scripts/gates/gate_yaml_status.sh <cmd_id>' "$skill_file"
    grep -q 'active queueからarchive済み' "$skill_file"
    grep -q 'archive/dashboard/gate_metrics上のCLEAR' "$skill_file"
}

@test "deploy_task report template does not instruct manual verdict writes" {
    run grep -n 'RFS verdict "PASS"\|verdict→PASS/FAIL\|verdict: "PASS" or "FAIL" を記入' "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 1 ]

    run grep -n 'verdict は gate_report_format.sh が binary_checks から自動導出する。手動記入禁止。' "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]

    run grep -n '^verdict: ""[[:space:]]*#' "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 1 ]
}

@test "report gate failure hints do not suggest setting verdict directly" {
    run grep -n 'report_field_set.sh \$REPORT_PATH verdict PASS' "$PROJECT_ROOT/scripts/inbox_write.sh"
    [ "$status" -eq 1 ]

    run grep -n 'verdict は gate_report_format.sh が binary_checks から自動導出' "$PROJECT_ROOT/scripts/inbox_write.sh"
    [ "$status" -eq 0 ]
}

@test "skill_gate_feedback normalizes report YAML source to cmd_id" {
    make_test_tmpdir
    export SKILL_EXECUTION_LOG_FILE="$TEST_TMPDIR/skill_execution_log.yaml"
    export SKILL_FEEDBACK_SKILLS_DIRS="$TEST_TMPDIR/skills"
    mkdir -p "$TEST_TMPDIR/skills/report-write" "$TEST_TMPDIR/queue/reports"
    cat > "$TEST_TMPDIR/skills/report-write/SKILL.md" <<'EOF'
---
name: report-write
description: Report YAML writing.
---

# report-write
EOF
    local report_path="$TEST_TMPDIR/queue/reports/saizo_report_cmd_3039.yaml"
    touch "$report_path"

    run bash "$PROJECT_ROOT/scripts/skill_gate_feedback.sh" \
        --gate gate_report_format \
        --result FAIL \
        --reason lesson_candidate_missing \
        --executor saizo \
        --source "$report_path" \
        --skill report-write

    [ "$status" -eq 0 ]
    run python3 - "$SKILL_EXECUTION_LOG_FILE" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as fh:
    data = yaml.safe_load(fh)
entry = data["executions"][-1]
assert entry["source"] == "cmd_3039", entry
PY
    [ "$status" -eq 0 ]
}

@test "skill usage metrics outputs recommendation counts and stale debt as JSON" {
    make_test_tmpdir
    mkdir -p "$TEST_TMPDIR/skills/used" "$TEST_TMPDIR/skills/unused" "$TEST_TMPDIR/skills/stale"
    cat > "$TEST_TMPDIR/skills/used/SKILL.md" <<'EOF'
---
name: used
---
# used
EOF
    cat > "$TEST_TMPDIR/skills/unused/SKILL.md" <<'EOF'
---
name: unused
---
# unused
EOF
    cat > "$TEST_TMPDIR/skills/stale/SKILL.md" <<'EOF'
---
name: stale
---
# stale
EOF
    touch -d '2099-01-09T00:00:00Z' "$TEST_TMPDIR/skills/used/SKILL.md"
    touch -d '2099-01-09T00:00:00Z' "$TEST_TMPDIR/skills/unused/SKILL.md"
    touch -d '2098-12-01T00:00:00Z' "$TEST_TMPDIR/skills/stale/SKILL.md"
    cat > "$TEST_TMPDIR/skill_recommend_log.yaml" <<'EOF'
recommendations:
- ts: "2099-01-10T00:00:00+09:00"
  agent_id: "hanzo"
  prompt_hash: "a"
  recommended_skills:
  - "used"
  - "stale"
- ts: "2099-01-10T00:01:00+09:00"
  agent_id: "hanzo"
  prompt_hash: "b"
  recommended_skills:
  - "used"
EOF

    run bash "$PROJECT_ROOT/scripts/skill_usage_metrics.sh" \
        --skills-dir "$TEST_TMPDIR/skills" \
        --recommend-log "$TEST_TMPDIR/skill_recommend_log.yaml" \
        --stale-days 30 \
        --now "2099-01-10T00:00:00Z"

    [ "$status" -eq 0 ]
    python3 - "$output" <<'PY'
import json
import sys
data = json.loads(sys.argv[1])
by_name = {item["skill"]: item for item in data["skills"]}
assert data["total_skills"] == 3
assert data["used_skill_count"] == 2
assert data["unused_skill_count"] == 1
assert data["stale_skill_count"] == 1
assert by_name["used"]["recommend_count"] == 2
assert by_name["unused"]["unused"] is True
assert by_name["stale"]["stale"] is True
PY
}

@test "karo unread cmd_new is injected as deployment-omission warning" {
    make_test_tmpdir
    mkdir -p "$TEST_TMPDIR/scripts/hooks" "$TEST_TMPDIR/queue/inbox"
    cp "$PROJECT_ROOT/scripts/hooks/prompt_state_inject.sh" "$TEST_TMPDIR/scripts/hooks/prompt_state_inject.sh"
    chmod +x "$TEST_TMPDIR/scripts/hooks/prompt_state_inject.sh"
    cat > "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'EOF'
messages:
- content: "cmd_3457を書いた。配備せよ。"
  type: cmd_new
  read: false
  id: msg_cmd_3457
- content: "FYI"
  type: bulletin_notify
  read: false
  id: msg_fyi
EOF

    run env PROMPT_STATE_AGENT_ID=karo bash "$TEST_TMPDIR/scripts/hooks/prompt_state_inject.sh" <<'JSON'
{"prompt":"status"}
JSON
    [ "$status" -eq 0 ]
    [[ "$output" == *"inbox_unread: 2"* ]]
    [[ "$output" == *"KARO CMD_NEW 1件未処理"* ]]
    [[ "$output" == *"msg_cmd_3457"* ]]
    [[ "$output" == *"配備漏れ直結"* ]]
}

@test "deploy_training preserves explicit target_path across deploy_task training fallback" {
    make_test_tmpdir
    local tmp_root="$TEST_TMPDIR/deploy_training"
    mkdir -p "$tmp_root/scripts/lib" "$tmp_root/queue/tasks"
    cp "$PROJECT_ROOT/scripts/deploy_training.sh" "$tmp_root/scripts/deploy_training.sh"
    cp "$PROJECT_ROOT/scripts/lib/field_get.sh" "$tmp_root/scripts/lib/field_get.sh"
    cp "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$tmp_root/scripts/lib/yaml_field_set.sh"

    cat > "$tmp_root/queue/shogun_to_karo.yaml" <<'YAML'
commands:
YAML
    cat > "$tmp_root/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: idle
  target_path: docs/research/old.md
YAML
    cat > "$tmp_root/scripts/deploy_task.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
ninja="$1"
bash "$root/scripts/lib/yaml_field_set.sh" "$root/queue/tasks/${ninja}.yaml" task target_path "docs/research/wrong.md" >/dev/null
echo "deployment complete"
SH
    chmod +x "$tmp_root/scripts/deploy_task.sh"

    run bash "$tmp_root/scripts/deploy_training.sh" Rtarget hayate:scripts/report_field_set.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: hayate target_path corrected after deploy (docs/research/wrong.md -> scripts/report_field_set.sh)"* ]]
    [[ "$output" == *"OK: hayate"* ]]
    grep -q 'target_path: "scripts/report_field_set.sh"' "$tmp_root/queue/shogun_to_karo.yaml"

    python3 - "$tmp_root/queue/tasks/hayate.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as fh:
    task = yaml.safe_load(fh)["task"]
assert task["target_path"] == "scripts/report_field_set.sh", task
PY
}

@test "idle next action runs semantic stress when NO_MATCH exists and accumulates insights" {
    make_test_tmpdir
    mkdir -p "$TEST_TMPDIR/logs" "$TEST_TMPDIR/queue"
    cat > "$TEST_TMPDIR/semantic_stress_mock.sh" <<'EOF'
#!/usr/bin/env bash
log_file="${GUNSHI_NEXT_ACTION_STRESS_CALL_LOG:?call log required}"
printf 'semantic_stress_called %s\n' "$*" >> "$log_file"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --insights) insights="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$(dirname "$insights")"
if [ ! -f "$insights" ]; then
  printf 'insights:\n' > "$insights"
fi
printf -- '- id: INS-MOCK\n  insight: "NO_MATCH alias candidate"\n  priority: "low"\n  source: "semantic_stress_test"\n  status: pending\n' >> "$insights"
echo 'SEMANTIC_STRESS total=1 hits=0 no_match=1 errors=0 hit_rate=0.0%'
EOF
    chmod +x "$TEST_TMPDIR/semantic_stress_mock.sh"

    export SEMANTIC_STRESS_CMD="$TEST_TMPDIR/semantic_stress_mock.sh"
    export GUNSHI_NEXT_ACTION_STRESS_CALL_LOG="$TEST_TMPDIR/logs/stress_call.log"
    export GUNSHI_NEXT_ACTION_DEPLOY_LOG="$TEST_TMPDIR/logs/deploy_task.log"
    export GUNSHI_NEXT_ACTION_PROMPT_NO_MATCH_LOG="$TEST_TMPDIR/logs/semantic_no_match_metrics.log"
    export GUNSHI_NEXT_ACTION_INSIGHTS="$TEST_TMPDIR/queue/insights.yaml"
    export GUNSHI_NEXT_ACTION_INBOX="$TEST_TMPDIR/queue/inbox.yaml"
    export GUNSHI_NEXT_ACTION_WA_LOG="$TEST_TMPDIR/logs/karo_workarounds.yaml"
    export GUNSHI_NEXT_ACTION_REVIEW_LOG="$TEST_TMPDIR/logs/gunshi_review_log.yaml"
    export GUNSHI_NEXT_ACTION_SNAPSHOT="$TEST_TMPDIR/queue/karo_snapshot.txt"
    export GUNSHI_NEXT_ACTION_FIRE_LOG="$TEST_TMPDIR/logs/gate_fire_log.yaml"
    export GUNSHI_NEXT_ACTION_NO_MATCH_SCAN_LINES=20
    printf 'reviews:\n' > "$GUNSHI_NEXT_ACTION_REVIEW_LOG"
    : > "$GUNSHI_NEXT_ACTION_SNAPSHOT"
    cat > "$GUNSHI_NEXT_ACTION_DEPLOY_LOG" <<'EOF'
2026-05-21 inject_semantic_concepts: NO_MATCH purpose=未登録概念 target_path=scripts/foo.sh
EOF

    run bash "$PROJECT_ROOT/scripts/gunshi_next_action.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"semantic_stress: NO_MATCH 1件 → insights蓄積実行"* ]]
    [[ "$output" == *"SEMANTIC_STRESS total=1 hits=0 no_match=1 errors=0 hit_rate=0.0%"* ]]
    [[ "$output" == *"semantic_stress: OK"* ]]
    grep -q 'semantic_stress_called' "$GUNSHI_NEXT_ACTION_STRESS_CALL_LOG"
    grep -q 'NO_MATCH alias candidate' "$GUNSHI_NEXT_ACTION_INSIGHTS"
}

@test "training_task_generator emits deployable skill_training task YAML" {
    make_test_tmpdir
    local tmp_root="$TEST_TMPDIR/training_generator"
    mkdir -p "$tmp_root/scripts" "$tmp_root/skills/report-write" "$tmp_root/queue/training"
    cat > "$tmp_root/scripts/inbox_write.sh" <<SH
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "\$1" "\$2" "\$3" "\$4" >> "$tmp_root/inbox.log"
SH
    chmod +x "$tmp_root/scripts/inbox_write.sh"
    printf '# report-write\n' > "$tmp_root/skills/report-write/SKILL.md"

    run bash "$PROJECT_ROOT/scripts/training_task_generator.sh" \
        --repo-root "$tmp_root" \
        --skill report-write \
        --gate gate_report_format \
        --reason "verdict missing" \
        --streak 2

    [ "$status" -eq 0 ]
    [[ "$output" == *"TRAINING_TASK_GENERATED:"* ]]
    [[ "$output" == *"KARO_NOTIFIED: training task for report-write"* ]]

    local generated_file
    generated_file="$(printf '%s\n' "$output" | sed -n 's/^TRAINING_TASK_GENERATED: \([^ ]*\).*/\1/p')"
    [ -f "$generated_file" ]
    grep -Fq "deploy_task.sh --direct --yaml" "$generated_file"

    FILE="$generated_file" python3 - <<'PY'
import os
import yaml

with open(os.environ["FILE"], encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

task = data.get("task") or {}
proposal = data.get("training_proposal") or {}

assert task["task_type"] == "skill_training", task
assert task["project"] == "infra", task
assert task["target_path"] == "skills/report-write/SKILL.md", task
assert task["parent_cmd"].startswith("cmd_training_L1_report-write_"), task["parent_cmd"]
assert task["task_id"] == task["parent_cmd"] + "_training", task["task_id"]
assert "verdict非二値" in task["purpose"], task["purpose"]
assert list(task["acceptance_criteria"].keys()) == ["AC1", "AC2", "AC3"]
assert "gate_report_format" in task["acceptance_criteria"]["AC2"]["description"]

assert proposal["skill"] == "report-write", proposal
assert proposal["gate"] == "gate_report_format", proposal
assert proposal["suggested_parent_cmd"] == task["parent_cmd"], proposal
assert proposal["status"] == "pending_karo_review", proposal
PY

    grep -Fq "karo|修行課題自動生成: skill=report-write level=L1 gate=gate_report_format streak=2" "$tmp_root/inbox.log"
}
