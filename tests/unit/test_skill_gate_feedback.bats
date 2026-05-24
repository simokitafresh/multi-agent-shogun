#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/skill_gate_feedback.XXXXXX")"
  export SKILL_EXECUTION_LOG_FILE="$TEST_TMPDIR/skill_execution_log.yaml"
  export SKILL_FEEDBACK_SKILLS_DIRS="$TEST_TMPDIR/skills"
  mkdir -p "$TEST_TMPDIR/skills/report-write"
  cat > "$TEST_TMPDIR/skills/report-write/SKILL.md" <<'EOF'
---
name: report-write
description: Report YAML writing.
---

# report-write
EOF
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "skill_gate_feedback normalizes report YAML source to cmd_id" {
  report_path="$TEST_TMPDIR/queue/reports/saizo_report_cmd_3039.yaml"
  mkdir -p "$(dirname "$report_path")"
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
