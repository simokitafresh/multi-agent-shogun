#!/usr/bin/env bats
setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd); T=$(mktemp -d)
  mkdir -p "$T/queue/tasks" "$T/queue/reports" "$T/queue/archive/cmds"
}
teardown() { rm -rf "$T"; }
parent() { cat > "$T/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_3869
    purpose: rotate safely
    acceptance_criteria:
      - {id: AC1, description: inventory}
      - {id: AC2, description: delete}
      - {id: AC3, description: rotate}
YAML
}
fp() { python3 - "$ROOT" <<'PY'
import sys; sys.path.insert(0,sys.argv[1]); from scripts.lib.parent_cmd_contract import contract_fingerprint
print(contract_fingerprint('cmd_3869','rotate safely',['AC1','AC2','AC3']))
PY
}
task() { local coverage=${1:-AC1}; cat > "$T/queue/tasks/ninja.yaml" <<YAML
task:
  parent_cmd: cmd_3869
  purpose: independently worded child task
  parent_ac_coverage: [$coverage]
  parent_contract_fingerprint: $(fp)
YAML
}
report() { local coverage=${1:-AC1}; printf 'worker_id: ninja\nparent_cmd: cmd_3869\nparent_ac_coverage: [%s]\nparent_contract_fingerprint: %s\nbinary_checks:\n  CHILD1: [{check: child evidence, result: yes}]\n' "$coverage" "$(fp)" > "$T/queue/reports/ninja_report_cmd_3869.yaml"; }
@test "partial recon report cannot clear parent ACs" { parent; task AC1; report AC1; run python3 "$ROOT/scripts/lib/parent_cmd_contract.py" cmd_3869 --root "$T"; [ "$status" -eq 1 ]; [[ "$output" == *'parent_ac_uncovered:AC2,AC3'* ]]; }
@test "missing SSOT and stale fingerprint fail closed" { task AC1; report AC1; run python3 "$ROOT/scripts/lib/parent_cmd_contract.py" cmd_3869 --root "$T"; [ "$status" -eq 1 ]; parent; sed -i 's/parent_contract_fingerprint:.*/parent_contract_fingerprint: stale/' "$T/queue/tasks/ninja.yaml"; run python3 "$ROOT/scripts/lib/parent_cmd_contract.py" cmd_3869 --root "$T"; [ "$status" -eq 1 ]; [[ "$output" == *parent_mapping_missing_or_stale* ]]; }
@test "complete aggregate mapping covers parent despite child purpose namespace" { parent; task 'AC1, AC2, AC3'; report 'AC1, AC2, AC3'; run python3 "$ROOT/scripts/lib/parent_cmd_contract.py" cmd_3869 --root "$T"; [ "$status" -eq 0 ]; }
@test "direct hotfix is exempt" { run python3 "$ROOT/scripts/lib/parent_cmd_contract.py" cmd_karo_hotfix_x --root "$T"; [ "$status" -eq 0 ]; }

@test "reopened parent is an authoritative contract source" {
  parent
  mkdir -p "$T/queue/reopened_cmds"
  mv "$T/queue/shogun_to_karo.yaml" "$T/queue/reopened_cmds/cmd_3869.yaml"
  task 'AC1, AC2, AC3'; report 'AC1, AC2, AC3'
  run python3 "$ROOT/scripts/lib/parent_cmd_contract.py" cmd_3869 --root "$T"
  [ "$status" -eq 0 ]
  [[ "$output" == *'queue/reopened_cmds/cmd_3869.yaml'* ]]
}

@test "standard deployment resolves a reopened parent before metadata injection" {
  mkdir -p "$T/queue/reopened_cmds"
  cat > "$T/queue/reopened_cmds/cmd_3869.yaml" <<'YAML'
commands:
  cmd_3869:
    project: infra
    scope_mode: recon
    title: resumed cleanup
    purpose: rotate safely
    acceptance_criteria:
      AC1: inventory
      AC2: delete
      AC3: rotate
YAML
  printf 'task:\n  status: idle\n' > "$T/queue/tasks/ninja.yaml"
  run bash -c "source '$ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$T'; LOG='$T/deploy.log'; resolve_cmd_to_task cmd_3869 ninja"
  echo "$output"
  [ "$status" -eq 0 ]
  run python3 - "$T/queue/tasks/ninja.yaml" <<'PY'
import sys,yaml
t=yaml.safe_load(open(sys.argv[1]))['task']
assert t['parent_cmd']=='cmd_3869'
assert t['project']=='infra'
assert t['task_type']=='recon'
assert t['status']=='assigned'
PY
  [ "$status" -eq 0 ]
}

@test "deployment producer binds identical task and report contracts" {
  parent
  mkdir -p "$T/queue/reports"
  cat > "$T/queue/tasks/ninja.yaml" <<'YAML'
task:
  parent_cmd: cmd_3869
  assigned_acs: [AC1]
  acceptance_criteria: [{id: CHILD1, description: inventory child}]
  report_filename: ninja_report_cmd_3869.yaml
YAML
  printf 'parent_cmd: cmd_3869\nworker_id: ninja\n' > "$T/queue/reports/ninja_report_cmd_3869.yaml"
  run bash -c "source '$ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$T'; inject_parent_contract '$T/queue/tasks/ninja.yaml' '$T/queue/reports/ninja_report_cmd_3869.yaml'"
  [ "$status" -eq 0 ]
  run python3 - "$T" <<'PY'
import sys,yaml
r=sys.argv[1]; t=yaml.safe_load(open(r+'/queue/tasks/ninja.yaml'))['task']; p=yaml.safe_load(open(r+'/queue/reports/ninja_report_cmd_3869.yaml'))
assert t['parent_ac_coverage']==p['parent_ac_coverage']==['AC1']
assert t['parent_contract_fingerprint']==p['parent_contract_fingerprint']
PY
  [ "$status" -eq 0 ]
}

@test "deployment producer binds mapping-form parent AC contracts" {
  cat > "$T/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_3869:
    purpose: rotate safely
    acceptance_criteria:
      AC1: {description: inventory}
      AC2: {description: delete}
      AC3: {description: rotate}
YAML
  cat > "$T/queue/tasks/ninja.yaml" <<'YAML'
task:
  parent_cmd: cmd_3869
  acceptance_criteria:
    - {id: AC1, description: inventory}
    - {id: AC2, description: delete}
    - {id: AC3, description: rotate}
YAML
  printf 'parent_cmd: cmd_3869\nworker_id: ninja\n' > "$T/queue/reports/ninja_report_cmd_3869.yaml"

  run bash -c "source '$ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$T'; inject_parent_contract '$T/queue/tasks/ninja.yaml' '$T/queue/reports/ninja_report_cmd_3869.yaml'"
  [ "$status" -eq 0 ]
  run python3 - "$T" <<'PY'
import sys,yaml
r=sys.argv[1]
t=yaml.safe_load(open(r+'/queue/tasks/ninja.yaml'))['task']
p=yaml.safe_load(open(r+'/queue/reports/ninja_report_cmd_3869.yaml'))
assert t['parent_ac_coverage']==p['parent_ac_coverage']==['AC1','AC2','AC3']
assert t['parent_contract_fingerprint']==p['parent_contract_fingerprint']
PY
  [ "$status" -eq 0 ]
}

@test "validator does not read unrelated report files" {
  parent
  task 'AC1, AC2, AC3'
  report 'AC1, AC2, AC3'
  mkfifo "$T/queue/reports/unrelated_report.yaml"

  run timeout 2 python3 "$ROOT/scripts/lib/parent_cmd_contract.py" cmd_3869 --root "$T"
  [ "$status" -eq 0 ]
  [[ "$output" == *parent_contract_ok* ]]
}
