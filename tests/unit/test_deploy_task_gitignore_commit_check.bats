#!/usr/bin/env bats
# test_deploy_task_gitignore_commit_check.bats
# cmd_1838: gitignore対象ファイルのみ変更するcmdでcommit check=noが自動設定される

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_gitignore_cc"
    # shellcheck disable=SC1090
    source "$TEST_PROJECT/scripts/lib/field_get.sh"

    # TEST_PROJECTをgit repoとして初期化し outputs/を gitignore
    git -C "$TEST_PROJECT" init --quiet
    printf 'outputs/\n' > "$TEST_PROJECT/.gitignore"
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

@test "gitignore対象ファイルのみ変更するcmdでcommit check=noが自動設定される" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "gitignore commit check test"
  task_type: impl
  parent_cmd: cmd_1838
  task_id: cmd_1838_impl
  project: infra
  target_path: "outputs/test_result.csv"
  acceptance_criteria:
    - id: AC1
      description: "outputs/にCSVを出力する"
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
bc = data["binary_checks"]
commit_items = bc.get("commit", [])
assert len(commit_items) >= 1, f"commit checkが存在しない: {bc}"
commit_result = commit_items[0].get("result", "")
assert commit_result == "no", f"commit checkのresultが'no'でない: {commit_result!r}"
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "gitignore対象外ファイルのcmdではcommit checkは空のまま" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "non-gitignore commit check test"
  task_type: impl
  parent_cmd: cmd_1838
  task_id: cmd_1838_impl2
  project: infra
  target_path: "scripts/deploy_task.sh"
  acceptance_criteria:
    - id: AC1
      description: "scripts/deploy_task.shを修正する"
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
bc = data["binary_checks"]
commit_items = bc.get("commit", [])
assert len(commit_items) >= 1, f"commit checkが存在しない: {bc}"
commit_result = commit_items[0].get("result", "")
assert commit_result == "", f"commit checkのresultが空でない: {commit_result!r}"
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
