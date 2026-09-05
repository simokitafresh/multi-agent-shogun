#!/usr/bin/env bats
# test_necessity: report publication may skip filesystem rewrites only when
# generator source_fp and task query_key match and report schema, AC/binary
# checks, and v2 identity are current; either source or task generation change
# must archive the stale report and mint a fresh complete identity.

load '../helpers/deploy_task_scaffold'

setup_file() {
  deploy_task_setup_file
}

setup() {
  deploy_task_scaffold "report_generation_cache"
  SCRIPT_DIR="$TEST_PROJECT"
  export SCRIPT_DIR
  export DEPLOY_TASK_REPORT_SOURCE_FILE="$TEST_TMPDIR/report-generator.source"
  printf 'generation-source-v1\n' > "$DEPLOY_TASK_REPORT_SOURCE_FILE"
}

teardown() {
  deploy_task_teardown
}

write_task() {
  local ac_version="$1" include_ac2="${2:-false}"
  {
    printf '%s\n' \
      'task:' \
      '  assigned_to: saizo' \
      '  task_id: cmd_report_generation_cache_normal' \
      '  parent_cmd: cmd_report_generation_cache' \
      '  task_type: normal' \
      '  project: infra' \
      '  purpose: report generation cache contract' \
      "  ac_version: ${ac_version}" \
      '  report_filename: saizo_report_cmd_report_generation_cache.yaml' \
      '  target_path: scripts/deploy_task.sh' \
      '  acceptance_criteria:' \
      '  - id: AC1' \
      '    description: schema and identity stay current'
    if [ "$include_ac2" = "true" ]; then
      printf '%s\n' \
        '  - id: AC2' \
        '    description: changed AC regenerates binary checks'
    fi
  } > "$TEST_PROJECT/queue/tasks/saizo.yaml"
}

generate_fixture_report() {
  generate_report_template saizo cmd_report_generation_cache_normal \
    cmd_report_generation_cache infra "$TEST_PROJECT/queue/tasks/saizo.yaml"
}

assert_complete_contract() {
  local expected_ac="$1"
  REPORT="$TEST_PROJECT/queue/reports/saizo_report_cmd_report_generation_cache.yaml" \
  TASK="$TEST_PROJECT/queue/tasks/saizo.yaml" \
  EXPECTED_AC="$expected_ac" python3 - <<'PY'
import os
import json
import yaml

report = yaml.safe_load(open(os.environ["REPORT"], encoding="utf-8"))
task = yaml.safe_load(open(os.environ["TASK"], encoding="utf-8"))["task"]
required = {
    "worker_id", "report_id", "report_identity_version", "task_id",
    "parent_cmd", "task_contract_snapshot", "result", "purpose_validation",
    "files_modified", "lesson_candidate", "lessons_useful", "binary_checks",
    "failure_origin", "self_gate_check", "verdict",
}
assert required <= report.keys(), required - report.keys()
assert report["worker_id"] == "saizo"
assert report["task_id"] == task["task_id"]
assert report["parent_cmd"] == task["parent_cmd"]
assert report["ac_version_read"] == task["ac_version"]
assert report["report_identity_version"] == 2
assert report["report_id"] == task["report_id"]
assert report["task_contract_snapshot"]["acceptance_criteria"] == task["acceptance_criteria"]
assert isinstance(task["commit_contract"], dict)
assert task["commit_contract"] == report["commit_contract"]
assert set(report["failure_origin"]) == {"primary", "secondary", "evidence_strength", "root_cause_key"}
assert report["failure_origin"]["evidence_strength"] == "missing"
templates = task["report_contract_templates"]
if isinstance(templates, str):
    templates = json.loads(templates)
assert isinstance(templates, dict)
assert templates["ac_evidence_mapping"] == report["ac_evidence_mapping"]
expected = set(os.environ["EXPECTED_AC"].split(",")) | {"commit"}
assert expected <= report["binary_checks"].keys(), report["binary_checks"].keys()
PY
}

@test "same source_fp and query_key skip all report task and pointer rewrites" {
  write_task generation-v1 false
  run generate_fixture_report
  [ "$status" -eq 0 ]
  assert_complete_contract AC1

  local report="$TEST_PROJECT/queue/reports/saizo_report_cmd_report_generation_cache.yaml"
  local task="$TEST_PROJECT/queue/tasks/saizo.yaml"
  local pointer="$TEST_PROJECT/queue/reports/.deploy_active_saizo"
  local marker="$TEST_PROJECT/queue/reports/.deploy_generation_saizo_report_cmd_report_generation_cache.yaml"
  local before
  before="$(sha256sum "$report" "$task" "$pointer" "$marker")"

  local trial started ended
  for trial in 1 2 3; do
    started="$(date +%s%N)"
    run generate_fixture_report
    ended="$(date +%s%N)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"report_template: generation cache hit"* ]]
    printf 'CACHE_TRIAL_%s_MS=%s\n' "$trial" "$(( (ended - started) / 1000000 ))" >&3
  done

  [ "$(sha256sum "$report" "$task" "$pointer" "$marker")" = "$before" ]
  assert_complete_contract AC1
}

@test "task generation change regenerates AC binary checks and report identity" {
  write_task generation-v1 false
  generate_fixture_report >/dev/null
  local report="$TEST_PROJECT/queue/reports/saizo_report_cmd_report_generation_cache.yaml"
  local old_id
  old_id="$(awk '/^report_id:/{print $2; exit}' "$report")"

  write_task generation-v2 true
  run generate_fixture_report
  [ "$status" -eq 0 ]
  [[ "$output" == *"generation changed; archived stale report"* ]]
  local new_id
  new_id="$(awk '/^report_id:/{print $2; exit}' "$report")"
  [ "$new_id" != "$old_id" ]
  [ "$(find "$TEST_PROJECT/archive/reports/stale" -maxdepth 1 -type f -name 'saizo_report_cmd_report_generation_cache.yaml.generation-*' | wc -l)" -eq 1 ]
  assert_complete_contract AC1,AC2
}

@test "generator source_fp change regenerates a fresh report identity" {
  write_task generation-v1 false
  generate_fixture_report >/dev/null
  local report="$TEST_PROJECT/queue/reports/saizo_report_cmd_report_generation_cache.yaml"
  local old_id
  old_id="$(awk '/^report_id:/{print $2; exit}' "$report")"

  printf 'generation-source-v2\n' >> "$DEPLOY_TASK_REPORT_SOURCE_FILE"
  run generate_fixture_report
  [ "$status" -eq 0 ]
  [[ "$output" == *"generation changed; archived stale report"* ]]
  local new_id
  new_id="$(awk '/^report_id:/{print $2; exit}' "$report")"
  [ "$new_id" != "$old_id" ]
  assert_complete_contract AC1
}

@test "same fixture three-run median proves generation cache speedup" {
  write_task generation-v1 false
  local report="$TEST_PROJECT/queue/reports/saizo_report_cmd_report_generation_cache.yaml"
  local marker="$TEST_PROJECT/queue/reports/.deploy_generation_saizo_report_cmd_report_generation_cache.yaml"
  local pointer="$TEST_PROJECT/queue/reports/.deploy_active_saizo"
  local -a before_ms=() after_ms=()
  local trial started ended

  for trial in 1 2 3; do
    if [ -f "$report" ]; then
      mv "$report" "$TEST_TMPDIR/fresh-report-${trial}.yaml"
      mv "$marker" "$TEST_TMPDIR/fresh-marker-${trial}.txt"
      mv "$pointer" "$TEST_TMPDIR/fresh-pointer-${trial}.txt"
    fi
    started="$(date +%s%N)"
    generate_fixture_report >/dev/null 2>&1
    ended="$(date +%s%N)"
    before_ms+=("$(( (ended - started) / 1000000 ))")
  done

  for trial in 1 2 3; do
    started="$(date +%s%N)"
    generate_fixture_report >/dev/null 2>&1
    ended="$(date +%s%N)"
    after_ms+=("$(( (ended - started) / 1000000 ))")
  done

  local before_median after_median
  before_median="$(printf '%s\n' "${before_ms[@]}" | sort -n | sed -n '2p')"
  after_median="$(printf '%s\n' "${after_ms[@]}" | sort -n | sed -n '2p')"
  printf 'SAME_FIXTURE before_ms=%s,%s,%s median=%s after_ms=%s,%s,%s median=%s\n' \
    "${before_ms[0]}" "${before_ms[1]}" "${before_ms[2]}" "$before_median" \
    "${after_ms[0]}" "${after_ms[1]}" "${after_ms[2]}" "$after_median" >&3
  [ "$after_median" -lt "$before_median" ]
  assert_complete_contract AC1
}
