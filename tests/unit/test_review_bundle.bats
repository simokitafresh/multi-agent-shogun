#!/usr/bin/env bats
# test_necessity: the public single-review command must preserve the existing
# batch transaction order: precheck, bundle, rich ledger, approval, one notify.

@test "single APPROVE completes the review transaction once in canonical order" {
  root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/scripts/gates" "$root/scripts/lib" "$root/queue/reports" \
    "$root/queue/tasks" "$root/queue/gates" "$root/logs"
  ln -s "$BATS_TEST_DIRNAME/../../scripts/review_bundle.py" "$root/scripts/review_bundle.py"
  cat >"$root/scripts/gates/gate_gunshi_report_precheck.sh" <<'SH'
#!/bin/sh
echo precheck >>"$TEST_CALLS"
SH
  cat >"$root/scripts/gunshi_log_append.sh" <<'SH'
#!/bin/sh
test -s "$TEST_ROOT/queue/gates/cmd_one/sg7_bundle.json"
echo ledger >>"$TEST_CALLS"
cat >"$TEST_ROOT/logs/gunshi_review_log.yaml"
SH
  cat >"$root/scripts/review_approval.sh" <<'SH'
#!/bin/sh
grep -q 'cmd_id: cmd_one' "$TEST_ROOT/logs/gunshi_review_log.yaml"
echo approval >>"$TEST_CALLS"
SH
  cat >"$root/scripts/lib/review_approval.sh" <<'SH'
review_two_phase_ready_gunshi() { echo notify >>"$TEST_CALLS"; return 0; }
SH
  cat >"$root/scripts/inbox_write.sh" <<'SH'
#!/bin/sh
echo inbox >>"$TEST_CALLS"
SH
  chmod +x "$root/scripts/gates/gate_gunshi_report_precheck.sh" \
    "$root/scripts/gunshi_log_append.sh" "$root/scripts/review_approval.sh" "$root/scripts/inbox_write.sh"
  cat >"$root/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_one:
    acceptance_criteria: [one]
    target_path: scripts/review_bundle.py
    project: infra
YAML
  cat >"$root/queue/reports/worker_report_cmd_one.yaml" <<'YAML'
parent_cmd: cmd_one
report_id: rpt-one
status: completed
verdict: PASS
binary_checks: {AC1: [{result: yes}]}
result: {summary: measured pass}
YAML
  cat >"$root/queue/tasks/worker.yaml" <<'YAML'
task: {parent_cmd: cmd_one, report_filename: worker_report_cmd_one.yaml}
YAML
  cat >"$root/review-entry.yaml" <<'YAML'
cmd_id: cmd_one
review_type: report
verdict: LGTM
observations: [measured]
brainwash_check: numeric evidence 1/1
verified_files: [scripts/review_bundle.py]
operational_simulation: {result: PASS}
YAML
  export TEST_ROOT="$root" TEST_CALLS="$root/calls"

  run python3 "$root/scripts/review_bundle.py" --root "$root" single \
    --cmd cmd_one --verdict APPROVE --report queue/reports/worker_report_cmd_one.yaml \
    --review-entry "$root/review-entry.yaml"
  echo "$output" >&3
  [ "$status" -eq 0 ]
  [ "$(grep -c '^precheck$' "$TEST_CALLS")" -eq 1 ]
  [ "$(grep -c '^ledger$' "$TEST_CALLS")" -eq 1 ]
  [ "$(grep -c '^approval$' "$TEST_CALLS")" -eq 1 ]
  [ "$(grep -c '^inbox$' "$TEST_CALLS")" -eq 1 ]
  [ "$(tr '\n' ' ' <"$TEST_CALLS")" = "precheck ledger approval notify inbox " ]
}
