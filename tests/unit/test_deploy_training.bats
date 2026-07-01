#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TMP_ROOT="$(mktemp -d)"

    mkdir -p "$TMP_ROOT/scripts/lib" "$TMP_ROOT/queue/tasks"
    cp "$PROJECT_ROOT/scripts/deploy_training.sh" "$TMP_ROOT/scripts/deploy_training.sh"
    cp "$PROJECT_ROOT/scripts/lib/field_get.sh" "$TMP_ROOT/scripts/lib/field_get.sh"
    cp "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$TMP_ROOT/scripts/lib/yaml_field_set.sh"

    cat > "$TMP_ROOT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
YAML

    cat > "$TMP_ROOT/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: idle
  target_path: docs/research/old.md
YAML

    cat > "$TMP_ROOT/scripts/deploy_task.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
ninja="$1"
# Simulate deploy_task.sh resetting/reselecting a training target during deploy.
bash "$root/scripts/lib/yaml_field_set.sh" "$root/queue/tasks/${ninja}.yaml" task target_path "docs/research/wrong.md" >/dev/null
echo "deployment complete"
SH
    chmod +x "$TMP_ROOT/scripts/deploy_task.sh"
}

teardown() {
    rm -rf "$TMP_ROOT"
}

@test "deploy_training preserves explicit target_path across deploy_task training fallback" {
    run bash "$TMP_ROOT/scripts/deploy_training.sh" Rtarget hayate:scripts/report_field_set.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: hayate target_path corrected after deploy (docs/research/wrong.md -> scripts/report_field_set.sh)"* ]]
    [[ "$output" == *"OK: hayate"* ]]

    grep -q 'target_path: "scripts/report_field_set.sh"' "$TMP_ROOT/queue/shogun_to_karo.yaml"

    python3 - "$TMP_ROOT/queue/tasks/hayate.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as fh:
    task = yaml.safe_load(fh)["task"]

assert task["target_path"] == "scripts/report_field_set.sh", task
PY
}
