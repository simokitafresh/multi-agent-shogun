#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TMP_ROOT="$(mktemp -d "$BATS_TMPDIR/training_generator.XXXXXX")"
    mkdir -p "$TMP_ROOT/scripts" "$TMP_ROOT/skills/report-write" "$TMP_ROOT/queue/training"

    cat > "$TMP_ROOT/scripts/inbox_write.sh" <<SH
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "\$1" "\$2" "\$3" "\$4" >> "$TMP_ROOT/inbox.log"
SH
    chmod +x "$TMP_ROOT/scripts/inbox_write.sh"
    printf '# report-write\n' > "$TMP_ROOT/skills/report-write/SKILL.md"
}

teardown() {
    rm -rf "$TMP_ROOT"
}

@test "training_task_generator emits deployable skill_training task YAML" {
    run bash "$PROJECT_ROOT/scripts/training_task_generator.sh" \
        --repo-root "$TMP_ROOT" \
        --skill report-write \
        --gate gate_report_format \
        --reason "verdict missing" \
        --streak 2

    [ "$status" -eq 0 ]
    [[ "$output" == *"TRAINING_TASK_GENERATED:"* ]]
    [[ "$output" == *"KARO_NOTIFIED: training task for report-write"* ]]

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

    grep -Fq "karo|修行課題自動生成: skill=report-write level=L1 gate=gate_report_format streak=2" "$TMP_ROOT/inbox.log"
}
