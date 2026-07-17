#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; T="$BATS_TEST_TMPDIR/project"
  mkdir -p "$T/scripts/gates" "$T/scripts/lib" "$T/queue/reports" "$T/queue/gates" "$T/logs"
  cp "$ROOT/scripts/review_bundle.py" "$T/scripts/"
  cat >"$T/scripts/gates/gate_gunshi_report_precheck.sh" <<'SH'
#!/usr/bin/env bash
sleep 0.1
[[ "$1" != *fail* ]] || { echo 'ERRORS=1'; exit 2; }
echo 'ERRORS=0 GATE_PREDICTION=CLEAR'
SH
  cat >"$T/scripts/gunshi_log_append.sh" <<'SH'
#!/usr/bin/env bash
[[ "$1" = --batch ]] || exit 2
cat >"$(dirname "$0")/../review-log-batch.yaml"
SH
  cat >"$T/scripts/review_approval.sh" <<'SH'
#!/usr/bin/env bash
touch "$(dirname "$0")/../approval-$1"
SH
  cat >"$T/scripts/lib/review_approval.sh" <<'SH'
review_two_phase_ready_gunshi() { [[ -f "$PROJECT_ROOT/approval-$1" ]]; }
SH
  cat >"$T/scripts/inbox_write.sh" <<'SH'
#!/usr/bin/env bash
printf '%s|%s|%s\n' "$1" "$3" "$4" >>"$(dirname "$0")/../inbox-events"
SH
  chmod +x "$T/scripts/"*.sh "$T/scripts/gates/"*.sh
  printf 'commands:\n' >"$T/queue/shogun_to_karo.yaml"
  for n in 1 2 3 4 5; do
    cat >>"$T/queue/shogun_to_karo.yaml" <<YAML
  cmd_b$n:
    id: cmd_b$n
    project: infra
    target_path: scripts/file$n.sh
    acceptance_criteria: [{id: AC1}]
YAML
    cat >"$T/queue/reports/ninja_report_cmd_b$n.yaml" <<YAML
parent_cmd: cmd_b$n
result: {summary: "batch $n complete"}
YAML
  done
}

make_manifest() {
  local path="$1"; printf 'reviews:\n' >"$path"
  for n in 1 2 3 4 5; do
    cat >>"$path" <<YAML
  - cmd: cmd_b$n
    report: queue/reports/ninja_report_cmd_b$n.yaml
    verdict: APPROVE
    review_entry: {cmd_id: cmd_b$n, review_type: report}
YAML
  done
}

@test "five reviews precheck concurrently and preserve 1:1 bundle log inbox" {
  make_manifest "$T/manifest.yaml"
  run python3 "$T/scripts/review_bundle.py" --root "$T" batch --manifest "$T/manifest.yaml"
  [ "$status" -eq 0 ]; [[ "$output" == *'"total": 5'* ]]; [[ "$output" == *'"fail": 0'* ]]; [[ "$output" == *'"skip": 0'* ]]
  [ "$(find "$T/queue/gates" -name sg7_bundle.json | wc -l)" -eq 5 ]
  [ "$(grep -c 'cmd_id: cmd_b' "$T/review-log-batch.yaml")" -eq 5 ]
  [ "$(wc -l <"$T/inbox-events")" -eq 5 ]
  echo "$output"
  python3 - "$T/queue/gates" <<'PY'
import glob,json,sys
for p in glob.glob(sys.argv[1]+'/*/sg7_bundle.json'):
    assert json.load(open(p))['review']['precheck']['status']=='PASS'
PY
}

@test "explicit physical-target N/A is evidence, never skip" {
  cat >"$T/manifest.yaml" <<'YAML'
reviews:
  - cmd: cmd_b1
    report: queue/reports/ninja_report_cmd_b1.yaml
    verdict: APPROVE
    precheck_na: {reason: "karo_direct has no physical target", evidence: "files_modified=[] verified in report"}
    review_entry: {cmd_id: cmd_b1, review_type: report}
YAML
  run python3 "$T/scripts/review_bundle.py" --root "$T" batch --manifest "$T/manifest.yaml"
  [ "$status" -eq 0 ]; [[ "$output" == *'"skip": 0'* ]]
  grep -q '"status": "N/A"' "$T/queue/gates/cmd_b1/sg7_bundle.json"
  grep -q 'files_modified=\[\] verified in report' "$T/queue/gates/cmd_b1/sg7_bundle.json"
}

@test "one precheck failure blocks every bundle log and inbox mutation" {
  make_manifest "$T/manifest.yaml"
  sed -i 's@ninja_report_cmd_b3.yaml@ninja_report_cmd_b3_fail.yaml@' "$T/manifest.yaml"
  cp "$T/queue/reports/ninja_report_cmd_b3.yaml" "$T/queue/reports/ninja_report_cmd_b3_fail.yaml"
  run python3 "$T/scripts/review_bundle.py" --root "$T" batch --manifest "$T/manifest.yaml"
  [ "$status" -eq 2 ]; [[ "$output" == *'precheck failed cmd=cmd_b3'* ]]
  [ "$(find "$T/queue/gates" -name sg7_bundle.json | wc -l)" -eq 0 ]
  [ ! -e "$T/review-log-batch.yaml" ]; [ ! -e "$T/inbox-events" ]
}

@test "missing N/A evidence and duplicate cmd fail closed" {
  cat >"$T/manifest.yaml" <<'YAML'
reviews:
  - {cmd: cmd_b1, report: queue/reports/ninja_report_cmd_b1.yaml, verdict: APPROVE, precheck_na: {reason: absent}, review_entry: {cmd_id: cmd_b1}}
YAML
  run python3 "$T/scripts/review_bundle.py" --root "$T" batch --manifest "$T/manifest.yaml"
  [ "$status" -eq 2 ]; [[ "$output" == *'reason and evidence'* ]]
}

@test "review log batch validates every entry before appending any" {
  local V="$BATS_TEST_TMPDIR/real-log"
  mkdir -p "$V/scripts/lib" "$V/logs/archive"
  cp "$ROOT/scripts/gunshi_log_append.sh" "$V/scripts/"
  cp "$ROOT/scripts/lib/yaml_atomic.py" "$V/scripts/lib/"
  printf '# review log\n' >"$V/logs/gunshi_review_log.yaml"
  run bash "$V/scripts/gunshi_log_append.sh" --batch <<'YAML'
- cmd_id: valid_first
  review_type: report
  verdict: APPROVE
  finding_categories: [assumptions, numbers, premortem, adversarial, ambiguity]
  brainwash_check: "1/1 verified before0 after1"
  operational_simulation: {command: "bats test", expected: pass, actual: pass, result: PASS}
  verified_files: ["tests/example.bats:1"]
  observations: ["fact one"]
- cmd_id: invalid_second
  review_type: report
  verdict: APPROVE
YAML
  [ "$status" -eq 2 ]
  ! grep -q 'valid_first' "$V/logs/gunshi_review_log.yaml"
}
