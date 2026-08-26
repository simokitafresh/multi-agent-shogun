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
  # Infra側の同名pathがignoreでも、外部repoのcommit判定へ漏れてはならない。
  printf 'backend/\n' >"$TEST_PROJECT/.gitignore"
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
check = report["binary_checks"]["commit"][0]
assert check["result"] == "", check
assert "gitignore対象" not in check["check"], check
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

# test_necessity: readonly偵察の成功を期待発見へ再結合すると、ゼロ件という
# 正しい調査結果が再びFAILになる。配備されたtaskと凍結report snapshotが同じ
# outcome-neutral契約を持ち、報告欄も自動生成される不変量を守る。
@test "recon deployment freezes one outcome-neutral investigation contract into task and report" {
  cat >"$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  assigned_to: sasuke
  task_id: cmd_recon_outcome_neutral
  parent_cmd: cmd_recon_outcome_neutral
  project: infra
  task_type: recon
  title: locate an optional caller
  target_path: scripts/deploy_task.sh
  ac_version: fixture-v1
  acceptance_criteria:
    - id: AC1
      description: resolve whether the optional caller exists
EOF

  inject_outcome_neutral_investigation_contract "$TEST_PROJECT/queue/tasks/sasuke.yaml"
  generate_report_template sasuke cmd_recon_outcome_neutral cmd_recon_outcome_neutral infra >/dev/null
  local report="$TEST_PROJECT/queue/reports/sasuke_report_cmd_recon_outcome_neutral.yaml"

  run python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" "$report" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1]))["task"]
report = yaml.safe_load(open(sys.argv[2]))
contract = task["investigation_contract"]
assert contract["outcome_neutral"] is True
assert contract["discovery_required"] is False
assert isinstance(task["commit_contract"], dict)
assert task["commit_contract"] == report["commit_contract"]
assert contract == report["task_contract_snapshot"]["investigation_contract"]
assert report["investigation_outcome"] == {
    "outcome": "", "method_completed": False,
    "primary_evidence": [], "remaining_unknowns": [],
}
PY
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&3; fi
  [ "$status" -eq 0 ]
}

# test_necessity: recon2/scout consumer seam investigations must receive all
# nine typed seam questions and nine primary-evidence slots, while unrelated
# investigations keep the existing one-evidence contract.
@test "consumer seam contract injects nine fields and fail-closes blank evidence" {
  cat >"$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  assigned_to: sasuke
  task_id: cmd_seam_contract_fixture
  parent_cmd: cmd_seam_contract_fixture
  project: infra
  task_type: recon2
  title: inspect consumer cache cutover read reduction
  target_path: scripts/deploy_task.sh
  ac_version: fixture-v1
  acceptance_criteria:
    - id: AC1
      description: verify the cache consumer seam
EOF

  inject_outcome_neutral_investigation_contract "$TEST_PROJECT/queue/tasks/sasuke.yaml"
  inject_seam_contract "$TEST_PROJECT/queue/tasks/sasuke.yaml"
  generate_report_template sasuke cmd_seam_contract_fixture cmd_seam_contract_fixture infra >/dev/null
  local report="$TEST_PROJECT/queue/reports/sasuke_report_cmd_seam_contract_fixture.yaml"

  run python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" "$report" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1]))["task"]
report = yaml.safe_load(open(sys.argv[2]))
contract = task["investigation_contract"]["seam_contract"]
fields = [
    "primary_payload", "companion_caches", "key_set", "date_domain",
    "empty_behavior", "fallback", "side_effects", "legacy_only_policy",
    "downstream_cardinality",
]
assert contract["required"] is True
assert list(contract["fields"]) == fields
assert all(value == "" for value in contract["fields"].values())
assert contract["field_guidance"]["date_domain"]
assert contract["field_guidance"]["legacy_only_policy"]
assert report["task_contract_snapshot"]["seam_contract"] == contract
evidence = report["investigation_outcome"]["primary_evidence"]
assert [item["field"] for item in evidence] == fields
assert all(item["source"] == "" and item["observation"] == "" for item in evidence)
PY
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&3; fi
  [ "$status" -eq 0 ]

  run env GATE_NO_LOG=1 bash "$PROJECT_ROOT/scripts/gates/gate_report_format.sh" "$report"
  [ "$status" -eq 1 ]
  [[ "$output" == *"finding:"* ]]

  cat >"$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  assigned_to: sasuke
  task_id: cmd_seam_contract_unrelated
  parent_cmd: cmd_seam_contract_unrelated
  project: infra
  task_type: scout
  title: locate an optional caller
  target_path: scripts/deploy_task.sh
  ac_version: fixture-v1
  acceptance_criteria:
    - id: AC1
      description: locate the caller
EOF
  inject_outcome_neutral_investigation_contract "$TEST_PROJECT/queue/tasks/sasuke.yaml"
  inject_seam_contract "$TEST_PROJECT/queue/tasks/sasuke.yaml"
  run python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1]))["task"]
contract = task["investigation_contract"]["seam_contract"]
assert contract["required"] is False
assert len(contract["fields"]) == 9
assert task["investigation_contract"]["minimum_primary_evidence"] == 1
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

# test_necessity: gitignore免除は commit_contract.required=true のtaskにだけ適用され、
# required=false のno-commit契約(N/A証跡check)を上書きしてはならない。
# 実データ由来: 2026-07-26 に才蔵のrecon2(target_path=queue/pending_decisions.yaml)と
# 半蔵の1件が、この上書きにより達成不能な result:"no" でBLOCKされた(実害3件)。
gitignore_exempt_fixture() {
  local task_type="$1" target="$2"
  if [ ! -d "$TEST_PROJECT/.git" ]; then
    git -C "$TEST_PROJECT" init -q
    # scripts/ はscaffoldがsymlinkで張るため check-ignore が pathspec を拒否する。
    # 実在ディレクトリ配下のコードpathを使う(queue/ 配下 かつ .sh = has_code_path=true)。
    printf 'queue/\n' >"$TEST_PROJECT/.gitignore"
  fi
  cat >"$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  assigned_to: sasuke
  task_id: cmd_gitignore_exempt_${task_type}
  parent_cmd: cmd_gitignore_exempt
  project: infra
  task_type: ${task_type}
  title: gitignore exempt fixture
  target_path: "${target}"
  ac_version: fixture-v1
  acceptance_criteria:
    - id: AC1
      description: gitignore exemption must respect the no-commit contract
EOF
  generate_report_template sasuke "cmd_gitignore_exempt_${task_type}" cmd_gitignore_exempt infra >/dev/null
  printf '%s/queue/reports/sasuke_report_cmd_gitignore_exempt.yaml\n' "$TEST_PROJECT"
}

@test "gitignore exemption does not overwrite the no-commit contract of a read-only task" {
  report="$(gitignore_exempt_fixture recon2 queue/pending_decisions.yaml)"

  run python3 - "$report" "$TEST_PROJECT" <<'PY'
import subprocess, sys, yaml
# 前提の一次確認: target_path が本当に gitignore 対象でなければ試験が無意味になる
assert subprocess.run(['git', '-C', sys.argv[2], 'check-ignore', '-q',
                       'queue/pending_decisions.yaml']).returncode == 0, 'fixture path is not gitignored'
d = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
assert d['commit_contract']['required'] is False, d['commit_contract']
check = d['binary_checks']['commit'][0]
assert 'commit N/A証跡' in check['check'], check
assert check['result'] == '', check
PY
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&3; fi
  [ "$status" -eq 0 ]
}

@test "gitignore exemption still applies to an implementation task and states the reason" {
  report="$(gitignore_exempt_fixture impl queue/generated_helper.sh)"

  run python3 - "$report" "$TEST_PROJECT" <<'PY'
import subprocess, sys, yaml
assert subprocess.run(['git', '-C', sys.argv[2], 'check-ignore', '-q',
                       'queue/generated_helper.sh']).returncode == 0, 'fixture path is not gitignored'
d = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
assert d['commit_contract']['required'] is True, d['commit_contract']
check = d['binary_checks']['commit'][0]
assert check['result'] == 'no', check
# AC2: なぜnoなのかがcheck本文から分かること
assert '理由: target_pathが全てgitignore対象' in check['check'], check
PY
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&3; fi
  [ "$status" -eq 0 ]
}

# B32 (2026-07-26): 実データ由来のfixture。2026-07-25/26に発生した
# "files_modified path is outside planned scope: tests/..." の実ペアを
# そのまま素材にする(合成しない)。real_test_pairs の左=起票時のplanned実装path、
# 右=忍者がACに従って触り、scope外BLOCKされた実在のtestファイル。
stage_real_test_fixtures() {
  mkdir -p "$TEST_PROJECT/tests/unit"
  local rel
  for rel in "$@"; do
    cp "$PROJECT_ROOT/$rel" "$TEST_PROJECT/tests/unit/$(basename "$rel")"
  done
}

build_test_requiring_task() {
  local task_id="$1" target="$2" ac_description="$3"
  cat >"$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  assigned_to: sasuke
  task_id: ${task_id}
  parent_cmd: ${task_id}
  project: infra
  task_type: hotfix
  title: b32 planned_paths fixture
  target_path: ${target}
  ac_version: fixture-v1
  acceptance_criteria:
    - id: AC1
      description: ${ac_description}
EOF
  generate_report_template sasuke "$task_id" "$task_id" infra >/dev/null
}

# test_necessity: ACがtestの拡張を要求する場合、実装pathに結び付く既存tests/
# ファイルはplanned_pathsに含まれなければならない(含まれないとcommit時に
# 必ずscope外BLOCKになる)。
@test "B32 positive control: AC requiring tests expands planned_paths to the real test files" {
  stage_real_test_fixtures \
    tests/unit/test_ninja_scope_commit.bats \
    tests/unit/test_scratch_retention.bats \
    tests/unit/test_archive_completed_queue_flag_retention.bats \
    tests/unit/test_gate_skill_script_refs.bats \
    tests/unit/test_gate_gunshi_report_precheck_cache.bats \
    tests/unit/test_cmd_complete_gate_task_idle.bats

  local expanded=0 total=0
  local pair impl expected
  for pair in \
    "scripts/ninja_scope_commit.sh|tests/unit/test_ninja_scope_commit.bats" \
    "scripts/ninja_monitor.sh|tests/unit/test_scratch_retention.bats" \
    "scripts/archive_completed.sh|tests/unit/test_archive_completed_queue_flag_retention.bats" \
    "scripts/gates/gate_skill_script_refs.sh|tests/unit/test_gate_skill_script_refs.bats" \
    "scripts/gates/gate_gunshi_report_precheck.sh|tests/unit/test_gate_gunshi_report_precheck_cache.bats" \
    "scripts/cmd_complete_gate.sh|tests/unit/test_cmd_complete_gate_task_idle.bats" \
  ; do
    impl="${pair%%|*}"
    expected="${pair##*|}"
    total=$((total + 1))
    build_test_requiring_task "cmd_b32_${total}" "$impl" \
      "既存テストを拡張して両方向fixtureを固定する。新規testファイルを作るな"
    if python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" "$impl" "$expected" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
paths = task["commit_contract"]["planned_paths"]
assert sys.argv[2] in paths, (sys.argv[2], paths)
assert sys.argv[3] in paths, (sys.argv[3], paths)
assert task["commit_contract"]["scope_expansion_reason"], task["commit_contract"]
PY
    then
      expanded=$((expanded + 1))
    else
      printf 'not expanded: %s -> %s\n' "$impl" "$expected" >&3
    fi
  done
  [ "$expanded" -eq "$total" ]
}

# test_necessity: 拡張は非対称でなければならない。ACがtestを要求しない場合と、
# 実装pathに無関係なtests/ファイルは、従来通りscope外に留まる。
@test "B32 negative control: unrelated tests and non-test ACs keep the original ceiling" {
  stage_real_test_fixtures \
    tests/unit/test_archive_completed_queue_flag_retention.bats \
    tests/unit/test_inbox_write.bats

  build_test_requiring_task cmd_b32_neg_related scripts/archive_completed.sh \
    "既存テストを拡張して両方向fixtureを固定する"
  run python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import sys, yaml
paths = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]["commit_contract"]["planned_paths"]
assert "tests/unit/test_archive_completed_queue_flag_retention.bats" in paths, paths
assert "tests/unit/test_inbox_write.bats" not in paths, paths
assert not any(p.startswith("scripts/") and p != "scripts/archive_completed.sh" for p in paths), paths
PY
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&3; fi
  [ "$status" -eq 0 ]

  build_test_requiring_task cmd_b32_neg_notest scripts/archive_completed.sh \
    "queue flagの保持を実装する"
  run python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import sys, yaml
contract = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]["commit_contract"]
paths = contract["planned_paths"]
assert paths == ["scripts/archive_completed.sh"], paths
assert "scope_expansion_reason" not in contract, contract
PY
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&3; fi
  [ "$status" -eq 0 ]
}

# test_necessity: 明示済みtest所有権があるtaskを参照grepで再拡張すると、
# focused contractがdeploy_task参照test全体へ膨張する。明示2-pathをSSOTとして保つ。
@test "B32 negative control: explicit test ownership suppresses inferred widening" {
  stage_real_test_fixtures \
    tests/unit/test_deploy_task_nocode_commit_contract.bats \
    tests/unit/test_deploy_task.bats

  build_test_requiring_task cmd_b32_explicit scripts/deploy_task.sh \
    "既存テストを拡張して両方向fixtureを固定する"
  bash "$TEST_PROJECT/scripts/lib/yaml_field_set.sh" \
    "$TEST_PROJECT/queue/tasks/sasuke.yaml" task planned_paths \
    '["scripts/deploy_task.sh","tests/unit/test_deploy_task_nocode_commit_contract.bats"]'
  bash "$TEST_PROJECT/scripts/lib/yaml_field_set.sh" \
    "$TEST_PROJECT/queue/tasks/sasuke.yaml" task commit_contract \
    '{"required":true,"reason":"implementation_path_present","task_type":"hotfix","planned_paths":["scripts/deploy_task.sh","tests/unit/test_deploy_task_nocode_commit_contract.bats"],"repo_root":"'"$TEST_PROJECT"'"}'
  bash "$TEST_PROJECT/scripts/report_field_set.sh" \
    "$TEST_PROJECT/queue/reports/sasuke_report_cmd_b32_explicit.yaml" commit_contract \
    '{"required":true,"reason":"implementation_path_present","task_type":"hotfix","planned_paths":["scripts/deploy_task.sh","tests/unit/test_deploy_task_nocode_commit_contract.bats"],"repo_root":"'"$TEST_PROJECT"'"}'
  generate_report_template sasuke cmd_b32_explicit cmd_b32_explicit infra >/dev/null

  run python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import sys, yaml
contract = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]["commit_contract"]
assert contract["planned_paths"] == [
    "scripts/deploy_task.sh",
    "tests/unit/test_deploy_task_nocode_commit_contract.bats",
], contract
assert "scope_expansion_reason" not in contract, contract
PY
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&3; fi
  [ "$status" -eq 0 ]
}
