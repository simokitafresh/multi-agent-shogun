#!/usr/bin/env bats

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_monthly_scout"
    # shellcheck disable=SC1090
    source "$TEST_PROJECT/scripts/lib/field_get.sh"
}

teardown() {
    deploy_task_teardown
}

task_file() {
    printf '%s\n' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
}

read_task_report_path() {
    FIELD_GET_NO_LOG=1 field_get "$(task_file)" "report_path" "" 2>/dev/null
}

@test "scout_exempt=true のcmdでcommit checkが注入されない (GP-190)" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "scout exempt commit check test"
  task_type: impl
  parent_cmd: cmd_gp183
  task_id: cmd_gp183_impl
  project: infra
  scout_exempt: true
  acceptance_criteria:
    - id: AC1
      description: "report templateのみ更新する"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run python3 - <<PYEOF
import yaml
from pathlib import Path
report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
assert "commit" not in data["binary_checks"], f"commit checkが注入されている(不要): {data['binary_checks']}"
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "recon taskではcommit checkを引き続き注入しない" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "recon commit skip test"
  task_type: recon
  parent_cmd: cmd_gp183
  task_id: cmd_gp183_recon
  project: infra
  acceptance_criteria:
    - id: AC1
      description: "既存の挙動を確認する"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run python3 - <<PYEOF
import yaml
from pathlib import Path
report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
assert "commit" not in data["binary_checks"], data["binary_checks"]
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC descriptionにmonthlyを含む場合はdescription由来checkへ進行中月除外を付記する" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "monthly annotation test"
  task_type: impl
  parent_cmd: cmd_gp184
  task_id: cmd_gp184_impl
  project: infra
  acceptance_criteria:
    - id: AC1
      description: "monthly returns parityを確認する。差分が0である"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run python3 - <<PYEOF
import yaml
from pathlib import Path
report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
checks = data["binary_checks"]["AC1"]
texts = [item["check"] for item in checks]
assert any("進行中月除外" in text for text in texts), texts
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC descriptionに月次を含む場合は手書きbinary_checksにも進行中月除外を付記する" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "monthly handwritten binary check test"
  task_type: impl
  parent_cmd: cmd_gp184
  task_id: cmd_gp184_impl_handwritten
  project: infra
  acceptance_criteria:
    - id: AC1
      description: "月次データの確認"
      binary_checks:
        - check: "月次リターン差分を確認したか"
EOF

    run deploy_task_template_only sasuke
    [ "$status" -eq 0 ]

    run read_task_report_path
    [ "$status" -eq 0 ]
    local report_path="$TEST_PROJECT/$output"

    run python3 - <<PYEOF
import yaml
from pathlib import Path
report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
checks = data["binary_checks"]["AC1"]
assert "進行中月除外" in checks[0]["check"], checks
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
