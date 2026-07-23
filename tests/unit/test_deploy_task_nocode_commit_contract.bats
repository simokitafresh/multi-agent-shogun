#!/usr/bin/env bats
# test_necessity: no-code commit免除は許可scopeかつ一致するtree証跡がある場合だけ成立する

load '../helpers/deploy_task_scaffold'

setup_file() {
  deploy_task_setup_file
}

setup() {
  deploy_task_scaffold "nocode_commit_contract"
}

teardown() {
  deploy_task_teardown
}

build_report() {
  local task_type="$1" target_path="$2" command="$3" files_modified="$4"
  cat >"$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  assigned_to: sasuke
  task_id: cmd_nocode_fixture_${task_type}
  parent_cmd: cmd_nocode_fixture
  project: infra
  task_type: ${task_type}
  title: no-code commit contract fixture
  command: "${command}"
  target_path: "${target_path}"
  files_modified: ${files_modified}
  ac_version: fixture-v1
  acceptance_criteria:
    - id: AC1
      description: report template contract is structured
EOF
  generate_report_template sasuke "cmd_nocode_fixture_${task_type}" cmd_nocode_fixture infra >/dev/null
  printf '%s/queue/reports/sasuke_report_cmd_nocode_fixture.yaml\n' "$TEST_PROJECT"
}

# test_necessity: LG044の正直報告は各ACの証拠slotが配備時点で存在しなければ、
# workerがschemaを推測して再提出するため、AC SSOT由来の1:1 mappingを守る。
@test "Level5 report template preinjects LG044 AC evidence slots into task and report" {
  report="$(build_report impl scripts/deploy_task.sh "implementation update" '[scripts/deploy_task.sh]')"

  run python3 - "$report" "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import json, sys, yaml
report = yaml.safe_load(open(sys.argv[1]))
task = yaml.safe_load(open(sys.argv[2]))["task"]
assert report["ac_evidence_mapping"] == {"AC1": ""}
assert json.loads(task["report_contract_templates"])["ac_evidence_mapping"] == {"AC1": ""}
PY
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&3; fi
  [ "$status" -eq 0 ]
}

# test_necessity: LG048のN×M検算は4つの正規field名をLevel5で供給し、
# 空欄をPASSへ捏造せずworkerの実測入力を要求する契約を守る。
@test "Level5 report template preinjects empty LG048 semantic validation schema" {
  report="$(build_report impl scripts/deploy_task.sh "implementation update" '[scripts/deploy_task.sh]')"

  run python3 - "$report" "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import json, sys, yaml
report = yaml.safe_load(open(sys.argv[1]))
task = yaml.safe_load(open(sys.argv[2]))["task"]
expected = {"classification_axis": "", "recount": "", "actual": "", "result": ""}
assert report["semantic_validation"] == expected
assert json.loads(task["report_contract_templates"])["semantic_validation"] == expected
PY
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&3; fi
  [ "$status" -eq 0 ]
}

# test_necessity: 外部projectのcommitはinfra repo基準の相対pathと混同せず、
# 対象Git rootと所有pathを同じcontractからreportへ供給する必要がある。
@test "DM-signal commit contract preinjects external repo scope" {
  local dm_repo
  dm_repo="$(get_project_path dm-signal)"
  cat >"$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  assigned_to: sasuke
  task_id: cmd_dm_scope
  parent_cmd: cmd_dm_scope
  project: dm-signal
  task_type: impl
  title: dm scope fixture
  target_path: backend/app/main.py
  planned_paths: [backend/app/main.py]
  ac_version: fixture-v1
  acceptance_criteria:
    - id: AC1
      description: external scope is structured
EOF
  generate_report_template sasuke cmd_dm_scope cmd_dm_scope dm-signal >/dev/null
  local report="$TEST_PROJECT/queue/reports/sasuke_report_cmd_dm_scope.yaml"

  run python3 - "$report" "$TEST_PROJECT/queue/tasks/sasuke.yaml" "$dm_repo" <<'PY'
import sys, yaml
report = yaml.safe_load(open(sys.argv[1]))
task = yaml.safe_load(open(sys.argv[2]))["task"]
root = sys.argv[3]
assert task["commit_contract"]["repo_root"] == root
assert task["commit_contract"]["planned_paths"] == ["backend/app/main.py"]
assert report["cross_repo_commits"] == [{
    "repo": root, "commit_hash": "", "paths": ["backend/app/main.py"]
}]
PY
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&3; fi
  [ "$status" -eq 0 ]
}

@test "decision_candidate no-code scope emits machine-readable commit N/A" {
  report="$(build_report decision_candidate queue/pending_decisions.yaml "decision candidate only" '[]')"

  run python3 - "$report" "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
c = d['commit_contract']
task = yaml.safe_load(open(sys.argv[2]))['task']
assert task['commit_contract'] == c, (task['commit_contract'], c)
assert c['required'] is False
assert c['reason'] == 'allowed_no_code_task_type'
assert c['task_type'] == 'decision_candidate'
assert 'queue/pending_decisions.yaml' in c['planned_paths']
check = d['binary_checks']['commit'][0]
assert 'commit N/A証跡' in check['check'] and check['result'] == ''
PY
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&3; fi
  [ "$status" -eq 0 ]
}

@test "data_readonly scope emits commit N/A evidence" {
  report="$(build_report data_readonly docs/research/input.csv "read data only" '[docs/research/input.csv]')"

  run python3 - "$report" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print(d['commit_contract'])
assert d['commit_contract']['required'] is False
assert d['commit_contract']['task_type'] == 'data_readonly'
assert 'docs/research/input.csv' in d['commit_contract']['planned_paths']
PY
  [ "$status" -eq 0 ]
}

@test "free-text no-code claim cannot waive implementation task commit" {
  report="$(build_report impl scripts/deploy_task.sh "no-code change; commit unnecessary" '[scripts/deploy_task.sh]')"

  run python3 - "$report" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
assert d['commit_contract']['required'] is True
assert d['commit_contract']['reason'] == 'implementation_path_present'
assert 'git commitが完了したか' in d['binary_checks']['commit'][0]['check']
PY
  [ "$status" -eq 0 ]
}

@test "allowed no-code type with implementation path emits commit N/A (recon reads but does not modify)" {
  report="$(build_report decision_candidate scripts/decision_helper.py "decision helper update" '[scripts/decision_helper.py]')"

  run python3 - "$report" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
# recon/decision_candidate等の読み取り専用タスクはplanned_pathsにscripts/があっても
# commit_contract.required=false (2026-07-23 軍師D0: inspection_path≠変更対象)
assert d['commit_contract']['required'] is False
assert d['commit_contract']['reason'] == 'allowed_no_code_task_type'
PY
  [ "$status" -eq 0 ]
}

@test "same-command retry rehydrates task commit contract from preserved report" {
  # test_necessity: reset_stale_fields clears the task contract before a retry,
  # while L060 preserves the report; both SSOTs must be synchronized again.
  report="$(build_report impl scripts/deploy_task.sh "implementation update" '[scripts/deploy_task.sh]')"

  cat >"$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  assigned_to: sasuke
  task_id: cmd_nocode_fixture_impl
  parent_cmd: cmd_nocode_fixture
  project: infra
  task_type: impl
  target_path: scripts/deploy_task.sh
  ac_version: fixture-v1
EOF

  generate_report_template sasuke cmd_nocode_fixture_impl cmd_nocode_fixture infra >/dev/null

  run python3 - "$report" "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import sys, yaml
report = yaml.safe_load(open(sys.argv[1]))
task = yaml.safe_load(open(sys.argv[2]))["task"]
assert task["commit_contract"] == report["commit_contract"]
assert task["commit_contract"]["planned_paths"] == ["scripts/deploy_task.sh"]
PY
  [ "$status" -eq 0 ]
}

@test "no-code identity requires matching tree evidence" {
  run python3 - "$PROJECT_ROOT" <<'PY'
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / 'scripts' / 'lib'))
from report_commit_identity import valid_commit_identity
root = pathlib.Path(sys.argv[1])
tree = 'a' * 40
report = {
  'files_modified': ['queue/tasks/sasuke.yaml'],
  'binary_checks': {'commit': [{'check': 'commit不要', 'result': 'yes'}]},
}
assert not valid_commit_identity('no-code-change', report, root)
report['no_code_change_evidence'] = {'before_tree': tree, 'after_tree': tree, 'tree_unchanged': True}
assert valid_commit_identity('no-code-change', report, root)
report['no_code_change_evidence']['after_tree'] = 'b' * 40
assert not valid_commit_identity('no-code-change', report, root)
PY
  [ "$status" -eq 0 ]
}
